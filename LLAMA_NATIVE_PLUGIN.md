# KanMon GO — Kotlin Native Plugin (llama.cpp JNI)

## Arsitektur

```
Flutter Dart
    │
    ├── MethodChannel "com.kanmongo.llama/engine"
    │       loadModel / loadModelWithParams / startGeneration / stopGeneration
    │       freeModel / isModelLoaded / getModelInfo / getTokensPerSecond
    │
    └── EventChannel "com.kanmongo.llama/stream"
            {"type":"token","text":"...","done":false}   ← per token
            {"type":"token","text":"","done":true}        ← selesai
            {"type":"error","code":"...","message":"..."}
            {"type":"progress","value":0.0..1.0}
                │
        LlamaPlugin.kt  (android/app/src/main/kotlin/)
            │  SingleThreadExecutor (background thread)
            │  Handler → main thread → EventSink
            │
        JNI (libkanmongo_llama.so)
            │
        android/app/src/main/cpp/
            ├── CMakeLists.txt
            ├── llama_jni.cpp       ← JNI bridge (Memory V2 API, b10350+)
            ├── llama_stub.cpp      ← stub jika llama.cpp tidak ada
            └── llama.cpp/          ← didownload oleh setup_llama.sh atau CI
```

## API JNI yang Tersedia

| Method Kotlin | Native C++ | Keterangan |
|---------------|-----------|-----------|
| `nativeLoadModel(path)` | `load_model_with_params()` | Load dengan default params |
| `nativeLoadModelWithParams(path, n_ctx, n_threads, n_gpu_layers, use_mmap, use_mlock)` | `load_model_with_params()` | Load dengan custom params |
| `nativeGenerate(prompt, n_keep, max_new_tokens, temp, top_p, top_k, repeat_penalty)` | `run_inference()` | Generate token streaming |
| `nativeCancel()` | `g_engine.cancel = true` | Stop generation |
| `nativeForceClear()` | `force_clear_engine()` | Free model + context |
| `nativeIsLoaded()` | `g_engine.is_loaded()` | Cek status model |
| `nativeSetEventSink(sink)` | — | Register EventChannel sink |
| `nativeGetModelInfo()` | — | JSON: name, nCtx, nLayers, tps, nCtxUsed |
| `nativeGetTokensPerSecond()` | `g_engine.last_tps` | Kecepatan inferensi |
| `nativeContextTokenCount()` | `g_engine.token_history.size()` | Token di KV cache |

## Memory V2 API (llama.cpp b10350+)

Sejak build error #104 (2026-04-05), `llama_jni.cpp` **hanya** menggunakan Memory V2 API.
API lama (`llama_kv_self_*`) telah dihapus dari llama.cpp dan **tidak boleh digunakan**.

```cpp
// ✅ Memory V2 API — GUNAKAN INI
llama_memory_clear(llama_get_memory(ctx), true);
llama_memory_seq_rm(llama_get_memory(ctx), seq_id, p0, p1);
llama_memory_seq_add(llama_get_memory(ctx), seq_id, p0, p1, delta);

// ❌ API Lama — SUDAH DIHAPUS dari llama.cpp b10350+
llama_kv_self_clear(ctx);           // REMOVED
llama_kv_self_seq_rm(ctx, ...);     // REMOVED
llama_kv_self_seq_add(ctx, ...);    // REMOVED
```

## InferenceParams Default

```cpp
int32_t n_ctx          = 2048;   // Context window
int32_t n_batch        = 512;    // Batch size
int32_t n_threads      = auto;   // CPU threads (hardware_concurrency - 2)
int32_t max_new_tokens = 1024;   // Max output tokens
float   temperature    = 0.7f;
float   top_p          = 0.9f;
int32_t top_k          = 40;
float   repeat_penalty = 1.1f;
int32_t n_gpu_layers   = 0;      // GPU offload layers (0 = CPU only)
bool    use_mmap       = true;   // KRITIS: lazy-load dari storage, hemat RAM
bool    use_mlock      = false;  // Jangan lock ke RAM (OOM pada device kecil)
```

## KV Cache Config

```cpp
cp.type_k = GGML_TYPE_Q4_0;  // Q4_0 hemat ~50% vs default F16
cp.type_v = GGML_TYPE_Q4_0;
```

## Foreground Service

`LlamaPlugin.kt` menjalankan inference di `LlamaForegroundService` dengan `PARTIAL_WAKE_LOCK`.
Ini memastikan proses berjalan di `oom_score_adj≈0` (foreground priority) sehingga tidak
dibunuh Android LMK selama inference panjang (30s+).

**Permissions di AndroidManifest.xml:**
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
```

## Setup Lokal (Pertama Kali)

```bash
# 1. Clone llama.cpp source
bash scripts/setup_llama.sh

# 2. Build dan run
flutter run --release
```

## CI (GitHub Actions)

Workflow `build.yml` sudah otomatis:
1. Install NDK 28.2.13676358
2. Install CMake 3.22.1 via sdkmanager
3. Clone llama.cpp (sparse checkout ~30MB)
4. `flutter pub get`
5. `flutter build apk --release --target-platform android-arm64`

## Chat Template Auto-Detection

Berdasarkan nama file model:
- `*llama*` / `*meta*` → Llama 3 template (`<|start_header_id|>`)
- `*gemma*` → Gemma template (`<start_of_turn>`)
- Lainnya → ChatML (`<|im_start|>`) — default untuk Mistral/Phi/Qwen/DeepSeek

## Model Recommendations

| Model | Size | RAM Min | Rating |
|-------|------|---------|--------|
| Qwen3 0.6B Q4_K_M | 430MB | 2GB | ⭐⭐⭐ Low-end |
| Gemma 3 1B .task | 650MB | 3GB | ⭐⭐⭐ |
| Qwen3 1.7B Q4_K_M | 1.1GB | 4GB | ⭐⭐⭐⭐ |
| Phi-4 Mini 3.8B Q4_K_M | 2.5GB | 6GB | ⭐⭐⭐⭐⭐ |
| Llama-3.2 3B Q4_K_M | 2.0GB | 5GB | ⭐⭐⭐⭐ |

## Troubleshooting

| Error | Solusi |
|-------|--------|
| `llama.h: No such file` | Jalankan `bash scripts/setup_llama.sh` |
| `llama_kv_self_*` undeclared | Cek `llama_jni.cpp` — harus pakai Memory V2 API |
| `libkanmongo_llama.so not found` | Pastikan `externalNativeBuild { cmake {...} }` di `build.gradle` |
| "Model belum loaded" | Panggil `OfflineAiService.instance.initActiveModel()` |
| RAM tidak cukup | Gunakan model lebih kecil (Q4_K_M 1B) atau tutup app lain |
| Output kacau / repetisi | Chat template tidak sesuai — cek nama file model |
| Token/s < 2 | Normal untuk 3B+ di mid-range. Gunakan Qwen3 0.6B |

## File Structure

```
android/app/src/main/
├── cpp/
│   ├── CMakeLists.txt       ← build config (CMake 3.22.1)
│   ├── llama_jni.cpp        ← JNI bridge (Memory V2 API only)
│   ├── llama_stub.cpp       ← stub fallback
│   └── llama.cpp/           ← source llama.cpp (gitignored)
└── kotlin/com/kanmongo/app/
    ├── MainActivity.kt
    └── LlamaPlugin.kt       ← Kotlin bridge + ForegroundService

lib/data/services/
└── offline_ai_service.dart  ← Dart API wrapper

scripts/
└── setup_llama.sh           ← clone llama.cpp source

.github/workflows/
└── build.yml                ← CI dengan llama.cpp auto-setup
```
