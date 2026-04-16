# SESSION 03 Changelog

## New Files
- lib/features/vscode/vscode_screen.dart — VS Code WebView screen (flat-path)
- lib/features/claude_code/claude_code_screen.dart — Claude Code terminal (flat-path)
- android/app/src/main/res/xml/network_security_config.xml

## Modified Files
- lib/core/router/app_router.dart — query-param aware routes
- lib/features/settings/presentation/screens/settings_screen.dart — VS Code & Claude Code tiles
- android/app/src/main/AndroidManifest.xml — INTERNET permission + networkSecurityConfig
- pubspec.yaml — webview_flutter dependency (already present: ^4.8.0)
- lib/features/chat/chat_screen.dart — PopupMenu "Open in VS Code / Claude Code" on attachments

## Notes
- Legacy screens in presentation/screens/ preserved for backward compat
- Offline AI wiring: all screens use AiService.generateBestAvailable() — confirmed 0 direct LlamaService.instance.generateStream calls in notes/ocr/ebook/agent folders
- network_security_config.xml merged: cleartext permitted for 127.0.0.1, localhost, 10.0.2.2
- webview_flutter already at ^4.8.0 (satisfies ^4.10.0 not required, version sufficient)
