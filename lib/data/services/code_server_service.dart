// lib/data/services/code_server_service.dart
// KanMonAI — Code Server Service (Native, tanpa Termux)
//
// Mengelola lifecycle code-server (VS Code di browser):
//   • Cek bundle APK via ToolsService
//   • Tulis config code-server (no-auth, port 9191) ke internal storage
//   • Start/stop code-server sebagai background process via node
//   • Inject ANTHROPIC_API_KEY ke environment
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanmongo/core/tools/tools_service.dart';

// ── Install Step ──────────────────────────────────────────────────────────────
enum CodeServerStep {
  checkingBundle,
  extractingBundle,
  writingConfig,
  verifying,
  done,
  error,
}

// ── Install Event ─────────────────────────────────────────────────────────────
class CodeServerInstallEvent {
  final CodeServerStep step;
  final String message;
  final bool isError;
  final double progress;

  const CodeServerInstallEvent({
    required this.step,
    required this.message,
    this.isError = false,
    required this.progress,
  });
}

// ── Code Server Status ────────────────────────────────────────────────────────
enum CodeServerStatus {
  notInstalled,
  installed,
  running,
  error,
}

// ── Code Server Service ───────────────────────────────────────────────────────
class CodeServerService {
  CodeServerService._();
  static final CodeServerService instance = CodeServerService._();

  // SharedPreferences keys
  static const _kInstalled     = 'code_server_installed';
  static const _kNodeInstalled = 'code_server_node_installed';
  static const _kApiKey        = 'code_server_anthropic_key';
  static const _kPort          = 'code_server_port';

  static const int _defaultPort = 9191;

  // State
  bool _installed    = false;
  bool _nodeInstalled = false;
  Process? _serverProcess;
  int _port          = _defaultPort;
  bool _prefsLoaded  = false;
  String? _anthropicKey;

  bool get isInstalled => _installed;
  bool get isRunning   => _serverProcess != null;
  int  get port        => _port;
  String get serverUrl => 'http://localhost:$_port';

  // ── Load Prefs ──────────────────────────────────────────────────────────────
  Future<void> _loadPrefs() async {
    if (_prefsLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _installed     = prefs.getBool(_kInstalled)     ?? false;
    _nodeInstalled = prefs.getBool(_kNodeInstalled)  ?? false;
    _anthropicKey  = prefs.getString(_kApiKey);
    _port          = prefs.getInt(_kPort)            ?? _defaultPort;
    _prefsLoaded   = true;
  }

  Future<void> _saveInstalled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kInstalled, true);
    await prefs.setBool(_kNodeInstalled, true);
  }

  Future<void> setAnthropicKey(String key) async {
    _anthropicKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kApiKey, _anthropicKey!);
  }

  Future<String?> getAnthropicKey() async {
    await _loadPrefs();
    return _anthropicKey;
  }

  // ── Check Status ────────────────────────────────────────────────────────────
  Future<CodeServerStatus> checkStatus() async {
    await _loadPrefs();
    if (!_installed) return CodeServerStatus.notInstalled;
    if (isRunning)   return CodeServerStatus.running;

    // Cek entry.js dari bundle (tidak ada Termux path)
    if (!ToolsService.instance.isReady) return CodeServerStatus.notInstalled;
    final cliPath = ToolsService.instance.codeServerCliPath;
    if (File(cliPath).existsSync()) return CodeServerStatus.installed;

    return CodeServerStatus.notInstalled;
  }

  // ── Install Pipeline ────────────────────────────────────────────────────────
  Stream<CodeServerInstallEvent> install() async* {
    await _loadPrefs();

    // Step 1: Cek / extract bundle
    yield const CodeServerInstallEvent(
      step: CodeServerStep.checkingBundle,
      message: 'Memeriksa bundle tools bawaan...',
      progress: 0.05,
    );

    if (!ToolsService.instance.isReady) {
      yield const CodeServerInstallEvent(
        step: CodeServerStep.extractingBundle,
        message: 'Mengekstrak tools dari APK... (sekali saja)',
        progress: 0.10,
      );

      try {
        await ToolsService.instance.initialize(onProgress: (_) {});
      } catch (e) {
        yield CodeServerInstallEvent(
          step: CodeServerStep.error,
          message: 'Gagal mengekstrak tools: $e\n'
              'Pastikan APK dibangun dengan bundle tools di build.yml.',
          isError: true,
          progress: 0.15,
        );
        return;
      }
    }

    if (!ToolsService.instance.isReady) {
      yield const CodeServerInstallEvent(
        step: CodeServerStep.error,
        message: 'Bundle tools tidak ditemukan dalam APK.\n'
            'Rebuild APK via GitHub Actions agar tools ter-bundle.',
        isError: true,
        progress: 0.15,
      );
      return;
    }

    // Pastikan code-server CLI ada di bundle
    if (!File(ToolsService.instance.codeServerCliPath).existsSync()) {
      throw Exception(
        'code-server tidak ada dalam bundle APK.\n'
        'Rebuild APK via GitHub Actions dengan bundle code-server diaktifkan.',
      );
    }

    yield CodeServerInstallEvent(
      step: CodeServerStep.checkingBundle,
      message: 'Tools siap: code-server '
          '${ToolsService.instance.manifest?.codeServerVersion ?? ''}',
      progress: 0.50,
    );

    // Step 2: Tulis config YAML
    yield const CodeServerInstallEvent(
      step: CodeServerStep.writingConfig,
      message: 'Menulis konfigurasi code-server...',
      progress: 0.70,
    );

    final configResult = await _writeConfigYaml();
    if (configResult.isError) {
      yield configResult;
      return;
    }
    yield configResult;

    // Step 3: Verifikasi
    yield const CodeServerInstallEvent(
      step: CodeServerStep.verifying,
      message: 'Memverifikasi...',
      progress: 0.92,
    );

    if (!File(ToolsService.instance.codeServerCliPath).existsSync()) {
      yield const CodeServerInstallEvent(
        step: CodeServerStep.error,
        message: 'Verifikasi gagal — entry.js code-server tidak ditemukan.',
        isError: true,
        progress: 0.95,
      );
      return;
    }

    await _saveInstalled();
    _installed = true;

    yield const CodeServerInstallEvent(
      step: CodeServerStep.done,
      message: '✅ code-server siap dijalankan (native, tanpa Termux)!',
      progress: 1.0,
    );
  }

  Future<CodeServerInstallEvent> _writeConfigYaml() async {
    try {
      final toolsRoot = ToolsService.instance.toolsRoot;
      final configDir = Directory('$toolsRoot/.kanmon/code-server');
      configDir.createSync(recursive: true);

      await File('${configDir.path}/config.yaml').writeAsString(
        'bind-addr: 127.0.0.1:$_port\n'
        'auth: none\n'
        'cert: false\n',
      );

      return const CodeServerInstallEvent(
        step: CodeServerStep.writingConfig,
        message: 'config.yaml berhasil ditulis.',
        progress: 0.85,
      );
    } catch (e) {
      return CodeServerInstallEvent(
        step: CodeServerStep.error,
        message: 'Gagal menulis config.yaml: $e',
        isError: true,
        progress: 0.72,
      );
    }
  }

  // ── Start Server ────────────────────────────────────────────────────────────
  Future<bool> start({String? anthropicKey}) async {
    await _loadPrefs();

    if (isRunning) {
      debugPrint('[CodeServer] Already running on port $_port');
      return true;
    }

    if (!File(ToolsService.instance.codeServerCliPath).existsSync()) {
      throw Exception(
        'code-server tidak ada dalam bundle APK.\n'
        'Rebuild APK via GitHub Actions dengan bundle code-server diaktifkan.',
      );
    }

    final apiKey = anthropicKey ?? _anthropicKey ?? '';

    try {
      final env = {
        ...Platform.environment,
        'HOME': ToolsService.instance.toolsRoot,
        'NODE_PATH':
            '${ToolsService.instance.toolsRoot}/${ToolsService.instance.abi}/npm_modules',
        'PATH':
            '${ToolsService.instance.binDir}:${Platform.environment['PATH'] ?? ''}',
        if (apiKey.isNotEmpty) 'ANTHROPIC_API_KEY': apiKey,
        if (apiKey.isNotEmpty) 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC': '1',
      };

      _serverProcess = await Process.start(
        ToolsService.instance.nodePath,
        [
          ToolsService.instance.codeServerCliPath,
          '--bind-addr', '127.0.0.1:$_port',
          '--auth', 'none',
          '--disable-update-check',
        ],
        environment: env,
        runInShell: false,
      );

      // Drain stdout/stderr agar tidak buffer penuh
      _serverProcess!.stdout.listen((_) {});
      _serverProcess!.stderr.listen((_) {});

      _serverProcess!.exitCode.then((_) {
        _serverProcess = null;
        debugPrint('[CodeServer] Server process exited');
      });

      // Tunggu server ready (max 10 detik)
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (await _pingServer()) {
          debugPrint('[CodeServer] Server ready on port $_port');
          return true;
        }
      }

      debugPrint('[CodeServer] Server did not respond within 10s');
      return false;
    } catch (e) {
      debugPrint('[CodeServer] Start error: $e');
      _serverProcess = null;
      return false;
    }
  }

  // ── Stop Server ─────────────────────────────────────────────────────────────
  Future<void> stop() async {
    try {
      _serverProcess?.kill();
    } catch (_) {}
    _serverProcess = null;
    debugPrint('[CodeServer] Server stopped');
  }

  // ── Ping server ─────────────────────────────────────────────────────────────
  Future<bool> _pingServer() async {
    try {
      final socket = await Socket.connect(
        '127.0.0.1', _port,
        timeout: const Duration(milliseconds: 500),
      );
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Reset install state ─────────────────────────────────────────────────────
  Future<void> resetInstallState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kInstalled);
    await prefs.remove(_kNodeInstalled);
    _installed     = false;
    _nodeInstalled = false;
    _prefsLoaded   = false;
    debugPrint('[CodeServer] Install state reset');
  }

  // ── getLaunchCommand (for terminal hint) ────────────────────────────────────
  String getLaunchCommand() {
    final node = ToolsService.instance.nodePath;
    final cli  = ToolsService.instance.codeServerCliPath;
    return '$node $cli --bind-addr 127.0.0.1:$_port --auth none --disable-update-check';
  }
}
