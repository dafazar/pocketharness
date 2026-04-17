// lib/core/tools/native_tools_manager.dart
// KanMon AI — Native Tools Manager
//
// Central registry & health monitor for ALL bundled CLI tools.
// Setelah ToolsService.initialize() selesai, semua tool terdaftar di sini
// dan dapat di-query status, path, dan dijalankan.
//
// Architecture:
//   ToolsService        → ekstraksi APK assets → disk
//   NativeToolsManager  → registry, health check, run shortcut
//   ClaudeCodeService   → lifecycle Claude Code CLI process
//   CodeServerService   → lifecycle code-server (VS Code) process
// =============================================================================

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'tools_service.dart';

// ── Tool Category ─────────────────────────────────────────────────────────────
enum ToolCategory {
  runtime,    // Node.js
  aiCode,     // Claude Code CLI
  ide,        // code-server (VS Code)
  vcs,        // git
  search,     // ripgrep, grep, find
  media,      // ffmpeg, ffprobe, sox, yt-dlp, imagemagick
  archive,    // zip, unzip, 7z, lz4, zstd, xz
  language,   // python3, sqlite3
  network,    // curl, wget, ssh, scp
  util,       // busybox, jq, nano, vim, pv, file, patch, diff, rsync, ps, free, pgrep, pkill
  debug,      // strace, exiftool
}

// ── Tool Descriptor ───────────────────────────────────────────────────────────
class NativeTool {
  final String name;
  final String displayName;
  final ToolCategory category;
  final String Function() pathGetter;
  final List<String> versionArgs;
  final String? description;

  const NativeTool({
    required this.name,
    required this.displayName,
    required this.category,
    required this.pathGetter,
    this.versionArgs = const ['--version'],
    this.description,
  });

  String get path => pathGetter();
  bool get existsOnDisk => File(path).existsSync();
}

// ── Tool Health ───────────────────────────────────────────────────────────────
class ToolHealth {
  final NativeTool tool;
  final bool exists;
  final bool executable;
  final String? version;
  final String? error;

  const ToolHealth({
    required this.tool,
    required this.exists,
    required this.executable,
    this.version,
    this.error,
  });

  bool get isHealthy => exists && executable;

  @override
  String toString() =>
      '${tool.name}: ${isHealthy ? "✅" : "❌"}'
      '${version != null ? " ($version)" : ""}'
      '${error != null ? " [$error]" : ""}';
}

// ── NativeToolsManager ────────────────────────────────────────────────────────
class NativeToolsManager {
  NativeToolsManager._();
  static final NativeToolsManager instance = NativeToolsManager._();

  final _svc = ToolsService.instance;

  // ── Tool Registry ─────────────────────────────────────────────────────────
  late final List<NativeTool> _allTools = [
    // Runtime
    NativeTool(
      name: 'node',
      displayName: 'Node.js',
      category: ToolCategory.runtime,
      pathGetter: () => _svc.nodePath,
      description: 'JavaScript runtime — core engine untuk Claude Code & VS Code',
    ),
    // AI Tools
    NativeTool(
      name: 'claude',
      displayName: 'Claude Code CLI',
      category: ToolCategory.aiCode,
      pathGetter: () => _svc.claudeCodeCliPath,
      versionArgs: const ['--version'],
      description: 'Anthropic Claude Code — AI coding agent terminal',
    ),
    NativeTool(
      name: 'code-server',
      displayName: 'VS Code (code-server)',
      category: ToolCategory.ide,
      pathGetter: () => _svc.codeServerCliPath,
      versionArgs: const ['--version'],
      description: 'VS Code IDE dijalankan natively di Android',
    ),
    // VCS
    NativeTool(
      name: 'git',
      displayName: 'Git',
      category: ToolCategory.vcs,
      pathGetter: () => _svc.gitPath,
      description: 'Version control system',
    ),
    // Search
    NativeTool(
      name: 'rg',
      displayName: 'ripgrep',
      category: ToolCategory.search,
      pathGetter: () => _svc.ripgrepPath,
      description: 'Ultra-fast text search — dipakai Claude Code untuk codebase scan',
    ),
    // Media
    NativeTool(
      name: 'ffmpeg',
      displayName: 'FFmpeg',
      category: ToolCategory.media,
      pathGetter: () => _svc.ffmpegPath,
      description: 'Video/audio converter & processor',
    ),
    NativeTool(
      name: 'ffprobe',
      displayName: 'FFprobe',
      category: ToolCategory.media,
      pathGetter: () => _svc.ffprobePath,
      description: 'Media file analyzer',
    ),
    NativeTool(
      name: 'sox',
      displayName: 'SoX',
      category: ToolCategory.media,
      pathGetter: () => _svc.soxPath,
      description: 'Audio manipulation tool',
    ),
    NativeTool(
      name: 'yt-dlp',
      displayName: 'yt-dlp',
      category: ToolCategory.media,
      pathGetter: () => _svc.ytDlpPath,
      description: 'YouTube & media downloader',
    ),
    NativeTool(
      name: 'convert',
      displayName: 'ImageMagick (convert)',
      category: ToolCategory.media,
      pathGetter: () => _svc.convertPath,
      description: 'Image format converter',
    ),
    NativeTool(
      name: 'identify',
      displayName: 'ImageMagick (identify)',
      category: ToolCategory.media,
      pathGetter: () => _svc.identifyPath,
      description: 'Image info & metadata',
    ),
    // Archive
    NativeTool(
      name: 'zip',
      displayName: 'Zip',
      category: ToolCategory.archive,
      pathGetter: () => _svc.zipPath,
      description: 'ZIP compression',
    ),
    NativeTool(
      name: 'unzip',
      displayName: 'Unzip',
      category: ToolCategory.archive,
      pathGetter: () => _svc.unzipPath,
      description: 'ZIP extraction',
    ),
    NativeTool(
      name: '7z',
      displayName: '7-Zip',
      category: ToolCategory.archive,
      pathGetter: () => _svc.p7zipPath,
      versionArgs: const ['i'],
      description: 'Multi-format archive tool',
    ),
    NativeTool(
      name: 'lz4',
      displayName: 'LZ4',
      category: ToolCategory.archive,
      pathGetter: () => _svc.lz4Path,
      description: 'Extremely fast compression',
    ),
    NativeTool(
      name: 'zstd',
      displayName: 'Zstd',
      category: ToolCategory.archive,
      pathGetter: () => _svc.zstdPath,
      description: 'Zstandard compression',
    ),
    NativeTool(
      name: 'xz',
      displayName: 'XZ Utils',
      category: ToolCategory.archive,
      pathGetter: () => _svc.xzPath,
      description: 'LZMA2 compression',
    ),
    // Language
    NativeTool(
      name: 'python3',
      displayName: 'Python 3',
      category: ToolCategory.language,
      pathGetter: () => _svc.python3Path,
      description: 'Python scripting runtime',
    ),
    NativeTool(
      name: 'sqlite3',
      displayName: 'SQLite3',
      category: ToolCategory.language,
      pathGetter: () => _svc.sqlite3Path,
      description: 'SQLite database CLI',
    ),
    // Network
    NativeTool(
      name: 'curl',
      displayName: 'cURL',
      category: ToolCategory.network,
      pathGetter: () => _svc.curlPath,
      description: 'HTTP/S transfer tool',
    ),
    NativeTool(
      name: 'wget',
      displayName: 'Wget',
      category: ToolCategory.network,
      pathGetter: () => _svc.wgetPath,
      description: 'Network downloader',
    ),
    NativeTool(
      name: 'ssh',
      displayName: 'SSH',
      category: ToolCategory.network,
      pathGetter: () => _svc.sshPath,
      description: 'Secure shell client',
    ),
    NativeTool(
      name: 'scp',
      displayName: 'SCP',
      category: ToolCategory.network,
      pathGetter: () => _svc.scpPath,
      description: 'Secure file copy',
    ),
    // Utils
    NativeTool(
      name: 'busybox',
      displayName: 'BusyBox',
      category: ToolCategory.util,
      pathGetter: () => _svc.busyboxPath,
      description: 'Combined Unix utilities (ls, cat, grep, awk, sed, ...)',
    ),
    NativeTool(
      name: 'jq',
      displayName: 'jq',
      category: ToolCategory.util,
      pathGetter: () => _svc.jqPath,
      description: 'JSON processor — dipakai Claude Code untuk parse JSON',
    ),
    NativeTool(
      name: 'nano',
      displayName: 'Nano',
      category: ToolCategory.util,
      pathGetter: () => _svc.nanoPath,
      description: 'Terminal text editor',
    ),
    NativeTool(
      name: 'vim',
      displayName: 'Vim',
      category: ToolCategory.util,
      pathGetter: () => _svc.vimPath,
      description: 'Vi improved text editor',
    ),
    NativeTool(
      name: 'pv',
      displayName: 'pv',
      category: ToolCategory.util,
      pathGetter: () => _svc.pvPath,
      description: 'Pipe viewer (progress monitor)',
    ),
    NativeTool(
      name: 'file',
      displayName: 'file',
      category: ToolCategory.util,
      pathGetter: () => _svc.filePath,
      versionArgs: const ['--version'],
      description: 'File type detector',
    ),
    NativeTool(
      name: 'patch',
      displayName: 'patch',
      category: ToolCategory.util,
      pathGetter: () => _svc.patchPath,
      description: 'Apply diff patches',
    ),
    NativeTool(
      name: 'diff',
      displayName: 'diff',
      category: ToolCategory.util,
      pathGetter: () => _svc.diffPath,
      description: 'File comparison',
    ),
    NativeTool(
      name: 'rsync',
      displayName: 'rsync',
      category: ToolCategory.util,
      pathGetter: () => _svc.rsyncPath,
      description: 'Fast file synchronization',
    ),
    NativeTool(
      name: 'ps',
      displayName: 'ps',
      category: ToolCategory.util,
      pathGetter: () => _svc.psPath,
      versionArgs: const [],
      description: 'Process status',
    ),
    NativeTool(
      name: 'free',
      displayName: 'free',
      category: ToolCategory.util,
      pathGetter: () => _svc.freePath,
      versionArgs: const [],
      description: 'Memory usage',
    ),
    NativeTool(
      name: 'pgrep',
      displayName: 'pgrep',
      category: ToolCategory.util,
      pathGetter: () => _svc.pgrepPath,
      versionArgs: const ['--version'],
      description: 'Process grep by name',
    ),
    NativeTool(
      name: 'pkill',
      displayName: 'pkill',
      category: ToolCategory.util,
      pathGetter: () => _svc.pkillPath,
      versionArgs: const ['--version'],
      description: 'Kill processes by name',
    ),
    // Debug
    NativeTool(
      name: 'exiftool',
      displayName: 'ExifTool',
      category: ToolCategory.debug,
      pathGetter: () => _svc.exiftoolPath,
      description: 'Read/write media metadata',
    ),
    NativeTool(
      name: 'strace',
      displayName: 'strace',
      category: ToolCategory.debug,
      pathGetter: () => _svc.stracePath,
      description: 'Syscall tracer',
    ),
  ];

  // ── Public API ────────────────────────────────────────────────────────────

  /// All registered tools.
  List<NativeTool> get allTools => List.unmodifiable(_allTools);

  /// Tools that exist on disk right now.
  List<NativeTool> get presentTools =>
      _allTools.where((t) => t.existsOnDisk).toList();

  /// Tools grouped by category.
  Map<ToolCategory, List<NativeTool>> get byCategory {
    final map = <ToolCategory, List<NativeTool>>{};
    for (final t in _allTools) {
      map.putIfAbsent(t.category, () => []).add(t);
    }
    return map;
  }

  /// Find a tool by name (e.g. 'git', 'node').
  NativeTool? find(String name) =>
      _allTools.where((t) => t.name == name).firstOrNull;

  /// Quick existence check.
  bool has(String name) => find(name)?.existsOnDisk ?? false;

  /// Full path for a tool, or null if not present.
  String? pathOf(String name) {
    final t = find(name);
    if (t == null || !t.existsOnDisk) return null;
    return t.path;
  }

  /// Run a tool and return ProcessResult. Throws if tool not found.
  Future<ProcessResult> run(
    String toolName,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) =>
      _svc.runTool(toolName, args,
          workingDirectory: workingDirectory, environment: environment);

  /// Start a long-running tool process. Throws if tool not found.
  Future<Process> start(
    String toolName,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) =>
      _svc.startTool(toolName, args,
          workingDirectory: workingDirectory, environment: environment);

  // ── Health Check ──────────────────────────────────────────────────────────

  /// Check health of a single tool.
  Future<ToolHealth> checkTool(NativeTool tool) async {
    if (!tool.existsOnDisk) {
      return ToolHealth(tool: tool, exists: false, executable: false,
          error: 'Binary tidak ditemukan: ${tool.path}');
    }
    if (tool.versionArgs.isEmpty) {
      return ToolHealth(tool: tool, exists: true, executable: true);
    }
    try {
      final result = await Process.run(tool.path, tool.versionArgs)
          .timeout(const Duration(seconds: 8));
      final versionLine = (result.stdout as String).split('\n').first.trim();
      return ToolHealth(
        tool: tool,
        exists: true,
        executable: result.exitCode == 0,
        version: versionLine.isNotEmpty ? versionLine : null,
        error: result.exitCode != 0
            ? 'Exit ${result.exitCode}: ${result.stderr}'.trim()
            : null,
      );
    } on ProcessException catch (e) {
      return ToolHealth(tool: tool, exists: true, executable: false,
          error: 'ProcessException: ${e.message}');
    } catch (e) {
      return ToolHealth(tool: tool, exists: true, executable: false,
          error: e.toString());
    }
  }

  /// Run health checks for all tools (or a filtered list).
  Future<List<ToolHealth>> checkAll({
    List<ToolCategory>? categories,
    void Function(int done, int total)? onProgress,
  }) async {
    final tools = categories == null
        ? _allTools
        : _allTools.where((t) => categories.contains(t.category)).toList();
    final results = <ToolHealth>[];
    for (int i = 0; i < tools.length; i++) {
      results.add(await checkTool(tools[i]));
      onProgress?.call(i + 1, tools.length);
    }
    debugPrint('[NativeToolsManager] Health check done: '
        '${results.where((r) => r.isHealthy).length}/${results.length} healthy');
    return results;
  }

  /// Quick check — just node + claude + code-server.
  Future<bool> quickCheck() async {
    if (!_svc.isReady) return false;
    final nodeOk = File(_svc.nodePath).existsSync();
    final claudeOk = File(_svc.claudeCodeCliPath).existsSync();
    return nodeOk && claudeOk;
  }
}
