# CLAUDE.md — KanMon GO Project Guide (v3.0)
# Arsitektur PocketPal AI — Updated setelah migrasi Sesi 1–8

Panduan teknis untuk Claude saat bekerja di codebase KanMon GO Flutter.

---

## 🏗️ Arsitektur Proyek

| Aspek | Detail |
|-------|--------|
| Framework | Flutter (Dart) |
| State management | Riverpod (StateNotifier pattern) |
| Navigasi | GoRouter |
| Database konten | SQLite read-only asset (`assets/db/km_content.db`) |
| Database user | SQLite runtime (user progress, catatan, dll) |
| AI Native | llama.cpp JNI via `libkanmongo_llama.so` |
| AI Architecture | PocketPal AI style (LlamaService + LlamaContext + Riverpod providers) |
| Build CI/CD | GitHub Actions (`build.yml`) |
| Default tema | AMOLED Black + Red (`AppThemePack.original`) |

---

## 📁 Struktur Direktori Penting

```
lib/
  core/
    ai/
      llama_context.dart              ← Models: ChatMessage, InferenceConfig,
      │                                  LlamaModelConfig, ModelStatus, dll
      inference_params_provider.dart  ← Riverpod providers untuk AI state
      llama_isolate_manager.dart      ← Inference di Isolate terpisah (opsional)
      llama_status_provider.dart      ← Convenience providers untuk status (Sesi 8)
    theme/
      theme_provider.dart             ← ThemeNotifier + ThemePackNotifier + sharedPreferencesProvider
      app_theme.dart
      app_theme_service.dart
      km_colors.dart
      km_theme.dart
      # TIDAK ADA theme_providers.dart — sudah dihapus (legacy, penyebab bug #103)
  data/
    services/
      llama_service.dart              ← Core AI engine (singleton LlamaService)
      model_manager_service.dart      ← Download, scan, HuggingFace integration
      offline_ai_service.dart         ← BACKWARD COMPAT ALIAS ke LlamaService
      agent_service.dart              ← Multi-step agent dengan tool calling
      ai_service.dart                 ← Mode AI: offline/online/bulkApi
      puter_ai_service.dart           ← Puter.js API wrapper
      bulk_api_service.dart           ← Groq/Gemini/Claude/OpenRouter
      web_scraper_service.dart        ← HTML scraping
      tts_service.dart / edge_tts_service.dart
      file_processor_service.dart     ← Pemrosesan file attachment chat
      terminal_service.dart           ← Shell execution
  features/
    agent/presentation/screens/agent_screen.dart
    chat/chat_screen.dart
    settings/presentation/screens/
      offline_ai_screen.dart          ← Konfigurasi LlamaService + model loader
      ai_inference_params_screen.dart ← Parameter detail + preset + test (Sesi 8)
      model_manager_screen.dart
      settings_screen.dart
  shared/widgets/
    back_handler.dart                 ← ConfirmExitBack widget
    ai_source_picker.dart             ← Pilih sumber AI

android/app/src/main/
  cpp/
    llama_jni.cpp                     ← JNI bridge — Memory V2 API only (b10350+)
    llama_stub.cpp
    CMakeLists.txt
  kotlin/com/kanmongo/app/
    LlamaPlugin.kt                    ← Kotlin bridge + ForegroundService
    LlamaForegroundService.kt         ← Mencegah Android kill proses saat inferensi

assets/
  db/km_content.db                    ← SQLite content (~17MB, 76k+ rows)
  theme/original/                     ← PNG assets (1 pack saja)

.github/workflows/build.yml           ← GitHub Actions CI/CD
```

---

## 🔑 Pattern Kritis yang Harus Diikuti

### 1. LlamaService — Core AI Engine

`LlamaService` adalah singleton utama untuk semua inferensi AI offline.
**Selalu gunakan `LlamaService.instance`**, bukan buat instance baru.

```dart
// Cara pakai generateStream
final stream = LlamaService.instance.generateStream(
  messages: [
    ChatMessage.system('Kamu adalah asisten KanMon GO.'),
    ChatMessage.user(promptUser),
  ],
  config: ref.read(inferenceConfigProvider), // InferenceConfig dari provider
);
await for (final token in stream) {
  // proses token satu per satu
}

// Cek status sebelum generate
if (!LlamaService.instance.isModelLoaded) {
  // model belum dimuat
}

// Hentikan generasi
await LlamaService.instance.stopGeneration();

// Stream status (broadcast)
LlamaService.instance.statusStream   // Stream<ModelStatus>
LlamaService.instance.loadProgressStream  // Stream<double> 0.0–1.0
```

### 2. OfflineAiService — Backward Compatibility

`OfflineAiService` di `llama_service.dart` adalah alias class yang
meneruskan semua call ke `LlamaService.instance`. Ini ada hanya untuk
kompatibilitas kode lama. **Untuk kode baru, gunakan `LlamaService` langsung.**

```dart
// OfflineAiService.instance == LlamaService.instance (lewat alias)
// Hindari import offline_ai_service.dart untuk kode baru
```

### 3. Convenience Status Providers (Sesi 8)

Provider di `llama_status_provider.dart` untuk watch status dari widget mana saja:

```dart
// Di ConsumerWidget:
final isReady   = ref.watch(isLlamaReadyProvider);       // bool
final status    = ref.watch(llamaStatusProvider);         // AsyncValue<ModelStatus>
final label     = ref.watch(llamaStatusLabelProvider);    // String (Bahasa Indonesia)
final color     = ref.watch(llamaStatusColorProvider);    // Color
final progress  = ref.watch(llamaLoadProgressValueProvider); // double 0.0–1.0
final modelName = ref.watch(llamaModelNameProvider);      // String
final isGen     = ref.watch(isLlamaGeneratingProvider);   // bool
```

### 4. Theme System

```dart
// SELALU gunakan ini untuk warna UI:
final c = KmColors.of(context);

// Warna yang tersedia:
c.bg, c.card, c.surface, c.elevated
c.accent, c.accentSoft, c.gold
c.text, c.textSub, c.textMuted
c.border, c.borderSoft, c.divider
c.correct, c.wrong, c.warning, c.info

// JANGAN pernah import theme_providers.dart — sudah dihapus
```

### 5. Memory V2 API — llama_jni.cpp

File `llama_jni.cpp` **HANYA** menggunakan Memory V2 API (llama.cpp b10350+).
**Tidak boleh ada `#ifdef LLAMA_API_MEMORY_V2`** — hapus dual-branch legacy.

```cpp
// ✅ Benar — Memory V2 API
llama_memory_t mem = llama_get_memory(ctx);
llama_memory_clear(mem, true);
llama_memory_seq_rm(mem, 0, -1, -1);
llama_memory_seq_add(mem, 0, 0, n_past, delta);

// ❌ Salah — API lama (sudah dihapus dari llama.cpp b10350+)
// llama_kv_self_clear(ctx);
// llama_kv_self_seq_rm(ctx, 0, -1, -1);
```

### 6. Inference Config Providers

```dart
// Baca config saat ini
final config = ref.read(inferenceConfigProvider);

// Watch perubahan
final config = ref.watch(inferenceConfigProvider);

// Update via notifier
ref.read(inferenceConfigProvider.notifier).updateTemperature(0.8);
ref.read(inferenceConfigProvider.notifier).resetToDefaults();

// Provider lain yang tersedia:
inferenceConfigProvider      // InferenceConfig (sampling params)
modelConfigProvider          // LlamaModelConfig (GPU layers, context size, dll)
activeModelInfoProvider      // LlamaModelInfo? (model aktif)
systemPromptProvider         // String? (system prompt)
chatSessionProvider          // List<ChatMessage> (riwayat chat)
modelPerformanceProvider     // ModelPerformanceMetrics?
```

### 7. ForegroundService Android

`LlamaForegroundService` di Kotlin harus aktif saat inferensi berjalan
untuk mencegah Android membunuh proses. `LlamaService` mengelola ini
secara otomatis lewat `LlamaPlugin.kt`.

---

## 🧩 Daftar Screen & Navigasi

| Route | Screen | Keterangan |
|-------|--------|------------|
| `/` | SplashScreen | Splash + init |
| `/home` | HomeScreen | Dashboard utama |
| `/chat` | ChatScreen | Chat AI dengan file attachment |
| `/agent` | AgentScreen | Multi-step agent (tool calling) |
| `/settings` | SettingsScreen | Semua pengaturan |
| `/settings/offline-ai` | OfflineAiScreen | Konfigurasi LlamaService |
| `/settings/ai-params` | AiInferenceParamsScreen | Fine-tuning parameter (Sesi 8) |
| `/settings/model-manager` | ModelManagerScreen | Download & kelola model |
| `/settings/persona` | AiPersonaScreen | Persona & system prompt |
| `/settings/bulk-api` | BulkApiSettingsScreen | Groq/Gemini/Claude/OpenRouter |
| `/ebook` | EbookScreen | PDF/DOCX/PPTX viewer |
| `/ocr` | OcrScreen | Kamera + OCR |
| `/notes` | NotesScreen | Catatan |
| `/terminal` | TerminalScreen | Shell interaktif |
| `/media` | MediaCreatorScreen | Media creator |

---

## 🐛 Bug yang Pernah Diperbaiki

### Build Error #103 — theme_providers.dart (2026-04-05)

**Root cause:** `main.dart` import dua file yang sama-sama declare `themePackProvider`.

**Fix:**
1. Hapus `lib/core/theme/theme_providers.dart`
2. Pindah `sharedPreferencesProvider` ke `theme_provider.dart`
3. Hapus `import 'theme_providers.dart'` dari `main.dart`

### Build Error #104 — llama_jni.cpp (2026-04-05)

**Root cause:** llama.cpp b10350+ hapus API `llama_kv_self_*`. Code masih
pakai `#ifdef LLAMA_API_MEMORY_V2` dual-branch tapi macro tidak terdefinisi.

**Fix:** Hapus semua `#ifdef`/`#else`/`#endif` — gunakan Memory V2 API langsung.

### Build Error #23 — ebook_screen.dart (2025-03)

**Root cause:** Refactoring tidak lengkap — parenthesis `Scaffold` ditutup
terlalu awal di beberapa viewer class.

**Fix:** Setiap viewer: `ConfirmExitBack > child: Scaffold > appBar + body`

### Catatan Migrasi PocketPal (Sesi 1–8, 2026-04)

**Perubahan arsitektur besar:**
- `offline_ai_service.dart` (lama) → `llama_service.dart` (PocketPal pattern)
- Semua state AI pindah ke Riverpod providers di `inference_params_provider.dart`
- Backward compat dijaga via alias `class OfflineAiService` di `llama_service.dart`
- Memory management ditingkatkan: KV-cache cleanup otomatis saat ganti model
- ForegroundService ditambahkan untuk mencegah Android kill proses inferensi
- File attachment di chat diimplementasi: image, PDF, ZIP, text, media metadata
- Convenience providers ditambahkan di `llama_status_provider.dart`
- Screen `AiInferenceParamsScreen` ditambahkan untuk fine-tuning parameter

---

## 🔧 Build & CI/CD

### Secrets yang Diperlukan

| Secret | Keterangan |
|--------|-----------:|
| `KEYSTORE_BASE64` | Keystore JKS dalam format base64 |
| `KEY_STORE_PASSWORD` | Password keystore |
| `KEY_ALIAS` | Alias key (biasanya `kanmongo`) |
| `KEY_PASSWORD` | Password key |

### Error Build Umum

| Error | Kemungkinan Penyebab | Solusi |
|-------|---------------------|--------|
| `themePackProvider` ambiguous | Import dua file theme | Pastikan `theme_providers.dart` sudah dihapus |
| `llama_kv_self_*` undeclared | API lama di llama_jni.cpp | Ganti ke Memory V2 API |
| `Expected ';' after this` | Parenthesis tidak seimbang | Cek bracket Scaffold |
| `No named parameter 'body'` | `body` di luar Scaffold | Pastikan Scaffold belum ditutup |
| `llama.h: No such file` | llama.cpp belum di-clone | Jalankan `bash scripts/setup_llama.sh` |
| `LlamaService not found` | Import salah | Import dari `llama_service.dart` |
| `activeModelInfoProvider` not found | Import inference_params_provider hilang | Tambah import |

### Setup Awal

```bash
flutter pub get
bash scripts/setup_llama.sh   # clone/update llama.cpp header
flutter run
```

---

## 📦 Dependencies

```yaml
# State & Navigation
flutter_riverpod: ^2.5.1
riverpod_annotation: ^2.3.5
go_router: ^14.2.0

# Storage
shared_preferences: ^2.3.2
sqflite_sqlcipher: ^3.0.1+2
path: ^1.9.0
path_provider: ^2.1.4

# Firebase
firebase_core: ^3.6.0
firebase_auth: ^5.3.1
cloud_firestore: ^5.4.4
firebase_analytics: ^11.3.3
firebase_crashlytics: ^4.1.3
firebase_remote_config: ^5.1.3

# Auth
google_sign_in: ^6.2.1
crypto: ^3.0.3

# Membership
purchases_flutter: ^8.0.0

# Network
http: ^1.2.2
html: ^0.15.4
mime: ^2.0.0
share_plus: ^10.1.4
connectivity_plus: ^6.1.0

# UI & Animation
flutter_svg: ^2.0.10+1
cached_network_image: ^3.4.1
shimmer: ^3.0.0
lottie: ^3.1.2
fl_chart: ^0.69.0

# Media & Files
flutter_tts: ^4.2.0
audioplayers: ^6.1.0
file_picker: ^8.0.0+1
open_file: ^3.0.4
video_player: ^2.9.1
camera: ^0.11.0+2
photo_manager: ^3.3.0
saver_gallery: ^3.0.10
image_picker: ^1.1.2
speech_to_text: ^7.0.0

# OCR
google_mlkit_text_recognition: ^0.13.1

# Documents
syncfusion_flutter_pdfviewer: ^27.1.48
archive: ^4.0.0
xml: ^6.5.0

# Utils
intl: ^0.19.0
collection: ^1.18.0
uuid: ^4.5.0
permission_handler: ^11.3.1
iconsax: ^0.0.8

# AI Architecture (PocketPal — ditambahkan Sesi 1)
freezed_annotation: ^2.4.1
hive: ^2.2.3
hive_flutter: ^1.1.0
flutter_markdown: ^0.7.3

# dev_dependencies
build_runner: ^2.4.12
riverpod_generator: ^2.4.3
json_serializable: ^6.8.0
freezed: ^2.5.2
hive_generator: ^2.0.1
```

---

## 💡 Tips untuk Claude

1. **Jangan import `theme_providers.dart`** — sudah dihapus (bug #103)
2. **Di `llama_jni.cpp`** — selalu pakai `llama_get_memory(ctx)` + `llama_memory_*`
3. **Database content** — gunakan `DatabaseService`, jangan akses SQLite langsung
4. **Tema** — gunakan `KmColors.of(context)` untuk semua warna UI
5. **AI Service baru** — `LlamaService.instance`, bukan `OfflineAiService` untuk kode baru
6. **Status AI** — gunakan convenience providers di `llama_status_provider.dart`
7. **Generate stream** — selalu tangani `onError` dan `onDone` pada subscription
8. **Sebelum generate** — cek `LlamaService.instance.isModelLoaded`
9. **`agent_screen.dart`** — gunakan `LlamaService.instance.loadModel(model)` bukan `OfflineAiService.instance.loadActiveModel()`

---

## 🗂️ Git & Repository

| Path | Status | Alasan |
|------|--------|--------|
| `assets/data/**` | ✅ Di-commit | Source JSON |
| `assets/db/km_content.db` | ❌ Di-ignore | Generated artifact |
| `android/app/src/main/cpp/llama/**` | ❌ Di-ignore | llama.cpp submodule |
| `build/` | ❌ Di-ignore | Build output |
