// lib/data/services/claude_code_installer.dart
// KanMonAI — Claude Code CLI Installer & Environment Configurator
//
// Installs @anthropic-ai/claude-code into Termux and configures it to use
// KanMonAI's local llama.cpp HTTP server as the AI backend.
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanmongo/data/services/terminal_service.dart';

// ── Install Step Enum ─────────────────────────────────────────────────────────
enum ClaudeInstallStep {
  checkingTermux,
  checkingNode,
  installingNode,
  checkingNpm,
  installingClaudeCode,
  writingWrapperScript,
  writingSettings,
  verifying,
  done,
  error,
}

// ── Install Event ─────────────────────────────────────────────────────────────
class ClaudeInstallEvent {
  final ClaudeInstallStep step;
  final String message;
  final bool isError;
  final double progress; // 0.0 – 1.0

  const ClaudeInstallEvent({
    required this.step,
    required this.message,
    this.isError = false,
    required this.progress,
  });

  @override
  String toString() =>
      '[${step.name}] ${isError ? "ERROR: " : ""}$message (${(progress * 100).toStringAsFixed(0)}%)';
}

// ── Claude Code Installer ─────────────────────────────────────────────────────
class ClaudeCodeInstaller {
  ClaudeCodeInstaller._();
  static final ClaudeCodeInstaller instance = ClaudeCodeInstaller._();

  // SharedPreferences keys
  static const _kInstalled  = 'claude_code_installed';
  static const _kConfigured = 'claude_code_configured';
  static const _kClaudePath = 'claude_code_path';
  static const _kServerPort = 'claude_code_server_port';

  // Termux path constants
  static const _termuxPrefix = '/data/data/com.termux/files/usr';
  static const _termuxHome   = '/data/data/com.termux/files/home';
  static const _termuxBin    = '/data/data/com.termux/files/usr/bin';

  // In-memory cache
  bool _isInstalled  = false;
  bool _isConfigured = false;
  String? _claudeCodePath;
  int? _serverPort;
  bool _prefsLoaded = false;

  // ── Public State ────────────────────────────────────────────────────────────
  bool get isInstalled  => _isInstalled;
  bool get isConfigured => _isConfigured;
  String? get claudeCodePath => _claudeCodePath;
  int? get serverPort => _serverPort;

  // ── Load Prefs ──────────────────────────────────────────────────────────────
  Future<void> _loadPrefs() async {
    if (_prefsLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _isInstalled  = prefs.getBool(_kInstalled)  ?? false;
    _isConfigured = prefs.getBool(_kConfigured) ?? false;
    _claudeCodePath = prefs.getString(_kClaudePath);
    _serverPort   = prefs.getInt(_kServerPort);
    _prefsLoaded  = true;
    debugPrint('[ClaudeCodeInstaller] Prefs loaded — installed: $_isInstalled, configured: $_isConfigured');
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kInstalled, _isInstalled);
    await prefs.setBool(_kConfigured, _isConfigured);
    if (_claudeCodePath != null) {
      await prefs.setString(_kClaudePath, _claudeCodePath!);
    } else {
      await prefs.remove(_kClaudePath);
    }
    if (_serverPort != null) {
      await prefs.setInt(_kServerPort, _serverPort!);
    }
  }

  // ── Check Installed ─────────────────────────────────────────────────────────
  /// Checks SharedPreferences first, then verifies the CLI file actually exists
  /// on disk (cache can be stale after uninstall).
  Future<bool> checkInstalled() async {
    await _loadPrefs();
    debugPrint('[ClaudeCodeInstaller] checkInstalled() — cached: $_isInstalled');

    // Always verify disk state regardless of cache
    final cliJs = File('$_termuxPrefix/lib/node_modules/@anthropic-ai/claude-code/cli.js');
    final diskExists = cliJs.existsSync();

    if (!diskExists) {
      // Disk says not installed — update cache accordingly
      if (_isInstalled) {
        debugPrint('[ClaudeCodeInstaller] Cache stale — CLI not found on disk, updating cache');
        _isInstalled  = false;
        _isConfigured = false;
        _claudeCodePath = null;
        await _savePrefs();
      }
      return false;
    }

    // File exists on disk
    if (!_isInstalled) {
      // Update stale cache
      _isInstalled = true;
      _claudeCodePath = cliJs.path;
      await _savePrefs();
    }

    debugPrint('[ClaudeCodeInstaller] Claude Code verified at: ${cliJs.path}');
    return true;
  }

  // ── Full Install Pipeline ───────────────────────────────────────────────────
  Stream<ClaudeInstallEvent> install() async* {
    await _loadPrefs();
    final svc = TerminalService.instance;

    // ── Step 1: Check Termux ──────────────────────────────────────────────────
    yield const ClaudeInstallEvent(
      step: ClaudeInstallStep.checkingTermux,
      message: 'Memeriksa Termux...',
      progress: 0.05,
    );

    await svc.init();
    // BUG FIX: Force re-check Termux via PackageManager, bukan cache lama.
    // Ini penting jika app sudah berjalan sebelum Termux diinstall.
    await svc.resetTermuxState();

    if (!svc.hasTermux) {
      yield const ClaudeInstallEvent(
        step: ClaudeInstallStep.error,
        message: 'Termux tidak ditemukan. Install Termux dari F-Droid terlebih dahulu.',
        isError: true,
        progress: 0.05,
      );
      return;
    }
    debugPrint('[ClaudeCodeInstaller] Termux OK: $_termuxPrefix');

    // ── Step 2: Check Node.js ─────────────────────────────────────────────────
    yield const ClaudeInstallEvent(
      step: ClaudeInstallStep.checkingNode,
      message: 'Memeriksa Node.js...',
      progress: 0.10,
    );

    final nodeCheck = await svc.run('$_termuxBin/node --version',
        timeout: const Duration(seconds: 10));
    final nodeInstalled = nodeCheck.exitCode == 0 && nodeCheck.stdout.trim().isNotEmpty;
    debugPrint('[ClaudeCodeInstaller] node check: exit=${nodeCheck.exitCode}, out=${nodeCheck.stdout.trim()}');

    // ── Step 3: Install Node if missing ───────────────────────────────────────
    if (!nodeInstalled) {
      yield const ClaudeInstallEvent(
        step: ClaudeInstallStep.installingNode,
        message: 'Node.js tidak ditemukan. Menginstall nodejs via pkg...',
        progress: 0.20,
      );

      bool nodeOk = false;
      await for (final chunk in svc.runStream(
        '$_termuxBin/pkg install -y nodejs',
        timeout: const Duration(minutes: 5),
      )) {
        debugPrint('[ClaudeCodeInstaller] pkg install nodejs: $chunk');
        yield ClaudeInstallEvent(
          step: ClaudeInstallStep.installingNode,
          message: chunk.trim().isEmpty ? 'Installing nodejs...' : chunk.trim(),
          progress: 0.25,
        );
        if (chunk.contains('installed') || chunk.contains('already')) nodeOk = true;
      }

      // Verify after install
      final nodeVerify = await svc.run('$_termuxBin/node --version',
          timeout: const Duration(seconds: 10));
      if (nodeVerify.exitCode != 0) {
        yield const ClaudeInstallEvent(
          step: ClaudeInstallStep.error,
          message: 'Gagal menginstall Node.js. Coba manual: pkg install nodejs',
          isError: true,
          progress: 0.28,
        );
        return;
      }
      debugPrint('[ClaudeCodeInstaller] Node.js installed: ${nodeVerify.stdout.trim()}');
    } else {
      yield ClaudeInstallEvent(
        step: ClaudeInstallStep.checkingNode,
        message: 'Node.js sudah terinstall: ${nodeCheck.stdout.trim()}',
        progress: 0.15,
      );
    }

    // ── Step 4: Check npm ─────────────────────────────────────────────────────
    yield const ClaudeInstallEvent(
      step: ClaudeInstallStep.checkingNpm,
      message: 'Memeriksa npm...',
      progress: 0.35,
    );

    final npmCheck = await svc.run('$_termuxBin/npm --version',
        timeout: const Duration(seconds: 10));
    if (npmCheck.exitCode != 0) {
      yield const ClaudeInstallEvent(
        step: ClaudeInstallStep.error,
        message: 'npm tidak ditemukan setelah install nodejs. Coba: pkg install nodejs',
        isError: true,
        progress: 0.36,
      );
      return;
    }
    debugPrint('[ClaudeCodeInstaller] npm OK: ${npmCheck.stdout.trim()}');

    yield ClaudeInstallEvent(
      step: ClaudeInstallStep.checkingNpm,
      message: 'npm tersedia: ${npmCheck.stdout.trim()}',
      progress: 0.38,
    );

    // ── Step 5: Install @anthropic-ai/claude-code ─────────────────────────────
    yield const ClaudeInstallEvent(
      step: ClaudeInstallStep.installingClaudeCode,
      message: 'Menginstall @anthropic-ai/claude-code (ini bisa memakan 2-5 menit)...',
      progress: 0.40,
    );

    final npmInstallCmd =
        'PREFIX=$_termuxPrefix NODE_PATH=$_termuxPrefix/lib/node_modules '
        '$_termuxBin/npm install -g @anthropic-ai/claude-code --prefer-offline';

    bool installError = false;
    await for (final chunk in svc.runStream(
      npmInstallCmd,
      timeout: const Duration(minutes: 10),
    )) {
      final trimmed = chunk.trim();
      debugPrint('[ClaudeCodeInstaller] npm install: $chunk');
      if (trimmed.isNotEmpty) {
        final isErr = trimmed.toLowerCase().contains('error') ||
            trimmed.toLowerCase().contains('err!') ||
            trimmed.toLowerCase().contains('npm warn');
        if (trimmed.toLowerCase().contains('err!') ||
            chunk.contains('ENOTFOUND') ||
            chunk.contains('EACCES') ||
            chunk.contains('code E')) {
          installError = true;
        }
        yield ClaudeInstallEvent(
          step: ClaudeInstallStep.installingClaudeCode,
          message: trimmed,
          isError: isErr && !trimmed.toLowerCase().contains('npm warn'),
          progress: 0.40 + 0.35 * 0.5, // approximate mid-progress
        );
      }
    }

    // Re-verify with disk check
    final cliPath = '$_termuxPrefix/lib/node_modules/@anthropic-ai/claude-code/cli.js';
    if (installError || !File(cliPath).existsSync()) {
      yield const ClaudeInstallEvent(
        step: ClaudeInstallStep.error,
        message: 'Gagal menginstall @anthropic-ai/claude-code. Cek koneksi internet dan coba lagi.',
        isError: true,
        progress: 0.75,
      );
      return;
    }

    yield const ClaudeInstallEvent(
      step: ClaudeInstallStep.installingClaudeCode,
      message: '@anthropic-ai/claude-code berhasil diinstall.',
      progress: 0.78,
    );

    // ── Step 6: Write wrapper script ──────────────────────────────────────────
    yield const ClaudeInstallEvent(
      step: ClaudeInstallStep.writingWrapperScript,
      message: 'Menulis wrapper script kanmon-claude...',
      progress: 0.80,
    );

    final port = _serverPort ?? 8080;
    final wrapperResult = await _writeWrapperScript(port);
    if (wrapperResult.isError) {
      yield wrapperResult;
      return;
    }
    yield wrapperResult;

    // ── Step 7: Write ~/.claude/settings.json ────────────────────────────────
    yield const ClaudeInstallEvent(
      step: ClaudeInstallStep.writingSettings,
      message: 'Menulis ~/.claude/settings.json...',
      progress: 0.88,
    );

    final settingsResult = await _writeSettingsJson();
    if (settingsResult.isError) {
      yield settingsResult;
      return;
    }
    yield settingsResult;

    // ── Step 8: Verify ────────────────────────────────────────────────────────
    yield const ClaudeInstallEvent(
      step: ClaudeInstallStep.verifying,
      message: 'Memverifikasi instalasi...',
      progress: 0.95,
    );

    final verified = await checkInstalled();
    if (!verified) {
      yield const ClaudeInstallEvent(
        step: ClaudeInstallStep.error,
        message: 'Verifikasi gagal — CLI tidak ditemukan setelah instalasi.',
        isError: true,
        progress: 0.97,
      );
      return;
    }

    // Update prefs
    _isInstalled  = true;
    _isConfigured = true;
    _claudeCodePath = cliPath;
    _serverPort   = port;
    await _savePrefs();

    // ── Step 9: Done ──────────────────────────────────────────────────────────
    yield const ClaudeInstallEvent(
      step: ClaudeInstallStep.done,
      message: 'Claude Code siap! Jalankan: kanmon-claude',
      progress: 1.0,
    );
  }

  // ── Configure (standalone) ──────────────────────────────────────────────────
  Future<ClaudeInstallEvent> configure({required int serverPort}) async {
    _serverPort = serverPort;
    final wrapperResult = await _writeWrapperScript(serverPort);
    if (wrapperResult.isError) return wrapperResult;
    final settingsResult = await _writeSettingsJson();
    if (settingsResult.isError) return settingsResult;
    _isConfigured = true;
    await _savePrefs();
    return const ClaudeInstallEvent(
      step: ClaudeInstallStep.done,
      message: 'Konfigurasi selesai.',
      progress: 1.0,
    );
  }

  // ── Write Wrapper Script ────────────────────────────────────────────────────
  Future<ClaudeInstallEvent> _writeWrapperScript(int port) async {
    try {
      final scriptPath = '$_termuxBin/kanmon-claude';
      final script = '''#!/data/data/com.termux/files/usr/bin/bash
# KanMonAI — Claude Code launcher
# Automatically routes to local llama.cpp server

export ANTHROPIC_BASE_URL="http://localhost:$port"
export ANTHROPIC_API_KEY="kanmon-local-llama"
export ANTHROPIC_MODEL="local"
export NODE_PATH="\$PREFIX/lib/node_modules"
export PATH="\$PREFIX/bin:\$PATH"

# Workaround: Termux npm global bin sometimes not in PATH
CLAUDE_CLI="\$PREFIX/lib/node_modules/@anthropic-ai/claude-code/cli.js"
if [ ! -f "\$CLAUDE_CLI" ]; then
  echo "❌ Claude Code not installed. Run: kanmon-server install-claude" >&2
  exit 1
fi

exec node "\$CLAUDE_CLI" "\$@"
''';

      final file = File(scriptPath);
      file.parent.createSync(recursive: true);
      await file.writeAsString(script);

      // chmod +x
      final svc = TerminalService.instance;
      await svc.run('chmod +x $scriptPath',
          timeout: const Duration(seconds: 5));

      debugPrint('[ClaudeCodeInstaller] Wrapper script written: $scriptPath');
      return const ClaudeInstallEvent(
        step: ClaudeInstallStep.writingWrapperScript,
        message: 'Wrapper script kanmon-claude berhasil ditulis.',
        progress: 0.85,
      );
    } catch (e) {
      debugPrint('[ClaudeCodeInstaller] _writeWrapperScript error: $e');
      return ClaudeInstallEvent(
        step: ClaudeInstallStep.error,
        message: 'Gagal menulis wrapper script: $e',
        isError: true,
        progress: 0.82,
      );
    }
  }

  // ── Write Settings JSON ─────────────────────────────────────────────────────
  Future<ClaudeInstallEvent> _writeSettingsJson() async {
    try {
      final settingsDir = Directory('$_termuxHome/.claude');
      settingsDir.createSync(recursive: true);

      final settingsPath = '${settingsDir.path}/settings.json';
      const settingsContent = '''{\n'''
          '''  "apiKeyHelper": null,\n'''
          '''  "autoUpdaterStatus": "disabled",\n'''
          '''  "theme": "dark",\n'''
          '''  "verboseDiff": false,\n'''
          '''  "disableTelemetry": true,\n'''
          '''  "model": "local",\n'''
          '''  "largeContextModel": "local",\n'''
          '''  "smallModel": "local",\n'''
          '''  "hasAcknowledgedCostThreshold": true,\n'''
          '''  "costThresholdDollars": 9999,\n'''
          '''  "costThresholdEnabled": false\n'''
          '''}''';

      await File(settingsPath).writeAsString(settingsContent);
      debugPrint('[ClaudeCodeInstaller] settings.json written: $settingsPath');

      return const ClaudeInstallEvent(
        step: ClaudeInstallStep.writingSettings,
        message: '~/.claude/settings.json berhasil ditulis.',
        progress: 0.92,
      );
    } catch (e) {
      debugPrint('[ClaudeCodeInstaller] _writeSettingsJson error: $e');
      return ClaudeInstallEvent(
        step: ClaudeInstallStep.error,
        message: 'Gagal menulis settings.json: $e',
        isError: true,
        progress: 0.89,
      );
    }
  }

  // ── Get Launch Command ──────────────────────────────────────────────────────
  /// Returns the full shell command to launch Claude Code.
  /// Prefers the node invocation path for reliability on Termux.
  String getLaunchCommand({String? workDir, int serverPort = 8080}) {
    final cliJs =
        '$_termuxPrefix/lib/node_modules/@anthropic-ai/claude-code/cli.js';
    final cdPart = (workDir != null && workDir.isNotEmpty)
        ? 'cd "$workDir" && '
        : '';
    return '${cdPart}ANTHROPIC_BASE_URL=http://localhost:$serverPort '
        'ANTHROPIC_API_KEY=kanmon-local-llama '
        'ANTHROPIC_MODEL=local '
        'node $cliJs';
  }

  // ── Get Node Invocation Command ─────────────────────────────────────────────
  /// Returns the direct node invocation for the claude-code cli.js file,
  /// as a workaround for Termux npm global bin PATH issues.
  /// Returns null if cli.js doesn't exist.
  String? getNodeInvocationCommand() {
    final cliJs =
        '$_termuxPrefix/lib/node_modules/@anthropic-ai/claude-code/cli.js';
    if (!File(cliJs).existsSync()) {
      debugPrint('[ClaudeCodeInstaller] getNodeInvocationCommand: cli.js not found');
      return null;
    }
    final nodeBin = '$_termuxBin/node';
    return '$nodeBin $cliJs';
  }

  // ── Unconfigure ─────────────────────────────────────────────────────────────
  /// Removes the wrapper script and settings.json.
  /// Does NOT uninstall the npm package.
  Future<void> unconfigure() async {
    try {
      final wrapperPath = '$_termuxBin/kanmon-claude';
      final wrapperFile = File(wrapperPath);
      if (wrapperFile.existsSync()) {
        wrapperFile.deleteSync();
        debugPrint('[ClaudeCodeInstaller] Wrapper script removed: $wrapperPath');
      }

      final settingsPath = '$_termuxHome/.claude/settings.json';
      final settingsFile = File(settingsPath);
      if (settingsFile.existsSync()) {
        settingsFile.deleteSync();
        debugPrint('[ClaudeCodeInstaller] settings.json removed: $settingsPath');
      }

      _isConfigured = false;
      await _savePrefs();
    } catch (e) {
      debugPrint('[ClaudeCodeInstaller] unconfigure error: $e');
    }
  }
}
