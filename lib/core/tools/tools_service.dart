import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Model ──────────────────────────────────────────────────────────────────

/// Metadata yang di-bundle bersama tools tarball.
/// Dibaca dari `assets/tools/tools_manifest.json` (injected oleh CI).
class ToolsManifest {
  final int schemaVersion;
  final String builtAt;
  final String runId;
  final String nodeVersion;
  final String claudeCodeVersion;
  final String codeServerVersion;
  final List<String> abis;
  final List<String> tools;

  const ToolsManifest({
    required this.schemaVersion,
    required this.builtAt,
    required this.runId,
    required this.nodeVersion,
    required this.claudeCodeVersion,
    required this.codeServerVersion,
    required this.abis,
    required this.tools,
  });

  factory ToolsManifest.fromJson(Map<String, dynamic> map) {
    return ToolsManifest(
      schemaVersion: (map['schema_version'] as num?)?.toInt() ?? 1,
      builtAt: map['built_at'] as String? ?? '',
      runId: map['run_id'] as String? ?? '',
      nodeVersion: map['node_version'] as String? ?? '',
      claudeCodeVersion: map['claude_code_version'] as String? ?? '',
      codeServerVersion: map['code_server_version'] as String? ?? '',
      abis: (map['abis'] as List<dynamic>?)?.cast<String>() ?? [],
      tools: (map['tools'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  bool get isValid => builtAt.isNotEmpty && runId.isNotEmpty;
}

// ── Service ────────────────────────────────────────────────────────────────

/// Manages bundled CLI tools extracted from APK assets to app internal storage.
///
/// Design: "extract-once, never re-check" — uses a manifest version key
/// in SharedPreferences. If the stored key matches the bundled manifest's
/// [builtAt] + [runId], extraction is skipped entirely.
///
/// Assets layout (injected by CI, not in git):
///   assets/tools/tools_manifest.json
///   assets/tools/tools_arm64-v8a.tar.gz   (or x86_64)
///
/// Extracted layout (at runtime):
///   {appSupportDir}/tools/
///     tools_manifest.json
///     arm64-v8a/
///       node
///       npm_modules/@anthropic-ai/claude-code/cli.js
///       npm_modules/code-server/out/node/entry.js
///       bin/git
///       bin/rg
///       launcher/claude_code_launcher.sh
///       launcher/code_server_launcher.sh
class ToolsService {
  ToolsService._();
  static final ToolsService instance = ToolsService._();

  static const String _kExtractedRunId = 'tools_extracted_run_id';
  static const String _assetsToolsPrefix = 'assets/tools';

  late String _toolsRoot;
  late String _abi;
  bool _isReady = false;
  ToolsManifest? _manifest;

  // ── Public state ──────────────────────────────────────────────────────────

  bool get isReady => _isReady;
  String get toolsRoot => _toolsRoot;
  String get abi => _abi;
  ToolsManifest? get manifest => _manifest;

  // ── Path getters ──────────────────────────────────────────────────────────

  String get nodePath =>
      '$_toolsRoot/$_abi/node';
  String get claudeCodeCliPath =>
      '$_toolsRoot/$_abi/npm_modules/@anthropic-ai/claude-code/cli.js';
  String get codeServerCliPath =>
      '$_toolsRoot/$_abi/npm_modules/code-server/out/node/entry.js';
  String get binDir =>
      '$_toolsRoot/$_abi/bin';
  String get claudeLauncherPath =>
      '$_toolsRoot/$_abi/launcher/claude_code_launcher.sh';
  String get codeServerLauncherPath =>
      '$_toolsRoot/$_abi/launcher/code_server_launcher.sh';

  /// Full command string untuk launcher script Claude Code.
  String get claudeLauncherCommand => claudeLauncherPath;

  // ── Initialize ────────────────────────────────────────────────────────────

  /// Initializes ToolsService:
  ///   1. Detects ABI (via `uname -m`, fallback arm64-v8a)
  ///   2. Loads bundled manifest from assets
  ///   3. Skips extraction if runId matches saved key AND node binary exists
  ///   4. Otherwise extracts tarball and chmods executables
  Future<void> initialize({void Function(double progress)? onProgress}) async {
    if (_isReady) return;

    final dir = await getApplicationSupportDirectory();
    _toolsRoot = '${dir.path}/tools';
    _abi = await _detectAbi();

    _manifest = await _loadBundledManifest();
    if (_manifest == null) {
      debugPrint('[ToolsService] No bundled manifest found in assets.');
      _isReady = false;
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final storedRunId = prefs.getString(_kExtractedRunId);
    final currentRunId = '${_manifest!.runId}_${_manifest!.builtAt}';

    if (storedRunId == currentRunId &&
        Directory(_toolsRoot).existsSync() &&
        File(nodePath).existsSync()) {
      debugPrint('[ToolsService] Tools already extracted (runId: $storedRunId). Skipping.');
      _isReady = true;
      onProgress?.call(1.0);
      return;
    }

    await _extractTarball(onProgress: onProgress);
    await _chmodExecutables();

    // Salin manifest ke toolsRoot untuk referensi runtime
    try {
      final manifestJson = await rootBundle
          .loadString('$_assetsToolsPrefix/tools_manifest.json');
      await File('$_toolsRoot/tools_manifest.json').writeAsString(manifestJson);
    } catch (_) {}

    if (File(nodePath).existsSync()) {
      await prefs.setString(_kExtractedRunId, currentRunId);
      _isReady = true;
      debugPrint('[ToolsService] Tools extracted successfully (runId: $currentRunId).');
    } else {
      debugPrint('[ToolsService] Extraction done but node binary not found at $nodePath!');
    }

    onProgress?.call(1.0);
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Detects device ABI via `uname -m`, fallback ke arm64-v8a.
  Future<String> _detectAbi() async {
    try {
      final result = await Process.run('uname', ['-m']);
      final machine = result.stdout.toString().trim();
      if (machine.contains('aarch64') || machine.contains('arm64')) {
        return 'arm64-v8a';
      } else if (machine.contains('x86_64')) {
        return 'x86_64';
      }
    } catch (_) {
      // uname tidak tersedia — fallback ke path resolvedExecutable
      final execPath = Platform.resolvedExecutable;
      if (execPath.contains('x86_64')) return 'x86_64';
    }
    return 'arm64-v8a'; // default Android ARM64
  }

  Future<ToolsManifest?> _loadBundledManifest() async {
    try {
      final raw = await rootBundle
          .loadString('$_assetsToolsPrefix/tools_manifest.json');
      final map = json.decode(raw) as Map<String, dynamic>;
      return ToolsManifest.fromJson(map);
    } catch (e) {
      debugPrint('[ToolsService] Failed to load bundled manifest: $e');
      return null;
    }
  }

  /// Extracts `assets/tools/tools_<abi>.tar.gz` into [_toolsRoot].
  /// Uses archive package (TarDecoder + GZipDecoder) — no shell needed.
  Future<void> _extractTarball({void Function(double)? onProgress}) async {
    final tarballAsset = '$_assetsToolsPrefix/tools_$_abi.tar.gz';
    debugPrint('[ToolsService] Extracting from $tarballAsset to $_toolsRoot');

    final byteData = await rootBundle.load(tarballAsset);
    final compressedBytes = byteData.buffer.asUint8List();

    final tarBytes = GZipDecoder().decodeBytes(compressedBytes);
    final archive = TarDecoder().decodeBytes(tarBytes);

    final total = archive.files.length;
    var done = 0;

    await Directory(_toolsRoot).create(recursive: true);

    for (final file in archive.files) {
      final destPath = '$_toolsRoot/${file.name}';
      if (file.isFile) {
        final destFile = File(destPath);
        await destFile.parent.create(recursive: true);
        await destFile.writeAsBytes(file.content as List<int>, flush: true);
      } else {
        await Directory(destPath).create(recursive: true);
      }
      done++;
      if (done % 10 == 0 || done == total) {
        onProgress?.call(done / total);
      }
    }

    debugPrint('[ToolsService] Extracted $done files.');
  }

  Future<void> _chmodExecutables() async {
    // chmod node binary
    if (File(nodePath).existsSync()) {
      await Process.run('chmod', ['755', nodePath]);
    }

    // chmod semua file di bin dir
    final binDirectory = Directory(binDir);
    if (binDirectory.existsSync()) {
      await for (final entity in binDirectory.list()) {
        if (entity is File) await Process.run('chmod', ['755', entity.path]);
      }
    }

    // chmod launcher scripts
    final launcherDir = Directory('$_toolsRoot/$_abi/launcher');
    if (launcherDir.existsSync()) {
      await for (final entity in launcherDir.list()) {
        if (entity is File) await Process.run('chmod', ['755', entity.path]);
      }
    }
  }

  Map<String, String> _buildEnv([Map<String, String>? extra]) {
    return {
      ...Platform.environment,
      'PATH': '$binDir:${Platform.environment['PATH'] ?? ''}',
      'NODE_PATH': '$_toolsRoot/$_abi/npm_modules',
      'HOME': _toolsRoot,
      'NODE_NO_WARNINGS': '1',
      ...?extra,
    };
  }

  // ── Public methods ────────────────────────────────────────────────────────

  /// Jalankan Node.js dengan args yang diberikan (blocking).
  Future<ProcessResult> runNode(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (!_isReady) {
      throw StateError('[ToolsService] Tools not ready. Call initialize() first.');
    }
    final env = _buildEnv(environment);
    return Process.run(
      nodePath,
      args,
      workingDirectory: workingDirectory,
      environment: env,
    );
  }

  /// Jalankan Node.js sebagai proses async (streaming output).
  Future<Process> startNode(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (!_isReady) {
      throw StateError('[ToolsService] Tools not ready. Call initialize() first.');
    }
    final env = _buildEnv(environment);
    return Process.start(
      nodePath,
      args,
      workingDirectory: workingDirectory,
      environment: env,
    );
  }

  /// Verifikasi bahwa node binary ada dan bisa dieksekusi.
  Future<bool> verifyTools() async {
    if (!_isReady) return false;
    try {
      final nodeFile = File(nodePath);
      if (!nodeFile.existsSync()) return false;
      final result = await Process.run(nodePath, ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Invalidate cache — force re-extract on next [initialize] call.
  Future<void> invalidateCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kExtractedRunId);
    debugPrint('[ToolsService] Cache invalidated.');
  }

  /// Reset extracted state (alias untuk [invalidateCache], juga reset _isReady).
  Future<void> clearExtractedState() async {
    await invalidateCache();
    _isReady = false;
    debugPrint('[ToolsService] Extracted state cleared.');
  }
}
