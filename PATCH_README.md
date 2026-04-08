# KanMon GO — Patch Notes: Offline AI Fix (V1 Architecture → V2)

## Masalah yang Diperbaiki

**V2 offline AI tidak merespons** — model "berpikir" terus tapi tidak ada output.

---

## Root Cause (5 Bug)

### Bug Dart (`offline_ai_service.dart`)
1. **EventChannel subscription dibuat ulang setiap `chatStream()` dipanggil** → gap null sink → token hilang → hang
2. **`_broadcastCtrl` di-recreate** setiap `_initEventChannel()` → siklus onCancel/onListen berulang
3. **`await for stream.timeout()`** dari `_broadcastCtrl` yang bisa di-recreate → stream lama invalid

### Bug Kotlin (`LlamaPlugin.kt`)
4. **EventSink di-null-kan saat `onCancel()`** meskipun generate sedang berjalan → token ke sink null → hilang
5. **`result.success()` dipanggil terlambat** → Dart blocking di `invokeMethod` → terlambat masuk `await for`

---

## Solusi yang Diterapkan

### `lib/data/services/offline_ai_service.dart` — MERGE (V1 arch + V2 classes)
- **Lines 1–408** (V2): Tetap dipertahankan — `AttachedFile`, `FileAttachmentProcessor`, `AttachmentKind`, `LlamaToken`, `ChatHistoryBuffer`, `ChatMessage` (dibutuhkan `chat_screen.dart`)
- **Lines 412–838** (V1): `OfflineAiService` class diganti dengan arsitektur V1 yang proven:
  - `chatStream()` pakai `StreamController` sederhana per-generate (tidak broadcast singleton)
  - Native ready check via `isModelReadySafe()` cross-check ke JNI
  - `flushInferenceBuffer()` setelah setiap sesi
  - Exception handling per kategori (OOM, INVALID, DESTROYED)
- **Lines 840–931** (V1): `_PromptFormat` enum + extension (5 format: chatMl, llama3, gemma, mistral, phi)
- **Lines 933–end** (V2): `ChatHistoryBuffer`, `ChatMessage` — tetap dipertahankan

### Method name alignment (Dart → Kotlin v2):
| Dart (lama/V1) | Dart (baru/fixed) | Kotlin V2 |
|---|---|---|
| `startGeneration` | `generate` | `"generate"` |
| `path` | `modelPath` | `call.argument("modelPath")` |
| `contextSize` | `nCtx` | `call.argument("nCtx")` |
| `numGpuLayers` | `nGpuLayers` | `call.argument("nGpuLayers")` |
| `isModelLoaded` | `isLoaded` | `"isLoaded"` |
| `getAvailableRam` | return 0 (removed) | (tidak ada di V2) |
| `maxTokens` | `maxNewTokens` | `call.argument("maxNewTokens")` |
| (none) | `topK: 40` | `call.argument("topK")` |
| (none) | `nKeep: 0` | `call.argument("nKeep")` |

### `android/app/src/main/kotlin/.../LlamaPlugin.kt` — V2 (ALREADY FIXED)
- EventSink **persistent** — tidak di-null saat `onCancel()` jika generate sedang berjalan
- `result.success(null)` dipanggil **SEBELUM** submit ke executor
- `LlamaForegroundService` — jaga inferensi dari Android LMK
- Semua ini sudah ada di V2, tidak ada perubahan

### File lain — TETAP V2 (tidak diubah):
- `llama_jni.cpp` — V2 fix: JNIEnv TLS, `done=true` selalu dikirim, timeout 30s
- `llama_stub.cpp` — V2 fix: stub kirim `done=true` agar Dart tidak hang
- `CMakeLists.txt` — V2 fix: `LLAMA_EXTERNAL_DIR` support untuk CI
- `android/app/build.gradle` — V2 fix: ccache, arm64-only, `LLAMA_EXTERNAL_DIR`
- `.github/workflows/build.yml` — V2 fix: NDK cache, SDK cache, timeout 90 min
- `AndroidManifest.xml` — V2 fix: ForegroundService permissions
- `pubspec.yaml` — V2 (archive, mime, path sudah ada)

---

## Build & Push

```bash
# 1. Push ke GitHub
git add .
git commit -m "fix: offline AI tidak merespons — merge V1 stream arch ke V2"
git push

# 2. Build di GitHub Actions
# Tab Actions → "🚀 Build KanMon GO" → Run workflow
# Target: apk-release-arm64 (default, paling cepat)
```

## GitHub Secrets yang Diperlukan (Settings → Secrets → Actions)
```
KEYSTORE_BASE64       # base64 dari .jks
KEY_STORE_PASSWORD    # password keystore
KEY_ALIAS             # alias key
KEY_PASSWORD          # password key
```
