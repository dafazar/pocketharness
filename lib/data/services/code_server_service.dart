// lib/data/services/code_server_service.dart
// KanMonAI — Code Server Service (Native, tanpa Termux)
//
// Mengelola lifecycle code-server (VS Code di browser):
//   • Auto-init ToolsService saat pertama kali dipakai
//   • Cek bundle APK via ToolsService
//   • Tulis config code-server (no-auth, port 9191) ke internal storage
//   • Start/stop code-server sebagai background process via node
//   • Auto-recover permission jika Permission denied
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
  bool _installed     = false;
  bool _nodeInstalled = false;
  Process? _serverProcess;
  int _port           = _defaultPort;
  bool _prefsLoaded   = false;
  String? _anthropicKey;
  String? _lastStartError;

  bool    get isInstalled    => _installed;
  bool    get isRunning      => _serverProcess != null;
  int     get port           => _port;
  String  get serverUrl      => 'http://localhost:$_port';
  String? get lastStartError => _lastStartError;

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

  // ── Ensure ToolsService ready ───────────────────────────────────────────────
  /// Pastikan ToolsService sudah di-initialize.
  /// Dipanggil sebelum setiap operasi yang butuh tools.
  Future<bool> _ensureToolsReady({void Function(double)? onProgress}) async {
    final svc = ToolsService.instance;
    if (svc.isReady) return true;

    debugPrint('[CodeServer] ToolsService not ready — initializing...');
    try {
      await svc.initialize(onProgress: onProgress);
    } catch (e) {
      debugPrint('[CodeServer] ToolsService.initialize() failed: $e');
      return false;
    }
    return svc.isReady;
  }

  // ── Check Status ────────────────────────────────────────────────────────────
  Future<CodeServerStatus> checkStatus() async {
    await _loadPrefs();
    if (isRunning) return CodeServerStatus.running;

    // Auto-init ToolsService jika belum ready
    final toolsReady = await _ensureToolsReady();
    if (!toolsReady) return CodeServerStatus.notInstalled;

    // Cek apakah node + code-server ada
    final nodeExists       = File(ToolsService.instance.nodePath).existsSync();
    final codeServerExists = File(ToolsService.instance.codeServerCliPath).existsSync();

    if (!nodeExists || !codeServerExists) {
      // Tools tidak lengkap — reset installed flag
      if (_installed) {
        _installed = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kInstalled, false);
      }
      return CodeServerStatus.notInstalled;
    }

    // Tools ada — pastikan _installed flag konsisten
    if (!_installed) {
      // Tools ada di disk tapi flag belum set — tandai sebagai installed
      await _saveInstalled();
      _installed = true;
    }

    return CodeServerStatus.installed;
  }

  // ── Install Pipeline ────────────────────────────────────────────────────────
  Stream<CodeServerInstallEvent> install() async* {
    await _loadPrefs();

    yield const CodeServerInstallEvent(
      step: CodeServerStep.checkingBundle,
      message: 'Memeriksa bundle tools bawaan...',
      progress: 0.05,
    );

    // Extract jika belum ready
    if (!ToolsService.instance.isReady) {
      yield const CodeServerInstallEvent(
        step: CodeServerStep.extractingBundle,
        message: 'Mengekstrak tools dari APK... (sekali saja)',
        progress: 0.10,
      );

      try {
        await ToolsService.instance.initialize(
          onProgress: (_) {},
        );
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

    // Cek code-server CLI
    if (!File(ToolsService.instance.codeServerCliPath).existsSync()) {
      yield CodeServerInstallEvent(
        step: CodeServerStep.error,
        message: 'code-server tidak ada dalam bundle APK.\n'
            'Rebuild APK via GitHub Actions dengan bundle code-server diaktifkan.',
        isError: true,
        progress: 0.15,
      );
      return;
    }

    // Re-apply permissions (pastikan tidak ada yang hilang)
    yield CodeServerInstallEvent(
      step: CodeServerStep.verifying,
      message: 'Memverifikasi permissions binary...',
      progress: 0.40,
    );

    await ToolsService.instance.reapplyPermissions();

    yield CodeServerInstallEvent(
      step: CodeServerStep.checkingBundle,
      message: 'Tools siap: code-server '
          '${ToolsService.instance.manifest?.codeServerVersion ?? ''}',
      progress: 0.50,
    );

    // Tulis config YAML
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

    // Verifikasi final
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
    _lastStartError = null;

    if (isRunning) {
      debugPrint('[CodeServer] Already running on port $_port');
      return true;
    }

    // Auto-init ToolsService jika belum ready
    final toolsReady = await _ensureToolsReady();
    if (!toolsReady) {
      _lastStartError = 'Bundle tools tidak ditemukan dalam APK.\n'
          'Rebuild APK via GitHub Actions agar tools ter-bundle.';
      return false;
    }

    if (!File(ToolsService.instance.codeServerCliPath).existsSync()) {
      _lastStartError = 'code-server tidak ada dalam bundle APK.\n'
          'Rebuild APK via GitHub Actions dengan bundle code-server diaktifkan.';
      debugPrint('[CodeServer] $_lastStartError');
      return false;
    }

    // Pastikan node binary punya permission execute
    final nodeBinary = ToolsService.instance.nodePath;
    if (File(nodeBinary).existsSync()) {
      for (final cmd in ['/system/bin/chmod', '/bin/chmod', 'chmod']) {
        try {
          final r = await Process.run(cmd, ['755', nodeBinary]);
          if (r.exitCode == 0) {
            debugPrint('[CodeServer] Node.js chmod 755: OK via $cmd');
            break;
          }
        } catch (_) { continue; }
      }
    } else {
      _lastStartError = 'Node.js binary tidak ditemukan di:\n$nodeBinary\n'
          'Coba reinstall VS Code.';
      return false;
    }

    final apiKey = anthropicKey ?? _anthropicKey ?? '';

    try {
      final systemPath = Platform.environment['PATH'] ?? '';
      final env = <String, String>{
        ...Platform.environment,
        'HOME': ToolsService.instance.toolsRoot,
        'NODE_PATH': '${ToolsService.instance.toolsRoot}/${ToolsService.instance.abi}/npm_modules',
        'PATH': '${ToolsService.instance.binDir}:$systemPath',
        'NODE_NO_WARNINGS': '1',
        'CS_DISABLE_GETTING_STARTED_OVERRIDE': '1',
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

      final stderrBuf = StringBuffer();
      _serverProcess!.stdout.listen((_) {});
      _serverProcess!.stderr
          .transform(const SystemEncoding().decoder)
          .listen((chunk) {
        stderrBuf.write(chunk);
        debugPrint('[CodeServer/stderr] $chunk');
      });

      bool processExited = false;
      _serverProcess!.exitCode.then((code) {
        processExited = true;
        _serverProcess = null;
        final errOut    = stderrBuf.toString().trim();
        final errSuffix = errOut.isNotEmpty ? ':\n$errOut' : '.';
        _lastStartError = 'Proses code-server berhenti (exit $code)$errSuffix';
        debugPrint('[CodeServer] Server exited: code=$code');
      });

      // Tunggu server ready — max 30 detik
      for (int i = 0; i < 60; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (processExited) {
          // Jika error permission denied — coba auto-fix
          final err = stderrBuf.toString();
          if (err.contains('Permission denied') || err.contains('EACCES')) {
            debugPrint('[CodeServer] Permission denied detected — attempting auto-fix...');
            await ToolsService.instance.reapplyPermissions();
            // Jangan langsung retry dari sini — biarkan user tekan Coba Lagi
            _lastStartError = 'Permission denied.\n\n'
                'Permissions telah diperbaiki otomatis.\n'
                'Silakan tekan "Coba Lagi" untuk memulai ulang VS Code.';
          }
          debugPrint('[CodeServer] Process exited before ready');
          return false;
        }
        if (await _pingServer()) {
          debugPrint('[CodeServer] Server ready on port $_port');
          return true;
        }
      }

      // Timeout
      final errOut    = stderrBuf.toString().trim();
      final errSuffix = errOut.isNotEmpty ? ':\n$errOut' : '.';
      _lastStartError = 'Server tidak merespons dalam 30 detik$errSuffix';
      debugPrint('[CodeServer] Timeout waiting for server');
      return false;

    } catch (e) {
      final errorMsg = e.toString();
      if (errorMsg.contains('Permission denied') || errorMsg.contains('EACCES')) {
        // Auto-fix permissions
        debugPrint('[CodeServer] Permission denied on start — auto-fixing...');
        await ToolsService.instance.reapplyPermissions();
        _lastStartError = 'Permission denied saat memulai Node.js.\n\n'
            'Permissions telah diperbaiki otomatis.\n'
            'Silakan tekan "Coba Lagi" untuk memulai ulang VS Code.';
      } else {
        _lastStartError = 'Exception saat memulai server: $e';
      }
      debugPrint('[CodeServer] Start error: $e');
      _serverProcess = null;
      return false;
    }
  }

  // ── Stop Server ─────────────────────────────────────────────────────────────
  Future<void> stop() async {
    try { _serverProcess?.kill(); } catch (_) {}
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
    } catch (_) { return false; }
  }

  // ── Reset install state ─────────────────────────────────────────────────────
  Future<void> resetInstallState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kInstalled);
    await prefs.remove(_kNodeInstalled);
    _installed     = false;
    _nodeInstalled = false;
    _prefsLoaded   = false;
    // Invalidate ToolsService cache juga agar re-extract
    await ToolsService.instance.invalidateCache();
    debugPrint('[CodeServer] Install state reset');
  }

  String getLaunchCommand() {
    final node = ToolsService.instance.nodePath;
    final cli  = ToolsService.instance.codeServerCliPath;
    return '$node $cli --bind-addr 127.0.0.1:$_port --auth none --disable-update-check';
  }
}
