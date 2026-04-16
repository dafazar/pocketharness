# KanMonAI — Native Environment Guide

## Arsitektur

KanMonAI menjalankan Claude Code CLI dan VS Code (code-server) secara **native**
di dalam APK, tanpa memerlukan app Termux eksternal.

## Cara Kerja

### Build time (GitHub Actions)
CI/CD (`build.yml`) otomatis:
1. Download Node.js ARM64 dari Termux packages (Bionic libc)
2. Install `@anthropic-ai/claude-code` via npm
3. Bundle git + ripgrep ARM64
4. Generate `tools_manifest.json` dengan versi dan runId
5. Pack ke `tools_arm64-v8a.tar.gz`
6. Inject ke `assets/tools/` sebelum `flutter build apk`

### Runtime (dalam APK)
1. `ToolsService.initialize()` dipanggil saat app start
2. Cek `SharedPreferences` key `tools_extracted_run_id`
3. Jika runId cocok → skip extract, langsung ready
4. Jika belum → extract `assets/tools/tools_arm64-v8a.tar.gz` ke `{appSupportDir}/tools/`
5. Set executable bit pada semua binary
6. Service lain (ClaudeCodeInstaller, CodeServerService, TerminalService) gunakan
   getter dari `ToolsService.instance`

## Struktur Path (Runtime)

```
{getApplicationSupportDirectory()}/tools/
  tools_manifest.json
  arm64-v8a/
    node                         ← Node.js binary
    npm_modules/
      @anthropic-ai/claude-code/
        cli.js                   ← Claude Code entry point
      code-server/
        out/node/entry.js        ← code-server entry point
    bin/
      git
      rg
    launcher/
      claude_code_launcher.sh
```

## Key Files

| File | Peran |
|------|-------|
| `lib/core/tools/tools_service.dart` | Extract + manage bundled tools |
| `lib/data/services/claude_code_installer.dart` | Lifecycle Claude Code (native) |
| `lib/data/services/code_server_service.dart` | Lifecycle code-server (native) |
| `lib/data/services/terminal_service.dart` | Shell execution + native fallback |
| `android/.../NativeEnvPlugin.kt` | Kotlin bridge — exec binary dari internal storage |
| `android/.../TermuxBridgePlugin.kt` | Kotlin bridge — Termux (tetap ada, opsional) |
| `.github/workflows/build.yml` | CI/CD — bundle tools ke APK |

## Build & Deploy

```bash
# Push ke GitHub, lalu jalankan GitHub Actions:
# Target: apk-release-arm64
# Tools akan otomatis ter-bundle saat CI build.
# Tidak perlu langkah manual apapun.
```

## Backward Compatibility

- `TermuxBridgePlugin.kt` tetap ada — jika user punya Termux, tetap bisa digunakan
- `TerminalService` cek Termux dulu, fallback ke native tools jika tidak ada
- Tidak ada breaking change untuk fitur yang sudah ada

## Troubleshooting

**"Bundle tools tidak ditemukan dalam APK"**
→ APK tidak di-build via GitHub Actions, atau step bundle tools gagal.
→ Cek log CI/CD, pastikan step "Bundle Node.js" berhasil.

**"code-server tidak ada dalam bundle APK"**
→ Build CI tidak menyertakan code-server.
→ Aktifkan bundle code-server di `build.yml`.

**Tools sudah ter-bundle tapi tidak bisa dieksekusi**
→ Cek apakah `ToolsService.verifyTools()` return `true`.
→ Coba `ToolsService.clearExtractedState()` lalu `initialize()` ulang.
