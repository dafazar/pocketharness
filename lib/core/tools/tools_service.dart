import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle, MethodChannel;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Model ──────────────────────────────────────────────────────────────────

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

class ToolsService {
  ToolsService._();
  static final ToolsService instance = ToolsService._();

  static const String _kExtractedRunId  = 'tools_extracted_run_id';
  static const String _kPermissionsSet   = 'tools_permissions_set_v2';
  static const String _assetsToolsPrefix = 'assets/tools';

  // MethodChannel to NativeEnvPlugin for chmod via Java File.setExecutable().
  // Required because Process.run('/system/bin/chmod') fails with EACCES on
  // Android API 29+ (SELinux untrusted_app domain blocks execve on system bins).
  static const MethodChannel _nativeEnv =
      MethodChannel('com.kanmongo.app/native_env');

  late String _toolsRoot;
  late String _abi;
  bool _isReady = false;
  ToolsManifest? _manifest;

  bool            get isReady   => _isReady;
  String          get toolsRoot => _toolsRoot;
  String          get abi       => _abi;
  ToolsManifest?  get manifest  => _manifest;

  String get nodePath           => '$_toolsRoot/$_abi/node';
  String get claudeCodeCliPath  => '$_toolsRoot/$_abi/npm_modules/@anthropic-ai/claude-code/cli.js';
  String get codeServerCliPath  => '$_toolsRoot/$_abi/npm_modules/code-server/out/node/entry.js';
  String get binDir             => '$_toolsRoot/$_abi/bin';
  String get claudeLauncherPath => '$_toolsRoot/$_abi/launcher/claude_code_launcher.sh';
  String get codeServerLauncherPath => '$_toolsRoot/$_abi/launcher/code_server_launcher.sh';
  String get claudeLauncherCommand  => claudeLauncherPath;

  // ── Native tool paths (bundled from Termux) ───────────────────────────────
  String get gitPath        => '$binDir/git';
  String get ripgrepPath    => '$binDir/rg';
  String get curlPath       => '$binDir/curl';
  String get wgetPath       => '$binDir/wget';
  String get jqPath         => '$binDir/jq';
  String get busyboxPath    => '$binDir/busybox';
  String get python3Path    => '$binDir/python3';
  String get pythonPath     => '$binDir/python';
  String get zipPath        => '$binDir/zip';
  String get unzipPath      => '$binDir/unzip';
  String get sqlite3Path    => '$binDir/sqlite3';
  String get ffmpegPath     => '$binDir/ffmpeg';
  String get ffprobePath    => '$binDir/ffprobe';
  String get convertPath    => '$binDir/convert';   // imagemagick
  String get identifyPath   => '$binDir/identify';  // imagemagick
  String get mogrifyPath    => '$binDir/mogrify';   // imagemagick
  String get soxPath        => '$binDir/sox';
  String get soxiPath       => '$binDir/soxi';
  String get ytDlpPath      => '$binDir/yt-dlp';
  String get nanoPath       => '$binDir/nano';
  String get vimPath        => '$binDir/vim';
  String get pvPath         => '$binDir/pv';
  String get filePath       => '$binDir/file';
  String get patchPath      => '$binDir/patch';
  String get diffPath       => '$binDir/diff';
  String get rsyncPath      => '$binDir/rsync';
  String get p7zipPath      => '$binDir/7z';
  String get lz4Path        => '$binDir/lz4';
  String get zstdPath       => '$binDir/zstd';
  String get xzPath         => '$binDir/xz';
  String get psPath         => '$binDir/ps';
  String get freePath       => '$binDir/free';
  String get pgrepPath      => '$binDir/pgrep';
  String get pkillPath      => '$binDir/pkill';
  String get exiftoolPath   => '$binDir/exiftool';
  String get sshPath        => '$binDir/ssh';
  String get scpPath        => '$binDir/scp';
  String get sshKeygenPath  => '$binDir/ssh-keygen';
  String get stracePath     => '$binDir/strace';

  /// Returns true if the bundled native tool binary exists on disk.
  bool hasNativeTool(String toolName) {
    final p = '$binDir/$toolName';
    return File(p).existsSync();
  }

  /// Returns the full path to a named native tool (bin/<name>),
  /// or null if it doesn't exist in the bundle.
  String? nativeToolPath(String toolName) {
    final p = '$binDir/$toolName';
    return File(p).existsSync() ? p : null;
  }

  /// List all native tools currently available in bin/.
  List<String> get availableNativeTools {
    final dir = Directory(binDir);
    if (!dir.existsSync()) return [];
    try {
      return dir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => !n.startsWith('.'))
          .toList()
        ..sort();
    } catch (_) {
      return [];
    }
  }

  // ── Initialize ────────────────────────────────────────────────────────────

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
    final storedRunId    = prefs.getString(_kExtractedRunId);
    final permissionsSet = prefs.getBool(_kPermissionsSet) ?? false;
    final currentRunId   = '${_manifest!.runId}_${_manifest!.builtAt}';

    final nodeExists       = File(nodePath).existsSync();
    final codeServerExists = File(codeServerCliPath).existsSync();

    if (storedRunId == currentRunId && nodeExists && codeServerExists) {
      debugPrint('[ToolsService] Tools already extracted (runId: $storedRunId).');
      // Permissions bisa hilang setelah update — set ulang jika perlu
      if (!permissionsSet) {
        debugPrint('[ToolsService] Re-applying permissions (missing flag)...');
        await _chmodExecutablesRobust();
        await prefs.setBool(_kPermissionsSet, true);
      }
      _isReady = true;
      onProgress?.call(1.0);
      return;
    }

    // Extract tarball
    debugPrint('[ToolsService] Extracting tools (runId: $currentRunId)...');
    await _extractTarball(onProgress: onProgress);

    // Set permissions SEGERA — kritis untuk Android
    debugPrint('[ToolsService] Setting executable permissions...');
    await _chmodExecutablesRobust();

    // Simpan manifest
    try {
      final manifestJson = await rootBundle.loadString('$_assetsToolsPrefix/tools_manifest.json');
      await File('$_toolsRoot/tools_manifest.json').writeAsString(manifestJson);
    } catch (_) {}

    if (File(nodePath).existsSync()) {
      await prefs.setString(_kExtractedRunId, currentRunId);
      await prefs.setBool(_kPermissionsSet, true);
      _isReady = true;
      debugPrint('[ToolsService] Tools ready (runId: $currentRunId).');
    } else {
      debugPrint('[ToolsService] Extraction done but node binary not found at $nodePath!');
    }

    onProgress?.call(1.0);
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<String> _detectAbi() async {
    try {
      final result = await Process.run('uname', ['-m']);
      final machine = result.stdout.toString().trim();
      if (machine.contains('aarch64') || machine.contains('arm64')) return 'arm64-v8a';
      if (machine.contains('x86_64')) return 'x86_64';
    } catch (_) {
      final execPath = Platform.resolvedExecutable;
      if (execPath.contains('x86_64')) return 'x86_64';
    }
    return 'arm64-v8a';
  }

  Future<ToolsManifest?> _loadBundledManifest() async {
    try {
      final raw = await rootBundle.loadString('$_assetsToolsPrefix/tools_manifest.json');
      final map = json.decode(raw) as Map<String, dynamic>;
      return ToolsManifest.fromJson(map);
    } catch (e) {
      debugPrint('[ToolsService] Failed to load bundled manifest: $e');
      return null;
    }
  }

  /// Ekstrak tarball dan set mode bits dari entry tar.
  Future<void> _extractTarball({void Function(double)? onProgress}) async {
    final tarballAsset = '$_assetsToolsPrefix/tools_$_abi.tar.gz';
    debugPrint('[ToolsService] Extracting $tarballAsset → $_toolsRoot');

    final byteData = await rootBundle.load(tarballAsset);
    final compressedBytes = byteData.buffer.asUint8List();

    final tarBytes = GZipDecoder().decodeBytes(compressedBytes);
    final archive  = TarDecoder().decodeBytes(tarBytes);

    final total = archive.files.length;
    var done = 0;

    await Directory(_toolsRoot).create(recursive: true);

    for (final file in archive.files) {
      final destPath = '$_toolsRoot/${file.name}';
      if (file.isFile) {
        final destFile = File(destPath);
        await destFile.parent.create(recursive: true);
        await destFile.writeAsBytes(file.content as List<int>, flush: true);

        // Jika entry tar punya executable bit, langsung chmod
        final unixMode = file.mode & 0x1FF;
        if (unixMode != 0 && (unixMode & 0x49) != 0) {
          // 0x49 = 0b001001001 (execute bits untuk user/group/other)
          _chmodFileSync(destPath, '755');
        }
      } else {
        await Directory(destPath).create(recursive: true);
      }
      done++;
      if (done % 20 == 0 || done == total) {
        onProgress?.call((done / total) * 0.85);
      }
    }

    debugPrint('[ToolsService] Extracted $done files.');
  }

  /// chmod sync — fire-and-forget during tar extraction.
  /// Delegates to _chmodFile() which uses NativeEnvPlugin (Java File.setExecutable).
  /// Does NOT call Process.run directly to avoid EACCES on Android API 29+.
  void _chmodFileSync(String path, String mode) {
    _chmodFile(path, mode).catchError((Object e) {
      debugPrint('[ToolsService] _chmodFileSync error for $path: $e');
      return false;
    });
  }

  /// chmod a single file on Android.
  ///
  /// Priority:
  ///   1. NativeEnvPlugin.chmodExecutable → Java File.setExecutable(true, false)
  ///      Works inside the Android sandbox on all API levels. No shell needed.
  ///   2. Process.run('/system/bin/chmod', ...) — last resort fallback for
  ///      rooted devices or emulators where shell execution is permitted.
  ///
  /// [mode] is accepted for API compatibility. For '644' (read-only) the
  /// NativeEnvPlugin still sets readable; setExecutable is still called but
  /// the effect is equivalent to +r on a file that Node won't run directly.
  Future<bool> _chmodFile(String path, String mode) async {
    // ── Primary: NativeEnvPlugin via MethodChannel ──────────────────────────
    try {
      final bool? ok = await _nativeEnv.invokeMethod<bool>(
        'chmodExecutable',
        {'path': path},
      );
      if (ok == true) {
        debugPrint('[ToolsService] chmod ✅ (NativeEnvPlugin) $path');
        return true;
      }
      debugPrint('[ToolsService] chmod ❌ (NativeEnvPlugin returned false) $path');
    } catch (e) {
      debugPrint('[ToolsService] chmod NativeEnvPlugin error: $e — trying Process.run fallback');
    }

    // ── Fallback: Process.run (rooted devices / emulator only) ──────────────
    for (final cmd in ['/system/bin/chmod', '/bin/chmod', 'chmod']) {
      try {
        final r = await Process.run(cmd, [mode, path]);
        if (r.exitCode == 0) {
          debugPrint('[ToolsService] chmod ✅ (Process.run $cmd) $path');
          return true;
        }
      } catch (_) {
        continue;
      }
    }

    debugPrint('[ToolsService] chmod ❌ ALL methods failed for $path');
    return false;
  }

  /// Set permissions secara robust untuk semua executable.
  Future<void> _chmodExecutablesRobust() async {
    // 1. Node binary — paling kritis
    if (File(nodePath).existsSync()) {
      final ok = await _chmodFile(nodePath, '755');
      debugPrint('[ToolsService] chmod node: ${ok ? "✅" : "❌"} $nodePath');
    }

    // 2. Code-server entry.js (read-only JS, tidak perlu +x)
    if (File(codeServerCliPath).existsSync()) {
      await _chmodFile(codeServerCliPath, '644');
    }

    // 3. Semua file di bin/ — ini mencakup semua native tools
    final binDirectory = Directory(binDir);
    if (binDirectory.existsSync()) {
      try {
        await for (final e in binDirectory.list()) {
          if (e is File) {
            await _chmodFile(e.path, '755');
          }
          // symlinks tidak perlu chmod
        }
        debugPrint('[ToolsService] chmod bin/: ✅ (${availableNativeTools.length} tools)');
      } catch (e) {
        debugPrint('[ToolsService] Warning chmod binDir: $e');
      }
    }

    // 4. Launcher scripts
    final launcherDir = Directory('$_toolsRoot/$_abi/launcher');
    if (launcherDir.existsSync()) {
      try {
        await for (final e in launcherDir.list()) {
          if (e is File) await _chmodFile(e.path, '755');
        }
      } catch (e) {
        debugPrint('[ToolsService] Warning chmod launcher: $e');
      }
    }

    // 5. Belt-and-suspenders: ensure node binary specifically is executable.
    if (File(nodePath).existsSync()) {
      final nodeOk = await _chmodFile(nodePath, '755');
      debugPrint('[ToolsService] chmod node (final check): ${nodeOk ? "✅" : "❌"} $nodePath');
    }

    // 6. Recursive pass: chmod every non-script file under _toolsRoot/$_abi.
    //    Catches files missed by the per-directory loops above.
    try {
      final rootDir = Directory('$_toolsRoot/$_abi');
      if (rootDir.existsSync()) {
        await for (final entity in rootDir.list(recursive: true)) {
          if (entity is File) {
            final name = entity.path.split('/').last;
            if (!name.endsWith('.js') &&
                !name.endsWith('.json') &&
                !name.endsWith('.md') &&
                !name.endsWith('.txt') &&
                !name.endsWith('.css') &&
                !name.endsWith('.html')) {
              await _chmodFile(entity.path, '755');
            }
          }
        }
        debugPrint('[ToolsService] chmod recursive pass: ✅');
      }
    } catch (e) {
      debugPrint('[ToolsService] Warning chmod recursive: $e');
    }

    debugPrint('[ToolsService] Permissions applied (NativeEnvPlugin primary).');
  }

  Map<String, String> _buildEnv([Map<String, String>? extra]) {
    return {
      ...Platform.environment,
      'PATH': '$binDir:${Platform.environment['PATH'] ?? ''}',
      'NODE_PATH': '$_toolsRoot/$_abi/npm_modules',
      'HOME': _toolsRoot,
      'NODE_NO_WARNINGS': '1',
      // Native tools environment
      'TMPDIR': '$_toolsRoot/tmp',
      'TERM': 'xterm-256color',
      'LANG': 'en_US.UTF-8',
      ...?extra,
    };
  }

  // ── Public methods ────────────────────────────────────────────────────────

  Future<ProcessResult> runNode(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (!_isReady) throw StateError('[ToolsService] Not ready. Call initialize() first.');
    return Process.run(nodePath, args,
        workingDirectory: workingDirectory, environment: _buildEnv(environment));
  }

  Future<Process> startNode(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (!_isReady) throw StateError('[ToolsService] Not ready. Call initialize() first.');
    return Process.start(nodePath, args,
        workingDirectory: workingDirectory, environment: _buildEnv(environment));
  }

  /// Run a bundled native CLI tool (e.g. 'git', 'ffmpeg', 'python3').
  /// Throws [StateError] if ToolsService is not ready.
  /// Throws [ArgumentError] if the tool binary is not found in the bundle.
  Future<ProcessResult> runTool(
    String toolName,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (!_isReady) throw StateError('[ToolsService] Not ready. Call initialize() first.');
    final toolBin = nativeToolPath(toolName) ?? nativeToolPath(toolName == 'python' ? 'python3' : toolName);
    if (toolBin == null) {
      throw ArgumentError('[ToolsService] Native tool not found in bundle: $toolName');
    }
    return Process.run(
      toolBin,
      args,
      workingDirectory: workingDirectory,
      environment: _buildEnv(environment),
    );
  }

  /// Start a bundled native CLI tool as a long-running process (streaming I/O).
  Future<Process> startTool(
    String toolName,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (!_isReady) throw StateError('[ToolsService] Not ready. Call initialize() first.');
    final toolBin = nativeToolPath(toolName) ?? nativeToolPath(toolName == 'python' ? 'python3' : toolName);
    if (toolBin == null) {
      throw ArgumentError('[ToolsService] Native tool not found in bundle: $toolName');
    }
    return Process.start(
      toolBin,
      args,
      workingDirectory: workingDirectory,
      environment: _buildEnv(environment),
    );
  }

  /// Verify a specific native tool is executable.
  Future<bool> verifyNativeTool(String toolName) async {
    if (!_isReady) return false;
    try {
      final toolBin = nativeToolPath(toolName);
      if (toolBin == null) return false;
      // For scripts or tools that support --version
      final r = await Process.run(toolBin, ['--version'])
          .timeout(const Duration(seconds: 10));
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifyTools() async {
    if (!_isReady) return false;
    try {
      if (!File(nodePath).existsSync()) return false;
      final r = await Process.run(nodePath, ['--version'])
          .timeout(const Duration(seconds: 10));
      return r.exitCode == 0;
    } catch (_) { return false; }
  }

  /// Force re-apply permissions tanpa re-extract.
  Future<void> reapplyPermissions() async {
    if (!File(nodePath).existsSync()) return;
    await _chmodExecutablesRobust();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPermissionsSet, true);
    debugPrint('[ToolsService] Permissions reapplied.');
  }

  Future<void> invalidateCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kExtractedRunId);
    await prefs.remove(_kPermissionsSet);
    debugPrint('[ToolsService] Cache invalidated.');
  }

  Future<void> clearExtractedState() async {
    await invalidateCache();
    _isReady = false;
    debugPrint('[ToolsService] Extracted state cleared.');
  }
}
