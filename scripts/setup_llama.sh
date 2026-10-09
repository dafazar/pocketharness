#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# scripts/setup_llama.sh
# Pocket Harness — Setup llama.cpp source untuk native GGUF inference
#
# CARA PAKAI:
#   Lokal (Mac/Linux):
#     bash scripts/setup_llama.sh
#
#   CI (GitHub Actions):
#     - name: Setup llama.cpp
#       run: bash scripts/setup_llama.sh
#       env:
#         LLAMA_TAG: b5048          # opsional, default: b5048
#
# HASIL:
#   android/app/src/main/cpp/llama.cpp/   ← source llama.cpp
#   (hanya file yang dibutuhkan — ~30MB, bukan full repo ~200MB)
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Konfigurasi ────────────────────────────────────────────────────────────────
LLAMA_TAG="${LLAMA_TAG:-b8604}"
LLAMA_REPO="https://github.com/ggerganov/llama.cpp"
DEST="android/app/src/main/cpp/llama.cpp"
STAMP="${DEST}/.kanmongo_setup_tag"

# ── Warna terminal ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[setup_llama]${NC} $*"; }
warn()  { echo -e "${YELLOW}[setup_llama]${NC} $*"; }
error() { echo -e "${RED}[setup_llama] ERROR:${NC} $*" >&2; exit 1; }

# ── Check dependency ───────────────────────────────────────────────────────────
command -v git >/dev/null 2>&1 || error "git tidak ditemukan. Install: sudo apt install git"

# ── Cek apakah sudah setup dengan tag yang sama ───────────────────────────────
if [ -f "${STAMP}" ] && [ "$(cat ${STAMP})" = "${LLAMA_TAG}" ]; then
    info "llama.cpp ${LLAMA_TAG} sudah ada — skip download"
    info "Untuk re-download paksa: rm -rf ${DEST} && bash scripts/setup_llama.sh"
    exit 0
fi

# ── Clone sparse (hanya file yang dibutuhkan) ─────────────────────────────────
if [ -d "${DEST}" ]; then
    warn "Direktori ${DEST} ada tapi tag berbeda — hapus dan clone ulang"
    rm -rf "${DEST}"
fi

info "Memverifikasi tag ${LLAMA_TAG} di remote ..."

# ── Validasi tag: jika tidak ada, fallback ke tag terbaru ─────────────────────
TAG_EXISTS=$(git ls-remote --tags "${LLAMA_REPO}" "refs/tags/${LLAMA_TAG}" | wc -l)
if [ "${TAG_EXISTS}" -eq 0 ]; then
    warn "Tag '${LLAMA_TAG}' tidak ditemukan di remote — mencari tag terbaru ..."
    # Ambil tag terbaru yang cocok pola b#### (build number llama.cpp)
    LATEST_TAG=$(git ls-remote --tags "${LLAMA_REPO}" 'refs/tags/b[0-9]*' \
        | awk '{print $2}' \
        | sed 's|refs/tags/||' \
        | grep -E '^b[0-9]+$' \
        | sort -t'b' -k2 -n \
        | tail -1)
    if [ -z "${LATEST_TAG}" ]; then
        error "Tidak bisa menentukan tag terbaru llama.cpp. Periksa koneksi atau repo."
    fi
    warn "Fallback ke tag terbaru: ${LATEST_TAG}"
    LLAMA_TAG="${LATEST_TAG}"
fi

info "Clone llama.cpp ${LLAMA_TAG} (sparse) ..."
info "Repo: ${LLAMA_REPO}"
info "Dest: ${DEST}"

# Sparse clone: ambil hanya folder src/ggml/include, bukan examples/tests
git clone \
    --depth 1 \
    --branch "${LLAMA_TAG}" \
    --filter=blob:none \
    --sparse \
    "${LLAMA_REPO}" \
    "${DEST}"

cd "${DEST}"

# Aktifkan sparse-checkout (no-cone mode = support file + direktori di root)
# Cone mode (default Git baru) hanya support direktori — pakai no-cone agar
# CMakeLists.txt dan file root lain bisa di-include.
git sparse-checkout init --no-cone
git sparse-checkout set \
    "CMakeLists.txt" \
    "cmake/**" \
    "include/**" \
    "src/**" \
    "ggml/**" \
    "common/**" \
    "scripts/**"

info "Sparse checkout selesai"

# ── Verifikasi file penting ada ───────────────────────────────────────────────
cd - >/dev/null

REQUIRED_FILES=(
    "${DEST}/CMakeLists.txt"
    "${DEST}/include/llama.h"
    "${DEST}/ggml/include/ggml.h"
    "${DEST}/src/llama.cpp"
)

for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$f" ]; then
        error "File kritis tidak ditemukan: $f\nClone mungkin gagal atau struktur repo berubah."
    fi
done

# ── Tulis stamp (catat tag aktual yang digunakan) ──────────────────────────────
echo "${LLAMA_TAG}" > "${STAMP}"

info "✅ llama.cpp ${LLAMA_TAG} siap di: ${DEST}"
info ""
info "Sekarang build app:"
info "  flutter run --release"
info "  # atau di Android Studio: Build → Generate Signed APK"
