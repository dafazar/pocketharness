#!/usr/bin/env python3
"""
KanMon GO — SQLite Database Builder  v2.0
==========================================
Membaca semua JSON dari assets/data/ dan menghasilkan assets/database/km_content.db

Cara pakai:
  python3 scripts/build_sqlite_db.py            # build normal
  python3 scripts/build_sqlite_db.py --force    # rebuild dari awal
  python3 scripts/build_sqlite_db.py --dry-run  # cek saja, tidak tulis

Output:
  assets/database/km_content.db  — SQLite database siap pakai di Flutter

PERUBAHAN v2.0:
  - Grammar  : assets/data/grammer/grammer_n{N}/
  - Kosakata : assets/data/kosakata/vocab_n{N}/
  - Partikel : assets/data/partikel/partikeln{N}/particles_n{N}.json
  - Soal     : scan rekursif assets/data/soal/** (jlpt/jft/soal kalimat/soalpartikel)
  - Writing  : assets/data/writing/kana/kvg_kana.json (deteksi unicode hiragana/katakana)
               assets/data/writing/kanji/kvg.json     (single merged file)
  - Schema   : tambah ex_hiragana, ex_romaji di tabel kanji
               tambah hiragana di tabel vocab_examples
  - Level    : normalisasi N5->n5 (uppercase -> lowercase)
"""

import sqlite3, json, sys, argparse, hashlib, re
from pathlib import Path

ROOT = Path(__file__).parent.parent
DATA = ROOT / "assets" / "data"
OUT  = ROOT / "assets" / "database" / "km_content.db"


def log(msg, level="INFO"):
    icons = {"INFO": "✅", "WARN": "⚠️ ", "ERR": "❌", "STEP": "🔧", "SKIP": "⏭️"}
    print(f"  {icons.get(level, '  ')} {msg}", flush=True)


def load_json(path):
    try:
        return json.loads(Path(path).read_text("utf-8"))
    except Exception as e:
        log(f"Skip {Path(path).name}: {e}", "WARN")
        return None


def norm_level(val, fallback):
    """Normalisasi level: 'N5' / 'JLPT_N5' / 'n5' -> 'n5'"""
    if not val:
        return fallback
    return str(val).lower().replace("jlpt_", "")


def build(force=False, dry_run=False):
    if not DATA.exists():
        log(f"assets/data/ tidak ditemukan di {DATA}", "ERR")
        sys.exit(1)

    if dry_run:
        log("DRY RUN — tidak ada file yang ditulis")

    if OUT.exists() and not force:
        db_hash = hashlib.md5(OUT.read_bytes()).hexdigest()[:8]
        log(f"km_content.db sudah ada (md5:{db_hash}). Gunakan --force untuk rebuild.")
        return

    if dry_run:
        log("Dry run selesai — database tidak di-generate")
        return

    OUT.parent.mkdir(parents=True, exist_ok=True)
    if OUT.exists():
        OUT.unlink()

    conn = sqlite3.connect(str(OUT))
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA page_size=4096")
    c = conn.cursor()

    # ── SCHEMA ──────────────────────────────────────────────────────────────
    log("Membuat schema...", "STEP")
    c.executescript("""
    CREATE TABLE kana (
      id INTEGER PRIMARY KEY, char TEXT NOT NULL, romaji TEXT NOT NULL,
      type TEXT NOT NULL, grp TEXT NOT NULL
    );
    CREATE INDEX idx_kana_type ON kana(type);

    CREATE TABLE kanji (
      id INTEGER PRIMARY KEY, kanji TEXT NOT NULL,
      onyomi_hira TEXT, onyomi_romaji TEXT,
      kunyomi_hira TEXT, kunyomi_romaji TEXT,
      ex_japanese TEXT, ex_indonesian TEXT,
      ex_hiragana TEXT, ex_romaji TEXT,
      story TEXT, level TEXT NOT NULL
    );
    CREATE INDEX idx_kanji_level ON kanji(level);

    CREATE TABLE kanji_vocab (
      id INTEGER PRIMARY KEY, kanji_id INTEGER NOT NULL,
      word TEXT, reading TEXT, meaning TEXT
    );
    CREATE INDEX idx_kv_kanji ON kanji_vocab(kanji_id);

    CREATE TABLE vocab (
      id INTEGER PRIMARY KEY, word TEXT NOT NULL, kana TEXT, meaning TEXT,
      level TEXT NOT NULL, category TEXT, tag TEXT
    );
    CREATE INDEX idx_vocab_level ON vocab(level);

    CREATE TABLE vocab_examples (
      id INTEGER PRIMARY KEY, vocab_id INTEGER NOT NULL,
      japanese TEXT, hiragana TEXT, romaji TEXT, meaning TEXT
    );
    CREATE INDEX idx_ve_vocab ON vocab_examples(vocab_id);

    CREATE TABLE grammar (
      id INTEGER PRIMARY KEY, title TEXT NOT NULL, formula TEXT,
      explanation TEXT, level TEXT NOT NULL
    );
    CREATE INDEX idx_grammar_level ON grammar(level);

    CREATE TABLE grammar_examples (
      id INTEGER PRIMARY KEY, grammar_id INTEGER NOT NULL,
      japanese TEXT, romaji TEXT, meaning TEXT
    );
    CREATE INDEX idx_ge_grammar ON grammar_examples(grammar_id);

    CREATE TABLE partikel (
      id INTEGER PRIMARY KEY, char TEXT NOT NULL, usage TEXT,
      explanation TEXT, example TEXT, level TEXT NOT NULL
    );
    CREATE INDEX idx_partikel_level ON partikel(level);

    CREATE TABLE partikel_examples (
      id INTEGER PRIMARY KEY, partikel_id INTEGER NOT NULL,
      japanese TEXT, romaji TEXT, meaning TEXT
    );
    CREATE INDEX idx_pe_partikel ON partikel_examples(partikel_id);

    CREATE TABLE quiz (
      id INTEGER PRIMARY KEY, question TEXT NOT NULL, kana TEXT, romaji TEXT,
      options TEXT NOT NULL, correct INTEGER NOT NULL, type TEXT NOT NULL,
      input_type TEXT, explanation TEXT, section TEXT, type_name TEXT,
      source_level TEXT DEFAULT '', file_stem TEXT DEFAULT '',
      quiz_type TEXT DEFAULT '',
      japanese_text TEXT DEFAULT '',
      meaning_text TEXT DEFAULT '',
      correct_answers TEXT DEFAULT '[]',
      if_correct TEXT DEFAULT '',
      if_wrong TEXT DEFAULT '',
      hiragana_text TEXT DEFAULT '',
      passage TEXT DEFAULT ''
    );
    CREATE INDEX idx_quiz_type ON quiz(type);
    CREATE INDEX idx_quiz_stem ON quiz(file_stem);
    CREATE INDEX idx_quiz_quiz_type ON quiz(quiz_type);

    CREATE TABLE writing_kana (
      id INTEGER PRIMARY KEY, char TEXT NOT NULL UNIQUE,
      type TEXT NOT NULL, svg_data TEXT NOT NULL
    );
    CREATE INDEX idx_wk_type ON writing_kana(type);

    CREATE TABLE writing_kanji (
      id INTEGER PRIMARY KEY, char TEXT NOT NULL UNIQUE,
      strokes TEXT NOT NULL, coords TEXT NOT NULL
    );
    """)
    conn.commit()

    # ── KANA ────────────────────────────────────────────────────────────────
    log("Importing kana...", "STEP")
    cnt = 0
    for ktype in ["hiragana", "katakana"]:
        kdir = DATA / "kana" / ktype
        for jf in sorted(kdir.glob("*.json")):
            if jf.name == "manifest.json": continue
            items = load_json(jf)
            if not isinstance(items, list): continue
            for item in items:
                c.execute("INSERT INTO kana(char,romaji,type,grp) VALUES(?,?,?,?)",
                    (item.get("char",""), item.get("romaji",""), ktype, item.get("group","")))
                cnt += 1
    conn.commit()
    log(f"Kana: {cnt} rows")

    # ── KANJI ────────────────────────────────────────────────────────────────
    # Path: assets/data/kanji/kanjin{N}/*.json
    log("Importing kanji...", "STEP")
    cnt = 0
    for n in range(1, 6):
        level = f"n{n}"
        for jf in sorted((DATA / "kanji" / f"kanjin{n}").glob("*.json")):
            if jf.name == "manifest.json": continue
            items = load_json(jf)
            if not isinstance(items, list): continue
            for item in items:
                ony  = item.get("onyomi", {}) or {}
                kuny = item.get("kunyomi", {}) or {}
                ex   = item.get("example_sentence", {}) or {}
                c.execute("""INSERT INTO kanji
                    (kanji,onyomi_hira,onyomi_romaji,kunyomi_hira,kunyomi_romaji,
                     ex_japanese,ex_indonesian,ex_hiragana,ex_romaji,story,level)
                    VALUES(?,?,?,?,?,?,?,?,?,?,?)""",
                    (item.get("kanji",""),
                     ony.get("hiragana",""), ony.get("romaji",""),
                     kuny.get("hiragana",""), kuny.get("romaji",""),
                     ex.get("japanese",""),
                     ex.get("indonesian", ex.get("meaning","")),
                     ex.get("hiragana",""),
                     ex.get("romaji",""),
                     item.get("story",""), level))
                kid = c.lastrowid
                for v in (item.get("vocabulary") or []):
                    c.execute("INSERT INTO kanji_vocab(kanji_id,word,reading,meaning) VALUES(?,?,?,?)",
                        (kid, v.get("word",""), v.get("reading",""), v.get("meaning","")))
                cnt += 1
    conn.commit()
    log(f"Kanji: {cnt} rows")

    # ── VOCAB / KOSAKATA ─────────────────────────────────────────────────────
    # Path: assets/data/kosakata/vocab_n{N}/*.json
    log("Importing vocab...", "STEP")
    cnt = 0
    for n in range(1, 6):
        level = f"n{n}"
        for jf in sorted((DATA / "kosakata" / f"vocab_n{n}").glob("*.json")):
            if jf.name == "manifest.json": continue
            items = load_json(jf)
            if not isinstance(items, list): continue
            for item in items:
                lv = norm_level(item.get("level"), level)
                c.execute("INSERT INTO vocab(word,kana,meaning,level,category,tag) VALUES(?,?,?,?,?,?)",
                    (item.get("word",""), item.get("kana",""), item.get("meaning",""),
                     lv, item.get("category",""), item.get("tag","")))
                vid = c.lastrowid
                for ex in (item.get("examples") or []):
                    c.execute("INSERT INTO vocab_examples(vocab_id,japanese,hiragana,romaji,meaning) VALUES(?,?,?,?,?)",
                        (vid, ex.get("japanese",""), ex.get("hiragana",""),
                         ex.get("romaji",""), ex.get("meaning","")))
                cnt += 1
    conn.commit()
    log(f"Vocab: {cnt} rows")

    # ── GRAMMAR / BUNPOU ─────────────────────────────────────────────────────
    # Path: assets/data/grammer/grammer_n{N}/*.json
    log("Importing grammar...", "STEP")
    cnt = 0
    for n in range(1, 6):
        level = f"n{n}"
        for jf in sorted((DATA / "grammer" / f"grammer_n{n}").glob("*.json")):
            if jf.name == "manifest.json": continue
            items = load_json(jf)
            if not isinstance(items, list): continue
            for item in items:
                lv = norm_level(item.get("level"), level)
                c.execute("INSERT INTO grammar(title,formula,explanation,level) VALUES(?,?,?,?)",
                    (item.get("title",""), item.get("formula",""),
                     item.get("explanation",""), lv))
                gid = c.lastrowid
                for ex in (item.get("examples") or []):
                    c.execute("INSERT INTO grammar_examples(grammar_id,japanese,romaji,meaning) VALUES(?,?,?,?)",
                        (gid, ex.get("japanese",""), ex.get("romaji",""), ex.get("meaning","")))
                cnt += 1
    conn.commit()
    log(f"Grammar: {cnt} rows")

    # ── PARTIKEL ─────────────────────────────────────────────────────────────
    # Path: assets/data/partikel/partikeln{N}/*.json
    log("Importing partikel...", "STEP")
    cnt = 0
    for n in range(1, 6):
        level = f"n{n}"
        for jf in sorted((DATA / "partikel" / f"partikeln{n}").glob("*.json")):
            if jf.name == "manifest.json": continue
            items = load_json(jf)
            if not isinstance(items, list): continue
            for item in items:
                lv = norm_level(item.get("level"), level)
                c.execute("INSERT INTO partikel(char,usage,explanation,example,level) VALUES(?,?,?,?,?)",
                    (item.get("char",""), item.get("usage",""), item.get("explanation",""),
                     item.get("example",""), lv))
                pid = c.lastrowid
                for ex in (item.get("examples") or []):
                    c.execute("INSERT INTO partikel_examples(partikel_id,japanese,romaji,meaning) VALUES(?,?,?,?)",
                        (pid, ex.get("japanese",""), ex.get("romaji",""), ex.get("meaning","")))
                cnt += 1
    conn.commit()
    log(f"Partikel: {cnt} rows")

    # ── QUIZ / SOAL ───────────────────────────────────────────────────────────
    # Struktur: assets/data/soal/**/*.json (rekursif, multi-level subdirektori)
    #   soal/jlpt/jlptn{N}/jlptn{N}_1.json
    #   soal/jft/jft_{level}/jft_{level}_1.json
    #   soal/soal kalimat/n{N}/soal_kalimat_n{N}.json
    #   soal/soalpartikel/n{N}/soal_partikel_n{N}.json
    log("Importing quiz...", "STEP")
    cnt = 0
    soal_root = DATA / "soal"
    all_soal = sorted([jf for jf in soal_root.rglob("*.json") if jf.name != "manifest.json"])
    log(f"  Ditemukan {len(all_soal)} file soal")
    for jf in all_soal:
        stem  = jf.stem
        items = load_json(jf)
        if not isinstance(items, list): continue
        m = re.search(r"n(\d)", stem.lower())
        src_level = f"n{m.group(1)}" if m else "general"
        for item in items:
            # Format baru JLPT: field 'question' + 'answer'
            # Format lama (tatabahasa/kosakata/partikel): field 'q' + 'correct'
            question_val    = (item.get("question") or item.get("q") or "")
            correct_val     = item.get("answer") if item.get("answer") is not None else item.get("correct", 0)
            passage_val     = item.get("passage") or ""
            kana_val        = (item.get("kana") or item.get("japanese") or item.get("particle") or "")
            romaji_val      = (item.get("romaji") or item.get("q_romaji") or "")
            input_type_val  = item.get("inputType", "CHOICE")
            correct_answers = item.get("correctAnswers") or []
            if input_type_val.upper() == "ESSAY":
                opts = correct_answers if correct_answers else (item.get("options") or [])
            else:
                opts = item.get("options") or correct_answers or []
            quiz_type_val   = item.get("quiz_type", "")
            japanese_val    = item.get("japanese", "")
            meaning_val     = item.get("meaning", "")
            hiragana_val    = item.get("hiragana", "")
            if_correct_val  = item.get("if correct", item.get("if_correct", ""))
            if_wrong_val    = item.get("if wrong", item.get("if_wrong", ""))

            # ── Defensive type coercion ──────────────────────────────────────
            # SQLite binding tidak mendukung list/dict/None untuk kolom scalar.
            # Jika correct_val adalah list → ambil index 0 jika ada, fallback 0.
            if isinstance(correct_val, list):
                correct_val = correct_val[0] if correct_val else 0
            elif isinstance(correct_val, dict):
                correct_val = 0
            # Pastikan semua string field benar-benar string
            explanation_val = item.get("explanation", "")
            if not isinstance(explanation_val, str):
                explanation_val = str(explanation_val) if explanation_val is not None else ""
            passage_val     = str(passage_val)   if passage_val   is not None else ""
            kana_val        = str(kana_val)       if kana_val      is not None else ""
            romaji_val      = str(romaji_val)     if romaji_val    is not None else ""
            japanese_val    = str(japanese_val)   if japanese_val  is not None else ""
            meaning_val     = str(meaning_val)    if meaning_val   is not None else ""
            hiragana_val    = str(hiragana_val)   if hiragana_val  is not None else ""
            if_correct_val  = str(if_correct_val) if if_correct_val is not None else ""
            if_wrong_val    = str(if_wrong_val)   if if_wrong_val  is not None else ""
            quiz_type_val   = str(quiz_type_val)  if quiz_type_val is not None else ""
            # ─────────────────────────────────────────────────────────────────

            c.execute("""INSERT INTO quiz
                (question,kana,romaji,options,correct,type,
                 input_type,explanation,section,type_name,source_level,file_stem,
                 quiz_type,japanese_text,meaning_text,correct_answers,
                 if_correct,if_wrong,hiragana_text,passage)
                VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (question_val, kana_val, romaji_val,
                 json.dumps(opts, ensure_ascii=False),
                 correct_val, item.get("type",""),
                 input_type_val, explanation_val,
                 item.get("section",""), item.get("type_name",""),
                 src_level, stem,
                 quiz_type_val, japanese_val, meaning_val,
                 json.dumps(correct_answers, ensure_ascii=False),
                 if_correct_val, if_wrong_val, hiragana_val, passage_val))
            cnt += 1
    conn.commit()
    log(f"Quiz: {cnt} rows")

    # ── WRITING KANA ──────────────────────────────────────────────────────────
    # assets/data/writing/kana/kvg_kana.json
    # Format dict: {"あ": {"s":[...],"n":[...]}, "ア": {...}, ...}
    # Deteksi tipe via Unicode range:
    #   Hiragana U+3041–U+309F  |  Katakana U+30A0–U+30FF
    log("Importing writing kana...", "STEP")
    cnt = 0
    kana_file = DATA / "writing" / "kana" / "kvg_kana.json"
    if kana_file.exists():
        kana_data = load_json(kana_file)
        if isinstance(kana_data, dict):
            for char, val in kana_data.items():
                if not char: continue
                cp = ord(char[0])
                if 0x3041 <= cp <= 0x309F:
                    ktype = "hiragana"
                elif 0x30A0 <= cp <= 0x30FF:
                    ktype = "katakana"
                else:
                    ktype = "hiragana"
                svg = json.dumps(val, ensure_ascii=False) if isinstance(val, dict) else str(val)
                try:
                    c.execute("INSERT OR IGNORE INTO writing_kana(char,type,svg_data) VALUES(?,?,?)",
                        (char, ktype, svg))
                    cnt += 1
                except Exception as e:
                    log(f"Skip kana '{char}': {e}", "WARN")
    conn.commit()
    log(f"Writing kana: {cnt} rows")

    # ── WRITING KANJI ─────────────────────────────────────────────────────────
    # assets/data/writing/kanji/kvg.json  (single merged file, kanji murni)
    # Format dict: {"一": {"s":[...],"n":[...]}, ...}
    log("Importing writing kanji (KVG)...", "STEP")
    cnt = 0
    kvg_file = DATA / "writing" / "kanji" / "kvg.json"
    if kvg_file.exists():
        kvg_data = load_json(kvg_file)
        if isinstance(kvg_data, dict):
            for char, val in kvg_data.items():
                try:
                    c.execute("INSERT OR IGNORE INTO writing_kanji(char,strokes,coords) VALUES(?,?,?)",
                        (char,
                         json.dumps(val.get("s",[]), ensure_ascii=False),
                         json.dumps(val.get("n",[]), ensure_ascii=False)))
                    cnt += 1
                except Exception as e:
                    log(f"Skip kanji '{char}': {e}", "WARN")
    conn.commit()
    log(f"Writing kanji: {cnt} rows")

    # ── FINALIZE ─────────────────────────────────────────────────────────────
    conn.execute("PRAGMA optimize")
    conn.execute("VACUUM")

    # ── VALIDASI AKHIR ───────────────────────────────────────────────────────
    print()
    print("🔍 Validasi hasil database:")
    checks = [
        ("kana",         "SELECT COUNT(*) FROM kana"),
        ("kanji",        "SELECT COUNT(*) FROM kanji"),
        ("vocab",        "SELECT COUNT(*) FROM vocab"),
        ("grammar",      "SELECT COUNT(*) FROM grammar"),
        ("partikel",     "SELECT COUNT(*) FROM partikel"),
        ("quiz",         "SELECT COUNT(*) FROM quiz"),
        ("writing_kana", "SELECT COUNT(*) FROM writing_kana"),
        ("writing_kanji","SELECT COUNT(*) FROM writing_kanji"),
    ]
    all_ok = True
    for name, sql in checks:
        cnt_val = conn.execute(sql).fetchone()[0]
        status = "✅" if cnt_val > 0 else "❌ KOSONG!"
        print(f"  {status} {name}: {cnt_val} rows")
        if cnt_val == 0 and name in ("kana", "writing_kana", "writing_kanji"):
            all_ok = False

    conn.close()

    size_mb = OUT.stat().st_size / 1_048_576
    print()
    log(f"Database selesai: {OUT.name}")
    log(f"Lokasi: {OUT}")
    log(f"Ukuran: {size_mb:.2f} MB")
    print()
    if all_ok:
        print("  ✅ Selesai! Commit assets/database/km_content.db ke repository.")
        print("  ✅ Tidak ada secrets / enkripsi yang diperlukan.")
    else:
        print("  ❌ WARNING: Ada tabel penting yang kosong! Periksa data sumber.")
        import sys; sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Build KanMon GO SQLite database v2")
    parser.add_argument("--force",   action="store_true", help="Rebuild dari awal")
    parser.add_argument("--dry-run", action="store_true", help="Cek saja, tidak tulis")
    args = parser.parse_args()
    build(force=args.force, dry_run=args.dry_run)
