#!/usr/bin/env python3
"""
Pocket Harness — AES-256-GCM Encrypted JSON Build Script  v3.0
==========================================================
Menggabungkan semua JSON dari assets/data/ menjadi chunk terenkripsi
di assets/enc/ dengan nama file teracak (sha256-based).

ALUR:
  1. Baca semua JSON dari assets/data/
  2. Gabungkan per category:level → minify
  3. Enkripsi tiap chunk: AES-256-GCM (format KFv1)
  4. Generate manifest terenkripsi: assets/enc/km.idx
  5. Hasilkan checksum SHA-256 per chunk
  6. (CI mode) Hapus assets/data/, CLAUDE.md, scripts/, file sensitif lain
  7. (CI mode) Update pubspec.yaml: hapus assets/data/, tambah assets/enc/

KEY: AES-256 key = XOR(hex2bytes(KM_S0 + KM_S1), static_mask)
  KM_S0 = env var, 32 hex chars (16 bytes)
  KM_S1 = env var, 32 hex chars (16 bytes)
  static_mask = sama dengan yang di crypto_service.dart

Cara pakai:
  python3 scripts/build_encrypted_db.py --kf-s0 <hex32> --kf-s1 <hex32>
  python3 scripts/build_encrypted_db.py  # ambil dari env KM_S0 / KM_S1
  python3 scripts/build_encrypted_db.py --dry-run
  python3 scripts/build_encrypted_db.py --force  # rebuild ulang
"""

import os, sys, json, shutil, hashlib, argparse, datetime, secrets
from datetime import timezone
from pathlib import Path

# ─── Coba import cryptography ─────────────────────────────────────────────────
try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
except ImportError:
    print("❌ Paket 'cryptography' tidak ada. Jalankan: pip install cryptography")
    sys.exit(1)

# ─── Konstanta ────────────────────────────────────────────────────────────────
ROOT        = Path(__file__).parent.parent
ASSETS_DATA = ROOT / "assets" / "data"
ASSETS_ENC  = ROOT / "assets" / "enc"
MANIFEST    = ASSETS_ENC / "km.idx"
PUBSPEC     = ROOT / "pubspec.yaml"

# Static XOR mask — HARUS SAMA dengan _m0 / _m1 di crypto_service.dart
STATIC_MASK = bytes([
    0x4b,0x61,0x6e,0x61,0x46,0x61,0x69,0x74,0x68,0x32,0x30,0x32,0x35,0x21,0x40,0x23,
    0x4a,0x50,0x4e,0x21,0x42,0x65,0x6c,0x61,0x6a,0x61,0x72,0x21,0x53,0x61,0x79,0x61,
])

MAGIC = b'KFv1'

# ─── Logging ──────────────────────────────────────────────────────────────────
def log(msg, level="INFO"):
    icons = {"INFO":"✅","WARN":"⚠️ ","ERR":"❌","STEP":"🔧","SKIP":"⏭️","SEC":"🔐","DEL":"🗑️"}
    print(f"  {icons.get(level,'  ')} {msg}", flush=True)

# ─── Kriptografi ──────────────────────────────────────────────────────────────
def build_master_key(kf_s0: str, kf_s1: str) -> bytes:
    """
    Bangun 32-byte master key: XOR(hex2bytes(s0+s1), STATIC_MASK)
    Harus cocok dengan CryptoService.buildMasterKey() di Dart.
    """
    raw = bytes.fromhex(kf_s0 + kf_s1)  # 32 bytes
    return bytes(a ^ b for a, b in zip(raw, STATIC_MASK))

def encrypt_chunk(plaintext: bytes, key: bytes) -> bytes:
    """Enkripsi bytes dengan AES-256-GCM. Output: MAGIC + nonce(12) + ciphertext+tag."""
    nonce    = secrets.token_bytes(12)
    aesgcm   = AESGCM(key)
    ct_tag   = aesgcm.encrypt(nonce, plaintext, None)  # ciphertext + 16-byte tag
    return MAGIC + nonce + ct_tag

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()

def chunk_filename(chunk_id: str, key: bytes) -> str:
    """
    Nama file = SHA-256(chunk_id + key_first8bytes)[:24] + ".bin"
    Acak tapi deterministik: build ulang = nama sama (idempoten).
    """
    h = hashlib.sha256(chunk_id.encode() + key[:8]).hexdigest()
    return h[:24] + ".bin"

# ─── JSON Loader ──────────────────────────────────────────────────────────────
def load_json_safe(path: Path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if data else None
    except Exception as e:
        log(f"Skip {path.name}: {e}", "WARN")
        return None

def collect_list_from_folder(folder: Path, exclude=("manifest.json",)) -> list:
    """Kumpulkan semua item dari JSON array di folder ini (tidak rekursif ke subfolder)."""
    result = []
    if not folder.exists():
        return result
    for jf in sorted(folder.glob("*.json")):
        if jf.name in exclude:
            continue
        data = load_json_safe(jf)
        if data is None:
            continue
        if isinstance(data, list):
            result.extend(data)
        elif isinstance(data, dict):
            result.append(data)
    return result

# ─── Chunk builders ───────────────────────────────────────────────────────────
def build_chunks(data_root: Path) -> dict:
    """
    Bangun dict: chunk_id → data (list/dict/map)

    Chunk IDs:
      bunpou:n5  bunpou:n4  bunpou:n3  bunpou:n2  bunpou:n1
      kana:hiragana  kana:katakana
      kanji:n5  kanji:n4  kanji:n3  kanji:n2  kanji:n1
      kosakata:n5  kosakata:n4  kosakata:n3  kosakata:n2  kosakata:n1
      partikel:n5  partikel:n4  partikel:n3  partikel:n2  partikel:n1
      soal:jlpt_n5  soal:jlpt_n4  soal:jlpt_n3  soal:jlpt_n2  soal:jlpt_n1
      soal:jft  soal:partikel  soal:kalimat
      writing:all
    """
    chunks = {}
    levels = ["n5", "n4", "n3", "n2", "n1"]

    # BUNPOU ─────────────────────────────────────────────────────────────────
    bunpou_root = data_root / "bunpou"
    for lvl in levels:
        folder = bunpou_root / f"bunpou{lvl}"
        items  = collect_list_from_folder(folder)
        if items:
            chunks[f"bunpou:{lvl}"] = items
            log(f"  bunpou:{lvl} — {len(items)} item")

    # KANA ───────────────────────────────────────────────────────────────────
    kana_root = data_root / "kana"
    for sub in ["hiragana", "katakana"]:
        folder = kana_root / sub
        items  = collect_list_from_folder(folder)
        if items:
            chunks[f"kana:{sub}"] = items
            log(f"  kana:{sub} — {len(items)} item")

    # KANJI ──────────────────────────────────────────────────────────────────
    kanji_root = data_root / "kanji"
    for lvl in levels:
        folder = kanji_root / f"kanji{lvl}"
        items  = collect_list_from_folder(folder)
        if items:
            chunks[f"kanji:{lvl}"] = items
            log(f"  kanji:{lvl} — {len(items)} item")

    # KOSAKATA ───────────────────────────────────────────────────────────────
    kosakata_root = data_root / "kosakata"
    for lvl in levels:
        folder = kosakata_root / f"kosakata{lvl}"
        items  = collect_list_from_folder(folder)
        if items:
            chunks[f"kosakata:{lvl}"] = items
            log(f"  kosakata:{lvl} — {len(items)} item")

    # PARTIKEL ───────────────────────────────────────────────────────────────
    partikel_root = data_root / "partikel"
    for lvl in levels:
        folder = partikel_root / f"partikel{lvl}"
        items  = collect_list_from_folder(folder)
        if items:
            chunks[f"partikel:{lvl}"] = items
            log(f"  partikel:{lvl} — {len(items)} item")

    # SOAL — dipecah per kategori agar loading cepat (bukan 1 chunk 12MB)
    # soal:jlpt_n5..n1  -> List langsung (~550-670KB masing-masing)
    # soal:jft          -> Map<stem,List> (~2.8MB, 4 file JFT)
    # soal:partikel     -> Map<stem,List> (~210KB)
    # soal:kalimat      -> Map<stem,List> (~4MB)
    soal_root = data_root / "soal"
    if soal_root.exists():
        SOAL_GROUPS = {
            "soal:jlpt_n5": ["jlptn5_1"],
            "soal:jlpt_n4": ["jlptn4_1"],
            "soal:jlpt_n3": ["jlptn3_1"],
            "soal:jlpt_n2": ["jlptn2_1"],
            "soal:jlpt_n1": ["jlptn1_1"],
            "soal:jft":     ["jft_basic_1","jft_intermediate_1",
                             "jft_advanced_1","jfta2b_1"],
            "soal:partikel":["soal_partikel_n5","soal_partikel_n4",
                             "soal_partikel_n3","soal_partikel_n2",
                             "soal_partikel_n1"],
            "soal:kalimat": ["soal_kalimat_n5","soal_kalimat_n4",
                             "soal_kalimat_n3","soal_kalimat_n2",
                             "soal_kalimat_n1","soal_kalimat_1"],
        }
        stem_data = {}
        for jf in sorted(soal_root.glob("*.json")):
            if jf.name == "manifest.json":
                continue
            data = load_json_safe(jf)
            if data is None:
                continue
            stem = jf.stem.replace("-", "_").lower()
            stem_data[stem] = data if isinstance(data, list) else []

        for chunk_id, stems in SOAL_GROUPS.items():
            if chunk_id.startswith("soal:jlpt_"):
                data = stem_data.get(stems[0])
                if data:
                    chunks[chunk_id] = data
                    log(f"  {chunk_id} -- {len(data)} soal")
            else:
                group_map = {s: stem_data[s] for s in stems if s in stem_data}
                if group_map:
                    chunks[chunk_id] = group_map
                    total = sum(len(v) for v in group_map.values())
                    log(f"  {chunk_id} -- {len(group_map)} file, {total} soal")

    # WRITING ────────────────────────────────────────────────────────────────
    writing_root = data_root / "writing"
    kanji_list   = []
    kvg_kana     = {}
    if writing_root.exists():
        for jf in sorted(writing_root.rglob("*.json")):
            if jf.name == "manifest.json":
                continue
            data = load_json_safe(jf)
            if data is None:
                continue
            if isinstance(data, list):
                kanji_list.extend(data)
            elif isinstance(data, dict):
                kvg_kana.update(data)
    writing_chunk = {"kanji_manifest": kanji_list, "kvg_kana": kvg_kana}
    chunks["writing:all"] = writing_chunk
    log(f"  writing:all — {len(kanji_list)} kanji, {len(kvg_kana)} kvg entries")

    return chunks

# ─── Main ─────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(description="Pocket Harness AES-256-GCM Build Script v3")
    ap.add_argument("--kf-s0",   default="",    help="KM_S0: 32-char hex (first half of key)")
    ap.add_argument("--kf-s1",   default="",    help="KM_S1: 32-char hex (second half of key)")
    ap.add_argument("--force",   action="store_true", help="Rebuild ulang meski file sudah ada")
    ap.add_argument("--dry-run", action="store_true", help="Simulasi tanpa menulis file")
    ap.add_argument("--ci",      action="store_true", help="Mode CI: hapus file sensitif")
    args = ap.parse_args()

    # ── Ambil key dari env jika tidak di-pass ─────────────────────────────
    kf_s0 = args.kf_s0 or os.environ.get("KM_S0", "")
    kf_s1 = args.kf_s1 or os.environ.get("KM_S1", "")
    is_ci = args.ci or os.environ.get("GITHUB_ACTIONS", "") == "true"

    print()
    print("╔══════════════════════════════════════════════════════════════╗")
    print("║   Pocket Harness  —  AES-256-GCM Encrypted JSON Build  v3.0     ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    print(f"  CI mode : {is_ci}")
    print(f"  Force   : {args.force}")
    print(f"  Dry-run : {args.dry_run}")
    print()

    # ── Validasi key ──────────────────────────────────────────────────────
    if not kf_s0 or not kf_s1:
        print("❌ KM_S0 dan KM_S1 harus di-set (32-char hex masing-masing).")
        print("   Via env: export KM_S0=... && export KM_S1=...")
        print("   Via arg: --kf-s0 ... --kf-s1 ...")
        sys.exit(1)
    if len(kf_s0) != 32 or len(kf_s1) != 32:
        print(f"❌ KM_S0 harus 32 char (dapat {len(kf_s0)}), KM_S1 harus 32 char (dapat {len(kf_s1)})")
        sys.exit(1)
    try:
        master_key = build_master_key(kf_s0, kf_s1)
        log(f"Master key siap: {len(master_key)} bytes AES-256")
    except ValueError as e:
        print(f"❌ Key tidak valid: {e}")
        sys.exit(1)

    # ── Periksa data tersedia ─────────────────────────────────────────────
    if not ASSETS_DATA.exists() or not list(ASSETS_DATA.rglob("*.json")):
        log("Tidak ada JSON di assets/data/ — skip", "SKIP")
        sys.exit(0)

    json_count = len(list(ASSETS_DATA.rglob("*.json")))
    log(f"Ditemukan {json_count} file JSON di assets/data/")

    # ═══════════════════════════════════════════════════════════════════════
    # TAHAP 1: Bangun chunks dari semua JSON
    # ═══════════════════════════════════════════════════════════════════════
    print()
    print("📦 TAHAP 1: Mengumpulkan & membangun chunk data")
    print("─" * 62)
    chunks = build_chunks(ASSETS_DATA)
    log(f"Total chunk: {len(chunks)}")

    if not chunks:
        log("Tidak ada chunk yang bisa dibuat", "WARN")
        sys.exit(0)

    # ═══════════════════════════════════════════════════════════════════════
    # TAHAP 2: Enkripsi tiap chunk → simpan ke assets/enc/
    # ═══════════════════════════════════════════════════════════════════════
    print()
    print("🔐 TAHAP 2: Enkripsi AES-256-GCM per chunk")
    print("─" * 62)

    if not args.dry_run:
        ASSETS_ENC.mkdir(parents=True, exist_ok=True)

    manifest_data = {}  # chunk_id → {file, sha256, size, rows}

    for chunk_id, data in chunks.items():
        fname  = chunk_filename(chunk_id, master_key)
        fpath  = ASSETS_ENC / fname

        if fpath.exists() and not args.force:
            log(f"{chunk_id} → {fname} (sudah ada, skip)", "SKIP")
            manifest_data[chunk_id] = {
                "file":   fname,
                "sha256": sha256_file(fpath),
                "size":   fpath.stat().st_size,
            }
            continue

        # Minify JSON
        plaintext_str  = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
        plaintext_bytes = plaintext_str.encode("utf-8")

        if args.dry_run:
            log(f"[DRY] {chunk_id} → {fname} ({len(plaintext_bytes)//1024} KB plaintext)")
            continue

        # Enkripsi
        encrypted = encrypt_chunk(plaintext_bytes, master_key)
        fpath.write_bytes(encrypted)

        checksum = sha256_file(fpath)
        kb_enc   = len(encrypted) // 1024
        kb_plain = len(plaintext_bytes) // 1024
        log(f"{chunk_id} → {fname}  [{kb_plain}KB → {kb_enc}KB enc]  sha256:{checksum[:16]}...", "SEC")

        manifest_data[chunk_id] = {
            "file":   fname,
            "sha256": checksum,
            "size":   len(encrypted),
        }

    # ═══════════════════════════════════════════════════════════════════════
    # TAHAP 3: Buat dan enkripsi manifest
    # ═══════════════════════════════════════════════════════════════════════
    print()
    print("📋 TAHAP 3: Generate & enkripsi manifest (km.idx)")
    print("─" * 62)

    manifest_obj = {
        "v":          3,
        "build_date": datetime.datetime.now(timezone.utc).isoformat(),
        "chunks":     manifest_data,
    }

    if not args.dry_run:
        manifest_bytes    = json.dumps(manifest_obj, ensure_ascii=False, separators=(",",":")).encode()
        manifest_enc      = encrypt_chunk(manifest_bytes, master_key)
        MANIFEST.write_bytes(manifest_enc)
        msha = sha256_file(MANIFEST)
        log(f"km.idx — {len(manifest_enc)//1024} KB  sha256:{msha[:16]}...", "SEC")
        log(f"Chunk terdaftar: {len(manifest_data)}")
    else:
        log(f"[DRY] Akan buat km.idx ({len(manifest_data)} chunk)")

    # ═══════════════════════════════════════════════════════════════════════
    # TAHAP 4: Update pubspec.yaml (tambah assets/enc/, hapus assets/data/)
    # ═══════════════════════════════════════════════════════════════════════
    print()
    print("📝 TAHAP 4: Update pubspec.yaml")
    print("─" * 62)

    if not args.dry_run:
        _update_pubspec(is_ci)

    # ═══════════════════════════════════════════════════════════════════════
    # TAHAP 5: Hapus file sensitif (CI mode saja)
    # ═══════════════════════════════════════════════════════════════════════
    if is_ci and not args.dry_run:
        print()
        print("🗑️  TAHAP 5: Hapus file sensitif (CI mode)")
        print("─" * 62)
        _cleanup_sensitive(ROOT, ASSETS_DATA)

    # ═══════════════════════════════════════════════════════════════════════
    # TAHAP 6: Verifikasi akhir
    # ═══════════════════════════════════════════════════════════════════════
    print()
    print("🔍 TAHAP 6: Verifikasi")
    print("─" * 62)

    if not args.dry_run:
        enc_files = list(ASSETS_ENC.glob("*.bin")) + list(ASSETS_ENC.glob("*.idx"))
        log(f"File terenkripsi di assets/enc/: {len(enc_files)}")
        for f in sorted(enc_files):
            log(f"  {f.name}  ({f.stat().st_size//1024} KB)")

    print()
    print("═" * 62)
    print("✅ Build selesai!")
    print()


def _update_pubspec(remove_data_entries: bool):
    """Update pubspec.yaml: tambah assets/enc/, hapus semua assets/data/ & assets/bin/ entries."""
    with open(PUBSPEC, "r", encoding="utf-8") as f:
        content = f.read()
    lines = content.splitlines(keepends=True)

    new_lines   = []
    enc_added   = "assets/enc/" in content

    for line in lines:
        stripped = line.strip()
        # Hapus baris assets/bin/ (SQLCipher lama — tidak boleh ada)
        if "assets/bin/" in line and stripped.startswith("-"):
            log(f"Hapus dari pubspec: {stripped}", "DEL")
            continue
        # Hapus SEMUA baris assets/data/ jika CI mode (termasuk subfoldernya)
        if remove_data_entries and "assets/data/" in line and stripped.startswith("-"):
            log(f"Hapus dari pubspec: {stripped}", "DEL")
            continue
        new_lines.append(line)

    # Pastikan assets/enc/ terdaftar (tambah setelah baris "assets:" flutter section)
    if not enc_added:
        for i, l in enumerate(new_lines):
            if l.strip() == "assets:" or ("assets:" in l and "# ──" not in l):
                new_lines.insert(i + 1, "    - assets/enc/\n")
                enc_added = True
                break
        if not enc_added:
            # Fallback: sisipkan sebelum assets/images/ atau assets/icons/
            for i, l in enumerate(new_lines):
                if "- assets/images/" in l or "- assets/icons/" in l:
                    new_lines.insert(i, "    - assets/enc/\n")
                    break

    with open(PUBSPEC, "w", encoding="utf-8") as f:
        f.writelines(new_lines)

    removed = len(lines) - len(new_lines)
    log(f"pubspec.yaml diperbarui: {removed} baris dihapus, assets/enc/ terdaftar")


def _cleanup_sensitive(root: Path, data_dir: Path):
    """Hapus semua file sensitif yang tidak boleh ada di APK."""
    # Hapus assets/data/ seluruhnya
    if data_dir.exists():
        shutil.rmtree(data_dir)
        log("assets/data/ dihapus", "DEL")

    # Hapus assets/bin/ seluruhnya (SQLCipher lama)
    bin_dir = root / "assets" / "bin"
    if bin_dir.exists():
        shutil.rmtree(bin_dir)
        log("assets/bin/ dihapus (SQLCipher lama)", "DEL")

    # Hapus file sensitif root
    sensitive_files = [
        "CLAUDE.md", "AUDIT_REPORT.md",
        ".env", ".env.local", ".env.production",
        "secrets.json", "keys.json",
    ]
    for fname in sensitive_files:
        fp = root / fname
        if fp.exists():
            fp.unlink()
            log(f"{fname} dihapus", "DEL")

    # Hapus scripts/ (build tools tidak perlu ada di APK)
    scripts_dir = root / "scripts"
    if scripts_dir.exists():
        shutil.rmtree(scripts_dir)
        log("scripts/ dihapus", "DEL")

    # Verifikasi: tidak boleh ada JSON mentah tersisa (kecuali theme)
    remaining_json = [
        str(p) for p in root.rglob("*.json")
        if ".git" not in str(p)
        and "assets/theme" not in str(p)
        and "assets/enc" not in str(p)
        and ".dart_tool" not in str(p)
    ]
    if remaining_json:
        log(f"⚠️  JSON tersisa ({len(remaining_json)} file): {remaining_json[:5]}", "WARN")
    else:
        log("Verifikasi: tidak ada JSON mentah tersisa di luar assets/enc/ ✓")

    # Verifikasi: encrypted files harus ada
    enc_count = len(list((root / "assets" / "enc").glob("*.bin"))) + \
                len(list((root / "assets" / "enc").glob("*.idx")))
    log(f"File terenkripsi tersedia: {enc_count}")


if __name__ == "__main__":
    main()
