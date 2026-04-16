// lib/data/services/code_server_service.dart
// KanMon GO — Code Server Service
//
// Mengelola lifecycle code-server (VS Code di browser) + Claude Code CLI:
//   • Cek & install Node.js via Termux
//   • Install code-server via npm
//   • Install @anthropic-ai/claude-code via npm
//   • Tulis config code-server (no-auth, port 9191)
//   • Start/stop code-server sebagai background process
//   • Inject ANTHROPIC_API_KEY ke environment
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanmongo/data/services/terminal_service.dart';

// ── Install Step ──────────────────────────────────────────────────────────────
enum CodeServerStep {
  checkingTermux,
  checkingNode,
  installingNode,
  checkingCodeServer,
  installingCodeServer,
  installingClaudeCode,
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
  final double progress; // 0.0 – 1.0

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
  static const _kInstalled       = 'code_server_installed';
  static const _kNodeInstalled   = 'code_server_node_installed';
  static const _kApiKey          = 'code_server_anthropic_key';
  static const _kPort            = 'code_server_port';

  static const int _defaultPort  = 9191;
  static const String _termuxPrefix = '/data/data/com.termux/files/usr';
  static const String _termuxHome   = '/data/data/com.termux/files/home';

  // State
  bool _installed        = false;
  bool _nodeInstalled    = false;
  Process? _serverProcess;
  int _port              = _defaultPort;
  bool _prefsLoaded      = false;
  String? _anthropicKey;

  bool get isInstalled  => _installed;
  bool get isRunning    => _serverProcess != null;
  int  get port         => _port;
  String get serverUrl  => 'http://localhost:$_port';

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

  // ── Check Installed ─────────────────────────────────────────────────────────
  Future<CodeServerStatus> checkStatus() async {
    await _loadPrefs();
    if (!_installed) return CodeServerStatus.notInstalled;
    if (isRunning)   return CodeServerStatus.running;

    // Cek binary tersedia di Termux
    final csBin = '$_termuxPrefix/bin/code-server';
    if (File(csBin).existsSync()) return CodeServerStatus.installed;

    // Cek via npm global bin
    final npmBin = '$_termuxHome/.npm-global/bin/code-server';
    if (File(npmBin).existsSync()) return CodeServerStatus.installed;

    return CodeServerStatus.notInstalled;
  }

  // ── Install Pipeline ────────────────────────────────────────────────────────
  Stream<CodeServerInstallEvent> install() async* {
    await _loadPrefs();
    final term = TerminalService.instance;
    await term.init();

    // Step 1: Cek Termux
    yield CodeServerInstallEvent(
      step: CodeServerStep.checkingTermux,
      message: 'Memeriksa Termux...',
      progress: 0.05,
    );

    if (!term.isTermuxAvailable) {
      yield CodeServerInstallEvent(
        step: CodeServerStep.error,
        message: '❌ Termux tidak ditemukan.\n'
            'Install Termux dari F-Droid: https://f-droid.org/packages/com.termux/\n'
            'Buka Termux sekali, lalu coba lagi.',
        isError: true,
        progress: 0.0,
      );
      return;
    }

    yield CodeServerInstallEvent(
      step: CodeServerStep.checkingTermux,
      message: '✅ Termux tersedia.',
      progress: 0.10,
    );

    // Step 2: Cek / Install Node.js
    yield CodeServerInstallEvent(
      step: CodeServerStep.checkingNode,
      message: 'Memeriksa Node.js...',
      progress: 0.15,
    );

    final nodeCheck = await term.run('node --version');
    if (!nodeCheck.isSuccess || nodeCheck.stdout.trim().isEmpty) {
      yield CodeServerInstallEvent(
        step: CodeServerStep.installingNode,
        message: '📦 Menginstall Node.js via Termux (±100MB)...',
        progress: 0.20,
      );

      // Update pkg dulu
      await for (final line in term.installPackageStream('nodejs-lts', update: true)) {
        yield CodeServerInstallEvent(
          step: CodeServerStep.installingNode,
          message: line.trim(),
          progress: 0.35,
        );
      }

      final nodeVerify = await term.run('node --version');
      if (!nodeVerify.isSuccess) {
        yield CodeServerInstallEvent(
          step: CodeServerStep.error,
          message: '❌ Gagal install Node.js: ${nodeVerify.stderr}',
          isError: true,
          progress: 0.0,
        );
        return;
      }

      yield CodeServerInstallEvent(
        step: CodeServerStep.installingNode,
        message: '✅ Node.js ${nodeVerify.stdout.trim()} terinstall.',
        progress: 0.40,
      );
    } else {
      yield CodeServerInstallEvent(
        step: CodeServerStep.checkingNode,
        message: '✅ Node.js ${nodeCheck.stdout.trim()} sudah ada.',
        progress: 0.30,
      );
    }

    // Step 3: Setup npm global path di Termux
    yield CodeServerInstallEvent(
      step: CodeServerStep.checkingCodeServer,
      message: 'Mengatur npm prefix...',
      progress: 0.42,
    );
    await term.run('npm config set prefix $_termuxHome/.npm-global');

    // Step 4: Cek / Install code-server
    yield CodeServerInstallEvent(
      step: CodeServerStep.checkingCodeServer,
      message: 'Memeriksa code-server...',
      progress: 0.45,
    );

    final csCheck = await term.run(
        'PATH=\$PATH:$_termuxHome/.npm-global/bin code-server --version');
    if (!csCheck.isSuccess || csCheck.stdout.trim().isEmpty) {
      yield CodeServerInstallEvent(
        step: CodeServerStep.installingCodeServer,
        message: '📦 Menginstall code-server (±200MB, mungkin 5–10 menit)...',
        progress: 0.48,
      );

      await for (final line in term.runStream(
        'npm install -g code-server --prefix $_termuxHome/.npm-global',
        timeout: const Duration(minutes: 15),
      )) {
        if (line.trim().isNotEmpty) {
          yield CodeServerInstallEvent(
            step: CodeServerStep.installingCodeServer,
            message: line.trim(),
            progress: 0.65,
          );
        }
      }

      final csVerify = await term.run(
          'PATH=\$PATH:$_termuxHome/.npm-global/bin code-server --version');
      if (!csVerify.isSuccess) {
        yield CodeServerInstallEvent(
          step: CodeServerStep.error,
          message: '❌ Gagal install code-server: ${csVerify.stderr}',
          isError: true,
          progress: 0.0,
        );
        return;
      }

      yield CodeServerInstallEvent(
        step: CodeServerStep.installingCodeServer,
        message: '✅ code-server ${csVerify.stdout.trim()} terinstall.',
        progress: 0.70,
      );
    } else {
      yield CodeServerInstallEvent(
        step: CodeServerStep.checkingCodeServer,
        message: '✅ code-server ${csCheck.stdout.trim()} sudah ada.',
        progress: 0.60,
      );
    }

    // Step 5: Install @anthropic-ai/claude-code
    yield CodeServerInstallEvent(
      step: CodeServerStep.installingClaudeCode,
      message: '📦 Menginstall @anthropic-ai/claude-code...',
      progress: 0.72,
    );

    await for (final line in term.runStream(
      'npm install -g @anthropic-ai/claude-code --prefix $_termuxHome/.npm-global',
      timeout: const Duration(minutes: 10),
    )) {
      if (line.trim().isNotEmpty) {
        yield CodeServerInstallEvent(
          step: CodeServerStep.installingClaudeCode,
          message: line.trim(),
          progress: 0.82,
        );
      }
    }

    // Step 6: Tulis config code-server (no-auth)
    yield CodeServerInstallEvent(
      step: CodeServerStep.writingConfig,
      message: 'Menulis konfigurasi code-server...',
      progress: 0.85,
    );

    final configDir = '$_termuxHome/.config/code-server';
    await term.run('mkdir -p $configDir');
    await term.writeFile(
      '$configDir/config.yaml',
      'bind-addr: 127.0.0.1:$_port\n'
      'auth: none\n'
      'cert: false\n',
    );

    // Step 7: Verifikasi
    yield CodeServerInstallEvent(
      step: CodeServerStep.verifying,
      message: 'Memverifikasi instalasi...',
      progress: 0.92,
    );

    final finalCheck = await term.run(
        'PATH=\$PATH:$_termuxHome/.npm-global/bin code-server --version');
    if (!finalCheck.isSuccess) {
      yield CodeServerInstallEvent(
        step: CodeServerStep.error,
        message: '❌ Verifikasi gagal: ${finalCheck.stderr}',
        isError: true,
        progress: 0.0,
      );
      return;
    }

    await _saveInstalled();
    _installed = true;

    yield CodeServerInstallEvent(
      step: CodeServerStep.done,
      message: '✅ Instalasi selesai! code-server siap dijalankan.',
      progress: 1.0,
    );
  }

  // ── Start Server ────────────────────────────────────────────────────────────
  Future<bool> start({String? anthropicKey}) async {
    await _loadPrefs();

    if (isRunning) {
      debugPrint('[CodeServer] Already running on port $_port');
      return true;
    }

    final key = anthropicKey ?? _anthropicKey ?? '';
    final csPath = '$_termuxHome/.npm-global/bin/code-server';

    if (!File(csPath).existsSync()) {
      debugPrint('[CodeServer] code-server binary not found at $csPath');
      return false;
    }

    try {
      final env = {
        ...Platform.environment,
        'PATH': '${Platform.environment['PATH']}:$_termuxPrefix/bin:$_termuxHome/.npm-global/bin',
        'HOME': _termuxHome,
        if (key.isNotEmpty) 'ANTHROPIC_API_KEY': key,
        if (key.isNotEmpty) 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC': '1',
      };

      _serverProcess = await Process.start(
        csPath,
        ['--bind-addr', '127.0.0.1:$_port', '--auth', 'none'],
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
  String getLaunchCommand() =>
      'PATH=\$PATH:$_termuxHome/.npm-global/bin code-server '
      '--bind-addr 127.0.0.1:$_port --auth none';
}
