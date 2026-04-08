# ══════════════════════════════════════════════════════════════════════════════
# KanMon GO — Native llama.cpp Build
#
# CMake minimum: 3.22.1  ← tersedia via sdkmanager, TIDAK perlu CMake 3.31!
# NDK: 28.2.13676358     ← install via sdkmanager di CI
#
# CARA KERJA:
#   Jika llama.cpp/ ada  → build libkanmongo_llama.so dengan llama.cpp penuh
#   Jika llama.cpp/ tidak ada → build stub (app tetap jalan, GGUF nonaktif)
#
# SETUP LOKAL:
#   bash scripts/setup_llama.sh
#
# CI (GitHub Actions):
#   Otomatis — step "Setup llama.cpp" di workflow
# ══════════════════════════════════════════════════════════════════════════════

cmake_minimum_required(VERSION 3.22.1)
project(kanmongo_llama CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── Lokasi source llama.cpp ────────────────────────────────────────────────────
# Prioritas 1: LLAMA_EXTERNAL_DIR dari CI (build.gradle / env var)
# Prioritas 2: llama.cpp/ lokal (developer setup via setup_llama.sh)
if(DEFINED LLAMA_EXTERNAL_DIR AND NOT LLAMA_EXTERNAL_DIR STREQUAL "")
    set(LLAMA_SRC "${LLAMA_EXTERNAL_DIR}")
    message(STATUS "🦙 llama.cpp (external/CI): ${LLAMA_SRC}")
else()
    set(LLAMA_SRC "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp")
    message(STATUS "🦙 llama.cpp (local): ${LLAMA_SRC}")
endif()

# ══════════════════════════════════════════════════════════════════════════════
if(EXISTS "${LLAMA_SRC}/CMakeLists.txt")
# ══════════════════════════════════════════════════════════════════════════════

    message(STATUS "✅ llama.cpp found: ${LLAMA_SRC}")

    # Disable semua yang tidak kita perlukan (speed up build, kurangi dependency)
    set(LLAMA_BUILD_TESTS    OFF CACHE BOOL "" FORCE)
    set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(LLAMA_BUILD_SERVER   OFF CACHE BOOL "" FORCE)
    set(LLAMA_CURL           OFF CACHE BOOL "" FORCE)
    set(BUILD_SHARED_LIBS    OFF CACHE BOOL "" FORCE)
    set(GGML_NATIVE          OFF CACHE BOOL "" FORCE)
    set(GGML_OPENMP          OFF CACHE BOOL "" FORCE)
    set(GGML_BLAS            OFF CACHE BOOL "" FORCE)
    set(GGML_METAL           OFF CACHE BOOL "" FORCE)

    add_subdirectory(${LLAMA_SRC} llama_build EXCLUDE_FROM_ALL)

    add_library(kanmongo_llama SHARED llama_jni.cpp)

    # ── Auto-detect KV cache API name (berubah antar build llama.cpp) ─────────
    # Tier 1: llama_kv_self_clear      → b5000–b10xxx (API "kv_self" era)
    # Tier 2: llama_kv_cache_clear     → pre-b5000 (API lama)
    # Tier 3: llama_kv_self_seq_rm     → b3000–b5000 (fallback seq_rm era lama)
    # Tier 4: llama_memory_seq_rm      → b10xxx+ (API "memory" era terbaru)
    #          dipanggil (ctx, seq_id=-1, p0=-1, p1=-1) = clear all sequences
    #
    # CATATAN: file(STRINGS...) mencari REGEX sebagai substring di tiap baris.
    # Ini mendeteksi deklarasi fungsi, macro alias, maupun komentar yang mengandung nama tsb.
    file(STRINGS "${LLAMA_SRC}/include/llama.h" _llama_h_kv_self_clear
         REGEX "llama_kv_self_clear")
    file(STRINGS "${LLAMA_SRC}/include/llama.h" _llama_h_kv_cache_clear
         REGEX "llama_kv_cache_clear")
    file(STRINGS "${LLAMA_SRC}/include/llama.h" _llama_h_kv_self_seq_rm
         REGEX "llama_kv_self_seq_rm")
    file(STRINGS "${LLAMA_SRC}/include/llama.h" _llama_h_memory_seq_rm
         REGEX "llama_memory_seq_rm")

    if(_llama_h_kv_self_clear)
        message(STATUS "✅ KV cache API: llama_kv_self_clear (b5000–b10xxx)")
        target_compile_definitions(kanmongo_llama PRIVATE LLAMA_HAS_KV_SELF_CLEAR=1)
    elseif(_llama_h_kv_cache_clear)
        message(STATUS "ℹ️  KV cache API: llama_kv_cache_clear (pre-b5000)")
        target_compile_definitions(kanmongo_llama PRIVATE LLAMA_HAS_KV_CACHE_CLEAR=1)
    elseif(_llama_h_kv_self_seq_rm)
        message(STATUS "ℹ️  KV cache API: llama_kv_self_seq_rm fallback (b3000+)")
        target_compile_definitions(kanmongo_llama PRIVATE LLAMA_HAS_KV_SELF_SEQ_RM=1)
    elseif(_llama_h_memory_seq_rm)
        message(STATUS "ℹ️  KV cache API: llama_memory_seq_rm (b10xxx+ API baru)")
        target_compile_definitions(kanmongo_llama PRIVATE LLAMA_HAS_MEMORY_SEQ_RM=1)
    else()
        message(WARNING
            "⚠️  Tidak ada API KV cache yang dikenali di llama.h!\n"
            "   llama_jni.cpp akan pakai llama_memory_seq_rm sebagai last-resort fallback.\n"
            "   Jika build gagal, periksa llama.h versi ini secara manual.")
        # last-resort: coba llama_memory_seq_rm (API ter-baru)
        target_compile_definitions(kanmongo_llama PRIVATE LLAMA_HAS_MEMORY_SEQ_RM=1)
    endif()

    target_include_directories(kanmongo_llama PRIVATE
        ${LLAMA_SRC}/include
        ${LLAMA_SRC}/ggml/include
        ${LLAMA_SRC}/common
    )

    target_compile_options(kanmongo_llama PRIVATE
        -O3
        -DNDEBUG
        -ffast-math
        -fvisibility=hidden
        -Wall
        -Wno-unused-variable
        -Wno-unused-parameter
        -Wno-deprecated-declarations
    )

    target_link_libraries(kanmongo_llama
        PRIVATE
        llama
        android
        log
    )

    # Strip debug symbols di release → kurangi ukuran .so ~50%
    if(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "MinSizeRel")
        target_link_options(kanmongo_llama PRIVATE "LINKER:--strip-all")
    endif()

# ══════════════════════════════════════════════════════════════════════════════
else()
# ══════════════════════════════════════════════════════════════════════════════

    message(WARNING
        "\n⚠️  llama.cpp TIDAK ditemukan di: ${LLAMA_SRC}\n"
        "   → Building STUB: app tetap jalan, GGUF nonaktif\n"
        "   → Untuk aktifkan GGUF: jalankan  bash scripts/setup_llama.sh\n"
    )

    add_library(kanmongo_llama SHARED llama_stub.cpp)
    target_link_libraries(kanmongo_llama PRIVATE android log)

endif()
