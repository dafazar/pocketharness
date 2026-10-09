# 🚀 Panduan Push ke GitHub & Build

## Langkah 1 — Inisialisasi Git (jika belum ada repo)

```bash
cd pocketharness_repo   # atau nama folder repo kamu
git init
git remote add origin https://github.com/USERNAME/REPO_NAME.git
```

Jika repo sudah ada, cukup:
```bash
git remote set-url origin https://github.com/USERNAME/REPO_NAME.git
```

---

## Langkah 2 — Tambahkan file changed ke staging

```bash
git add lib/data/services/model_manager_service.dart
git add lib/data/services/import_progress_service.dart
git add lib/data/services/offline_ai_service.dart
git add lib/data/services/ai_service.dart
git add lib/data/services/agent_service.dart
git add lib/features/settings/presentation/screens/model_manager_screen.dart
git add android/app/src/main/kotlin/com/pocketharness/app/LlamaPlugin.kt
git add android/app/src/main/cpp/llama_jni.cpp
git add CHANGELOG.md
git add .gitignore
```

Atau tambahkan semua sekaligus (pastikan .gitignore sudah benar dulu):
```bash
git add .
```

---

## Langkah 3 — Commit

```bash
git commit -m "fix: offline AI agent response + import cancel UX v5

- offline_ai_service: V3 fix — startGeneration await + _GenerateSession
  buffer + EventChannel singleton. Cegah hang/silent failure di agent chat.
- agent_service: auto-reset _running flag + guard response kosong
- model_manager_service: _CancelToken per-chunk → cancel import benar-benar
  berhenti + file parsial dihapus. DownloadProgress + speedBytesPerSec + etaSeconds.
- import_progress_service: cancelImport() trigger token dulu baru cancel sub
- model_manager_screen: konfirmasi dialog cancel + UI tile tampilkan ETA & speed
- llama_jni.cpp: Memory V2 API (llama.cpp b10350+)
"
```

---

## Langkah 4 — Push

```bash
git push origin main
# atau jika branch kamu 'master':
git push origin master
```

---

## Langkah 5 — Build di GitHub Actions (opsional)

Jika kamu sudah punya workflow `.github/workflows/build.yml`, build akan
trigger otomatis setelah push.

Jika belum, buat file `.github/workflows/build_android.yml`:

```yaml
name: Build Android APK

on:
  push:
    branches: [main, master]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.27.0'
          channel: 'stable'
      - run: flutter pub get
      - run: flutter build apk --release --split-per-abi
      - uses: actions/upload-artifact@v4
        with:
          name: apk-release
          path: build/app/outputs/flutter-apk/*.apk
```

---

## ⚠️ Sebelum Build — Pastikan

1. `android/app/google-services.json` sudah ada (dari Firebase Console)
2. `android/key.properties` + keystore sudah dikonfigurasi untuk release build
3. `lib/firebase_options.dart` sudah ada (generate via `flutterfire configure`)
4. Native llama.cpp `.so` sudah dicompile atau CMakeLists.txt sudah benar
   → lihat `LLAMA_NATIVE_PLUGIN.md` untuk instruksi build native

