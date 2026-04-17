---
name: kanmongo-feature-dev
description: >
  Gunakan skill ini untuk SEMUA tugas edit, tambah fitur, debug, atau refactor
  di project KanMon GO (Flutter). Trigger ketika user menyebut: kanmongo,
  kanmon go, tambah fitur, edit screen, buat screen baru, perbaiki bug,
  LlamaService, chat screen, agent screen, riverpod provider, GoRouter,
  KmColors, ai_service, database_service, history_service, ChatMessage,
  ChatSession, InferenceConfig, llama_jni, NativeToolsManager, ToolsService,
  ClaudeCodeService, CodeServerService, tools dashboard, atau nama file
  apapun dari project. WAJIB dibaca sebelum menyentuh satu baris kode pun.
compatibility:
  tools: [bash_tool, create_file, str_replace, view]
  flutter: ">=3.0, sdk >=3.0.0 <4.0.0"
  state_management: Riverpod 2.x (StateNotifier)
  navigation: GoRouter 14.x
  package: kanmongo
  appId: com.kanmongo.app
  version: "2.1.0+2"
---

# KanMon GO — Skill Pengembangan Fitur (Super Komprehensif)

## ⚡ Prinsip Hemat Token
1. **Skill ini = pengganti analisa ulang** — jangan `view` file yang sudah terdokumentasi di sini
2. **Gunakan `view_range`** — baca hanya baris yang relevan, bukan seluruh file
3. **Selalu `str_replace`** — edit parsial, bukan tulis ulang file
4. **Diagnosis sekali** — baca error → cocokkan tabel bug → fix tepat sasaran

---

## 🏗️ Arsitektur Inti

| Aspek | Detail |
|-------|--------|
| Package | `kanmongo` |
| App ID | `com.kanmongo.app` |
| State | Riverpod 2.x (`StateNotifier` pattern) |
| Nav | GoRouter 14.x (`lib/core/router/app_router.dart`) |
| DB Konten | SQLite read-only asset (`assets/database/km_content.db`) |
| DB User | SQLite runtime `kanmongo_user.db` via `DatabaseService` (terenkripsi) |
| Chat History | SQLite via `HistoryService` + Hive boxes (chat_history, model_cache, ai_settings) |
| AI Native | llama.cpp JNI → `libkanmongo_llama.so` via `MethodChannel` |
| AI Arsitektur | PocketPal style: `LlamaService` + Riverpod providers |
| AI Mode | Offline (llama.cpp) / Online (Puter.js) / BulkApi (Groq/Gemini/Claude/OpenRouter) |
| Tema | 4 pack: AMOLED(default), Dark, Light, Sakura. Warna via `KmColors.of(context)` |
| Auth | Firebase Auth + Google Sign-In |
| CI/CD | GitHub Actions `.github/workflows/build.yml` |
| Android | compileSdk 36, minSdk 23, targetSdk 36, NDK 28.2.13676358 |

---

## 🛠️ Arsitektur Tools Native (CLI Layer)

```
ToolsService                    ← Extract APK tarball → internal storage, chmod
NativeToolsManager              ← Registry 35+ tools, health check, run shortcut
ClaudeCodeInstaller             ← Setup wizard: verify bundle + write settings.json
ClaudeCodeService               ← Lifecycle Claude Code CLI process (stdio streaming)
CodeServerService               ← Lifecycle code-server (VS Code) process + WebView
FirstSetupService               ← Background init saat app pertama dibuka
```

### Urutan Init CLI Tools (KRITIS)
```
main.dart unawaited(FirstSetupService.instance.runIfNeeded())
  └→ ToolsService.instance.initialize()
       ├→ Load manifest dari assets/tools/tools_manifest.json
       ├→ Extract tools_<abi>.tar.gz → <appSupport>/tools/
       ├→ chmod via NativeEnvPlugin (Java File.setExecutable) — WAJIB
       └→ Set _isReady = true
           └→ NativeToolsManager.instance.presentTools → tersedia otomatis
```

### Aturan Kritis Tools
- **JANGAN** buat `lib/core/tools/code_server_service.dart` atau `lib/core/tools/claude_code_service.dart` — file stub ini sudah **DIHAPUS**. Versi lengkap ada di `lib/data/services/`
- Import `ClaudeCodeService` → `lib/data/services/claude_code_service.dart`
- Import `CodeServerService` → `lib/data/services/code_server_service.dart`
- Import `NativeToolsManager` → `lib/core/tools/native_tools_manager.dart`
- `ToolsService.instance.isReady` cek SELALU sebelum akses tools, dan await `initialize()` jika belum ready

---

## 📁 Peta File Lengkap

```
lib/
├── main.dart                          ← Entry + init semua service (urutan kritis)
├── firebase_options.dart
├── core/
│   ├── ai/
│   │   ├── llama_context.dart         ← Models: ChatMessage(llama), InferenceConfig,
│   │   │                                 LlamaModelConfig, LlamaModelInfo, ModelStatus
│   │   ├── inference_params_provider.dart ← SEMUA Riverpod provider AI + export chatSessionProvider
│   │   ├── llama_status_provider.dart ← Convenience providers (isLlamaReadyProvider, dll)
│   │   ├── llama_isolate_manager.dart ← Inference di Isolate terpisah
│   │   ├── intelligence_amplifier.dart
│   │   ├── claude_grade_system_prompt.dart
│   │   └── native_event_dispatcher.dart
│   ├── router/app_router.dart         ← KmRoutes constants + GoRouter config
│   ├── theme/
│   │   ├── theme_provider.dart
│   │   ├── km_colors.dart
│   │   ├── app_theme.dart
│   │   ├── app_theme_service.dart
│   │   └── km_theme.dart
│   ├── auth/auth_service.dart
│   ├── config/remote_config_service.dart
│   ├── lifecycle/app_lifecycle_service.dart
│   ├── membership/membership_service.dart + premium_gate.dart
│   ├── network/connectivity_service.dart
│   ├── security/crypto_service.dart + secure_db_key_service.dart
│   ├── sync/sync_service.dart
│   ├── constants/app_constants.dart
│   ├── inference_manager.dart
│   └── tools/
│       ├── tools_service.dart         ← ⭐ Extract APK tarball, chmod, path getters
│       ├── tools_provider.dart        ← Riverpod: toolsServiceProvider, toolsReadyProvider,
│       │                                 toolsManifestProvider, nativeToolsManagerProvider,
│       │                                 toolsQuickReadyProvider
│       ├── native_tools_manager.dart  ← ⭐ Registry 35+ CLI tools, health check, run shortcut
│       └── preload_prompt.dart
├── data/
│   ├── models/ ...
│   └── services/
│       ├── llama_service.dart         ← ⭐ Core AI engine (SINGLETON utama)
│       ├── ai_service.dart
│       ├── claude_code_service.dart   ← ⭐ Claude Code CLI process manager (FULL version)
│       ├── claude_code_installer.dart ← Setup wizard: verify bundle + write settings.json
│       ├── code_server_service.dart   ← ⭐ VS Code (code-server) process manager (FULL version)
│       ├── history_service.dart
│       ├── database_service.dart
│       ├── agent_service.dart
│       ├── first_setup_service.dart   ← Background init CLI tools saat app pertama buka
│       └── ... (services lain)
├── features/
│   ├── claude_code/claude_code_screen.dart    ← ClaudeCodeTerminalScreen
│   ├── vscode/vscode_screen.dart              ← VscodeScreen (WebView + code-server)
│   ├── tools/tools_dashboard_screen.dart      ← ⭐ NEW: Status & health semua CLI tools
│   ├── terminal/presentation/screens/terminal_screen.dart
│   ├── chat/chat_screen.dart
│   ├── settings/presentation/screens/settings_screen.dart
│   └── ... (features lain)
└── shared/ ...

android/app/src/main/
├── cpp/
│   ├── llama_jni.cpp
│   ├── llama_stub.cpp
│   └── CMakeLists.txt
└── kotlin/com/kanmongo/app/
    ├── MainActivity.kt
    ├── LlamaPlugin.kt
    ├── NativeEnvPlugin.kt             ← chmodExecutable via Java File.setExecutable
    └── TermuxBridgePlugin.kt
```

---

## 🗺️ Route Map Lengkap (KmRoutes)

| Konstanta | Path | Screen |
|-----------|------|--------|
| `home` | `/` | HomeScreen |
| `chat` | `/chat` | ChatScreen |
| `agent` | `/agent` | AgentScreen |
| `notes` | `/notes` | NotesScreen |
| `ebook` | `/ebook` | EbookScreen |
| `ocr` | `/ocr` | OcrScreen |
| `terminal` | `/terminal` | TerminalScreen |
| `reader` | `/reader` | ReaderScreen |
| `history` | `/history` | HistoryScreen |
| `media` | `/media` | MediaCreatorScreen |
| `profile` | `/profile` | ProfileScreen |
| `settings` | `/settings` | SettingsScreen |
| `offlineAi` | `/settings/offline-ai` | OfflineAiScreen |
| `modelManager` | `/settings/model-manager` | ModelManagerScreen |
| `modelManagerAlt` | `/model-manager` | ModelManagerScreen (alias) |
| `aiParams` | `/settings/ai-params` | AiInferenceParamsScreen |
| `aiInference` | `/settings/ai-inference` | AiInferenceParamsScreen (alias) |
| `aiPersona` | `/settings/ai-persona` | AiPersonaScreen |
| `aiCatalog` | `/settings/ai-catalog` | AiCatalogScreen |
| `onlineAi` | `/settings/online-ai` | OnlineAiScreen |
| `bulkApiSettings` | `/settings/bulk-api` | BulkApiSettingsScreen |
| `puterSetup` | `/settings/puter-setup` | PuterSetupScreen |
| `claudeCode` | `/claude-code` | ClaudeCodeTerminalScreen |
| `vsCode` | `/vscode` | VscodeScreen |
| `toolsDashboard` | `/settings/tools-dashboard` | ToolsDashboardScreen ⭐ NEW |
| `paywall` | `/membership` | PaywallScreen |
| `membershipStatus` | `/membership/status` | MembershipStatusScreen |
| `login` | `/auth/login` | LoginScreen |
| `register` | `/auth/register` | RegisterScreen |
| `forgotPassword` | `/auth/forgot` | ForgotPasswordScreen |

---

## 🔑 API Publik — NativeToolsManager ⭐ NEW

```dart
import 'package:kanmongo/core/tools/native_tools_manager.dart';

// Singleton
NativeToolsManager.instance

// Query tools
List<NativeTool>              allTools               // semua 35+ tools terdaftar
List<NativeTool>              presentTools           // tools yang ada di disk
Map<ToolCategory, List>       byCategory             // dikelompokkan per kategori
NativeTool?                   find(String name)      // cari by name ('git', 'node', dll)
bool                          has(String name)       // quick existence check
String?                       pathOf(String name)    // path lengkap atau null

// Run tools
Future<ProcessResult>         run(name, args, {workDir, env})
Future<Process>               start(name, args, {workDir, env})

// Health check
Future<ToolHealth>            checkTool(NativeTool)
Future<List<ToolHealth>>      checkAll({categories, onProgress})
Future<bool>                  quickCheck()           // node + claude ready?

// ToolCategory enum:
// runtime, aiCode, ide, vcs, search, media, archive, language, network, util, debug

// ToolHealth fields:
// .tool, .exists, .executable, .version, .error, .isHealthy
```

**Tools terdaftar (35+):**
```
runtime:  node
aiCode:   claude (claude-code cli.js)
ide:      code-server
vcs:      git
search:   rg (ripgrep)
media:    ffmpeg, ffprobe, sox, yt-dlp, convert, identify (imagemagick)
archive:  zip, unzip, 7z, lz4, zstd, xz
language: python3, sqlite3
network:  curl, wget, ssh, scp
util:     busybox, jq, nano, vim, pv, file, patch, diff, rsync, ps, free, pgrep, pkill
debug:    exiftool, strace
```

---

## 🔑 API Publik — ToolsService

```dart
import 'package:kanmongo/core/tools/tools_service.dart';

ToolsService.instance

// State
bool            isReady      // true setelah initialize() berhasil
String          toolsRoot    // <appSupport>/tools
String          abi          // 'arm64-v8a' | 'x86_64'
ToolsManifest?  manifest     // data dari tools_manifest.json

// Path getters (semua di bawah toolsRoot/abi/)
String  nodePath, claudeCodeCliPath, codeServerCliPath
String  binDir               // toolsRoot/abi/bin/
String  gitPath, ripgrepPath, curlPath, wgetPath, jqPath, busyboxPath
String  python3Path, sqlite3Path, ffmpegPath, ffprobePath
String  convertPath, identifyPath, mogrifyPath
String  soxPath, ytDlpPath, nanoPath, vimPath
String  zipPath, unzipPath, p7zipPath, lz4Path, zstdPath, xzPath
String  psPath, freePath, pgrepPath, pkillPath
String  sshPath, scpPath, sshKeygenPath
String  exiftoolPath, stracePath

// Methods
Future<void>            initialize({onProgress})
Future<ProcessResult>   runNode(args, {workDir, env})
Future<Process>         startNode(args, {workDir, env})
Future<ProcessResult>   runTool(name, args, {workDir, env})
Future<Process>         startTool(name, args, {workDir, env})
Future<bool>            verifyNativeTool(name)
Future<bool>            verifyTools()              // cek node saja
Future<void>            reapplyPermissions()
Future<void>            invalidateCache()
List<String>            availableNativeTools       // list nama tool di bin/
bool                    hasNativeTool(name)
String?                 nativeToolPath(name)
```

---

## 🔑 API Publik — LlamaService

```dart
import 'package:kanmongo/data/services/llama_service.dart';

LlamaService.instance

// Lifecycle
await LlamaService.instance.initialize()
await LlamaService.instance.loadSettings()
await LlamaService.instance.saveSettings()
await LlamaService.instance.releaseModel()

// Model
Future<bool>   loadModel(LlamaModelInfo model)
bool           isModelLoaded
String?        lastLoadedModelPath
String?        lastLoadedModelId
Future<int>    getAvailableMemoryMb()

// Inference
Stream<String> generateStream({required List<ChatMessage> messages, required InferenceConfig config})
Future<void>   stopGeneration()

// Streams
Stream<ModelStatus> statusStream
Stream<double>      loadProgressStream
```

**⚠️ KONFLIK NAMA — DUA ChatMessage:**
```dart
import 'package:kanmongo/core/ai/llama_context.dart' as llama_ctx;
import 'package:kanmongo/data/models/chat_models.dart' as chat_models;
// → llama_ctx.ChatMessage untuk generateStream()
// → chat_models.ChatMessage untuk UI / HistoryService
```

---

## 🔑 API Publik — HistoryService

```dart
import 'package:kanmongo/data/services/history_service.dart';

Future<void>              saveChatSession(ChatSession)
Future<List<ChatSession>> loadAllChatSessions({int limit = 50})
Future<ChatSession?>      loadChatSession(String sessionId)
Future<void>              deleteChatSession(String sessionId)
Future<void>              updateSessionTitle(String sessionId, String title)
Future<void>              deleteAllSessions()
Future<List<ChatSession>> loadChatSessionsPaged({int page, int pageSize = 20})
Future<int>               countChatSessions()
Future<List<ChatSession>> searchChatSessions(String query)
```

---

## 🔑 Semua Riverpod Providers

### tools_provider.dart
```dart
toolsServiceProvider          // Provider<ToolsService>
toolsReadyProvider            // FutureProvider<bool>
toolsManifestProvider         // Provider<ToolsManifest?>
nativeToolsManagerProvider    // Provider<NativeToolsManager>  ⭐ NEW
toolsQuickReadyProvider       // FutureProvider<bool>          ⭐ NEW
```

### inference_params_provider.dart
```dart
inferenceConfigProvider, modelConfigProvider, activeModelInfoProvider
systemPromptProvider, modelPerformanceProvider
chatSessionProvider           // (re-export dari chat_session_provider)
```

### llama_status_provider.dart
```dart
isLlamaReadyProvider, llamaStatusProvider, llamaStatusLabelProvider
llamaStatusColorProvider, llamaLoadProgressValueProvider
llamaModelNameProvider, isLlamaGeneratingProvider
```

### chat_session_provider.dart
```dart
aiSourceProvider, aiSourceChoiceProvider
chatSessionProvider, chatHistoryProvider
```

### theme_provider.dart
```dart
sharedPreferencesProvider, themeProvider, themePackProvider
```

---

## 🎨 KmColors — Semua Properti

```dart
final c = KmColors.of(context);

c.bg, c.card, c.surface, c.elevated
c.accent, c.accentSoft, c.gold
c.text, c.textSub, c.textMuted
c.border, c.borderSoft, c.divider, c.overlay
c.canvasBg, c.canvasInk, c.canvasShadow, c.canvasGrid, c.inputFill
c.navBar, c.navBarItem, c.navBarSelected, c.streak
c.correct, c.wrong, c.warning, c.info
c.isDark, c.isLight, c.onSurface
```

---

## 📦 Android Build Config Kritis

```groovy
namespace     "com.kanmongo.app"
compileSdk    36
minSdk        23
targetSdk     36
ndkVersion    "28.2.13676358"
multiDexEnabled true
abiFilters    "arm64-v8a"

aaptOptions { noCompress "gguf", "tflite", "lite", "task" }
// JANGAN noCompress tar.gz — assets/tools/*.tar.gz harus bisa dibaca rootBundle
```

---

## 📍 Line Map — chat_screen.dart (4271 baris)

| Baris | Isi |
|-------|-----|
| ~71 | `class ChatScreen` |
| ~79 | `class _ChatScreenState` |
| ~89 | State variables |
| ~158 | `initState()` |
| ~187 | `dispose()` |
| ~217 | `build()` |
| ~372 | `_buildContextUsageBar()` |
| ~417 | `_buildMessageList()` |
| ~499 | `_buildInputArea()` |
| ~801 | `_buildActionButton()` |
| ~2047 | `_deleteMessageWithUndo()` |
| ~2254 | `_showRenameDialog()` |
| ~2397 | `_newChat()` |
| ~2602 | `_switchToOnlineMode()` |
| ~2844 | `class _ModelStatusChip` |
| ~3036 | `class _EmptyStateChat` |
| ~3176 | `class _EmptyModelWidget` |
| ~3237 | `class _MessageBubble` |

---

## 🐛 Bug Historis Lengkap

| ID | Gejala | Root Cause | Fix |
|----|--------|-----------|-----|
| #103 | `themePackProvider` ambiguous | Dua file deklarasi provider sama | Hapus `theme_providers.dart` |
| #104 | `llama_kv_self_*` undeclared | API lama | Pakai Memory V2 API |
| #23 | `Expected ';'` / body outside Scaffold | Bracket awal | `ConfirmExitBack > Scaffold > appBar + body` |
| B-003 | Crash saat stop generate | Race condition | Cek `_genSubLocked` sebelum cancel |
| D-008 | Autosave terlalu sering | Tanpa debounce | Gunakan `_autoSaveTimer` |
| B-008 | Lag saat typing/search | Tanpa debounce | Gunakan `_debounceTimer` |
| S-001 | `withOpacity` deprecated | Flutter 3.x | Pakai `Color.withValues(alpha: x)` |
| S-002 | Screen duplikat ambigu | Placeholder tidak dihapus | Hapus file placeholder |
| **T-001** | **VscodeScreen tampil noBundle padahal tools ada** | `checkStatus()` tidak await `ToolsService.initialize()` | **FIXED: selalu await init sebelum check** |
| **T-002** | **ClaudeCodeScreen sama** | Same | **FIXED** |
| **T-003** | **`core/tools/code_server_service.dart` konflik dengan `data/services/`** | Dua versi berbeda | **FIXED: stub dihapus, pakai versi lengkap** |
| **T-004** | **Tidak ada registry terpusat untuk CLI tools** | — | **FIXED: NativeToolsManager** |
| **T-005** | **Tidak ada UI status tools** | — | **FIXED: ToolsDashboardScreen** |
| - | `LlamaService not found` | Import path salah | Import `llama_service.dart` |
| - | `activeModelInfoProvider` not found | Missing import | Tambah import `inference_params_provider.dart` |
| - | GGUF tidak bisa dibuka di device | File di-compress | `noCompress "gguf"` di `aaptOptions` |

---

## 🏗️ Catatan Struktur VsCode & ClaudeCode Screen

Router (`app_router.dart`) memakai:
- `VscodeScreen` dari `lib/features/vscode/vscode_screen.dart`
- `ClaudeCodeTerminalScreen` dari `lib/features/claude_code/claude_code_screen.dart`
- `ToolsDashboardScreen` dari `lib/features/tools/tools_dashboard_screen.dart` ⭐ NEW

**JANGAN** buat ulang file-file di `lib/features/vscode/presentation/screens/` atau `lib/features/claude_code/presentation/screens/` — placeholder sudah dihapus.

**JANGAN** buat `lib/core/tools/code_server_service.dart` atau `lib/core/tools/claude_code_service.dart` — sudah dihapus karena konflik dengan versi lengkap di `lib/data/services/`.

---

## 🛠️ Template Tambah Fitur

### A. Screen Baru
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/shared/widgets/back_handler.dart';

class NamaScreen extends ConsumerWidget {
  const NamaScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = KmColors.of(context);
    return ConfirmExitBack(
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          backgroundColor: c.card,
          iconTheme: IconThemeData(color: c.text),
          title: Text('Judul', style: TextStyle(color: c.text)),
        ),
        body: Center(child: Text('Konten', style: TextStyle(color: c.text))),
      ),
    );
  }
}
```

### B. Gunakan NativeTool di screen
```dart
import 'package:kanmongo/core/tools/native_tools_manager.dart';
import 'package:kanmongo/core/tools/tools_service.dart';

// Cek apakah tool tersedia
if (NativeToolsManager.instance.has('git')) {
  final result = await NativeToolsManager.instance.run('git', ['status']);
}

// Atau lewat ToolsService langsung
if (ToolsService.instance.isReady) {
  await ToolsService.instance.runTool('ffmpeg', ['-i', 'input.mp4', 'output.mp3']);
}
```

### C. Provider Tools di Widget
```dart
import 'package:kanmongo/core/tools/tools_provider.dart';

// Dalam ConsumerWidget
final isReady = ref.watch(toolsReadyProvider);
final manager = ref.read(nativeToolsManagerProvider);
```

### D. Warna — SELALU withValues, JANGAN withOpacity
```dart
// ✅ BENAR
color: someColor.withValues(alpha: 0.4)

// ❌ SALAH — deprecated sejak Flutter 3.x
color: someColor.withOpacity(0.4)
```

---

## 🔧 Alur Kerja Efisien per Tugas

| Tugas | Langkah | Tool Calls |
|-------|---------|-----------|
| Edit screen kecil | view_range → str_replace | ~2 |
| Screen baru | create_file + 2x str_replace router + 1x str_replace menu | ~4 |
| Tambah provider | view_range → str_replace | ~2 |
| Debug build error | Cocokkan tabel bug → view_range ±15 baris → str_replace | ~2–3 |
| Tambah service | create_file → str_replace main.dart (jika perlu) | ~2 |
| Gunakan native tool | check NativeToolsManager.has() → runTool() | ~1 |

---

## 🚀 Setup & Build

```bash
flutter pub get
bash scripts/setup_llama.sh   # clone llama.cpp headers
flutter run

flutter build apk --release --split-per-abi    # APK
flutter build appbundle --release              # AAB Play Store
```

**CI Secrets:**

| Secret | Keterangan |
|--------|-----------|
| `KEYSTORE_BASE64` | Keystore JKS base64 |
| `KEY_STORE_PASSWORD` | Password keystore |
| `KEY_ALIAS` | Alias key |
| `KEY_PASSWORD` | Password key |

---

## ⚠️ Larangan Keras

| Jangan | Alasan |
|--------|--------|
| Import `theme_providers.dart` | File dihapus — build error #103 |
| `OfflineAiService` untuk kode baru | Deprecated alias |
| Akses SQLite langsung | Pakai `DatabaseService` atau `HistoryService` |
| Hardcode warna | Pakai `KmColors.of(context)` |
| `Color.withOpacity(x)` | Deprecated — pakai `Color.withValues(alpha: x)` |
| `#ifdef LLAMA_API_MEMORY_V2` | Pakai Memory V2 langsung |
| Commit `assets/database/km_content.db` | CI inject, di-ignore |
| Commit `assets/tools/` | CI inject, di-ignore |
| `noCompress` tanpa "gguf" | GGUF rusak di device |
| Dua import ChatMessage tanpa alias | Naming conflict compile error |
| `new LlamaService()` | Singleton only via `.instance` |
| Buat `core/tools/code_server_service.dart` | **DIHAPUS** — konflik dengan `data/services/` |
| Buat `core/tools/claude_code_service.dart` | **DIHAPUS** — konflik dengan `data/services/` |
| Buat `presentation/screens/vscode_screen.dart` | Placeholder dihapus |
| Buat `presentation/screens/claude_code_screen.dart` | Placeholder dihapus |
| Akses tools tanpa await `ToolsService.initialize()` | `isReady` = false → crash |

---

## 💡 Tips Cepat

- **Snackbar** → `TopSnack.show(context, 'pesan')`
- **Cek model** → `LlamaService.instance.isModelLoaded`
- **Stream AI** → selalu `onError` + `onDone`
- **Widget baru?** → cek `km_widgets.dart` dulu
- **ChatScreen besar** → pakai tabel line map, view_range secara spesifik
- **Hive boxes** → `chat_history`, `model_cache`, `ai_settings`
- **GGUF disimpan** → di app documents dir, BUKAN assets
- **AiSourcePickerButton** → wajib di AppBar ChatScreen
- **Cek tools tersedia** → `NativeToolsManager.instance.has('nama_tool')`
- **Run CLI tool** → `NativeToolsManager.instance.run('git', ['status'])`
- **Dashboard tools** → `context.push(KmRoutes.toolsDashboard)`
- **Lihat CLAUDE.md** di root project untuk catatan sesi migrasi
