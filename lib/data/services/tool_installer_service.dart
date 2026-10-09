// lib/data/services/tool_installer_service.dart
// Pocket Harness — Tool Installer Service
//
// Auto-detect & install system tools (ffmpeg, imagemagick, python, dll)
// via Termux (pkg/apt) jika tersedia, atau lewat binary yang sudah dikompilasi.
// =============================================================================

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pocketharness/data/services/terminal_service.dart';
import 'package:pocketharness/core/tools/tools_service.dart';

class ToolCheckResult {
  final bool    success;
  final String  message;
  final String  installHint;
  const ToolCheckResult({
    required this.success,
    required this.message,
    this.installHint = '',
  });
}

class ToolInstallerService {
  ToolInstallerService._();
  static final ToolInstallerService instance = ToolInstallerService._();

  // Cache status tool agar tidak dicek ulang tiap kali
  final Map<String, bool> _toolCache = {};

  // ── Mapping: operasi media → tool yang dibutuhkan ─────────────────────────
  static const _opToTool = <String, String>{
    'resize':    'ffmpeg',
    'crop':      'ffmpeg',
    'rotate':    'ffmpeg',
    'flip':      'ffmpeg',
    'compress':  'ffmpeg',
    'trim':      'ffmpeg',
    'convert':   'ffmpeg',
    'watermark': 'ffmpeg',
    'thumbnail': 'ffmpeg',
    'grayscale': 'ffmpeg',
    'brightness':'ffmpeg',
    'contrast':  'ffmpeg',
    'blur':      'ffmpeg',
    'speed':     'ffmpeg',
    'volume':    'ffmpeg',
    'extract_audio': 'ffmpeg',
    'merge':     'ffmpeg',
  };

  // ── Mapping: tool → pkg name di Termux/Debian ─────────────────────────────
  static const _toolToPkg = <String, String>{
    'ffmpeg':       'ffmpeg',
    'imagemagick':  'imagemagick',
    'convert':      'imagemagick',
    'python':       'python',
    'python3':      'python',
    'node':         'nodejs',
    'nodejs':       'nodejs',
    'npm':          'nodejs',
    'git':          'git',
    'curl':         'curl',
    'wget':         'wget',
    'zip':          'zip',
    'unzip':        'unzip',
    'jq':           'jq',
    'sox':          'sox',
    'yt-dlp':       'yt-dlp',
    'exiftool':     'perl-image-exiftool',
  };

  // ── Cek tool untuk operasi tertentu ──────────────────────────────────────
  Future<ToolCheckResult> ensureToolForOperation(String operation) async {
    final toolName = _opToTool[operation.toLowerCase()];
    if (toolName == null) {
      return const ToolCheckResult(
        success: true,
        message: 'Operasi tidak memerlukan tool eksternal.',
      );
    }
    return checkAndInstall(toolName, autoInstall: true);
  }

  // ── Cek & install tool ────────────────────────────────────────────────────
  Future<ToolCheckResult> checkAndInstall(
    String tool, {
    bool autoInstall = true,
  }) async {
    // Cek cache
    if (_toolCache[tool] == true) {
      return ToolCheckResult(success: true, message: '$tool sudah tersedia.');
    }

    // Cek apakah tool ada di PATH
    final available = await _isToolAvailable(tool);
    if (available) {
      _toolCache[tool] = true;
      return ToolCheckResult(success: true, message: '$tool tersedia.');
    }

    // Tool tidak ada — coba install jika autoInstall
    if (!autoInstall) {
      return ToolCheckResult(
        success: false,
        message: '$tool tidak ditemukan.',
        installHint: _installHint(tool),
      );
    }

    debugPrint('[ToolInstaller] $tool tidak ditemukan, mencoba install...');
    final installed = await _installTool(tool);
    if (installed) {
      _toolCache[tool] = true;
      return ToolCheckResult(
        success: true,
        message: '$tool berhasil diinstall.',
      );
    }

    return ToolCheckResult(
      success: false,
      message: '$tool tidak berhasil diinstall.',
      installHint: _installHint(tool),
    );
  }

  // ── Cek apakah tool ada di PATH ───────────────────────────────────────────
  Future<bool> _isToolAvailable(String tool) async {
    // 1. Cek bundled native tools via ToolsService (prioritas tertinggi)
    try {
      final ts = ToolsService.instance;
      if (ts.isReady) {
        // Cek nama tool langsung dan aliases umum
        final aliases = <String>[tool];
        if (tool == 'python') aliases.add('python3');
        if (tool == 'python3') aliases.add('python');
        if (tool == 'convert') aliases.add('imagemagick');
        if (tool == 'ripgrep') aliases.add('rg');
        if (tool == '7z') aliases.add('p7zip');
        for (final alias in aliases) {
          if (ts.hasNativeTool(alias)) return true;
        }
      }
    } catch (_) {}

    // 2. Cek path Termux + system
    final paths = [
      '/data/data/com.termux/files/usr/bin/$tool',
      '/data/data/com.termux/files/usr/local/bin/$tool',
      '/system/bin/$tool',
      '/usr/bin/$tool',
      '/bin/$tool',
    ];
    for (final p in paths) {
      if (File(p).existsSync()) return true;
    }

    // 3. Cek via which command
    try {
      final result = await TerminalService.instance.run('which $tool',
          timeout: const Duration(seconds: 5));
      return result.isSuccess && result.stdout.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── Install tool via Termux pkg/apt ───────────────────────────────────────
  Future<bool> _installTool(String tool) async {
    final pkgName = _toolToPkg[tool] ?? tool;

    // Cek Termux tersedia
    final hasTermux = TerminalService.instance.hasTermux;
    if (!hasTermux) {
      debugPrint('[ToolInstaller] Termux tidak tersedia, tidak bisa install $pkgName');
      return false;
    }

    try {
      // Update package list dulu
      debugPrint('[ToolInstaller] apt update...');
      await TerminalService.instance.run(
        'DEBIAN_FRONTEND=noninteractive apt-get update -y',
        timeout: const Duration(minutes: 3),
      );

      // Install package
      debugPrint('[ToolInstaller] apt install $pkgName...');
      final result = await TerminalService.instance.run(
        'DEBIAN_FRONTEND=noninteractive apt-get install -y $pkgName',
        timeout: const Duration(minutes: 10),
      );

      if (result.isSuccess) {
        debugPrint('[ToolInstaller] ✅ $pkgName berhasil diinstall');
        return true;
      }

      // Fallback: pkg install (Termux native)
      debugPrint('[ToolInstaller] Fallback ke pkg install $pkgName...');
      final pkg = await TerminalService.instance.run(
        'pkg install -y $pkgName',
        timeout: const Duration(minutes: 10),
      );
      return pkg.isSuccess;
    } catch (e) {
      debugPrint('[ToolInstaller] Install error: $e');
      return false;
    }
  }

  String _installHint(String tool) {
    final pkg = _toolToPkg[tool] ?? tool;
    return 'Install Termux lalu jalankan: pkg install $pkg';
  }

  // ── Stream install dengan output real-time ────────────────────────────────
  Stream<String> installToolStream(String tool) async* {
    final pkgName = _toolToPkg[tool] ?? tool;

    yield '📦 Menginstall $pkgName...\n';

    if (!TerminalService.instance.hasTermux) {
      yield '❌ Termux tidak tersedia.\n'
            '💡 Install Termux dari F-Droid untuk menginstall tool sistem.\n';
      return;
    }

    yield '🔄 apt-get update...\n';
    yield* TerminalService.instance.runStream(
      'DEBIAN_FRONTEND=noninteractive apt-get update -y',
      timeout: const Duration(minutes: 3),
    );

    yield '\n📥 apt-get install $pkgName...\n';
    yield* TerminalService.instance.runStream(
      'DEBIAN_FRONTEND=noninteractive apt-get install -y $pkgName',
      timeout: const Duration(minutes: 10),
    );

    // Verifikasi
    final ok = await _isToolAvailable(tool);
    if (ok) {
      _toolCache[tool] = true;
      yield '\n✅ $pkgName berhasil terinstall!\n';
    } else {
      yield '\n⚠️ Verifikasi gagal. Coba: pkg install $pkgName\n';
    }
  }

  // ── Clear cache ───────────────────────────────────────────────────────────
  void clearCache() => _toolCache.clear();
}
