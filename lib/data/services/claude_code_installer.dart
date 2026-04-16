// lib/data/services/claude_code_installer.dart
// KanMonAI — Claude Code CLI Installer (Native, tanpa Termux)
//
// Arsitektur baru:
//   • Tools sudah di-bundle ke APK via CI (assets/tools/)
//   • ToolsService.instance.initialize() extract ke internal storage
//   • Tidak perlu install apapun — hanya verify + configure
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanmongo/core/tools/tools_service.dart';

enum ClaudeInstallStep {
  checkingBundle,    // cek apakah tools sudah di-extract
  extractingBundle,  // extract tarball dari assets
  writingSettings,   // tulis ~/.kanmon/claude/settings.json
  verifying,         // verifikasi node + cli.js ada
  done,
  error,
}

class ClaudeInstallEvent {
  final ClaudeInstallStep step;
  final String message;
  final bool isError;
  final double progress;

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

class ClaudeCodeInstaller {
  ClaudeCodeInstaller._();
  static final ClaudeCodeInstaller instance = ClaudeCodeInstaller._();

  // Pertahankan SharedPreferences keys yang sama dengan kode lama
  static const _kInstalled  = 'claude_code_installed';
  static const _kConfigured = 'claude_code_configured';

  bool _isInstalled  = false;
  bool _isConfigured = false;
  bool _prefsLoaded  = false;

  bool get isInstalled  => _isInstalled;
  bool get isConfigured => _isConfigured;

  // Path dari ToolsService — tidak ada hardcode Termux
  String get claudeCodePath => ToolsService.instance.claudeCodeCliPath;
  String get nodePath       => ToolsService.instance.nodePath;

  Future<void> _loadPrefs() async {
    if (_prefsLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _isInstalled  = prefs.getBool(_kInstalled)  ?? false;
    _isConfigured = prefs.getBool(_kConfigured) ?? false;
    _prefsLoaded = true;
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kInstalled,  _isInstalled);
    await prefs.setBool(_kConfigured, _isConfigured);
  }

  /// Cek apakah tools sudah siap dan cli.js ada.
  Future<bool> checkInstalled() async {
    await _loadPrefs();
    if (!ToolsService.instance.isReady) {
      _isInstalled = false;
      await _savePrefs();
      return false;
    }
    final cliExists = File(claudeCodePath).existsSync();
    if (!cliExists && _isInstalled) {
      _isInstalled  = false;
      _isConfigured = false;
      await _savePrefs();
    } else if (cliExists && !_isInstalled) {
      _isInstalled  = true;
      await _savePrefs();
    }
    return cliExists;
  }

  /// Install = initialize ToolsService (extract bundle) + tulis settings.
  Stream<ClaudeInstallEvent> install() async* {
    // Step 1: Check / extract bundle
    yield const ClaudeInstallEvent(
      step: ClaudeInstallStep.checkingBundle,
      message: 'Memeriksa bundle tools bawaan...',
      progress: 0.05,
    );

    if (!ToolsService.instance.isReady) {
      yield const ClaudeInstallEvent(
        step: ClaudeInstallStep.extractingBundle,
        message: 'Mengekstrak tools dari APK... (sekali saja)',
        progress: 0.10,
      );

      try {
        await ToolsService.instance.initialize(
          onProgress: (_) {},
        );
      } catch (e) {
        yield ClaudeInstallEvent(
          step: ClaudeInstallStep.error,
          message: 'Gagal mengekstrak tools: $e\n'
              'Pastikan APK dibangun dengan step bundle tools di build.yml.',
          isError: true,
          progress: 0.15,
        );
        return;
      }

      if (!ToolsService.instance.isReady) {
        yield const ClaudeInstallEvent(
          step: ClaudeInstallStep.error,
          message: 'Bundle tools tidak ditemukan dalam APK.\n'
              'Rebuild APK via GitHub Actions agar tools ter-bundle.',
          isError: true,
          progress: 0.15,
        );
        return;
      }
    }

    yield ClaudeInstallEvent(
      step: ClaudeInstallStep.checkingBundle,
      message: 'Tools siap: Node.js '
          '${ToolsService.instance.manifest?.nodeVersion ?? ''}, '
          'Claude Code '
          '${ToolsService.instance.manifest?.claudeCodeVersion ?? ''}',
      progress: 0.50,
    );

    // Step 2: Tulis settings.json
    yield const ClaudeInstallEvent(
      step: ClaudeInstallStep.writingSettings,
      message: 'Menulis konfigurasi Claude Code...',
      progress: 0.70,
    );

    final settingsResult = await _writeSettingsJson();
    if (settingsResult.isError) {
      yield settingsResult;
      return;
    }
    yield settingsResult;

    // Step 3: Verify
    yield const ClaudeInstallEvent(
      step: ClaudeInstallStep.verifying,
      message: 'Memverifikasi...',
      progress: 0.90,
    );

    final verified = await checkInstalled();
    if (!verified) {
      yield const ClaudeInstallEvent(
        step: ClaudeInstallStep.error,
        message: 'Verifikasi gagal — cli.js tidak ditemukan.',
        isError: true,
        progress: 0.92,
      );
      return;
    }

    _isInstalled  = true;
    _isConfigured = true;
    await _savePrefs();

    yield const ClaudeInstallEvent(
      step: ClaudeInstallStep.done,
      message: '✅ Claude Code siap digunakan (native, tanpa Termux)!',
      progress: 1.0,
    );
  }

  Future<ClaudeInstallEvent> _writeSettingsJson() async {
    try {
      final toolsRoot = ToolsService.instance.toolsRoot;
      final settingsDir = Directory('$toolsRoot/.kanmon/claude');
      settingsDir.createSync(recursive: true);

      const settingsContent = '{\n'
          '  "autoUpdaterStatus": "disabled",\n'
          '  "theme": "dark",\n'
          '  "verboseDiff": false,\n'
          '  "disableTelemetry": true,\n'
          '  "hasAcknowledgedCostThreshold": true,\n'
          '  "costThresholdDollars": 9999,\n'
          '  "costThresholdEnabled": false\n'
          '}';

      await File('${settingsDir.path}/settings.json')
          .writeAsString(settingsContent);

      return const ClaudeInstallEvent(
        step: ClaudeInstallStep.writingSettings,
        message: 'settings.json berhasil ditulis.',
        progress: 0.85,
      );
    } catch (e) {
      return ClaudeInstallEvent(
        step: ClaudeInstallStep.error,
        message: 'Gagal menulis settings.json: $e',
        isError: true,
        progress: 0.72,
      );
    }
  }

  /// Bangun command untuk launch Claude Code via launcher script.
  String getLaunchCommand({String? workDir, int serverPort = 8080}) {
    final launcher = ToolsService.instance.claudeLauncherPath;
    final cdPart = (workDir != null && workDir.isNotEmpty)
        ? 'cd "$workDir" && '
        : '';
    return '${cdPart}'
        'ANTHROPIC_BASE_URL=http://localhost:$serverPort '
        'ANTHROPIC_API_KEY=kanmon-local-llama '
        'CLAUDE_HOME=${ToolsService.instance.toolsRoot}/.kanmon/claude '
        '$launcher';
  }

  /// Command untuk invoke langsung via node (tanpa launcher script).
  String? getNodeInvocationCommand() {
    final cliJs = claudeCodePath;
    if (!File(cliJs).existsSync()) return null;
    return '${ToolsService.instance.nodePath} $cliJs';
  }

  /// Hapus settings.json (reset konfigurasi, tidak uninstall tools).
  Future<void> unconfigure() async {
    try {
      final settingsFile = File(
          '${ToolsService.instance.toolsRoot}/.kanmon/claude/settings.json');
      if (settingsFile.existsSync()) settingsFile.deleteSync();
      _isConfigured = false;
      await _savePrefs();
    } catch (e) {
      debugPrint('[ClaudeCodeInstaller] unconfigure error: $e');
    }
  }
}
