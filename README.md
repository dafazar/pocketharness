# Pocket Harness

<p align="center">
  <img src="assets/icons/logo/icon_theme_light.svg" width="96" alt="Pocket Harness logo" />
</p>

<p align="center">
  <strong>Offline-first AI workspace for Android</strong> — on-device LLM inference via
  llama.cpp, cloud AI routing, coding-agent tools, terminal, and document tools in one Flutter app.
</p>

<p align="center">
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-stable-02569B?logo=flutter&logoColor=white" alt="Flutter stable" /></a>
  <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-%3E%3D3.0_%3C4.0-0175C2?logo=dart&logoColor=white" alt="Dart SDK" /></a>
  <a href="https://developer.android.com"><img src="https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white" alt="Platform Android" /></a>
  <a href="android/app/build.gradle"><img src="https://img.shields.io/badge/minSdk-23_%28Android_6.0%2B%29-000000" alt="minSdk 23" /></a>
  <a href="firebase.json"><img src="https://img.shields.io/badge/Firebase-Auth_%7C_Firestore_%7C_Crashlytics-FFCA28?logo=firebase&logoColor=black" alt="Firebase" /></a>
  <a href="#license"><img src="https://img.shields.io/badge/License-Proprietary-lightgrey" alt="Proprietary license" /></a>
</p>

## Contents

- [Overview](#overview)
- [Feature overview](#feature-overview)
- [AI engine](#ai-engine)
- [Native CLI tools](#native-cli-tools)
- [Architecture](#architecture)
- [Tech stack](#tech-stack)
- [Project structure](#project-structure)
- [Getting started](#getting-started)
- [Configuration](#configuration)
- [Build and release](#build-and-release)
- [Security and privacy](#security-and-privacy)
- [Testing and quality](#testing-and-quality)
- [Troubleshooting](#troubleshooting)
- [Documentation index](#documentation-index)
- [Versioning](#versioning)
- [Known limitations](#known-limitations)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgements](#acknowledgements)

## Overview

Pocket Harness is an Android app that puts a complete AI workspace on the phone:
chat with local or cloud models, a multi-step agent, an in-app terminal with a
bundled CLI toolchain, Claude Code and VS Code (code-server) integration, OCR,
e-book/reader, notes, media tools, and an AI tutor — backed by Firebase for auth,
sync, and crash reporting.

Design priorities:

- **Offline-first.** GGUF models run on-device through a custom llama.cpp JNI
  bridge. The app stays usable with no network; cloud providers are opt-in.
- **Explicit AI routing.** Three engine modes — offline, online (Puter.js), and
  Bulk API (BYOK) — with deterministic fallback instead of silent switching.
- **Real native layer.** Inference runs in C++/Kotlin with a foreground service,
  structured event streaming, and memory-pressure handling — not a WebView demo.
- **Reproducible builds.** Pinned NDK/CMake/AGP, a one-command llama.cpp setup
  script, and a CI workflow that bundles the full CLI toolchain per ABI.

> Scope note: this repository is the Flutter AI app. It contains no
> DeepSeek-Harness/DSH server code.

## Feature overview

20+ feature modules under `lib/features/`, routed with GoRouter (30+ routes in
`lib/core/router/app_router.dart`).

| Area | What it does | Entry points |
|---|---|---|
| Chat | Streaming AI chat with file attachments (images, PDF, ZIP, text) and an AI-source picker | `/chat`, `lib/features/chat/` |
| Agent | Multi-step agent with tool calling and persistent memory | `/agent`, `agent_service.dart`, `agent_memory_service.dart` |
| Offline AI | On-device GGUF inference: download, import, activate, and monitor models | `/offline-ai`, `/model-manager`, `llama_service.dart` |
| Inference tuning | Sampling, context, and GPU presets with a live parameter test screen | `/ai-params`, `ai_inference_params_screen.dart` |
| Online AI | Cloud chat via Puter.js, with a guided setup screen | `/settings/online-ai`, `/settings/puter-setup`, `puter_ai_service.dart` |
| Bulk API | Bring-your-own-key multi-provider (Groq, Gemini, Claude, OpenRouter, OpenAI-compatible) | `/settings/bulk-api`, `bulk_api_service.dart` |
| AI catalog and persona | Model catalog plus persona / system-prompt editor | `/settings/ai-catalog`, `/settings/ai-persona` |
| Terminal | In-app shell with a Termux bridge | `/terminal`, `terminal_service.dart`, `termux_bridge.dart` |
| Claude Code | Bundled Claude Code CLI lifecycle (stdio streaming) plus an installer wizard | `/claude-code`, `claude_code_service.dart`, `claude_code_installer.dart` |
| VS Code | code-server lifecycle with an in-app WebView | `/vscode`, `code_server_service.dart` |
| Tools dashboard | Native CLI registry with health checks | `/settings/tools-dashboard`, `native_tools_manager.dart` |
| OCR | Camera capture plus on-device text recognition (ML Kit) | `/ocr` |
| E-book and Reader | PDF/DOCX/PPTX viewer and reading flows | `/ebook`, `/reader` |
| Notes | Local notes in the encrypted user database | `/notes` |
| Media | Media creation and editing helpers | `/media`, `media_edit_service.dart` |
| AI Tutor | Tutor flows including FSRS-5 spaced repetition | `lib/features/ai_tutor/`, `fsrs5_service.dart` |
| History and Profile | Chat history and user profile | `/history`, `/profile` |
| Membership | Premium gating via RevenueCat | `/membership`, `membership_service.dart`, `premium_gate.dart` |
| Auth | Firebase Auth with Google Sign-In | `/auth/*`, `auth_service.dart` |
| Voice | Text-to-speech (including Edge TTS) and speech-to-text | `tts_service.dart`, `edge_tts_service.dart` |
| Theming | Four packs — AMOLED (default), Dark, Light, Sakura | `theme_provider.dart`, `km_colors.dart` |
| Web research | HTML scraping and a research pipeline | `web_scraper_service.dart`, `web_research_service.dart` |
| Onboarding and setup | Permission onboarding, first-run tool extraction, splash | `/splash`, `first_setup_screen.dart`, `permission_onboarding_screen.dart` |

## AI engine

### Engine modes

`AiMode` (`lib/data/services/ai_service.dart`) has four states:

| Mode | Backend | Notes |
|---|---|---|
| `offline` | `LlamaService` — local GGUF via llama.cpp JNI | Works with no network once a model is loaded |
| `online` | `PuterAiService` — Puter.js cloud REST API | Requires opt-in setup and connectivity |
| `bulkApi` | `BulkApiService` — Groq, Gemini, Claude, OpenRouter, OpenAI-compatible | User-supplied API keys, managed in-app |
| `none` | — | No engine available; UI degrades gracefully |

Routing is deterministic: a forced offline choice always wins; otherwise Puter.js
is used when enabled and reachable; otherwise the router falls back to the local
model when one is loaded.

### `LlamaService` — the offline core

- Singleton at `lib/data/services/llama_service.dart`; new code must use
  `LlamaService.instance` (the `OfflineAiService` class in
  `offline_ai_service.dart` is a backward-compatibility alias).
- Token streaming via `generateStream(...)`, cancellable with `stopGeneration()`;
  broadcast `statusStream` and `loadProgressStream` (0.0–1.0) drive the UI.
- State lives in Riverpod providers (`inference_params_provider.dart` for
  sampling/model/session config, `llama_status_provider.dart` for ready-state,
  labels, colors, and progress), so any widget can observe engine state.
- `ModelManagerService` handles HuggingFace downloads (including
  `bartowski/Llama-3.2-1B/3B-Instruct-GGUF` `Q4_K_M` and Phi-3.5-mini builds),
  local GGUF import/scanning, activation, and per-device RAM guidance.

### Native inference path

```
Dart LlamaService → MethodChannel/EventChannel → LlamaPlugin.kt
    → llama_jni.cpp → llama.cpp (Memory V2 API) → libpocketharness_llama.so
```

- `android/app/src/main/cpp/llama_jni.cpp` uses the Memory V2 API only
  (`llama_get_memory` / `llama_memory_*`); legacy `llama_kv_self_*` calls were
  removed for llama.cpp b10350+.
- `use_mmap=false` is deliberate: mmap on Android internal storage causes
  SIGBUS crashes. Do not re-enable it.
- Context size is clamped to each model's trained context; thread count,
  batch, GPU layers, and rope settings are configurable from the Dart side.
- `LlamaGenerationService` (inside `LlamaPlugin.kt`) is a foreground service
  that keeps generation alive, with `onTrimMemory` handling for pressure.
- If `llama.cpp/` is absent, the build falls back to `llama_stub.cpp`: the app
  runs normally with GGUF inference disabled.

## Native CLI tools

The app ships a real command-line environment, extracted on first launch:

```
FirstSetupService.runIfNeeded() → ToolsService.initialize()
  → read assets/tools/tools_manifest.json (schema v3)
  → extract tools_<abi>.tar.gz → app support dir
  → chmod via NativeEnvPlugin → NativeToolsManager registry ready
```

- `FirstSetupScreen` subscribes to the extraction progress stream; a
  SharedPreferences flag makes later launches skip it (< 1 ms).
- The CI-built bundle includes Termux/Bionic Node.js, Claude Code, code-server
  (pinned to stay on Node 20), Python 3, git, ffmpeg, ImageMagick, sox, yt-dlp,
  vim/nano, exiftool, openssh, sqlite3, curl/wget/jq, busybox, and standard
  archive/compression/diff utilities.
- `ClaudeCodeInstaller` verifies the bundle and writes `settings.json`;
  `ClaudeCodeService` manages the CLI process with stdio streaming;
  `CodeServerService` manages the code-server process behind the WebView.
- Always check `ToolsService.instance.isReady` (and `await initialize()`)
  before touching tools from new code.

## Architecture

Layered Flutter app with a Kotlin/JNI native layer:

```
Presentation   lib/features/*/presentation (ConsumerWidget + GoRouter)
Application    Riverpod providers (AI, theme, membership, lifecycle)
Services       lib/data/services (40+ services) + lib/data/models + repositories
Platform       MethodChannel/EventChannel → Kotlin plugins → JNI/CMake → .so
Storage        SQLCipher user DB · read-only content asset · Hive boxes · prefs
```

| Concern | Choice | Location |
|---|---|---|
| State | Riverpod 2.x, StateNotifier pattern | `lib/core/ai/*_provider.dart`, feature providers |
| Navigation | GoRouter 14.x, declarative routes | `lib/core/router/app_router.dart` |
| Theming | `KmColors.of(context)` — never hardcode colors | `lib/core/theme/` |
| User data | Encrypted SQLite via `DatabaseService`; history via `HistoryService` | `lib/data/services/database_service.dart` |
| Cache | Hive boxes (`chat_history`, `model_cache`, `ai_settings`) | `lib/main.dart` init |
| Content | Read-only SQLite asset, generated at build time | `assets/database/km_content.db` (git-ignored artifact) |
| Native AI | llama.cpp JNI + foreground service | `android/app/src/main/cpp/`, `LlamaPlugin.kt` |
| Native env | Executable-bit handling, Termux bridge | `NativeEnvPlugin.kt`, `TermuxBridgePlugin.kt` |
| Backend | Firebase Auth, Firestore, Analytics, Crashlytics, Remote Config | `firebase.json`, `firestore.*`, `lib/core/*` |
| CI/CD | GitHub Actions, manual dispatch | `.github/workflows/build.yml` |

## Tech stack

Versions are pinned in `pubspec.yaml` and the Gradle files.

| Layer | Technology |
|---|---|
| App | Flutter (stable channel), Dart `>=3.0.0 <4.0.0` |
| State / nav | `flutter_riverpod` 2.5.1, `riverpod_annotation` 2.3.5, `go_router` 14.2.0 |
| Codegen | `build_runner`, `riverpod_generator`, `json_serializable`, `freezed` |
| Storage | `sqflite_sqlcipher` 3.0.1, `hive` + `hive_flutter`, `shared_preferences` |
| Firebase | core 3.6.0, auth 5.3.1, firestore 5.4.4, analytics 11.3.3, crashlytics 4.1.3, remote-config 5.1.3 |
| Monetization | `purchases_flutter` 8.0.0 (RevenueCat) |
| Media/docs | ML Kit text recognition 16.0.0, `syncfusion_flutter_pdfviewer` 27.1.48, TTS/STT, audio/video players |
| Android | compileSdk/targetSdk 36, minSdk 23, NDK 28.2.13676358, CMake 3.22.1, AGP 8.9.1, Kotlin 2.1.0, Java 17 |
| Native AI | llama.cpp (sparse checkout via `scripts/setup_llama.sh`, default tag `b8604`), Memory V2 API |

## Project structure

```text
pocketharness/
├── lib/
│   ├── main.dart                  # Entry: Firebase, Hive, Riverpod, first-setup, router
│   ├── firebase_options.dart      # FlutterFire options (Android)
│   ├── core/
│   │   ├── ai/                    # LlamaContext models, inference + status providers
│   │   ├── auth/ membership/      # AuthService, RevenueCat membership + premium gate
│   │   ├── config/ network/       # Remote Config, connectivity
│   │   ├── lifecycle/             # AppLifecycleService
│   │   ├── router/                # GoRouter table (30+ routes)
│   │   ├── security/              # CryptoService, SecureDbKeyService
│   │   ├── sync/                  # SyncService (Firestore)
│   │   ├── theme/                 # AppTheme, ThemeProvider, KmColors (4 packs)
│   │   ├── tools/                 # ToolsService, NativeToolsManager
│   │   └── wallpaper/ constants/  # Wallpaper provider, AppConstants
│   ├── data/
│   │   ├── models/                # Chat, AI source, catalog, file-context models
│   │   ├── repositories/          # UserRepository
│   │   └── services/              # 40+ services: llama, agent, puter, bulk API,
│   │                              # model manager, terminal, claude-code, code-server,
│   │                              # TTS/STT, OCR helpers, export, research, …
│   ├── features/                  # 20+ modules: chat, agent, home, settings (9 screens),
│   │                              # terminal, vscode, claude-code, tools, ocr, ebook,
│   │                              # reader, notes, media, ai_tutor, history, auth, …
│   └── shared/
│       ├── widgets/               # ai_source_picker, back_handler, main_shell, …
│       └── utils/                 # top_snack
├── android/app/
│   ├── build.gradle               # minSdk 23, arm64 filter, CMake, signing, minify
│   ├── src/main/
│   │   ├── AndroidManifest.xml    # Label, permissions, FileProvider, Termux query
│   │   ├── cpp/                   # llama_jni.cpp, llama_stub.cpp, CMakeLists.txt
│   │   └── kotlin/com/pocketharness/app/  # LlamaPlugin, MainActivity,
│   │                                       # NativeEnvPlugin, TermuxBridgePlugin
│   └── google-services.json       # Android Firebase config (replace for your project)
├── assets/
│   ├── database/                  # km_content.db generated here (not in git)
│   ├── tools/                     # tools_manifest.json + tools_<abi>.tar.gz (CI-injected)
│   ├── icons/logo/                # App + feature icon set
│   ├── theme/ html/ sounds/       # Theme packs, bundled HTML, SFX
├── scripts/
│   ├── setup_llama.sh             # Sparse llama.cpp checkout (~30 MB)
│   ├── build_sqlite_db.py         # Generate content SQLite
│   ├── build_encrypted_db.py      # Encrypted content variant
│   ├── convert_and_build.py       # Asset conversion pipeline
│   └── generate_sounds.py         # SFX generation
├── functions/                     # Cloud Functions scaffold (key derivation needs none)
├── test/widget_test.dart          # Smoke test
├── firebase.json firestore.rules firestore.indexes.json storage.rules
├── pubspec.yaml                   # Dependencies + version (source of truth)
└── .github/workflows/build.yml    # Manual-dispatch CI (Android + experimental iOS)
```

## Getting started

### Prerequisites

- Flutter on the **stable** channel (`flutter doctor` clean for Android)
- Dart SDK `>=3.0.0 <4.0.0` (ships with Flutter)
- Java 17, Android SDK with API 36, NDK `28.2.13676358`, CMake `3.22.1`
- Python 3 (content-database scripts), git
- An Android device or emulator, API 23+ (arm64 recommended for GGUF inference)

### Clone and run

```bash
git clone https://github.com/dafazar/pocketharness.git
cd pocketharness

# 1. Fetch the llama.cpp source used by the JNI bridge (~30 MB sparse checkout).
#    Override the tag when needed: LLAMA_TAG=bXXXX bash scripts/setup_llama.sh
bash scripts/setup_llama.sh

# 2. Install Dart dependencies.
flutter pub get

# 3. Generate the read-only content database (git-ignored build artifact).
python3 scripts/build_sqlite_db.py

# 4. Run on a connected Android device.
flutter run
```

Notes:

- Skipping step 1 is allowed: the build uses `llama_stub.cpp` and the app runs
  with GGUF inference disabled.
- First launch extracts the bundled CLI tools in the background
  (`FirstSetupScreen`); later launches skip it automatically.
- After editing annotated models/providers, run codegen before building:
  `flutter pub run build_runner build --delete-conflicting-outputs`.

## Configuration

| Item | How to configure |
|---|---|
| Firebase (Android) | `android/app/google-services.json` is committed for the reference project. For your own builds, replace it with your Firebase project's file and regenerate `lib/firebase_options.dart` with FlutterFire. |
| Firestore rules/indexes | Deploy `firestore.rules`, `firestore.indexes.json`, and `storage.rules` with the Firebase CLI. |
| Database salt | Create the Firestore document `_server_config/db_keys` with a `salt` field (64 random hex chars). `SecureDbKeyService` derives SQLCipher keys from it; without it the encrypted databases cannot open. |
| Cloud AI keys | Entered in-app on the Bulk API and Puter setup screens. Keys are never stored in code, env files, or the repo. |
| Release signing | `KEYSTORE_PATH`, `KEY_STORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` (local env or CI secrets). Without a keystore the release build falls back to debug signing — CI-only behavior, never ship that. |

## Build and release

### Local builds

```bash
flutter clean
flutter pub get
flutter build apk --release                 # arm64 (default ABI filter)
flutter build apk --release --split-per-abi # per-ABI APKs (adds x86_64)
flutter build appbundle --release           # Play Store bundle → build/app/outputs/bundle/release/
```

Release builds enable `minifyEnabled`, `shrinkResources`, and the ProGuard rules
in `android/app/proguard-rules.pro` (R8 full mode stays off to protect JNI
symbols). Debug builds use the `.debug` applicationId suffix.

### CI (GitHub Actions)

`Actions → Build Pocket Harness → Run workflow` — the workflow is
**manual-dispatch only** (no push/PR triggers) with three inputs: build target
(`apk-release-arm64` default, plus full APK, split-ABI, debug, AAB, all-Android,
and iOS), Flutter channel, and a Dart-obfuscation toggle for releases.

Each Android run: checks out the repo, strips scratch docs/secrets from the
workspace, provisions Java 17 / Android SDK / Flutter / NDK 28, resolves and
caches the llama.cpp tag, bundles the per-ABI CLI toolchain
(`tools_manifest.json` schema v3), runs `flutter analyze`, decodes the release
keystore from secrets, builds the selected targets, uploads the artifacts to a
GitHub Release, removes the keystore, and posts a build summary.

Required repository secrets for signed Android builds:

| Secret | Purpose |
|---|---|
| `KEYSTORE_BASE64` | Release keystore (JKS) as base64 |
| `KEY_STORE_PASSWORD` | Keystore password |
| `KEY_ALIAS` | Key alias |
| `KEY_PASSWORD` | Key password |

The workflow also contains an iOS no-codesign path, but this tree has no `ios/`
directory, so iOS is not buildable from this repository state.

## Security and privacy

### Android permissions (with rationale)

| Permission | Why |
|---|---|
| `INTERNET` | Cloud AI (Puter.js, Bulk APIs), GGUF downloads, Firebase |
| `ACCESS_NETWORK_STATE` | Connectivity-aware engine routing and offline fallback |
| `POST_NOTIFICATIONS` | Foreground-service and download-progress notifications |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC` | Keep token generation alive in the background |
| `READ_MEDIA_IMAGES/VIDEO/AUDIO` (+ user-selected) | Chat file attachments |
| `CAMERA` | OCR capture |
| `RECORD_AUDIO` | Speech-to-text input |
| `VIBRATE` | Haptic feedback |
| `com.termux.permission.RUN_COMMAND` + Termux visibility query | Optional Termux bridge integration |

### Data protection

- User and content SQLite databases are encrypted with SQLCipher.
- Keys are derived per install/user (`SHA-256(salt + uid + "user")` for the user
  key, `SHA-256(salt + "content")` for the content key), live only in memory,
  and are never written to disk or baked into the APK. The salt lives in the
  Firestore `_server_config/db_keys` document guarded by security rules.
- `*.jks`, `*.keystore`, `.env*`, and `secrets/` are git-ignored; CI deletes
  scratch documentation and secret files from the workspace before building and
  removes the decoded keystore afterwards.
- Crash reporting uses Firebase Crashlytics (fatal Flutter and platform errors);
  Analytics and Remote Config are present for diagnostics and feature flags.
- See `Privacy` in-app (`/privacy`) for the user-facing policy surface.

## Testing and quality

- `test/widget_test.dart` is a smoke placeholder — automated coverage is
  currently minimal and contributions that add widget/unit tests around the AI
  services and routing are welcome.
- CI runs `flutter analyze` on every build; keep the analyzer clean.
- Recommended manual gates before a release: cold start + first-setup tool
  extraction, GGUF download → load → stream → cancel, agent multi-step loop,
  Bulk API + Puter.js round-trips, tools-dashboard health, release-APK smoke on
  a mid-range arm64 device.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `NativeLoadModel returned 0` | Missing plugin registration, invalid GGUF path, or low memory | Follow the fix pack: `README_START_HERE.md` → `IMPLEMENTATION_GUIDE.md` → `MODEL_LOADING_FIX_GUIDE.md` |
| SIGBUS / crash while loading a model | mmap on internal storage | Already fixed via `use_mmap=false` in `llama_jni.cpp` — do not re-enable it |
| `themePackProvider` ambiguous import | Legacy `theme_providers.dart` resurrected | That file was deleted (bug #103); keep `theme_provider.dart` as the single source |
| `llama_kv_self_*` undeclared | Legacy KV-cache calls | Use the Memory V2 API (`llama_get_memory` + `llama_memory_*`) only |
| `llama.h: No such file` | llama.cpp source missing | Run `bash scripts/setup_llama.sh` (or `LLAMA_TAG=…` for a specific tag) |
| Release build unsigned / falls back to debug | Keystore env missing | Set `KEYSTORE_PATH`, `KEY_STORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` |
| CI out-of-memory / exit 143 | Gradle heap too large for the runner | Already tuned (`-Xmx4g`, daemon + parallel off in `gradle.properties`) — don't raise it |
| `Scaffold` / widget-tree compile errors | `ConfirmExitBack` refactor drift | Pattern is `ConfirmExitBack > Scaffold > appBar + body` per viewer |

## Documentation index

| Document | Covers |
|---|---|
| `CLAUDE.md` | Contributor and AI-agent code guide: LlamaService patterns, providers, theme, JNI rules, routes, CI secrets |
| `SKILL.md` | `kanmongo-feature-dev` skill: architecture, CLI tools, feature inventory, bug table |
| `BUILD_GUIDE.md` | Build and deploy walkthrough (local + release config) |
| `PUSH_GUIDE.md` | Push and release notes |
| `SETUP_FIREBASE.md`, `README_FIREBASE.md` | Firebase project setup |
| `SETUP_SQLCIPHER.md` | Encrypted-database setup |
| `LLAMA_NATIVE_PLUGIN.md` | JNI/Kotlin bridge reference |
| `NATIVE_ENV_GUIDE.md` | Native toolchain environment |
| `README_START_HERE.md`, `IMPLEMENTATION_GUIDE.md`, `MODEL_LOADING_FIX_GUIDE.md`, `QUICK_FIX_GUIDE.md`, `QUICK_REFERENCE.txt` | Model-loading fix pack (start with `README_START_HERE.md`) |
| `CHANGELOG.md`, `CHANGES.md`, `FIXES_CHANGELOG.md`, `CHANGELOG_SESSION03.md`, `CHANGELOG_SESSION_ENHANCED.md`, `SESSION_EXECUTION_REPORT.md` | Release and session history |
| `FILE_MANIFEST.txt`, `PATCH_README.md` | Manifest and patch notes |
| `setup.sh` | Root setup helper script |
| `.github/workflows/build.yml` | CI pipeline definition (comment header documents the merge history) |

## Versioning

- `pubspec.yaml` is the source of truth for the build version (`flutter.versionCode` /
  `flutter.versionName` flow into `build.gradle`); the current line is 2.1.x —
  see `CHANGELOG.md` for per-release notes.
- `AppConstants.appVersion` is a display constant and can drift from the build
  version; when they disagree, the pubspec value wins.

## Known limitations

- **Android only.** This tree has no `ios/` directory; the CI workflow's iOS
  option is experimental and not buildable here.
- **Legacy applicationId.** The installed `applicationId` remains
  `com.kanmongo.app` for update continuity, while the Gradle namespace and
  Kotlin sources use `com.pocketharness.app`. Historical `kanmongo`
  identifiers (notification channel, setup stamp, skill package name) are
  intentional — do not rename them without a migration plan.
- **Thin automated tests.** Coverage is a smoke placeholder plus `flutter
  analyze`; the manual gates above are the current quality bar.
- **Proprietary license.** There is no `LICENSE` file; see below.

## Contributing

1. Fork and branch from `main` (`feat/…`, `fix/…`, `docs/…`).
2. Keep `flutter analyze` clean and match the existing patterns: Riverpod
   providers for state, GoRouter for navigation, `KmColors.of(context)` for
   colors, `LlamaService.instance` for offline inference (see `CLAUDE.md` and
   `SKILL.md` before touching AI or theme code).
3. Never commit keystores, `.env` files, downloaded GGUFs, generated databases,
   or API keys.
4. Open a pull request with a clear scope, test evidence (device + Android
   version), and updated docs when behavior changes.

## License

Proprietary — © 2026 Pocket Harness. All rights reserved.

There is no open-source `LICENSE` file in this repository. You may clone and
build the app for personal evaluation; any other use, redistribution, or
derivative work requires prior written permission from the repository owner.
Questions: please use the repository's Issues tab.

## Acknowledgements

- [llama.cpp](https://github.com/ggerganov/llama.cpp) for the on-device inference engine
- Flutter, Dart, and Firebase for the app platform and backend
- Termux's Bionic Node.js builds and code-server for the bundled CLI toolchain
- Hugging Face and the bartowski GGUF builds used as default models
- RevenueCat, ML Kit, and the open-source package authors in `pubspec.yaml`
