import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages bundled CLI tools extracted from APK assets to app internal storage.
///
/// Design: "extract-once, never re-check" — uses a manifest version key
/// in SharedPreferences. If the stored key matches the bundled manifest's
/// [builtAt] + [runId], extraction is skipped entirely.
///
/// Assets layout (injected by CI, not in git):
///   assets/tools/tools_manifest.json
///   assets/tools/tools_arm64-v8a.tar.gz   (or x86_64)
class ToolsService {
  ToolsService._();
  static final ToolsService instance = ToolsService._();

  static const String _prefKey = 'tools_extracted_run_id';
  static const String _assetsToolsPrefix = 'assets/tools';

  late String _toolsRoot;
  late String _abi;
  bool _isReady = false;
  ToolsManifest? _manifest;

  bool get isReady => _isReady;
  String get toolsRoot => _toolsRoot;
  String get abi => _abi;
  ToolsManifest? get manifest => _manifest;

  String get nodePath => '$_toolsRoot/$_abi/node';
  String get claudeCodeCliPath =>
      '$_toolsRoot/$_abi/npm_modules/@anthropic-ai/claude-code/cli.js';
  String get codeServerCliPath =>
      '$_toolsRoot/$_abi/npm_modules/code-server/out/node/entry.js';
  String get binDir => '$_toolsRoot/$_abi/bin';
  String get claudeLauncherPath =>
      '$_toolsRoot/$_abi/launcher/claude_code_launcher.sh';
  String get codeServerLauncherPath =>
      '$_toolsRoot/$_abi/launcher/code_server_launcher.sh';

  Future<void> initialize({void Function(double progress)? onProgress}) async {
    final dir = await getApplicationSupportDirectory();
    _toolsRoot = '${dir.path}/tools';
    _abi = _detectAbi();

    _manifest = await _loadBundledManifest();
    if (_manifest == null) {
      _isReady = false;
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final storedRunId = prefs.getString(_prefKey);
    final currentRunId = '${_manifest!.runId}_${_manifest!.builtAt}';

    if (storedRunId == currentRunId && Directory(_toolsRoot).existsSync()) {
      _isReady = true;
      onProgress?.call(1.0);
      return;
    }

    await _extractTarball(onProgress: onProgress);
    await _chmodExecutables();
    await prefs.setString(_prefKey, currentRunId);
    _isReady = true;
    onProgress?.call(1.0);
  }

  Future<void> invalidateCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  String _detectAbi() {
    final execPath = Platform.resolvedExecutable;
    if (execPath.contains('x86_64')) return 'x86_64';
    return 'arm64-v8a';
  }

  Future<ToolsManifest?> _loadBundledManifest() async {
    try {
      final raw =
          await rootBundle.loadString('$_assetsToolsPrefix/tools_manifest.json');
      final map = json.decode(raw) as Map<String, dynamic>;
      return ToolsManifest.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// Extracts `assets/tools/tools_<abi>.tar.gz` into [_toolsRoot].
  /// Uses archive package (TarDecoder + GZipDecoder) — no shell needed.
  Future<void> _extractTarball({void Function(double)? onProgress}) async {
    final tarballAsset = '$_assetsToolsPrefix/tools_$_abi.tar.gz';

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
      onProgress?.call(done / total);
    }
  }

  Future<void> _chmodExecutables() async {
    // chmod launcher dir scripts
    final launcherDir = Directory('$_toolsRoot/$_abi/launcher');
    if (await launcherDir.exists()) {
      await for (final entity in launcherDir.list()) {
        if (entity is File) await Process.run('chmod', ['755', entity.path]);
      }
    }

    // chmod bin dir tools
    final binDirectory = Directory(binDir);
    if (await binDirectory.exists()) {
      await for (final entity in binDirectory.list()) {
        if (entity is File) await Process.run('chmod', ['755', entity.path]);
      }
    }

    // chmod node binary
    if (await File(nodePath).exists()) {
      await Process.run('chmod', ['755', nodePath]);
    }
  }

  Future<ProcessResult> runNode(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final env = _buildEnv(environment);
    return Process.run(nodePath, args,
        workingDirectory: workingDirectory, environment: env);
  }

  Future<Process> startNode(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final env = _buildEnv(environment);
    return Process.start(nodePath, args,
        workingDirectory: workingDirectory, environment: env);
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
}

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
