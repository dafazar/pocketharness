# KanMon GO — Changelog

## v2.1.3 — C++ Native API Migration (2026-04-05)

### 🔧 Critical Fix — llama.cpp Memory V2 API

**Build error:** `llama_kv_self_clear`, `llama_kv_self_seq_rm`, `llama_kv_self_seq_add` — use of undeclared identifier

- **`llama_jni.cpp`** — Removed legacy `#ifdef LLAMA_API_MEMORY_V2` dual-branch. llama.cpp b10350+ fully removed the `llama_kv_self_*` API family. All KV cache ops now use Memory V2 exclusively:
  - `llama_kv_self_clear(ctx)` → `llama_memory_clear(llama_get_memory(ctx), true)`
  - `llama_kv_self_seq_rm(ctx, ...)` → `llama_memory_seq_rm(llama_get_memory(ctx), ...)`
  - `llama_kv_self_seq_add(ctx, ...)` → `llama_memory_seq_add(llama_get_memory(ctx), ...)`
- **`llama_jni.cpp`** — Removed all `#ifdef`/`#else`/`#endif` preprocessor blocks from `kv_cache_clear()` and sliding window eviction — single clean code path

---

## v2.1.2 — Theme Provider Conflict Fix (2026-04-05)

### 🔧 Critical Fix — Ambiguous Import Build Error

**Build error:** `'themePackProvider' is imported from both 'theme_provider.dart' and 'theme_providers.dart'`

- **`lib/core/theme/theme_providers.dart`** — **Deleted.** Legacy file from old `KmThemePack` architecture conflicting with current `AppThemePack` system.
- **`lib/core/theme/theme_provider.dart`** — Added `sharedPreferencesProvider` (was only in deleted file).
- **`lib/main.dart`** — Removed `import 'package:kanmongo/core/theme/theme_providers.dart'`.

---

## v2.1.1 — BulkAPI & AI Source Picker (2026-04)

### 🆕 Fitur Baru
- **Bulk API** — Groq, Gemini, Anthropic Claude, OpenRouter, OpenAI-compatible (LM Studio, Ollama)
- **`AiSourcePicker`** — Widget pilih sumber AI di ChatScreen & AgentScreen
- **`BulkApiSettingsScreen`** — Pengaturan API key per provider + model selector

---

## v2.1.0 — Memory-Stable LLM Architecture (2026-04-04)

### 🔧 Critical Fixes — LLM Engine (OOM / Force Close)
- **`llama_jni.cpp`** — `use_mmap=true` + `use_mlock=false`: lazy-load dari storage, eliminasi OOM saat load
- **`llama_jni.cpp`** — Sliding KV-cache window (n_ctx=2048) dengan Memory V2 API: O(1) memory usage
- **`llama_jni.cpp`** — KV cache `GGML_TYPE_Q4_0`: ~50% hemat RAM vs Q8_0
- **`llama_jni.cpp`** — FIX-1~11: InferenceParams, n_past tracking, EventSink thread-safety, error JSON, progress callback, nativeLoadModelWithParams, nativeGetModelInfo, nativeGetTokensPerSecond, warmup, extended params
- **`LlamaPlugin.kt`** — `LlamaForegroundService` + `PARTIAL_WAKE_LOCK`: inference di `oom_score_adj≈0`
- **`LlamaPlugin.kt`** — 5-menit auto-release saat background, `onTrimMemory(RUNNING_CRITICAL)` handler
- **`offline_ai_service.dart`** — `AppLifecycleObserver`, `StringBuffer` streaming, timeout 120s
- **`chat_screen.dart`** — `StateNotifier`-owned subscription, `ListView.builder`

---

## v2.0.0 — Premium Edition (2026)

### 🆕 Fitur Baru
- AI Tutor, OCR Scan, Reader, Skill Tree, Analytics, FSRS-5
- Firebase: Auth, Firestore, Remote Config, Crashlytics
- Membership/Premium via RevenueCat

---

## v1.0.0 — Initial Release

- Kana, Kanji N5-N1, Kosakata, Grammar, Partikel
- Quiz JLPT & JFT, Flashcard, Writing stroke order
- Notes, E-Book, Mensetsu
