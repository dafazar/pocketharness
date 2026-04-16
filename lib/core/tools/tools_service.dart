import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages bundled CLI tools extracted from APK assets to app internal storage.
///
/// Design: "extract-once, never re-check" — uses a manifest version key
/// in SharedPreferences. If the stored key matches the bundled manifest's
/// [builtAt] + [runId], extraction is skipped entirely.
class ToolsService {
  ToolsService._();
  static final ToolsService instance = ToolsService._();

  static const String _prefKey = 'tools_extracted_run_id';
  static const String _assetsToolsPrefix = 'assets/tools';

  late String _toolsRoot;      // absolute path to extracted tools dir
  late String _abi;            // device ABI: arm64-v8a or x86_64
  bool _isReady = false;
  ToolsManifest? _manifest;

  bool get isReady => _isReady;
  String get toolsRoot => _toolsRoot;
  String get abi => _abi;
  ToolsManifest? get manifest => _manifest;

  /// Returns the absolute path to the Node.js binary.
  String get nodePath => '$_toolsRoot/$_abi/node';

  /// Returns the absolute path to the Claude Code CLI entry point (JS file).
  String get claudeCodeCliPath =>
      '$_toolsRoot/$_abi/npm_modules/@anthropic-ai/claude-code/cli.js';

  /// Returns the absolute path to the code-server entry point (JS file).
  String get codeServerCliPath =>
      '$_toolsRoot/$_abi/npm_modules/code-server/out/node/entry.js';

  /// Returns the bin directory for bundled CLI tools (git, rg, ssh).
  String get binDir => '$_toolsRoot/$_abi/bin';

  /// Returns the launcher script path for Claude Code.
  String get claudeLauncherPath => '$_toolsRoot/launcher/claude_code_launcher.sh';

  /// Returns the launcher script path for code-server.
  String get codeServerLauncherPath => '$_toolsRoot/launcher/code_server_launcher.sh';

  /// Initializes ToolsService. Must be called once from main() before runApp().
  ///
  /// [onProgress] receives a value from 0.0 to 1.0 during extraction.
  Future<void> initialize({void Function(double progress)? onProgress}) async {
    final dir = await getApplicationSupportDirectory();
    _toolsRoot = '${dir.path}/tools';
    _abi = _detectAbi();

    // Load manifest from assets (always present since it's bundled)
    _manifest = await _loadBundledManifest();
    if (_manifest == null) {
      // No manifest means tools were not bundled — skip silently
      _isReady = false;
      return;
    }

    // Check if already extracted with same build
    final prefs = await SharedPreferences.getInstance();
    final storedRunId = prefs.getString(_prefKey);
    final currentRunId = '${_manifest!.runId}_${_manifest!.builtAt}';

    if (storedRunId == currentRunId && Directory(_toolsRoot).existsSync()) {
      // Already extracted — skip all file checks, mark ready immediately
      _isReady = true;
      onProgress?.call(1.0);
      return;
    }

    // Extract all tools from assets to internal storage
    await _extractAll(onProgress: onProgress);

    // Make binaries executable
    await _chmodExecutables();

    // Persist the run ID so next launch skips extraction
    await prefs.setString(_prefKey, currentRunId);
    _isReady = true;
    onProgress?.call(1.0);
  }

  /// Forces re-extraction on next app launch (used after app update).
  Future<void> invalidateCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  String _detectAbi() {
    // Use dart:io Platform to detect ABI from the native library path or
    // fall back to arm64-v8a as the safe default for Android.
    // On Android the app is compiled for a specific ABI, so we check
    // which native lib directory exists at runtime.
    final execPath = Platform.resolvedExecutable;
    if (execPath.contains('x86_64')) return 'x86_64';
    return 'arm64-v8a';
  }

  Future<ToolsManifest?> _loadBundledManifest() async {
    try {
      final raw = await rootBundle.loadString('$_assetsToolsPrefix/tools_manifest.json');
      final map = json.decode(raw) as Map<String, dynamic>;
      return ToolsManifest.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _extractAll({void Function(double)? onProgress}) async {
    // Read the asset manifest to enumerate all files under assets/tools/
    // Flutter's AssetManifest lists all registered asset paths.
    final manifestJson = await rootBundle.loadString('AssetManifest.json');
    final assetMap = json.decode(manifestJson) as Map<String, dynamic>;

    final toolsAssets = assetMap.keys
        .where((k) => k.startsWith('$_assetsToolsPrefix/'))
        .toList()
      ..sort();

    if (toolsAssets.isEmpty) return;

    final total = toolsAssets.length;
    var done = 0;

    for (final assetPath in toolsAssets) {
      // Compute destination path
      final relativePath = assetPath.replaceFirst('$_assetsToolsPrefix/', '');
      final destPath = '$_toolsRoot/$relativePath';
      final destFile = File(destPath);

      // Create parent directory if needed
      await destFile.parent.create(recursive: true);

      // Copy from asset bundle to filesystem
      final bytes = await rootBundle.load(assetPath);
      await destFile.writeAsBytes(bytes.buffer.asUint8List(), flush: true);

      done++;
      onProgress?.call(done / total);
    }
  }

  Future<void> _chmodExecutables() async {
    final executablePaths = [
      nodePath,
      claudeLauncherPath,
      codeServerLauncherPath,
      '$_toolsRoot/$_abi/npm_modules/npm/bin/npm-cli.js',
    ];

    // Also chmod everything in binDir
    final binDirectory = Directory(binDir);
    if (await binDirectory.exists()) {
      await for (final entity in binDirectory.list()) {
        if (entity is File) {
          await Process.run('chmod', ['755', entity.path]);
        }
      }
    }

    for (final path in executablePaths) {
      if (await File(path).exists()) {
        await Process.run('chmod', ['755', path]);
      }
    }
  }

  /// Runs a command using the bundled Node.js binary.
  /// Returns a [ProcessResult] with stdout/stderr.
  Future<ProcessResult> runNode(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final env = _buildEnv(environment);
    return Process.run(
      nodePath,
      args,
      workingDirectory: workingDirectory,
      environment: env,
    );
  }

  /// Starts a persistent Node.js process (for streaming output).
  Future<Process> startNode(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final env = _buildEnv(environment);
    return Process.start(
      nodePath,
      args,
      workingDirectory: workingDirectory,
      environment: env,
    );
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

/// Parsed contents of `assets/tools/tools_manifest.json`.
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
