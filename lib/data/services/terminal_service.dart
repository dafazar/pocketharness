// lib/data/services/terminal_service.dart
// KanMon GO — Terminal Service (Full Shell Engine)
//
// Arsitektur:
//   • Persistent shell session via stdin/stdout pipe
//   • Auto-detect Termux environment → gunakan full PATH Termux
//   • Fallback ke /system/bin + busybox jika tidak ada Termux
//   • Built-in commands Dart (ls, cat, cd, dll) sebagai fallback
//   • Streaming output real-time (seperti Termux)
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'termux_bridge.dart';
import 'package:kanmongo/data/services/llama_http_server.dart';
import 'package:kanmongo/data/services/claude_code_installer.dart';

// ── Output dari satu perintah ─────────────────────────────────────────────────
class CommandResult {
  final String command;
  final String stdout;
  final String stderr;
  final int exitCode;
  final Duration duration;

  const CommandResult({
    required this.command,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.duration,
  });

  bool get isSuccess => exitCode == 0;
  String get output  => stdout.isNotEmpty ? stdout : stderr;

  String get formatted {
    final sb = StringBuffer();
    if (stdout.isNotEmpty) sb.write(stdout);
    if (stderr.isNotEmpty) sb.write(stderr);
    return sb.toString();
  }
}

// ── Download progress ─────────────────────────────────────────────────────────
class DlProgress {
  final String filename;
  final int received;
  final int total;
  final bool done;
  final String? error;
  DlProgress({required this.filename, required this.received,
      required this.total, this.done = false, this.error});
  double get fraction => total > 0 ? received / total : 0;
  String get pct => '${(fraction * 100).toStringAsFixed(1)}%';
  String get label {
    String fmt(int b) {
      if (b < 1024) return '${b}B';
      if (b < 1024*1024) return '${(b/1024).toStringAsFixed(0)}KB';
      return '${(b/(1024*1024)).toStringAsFixed(1)}MB';
    }
    return '${fmt(received)} / ${fmt(total)} ($pct)';
  }
}

// ── Terminal command type (spec Sesi 4) ───────────────────────────────────────
enum TerminalCommandType {
  general,       // alias untuk perintah umum (Sesi 7B)
  shell,
  packageInstall,
  codeRun,
  unknown,
}

// ── Terminal Result (spec Sesi 7B) ────────────────────────────────────────────
class TerminalResult {
  final String output;
  final int exitCode;
  final bool success;

  const TerminalResult({
    required this.output,
    required this.exitCode,
    required this.success,
  });
}

// ── Terminal Service ──────────────────────────────────────────────────────────
class TerminalService {
  TerminalService._();
  static final TerminalService instance = TerminalService._();

  late Directory _cwd;
  bool _initialized = false;

  // Shell session persisten
  Process? _shell;
  final _outputController = StreamController<String>.broadcast();
  Stream<String> get outputStream => _outputController.stream;

  // Environment
  late Map<String, String> _env;
  late String _shellBin;
  bool _termuxAvailable = false;
  bool _termuxChecked = false;
  String? _termuxPrefix; // e.g. /data/data/com.termux/files/usr

  // Command history (dua alias: _history lama + _commandHistory baru Sesi 7B)
  final List<String> _history = [];
  final List<String> _commandHistory = [];
  static const int _maxHistory = 100;

  List<String> get history => List.unmodifiable(_history);
  List<String> get commandHistory => List.unmodifiable(_commandHistory);
  bool get isTermuxAvailable => _termuxAvailable;
  bool get hasTermux => _termuxAvailable;

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;
    final docs = await getApplicationDocumentsDirectory();
    _cwd = Directory('${docs.path}/workspace');
    if (!_cwd.existsSync()) _cwd.createSync(recursive: true);

    await _detectEnvironment();
    await _startShellSession();
    _initialized = true;
    debugPrint('[Terminal] init — cwd: ${_cwd.path}, shell: $_shellBin');
    debugPrint('[Terminal] Termux: $_termuxAvailable, prefix: $_termuxPrefix');
  }

  // ── Initialize via TermuxBridge (Sesi 7B) ─────────────────────────────────
  /// Cek ketersediaan Termux via MethodChannel.
  /// Dipanggil sekali; pemanggilan berikutnya langsung return.
  Future<void> initialize() async {
    if (_termuxChecked) return;
    try {
      _termuxAvailable = await TermuxBridge.instance.isTermuxInstalled();
      _termuxChecked = true;
      debugPrint('[TerminalService] Termux available: $_termuxAvailable');
    } catch (e) {
      debugPrint('[TerminalService] initialize error: $e');
      _termuxAvailable = false;
      _termuxChecked = true;
    }
  }

  // ── Deteksi environment ───────────────────────────────────────────────────
  Future<void> _detectEnvironment() async {
    // Cek Termux
    final termuxPaths = [
      '/data/data/com.termux/files/usr',
      '/data/user/0/com.termux/files/usr',
    ];

    for (final prefix in termuxPaths) {
      if (Directory(prefix).existsSync()) {
        _termuxAvailable = true;
        _termuxPrefix = prefix;
        break;
      }
    }

    // Cari shell yang tersedia
    final shells = _termuxAvailable
        ? ['$_termuxPrefix/bin/bash', '$_termuxPrefix/bin/sh', '/system/bin/sh']
        : ['/system/bin/sh', '/system/bin/bash', '/bin/sh'];

    _shellBin = '/system/bin/sh'; // default
    for (final sh in shells) {
      if (File(sh).existsSync()) {
        _shellBin = sh;
        break;
      }
    }

    // Build environment variables
    final home = _termuxAvailable ? '$_termuxPrefix/../home' : _cwd.path;

    final pathDirs = <String>[];
    if (_termuxAvailable && _termuxPrefix != null) {
      pathDirs.addAll([
        '$_termuxPrefix/bin',
        '$_termuxPrefix/sbin',
        '$_termuxPrefix/bin/applets', // busybox applets
      ]);
    }
    pathDirs.addAll([
      '/system/bin',
      '/system/xbin',
      '/sbin',
      _cwd.path,
    ]);

    _env = {
      'HOME':     home,
      'TMPDIR':   '${_cwd.path}/tmp',
      'PATH':     pathDirs.join(':'),
      'TERM':     'xterm-256color',
      'LANG':     'en_US.UTF-8',
      'SHELL':    _shellBin,
      'USER':     'kanmon',
      'LOGNAME':  'kanmon',
      'PWD':      _cwd.path,
      if (_termuxAvailable && _termuxPrefix != null) ...{
        'PREFIX':   _termuxPrefix!,
        'LD_LIBRARY_PATH': '$_termuxPrefix/lib',
        'LD_PRELOAD': '',
      },
    };

    // Buat tmp dir
    Directory('${_cwd.path}/tmp').createSync(recursive: true);
  }

  // ── Start persistent shell session ────────────────────────────────────────
  Future<void> _startShellSession() async {
    try {
      _shell = await Process.start(
        _shellBin,
        [],
        workingDirectory: _cwd.path,
        environment: _env,
        runInShell: false,
      );
      debugPrint('[Terminal] Shell session started: PID=${_shell!.pid}');
    } catch (e) {
      debugPrint('[Terminal] Gagal start shell session: $e');
      _shell = null;
    }
  }

  Future<void> _restartShell() async {
    try { _shell?.kill(); } catch (_) {}
    _shell = null;
    await Future.delayed(const Duration(milliseconds: 200));
    await _startShellSession();
  }

  String get cwdPath => _cwd.path;
  String get cwdRelative {
    if (_termuxAvailable) {
      final home = '$_termuxPrefix/../home';
      if (_cwd.path.startsWith(home)) {
        return '~${_cwd.path.substring(home.length)}';
      }
    }
    final wsp = _cwd.path;
    if (wsp.contains('workspace')) {
      final idx = wsp.indexOf('workspace');
      return '~/${wsp.substring(idx)}';
    }
    return wsp;
  }

  String get shellInfo => _termuxAvailable
      ? 'Termux ($_termuxPrefix/bin)'
      : 'Android Shell (/system/bin)';

  // ── Jalankan perintah — ENTRY POINT UTAMA ─────────────────────────────────
  Future<CommandResult> run(String command, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    await init();
    _history.add(command);
    final start = DateTime.now();

    final cmd   = command.trim();
    final parts = _parseCommand(cmd);
    if (parts.isEmpty) {
      return CommandResult(command: cmd, stdout: '', stderr: '',
          exitCode: 0, duration: Duration.zero);
    }

    // Cek built-in Dart dulu (cd, clear, dll)
    final builtin = await _handleBuiltin(parts[0], parts.sublist(1), cmd);
    if (builtin != null) {
      return CommandResult(
        command: cmd, stdout: builtin, stderr: '',
        exitCode: builtin.startsWith('Error') || builtin.startsWith('bash:') ? 1 : 0,
        duration: DateTime.now().difference(start),
      );
    }

    // Jalankan via Process.run (satu-shot, bukan persistent session)
    // Lebih reliable untuk output yang besar
    return _runProcess(cmd, parts[0], parts.sublist(1), start, timeout);
  }

  // ── Streaming run — untuk long-running process ────────────────────────────
  Stream<String> runStream(String command, {
    Duration timeout = const Duration(minutes: 10),
  }) async* {
    await init();
    final cmd = command.trim();

    yield '\$ $cmd\n';

    try {
      final process = await Process.start(
        _shellBin,
        ['-c', cmd],
        workingDirectory: _cwd.path,
        environment: _env,
        runInShell: false,
      );

      // Stream stdout + stderr bersamaan
      final stdoutStream = process.stdout.transform(utf8.decoder);
      final stderrStream = process.stderr.transform(utf8.decoder);

      final combined = StreamGroup.merge([stdoutStream, stderrStream]);

      await for (final chunk in combined.timeout(timeout)) {
        yield chunk;
      }

      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        yield '\n[exit code: $exitCode]\n';
      }
    } on TimeoutException {
      yield '\n⏱ Timeout setelah ${timeout.inSeconds}s\n';
    } catch (e) {
      yield '\nError: $e\n';
    }
  }

  // ── Process.run one-shot ──────────────────────────────────────────────────
  Future<CommandResult> _runProcess(
    String command, String exe, List<String> args,
    DateTime start, Duration timeout,
  ) async {
    try {
      // Cari full path executable di environment PATH
      final exePath = await _resolveExe(exe);

      final result = await Process.run(
        exePath ?? _shellBin,
        exePath != null ? args : ['-c', command],
        workingDirectory: _cwd.path,
        environment: _env,
        runInShell: false,
      ).timeout(timeout);

      final stdout = _decodeOutput(result.stdout);
      final stderr = _decodeOutput(result.stderr);

      return CommandResult(
        command: command,
        stdout: stdout,
        stderr: stderr,
        exitCode: result.exitCode,
        duration: DateTime.now().difference(start),
      );
    } on TimeoutException {
      return CommandResult(
        command: command, stdout: '',
        stderr: '⏱ Timeout setelah ${timeout.inSeconds}s',
        exitCode: 124,
        duration: DateTime.now().difference(start),
      );
    } catch (e) {
      // Fallback: coba via shell -c
      try {
        final result = await Process.run(
          _shellBin, ['-c', command],
          workingDirectory: _cwd.path,
          environment: _env,
          runInShell: false,
        ).timeout(timeout);
        return CommandResult(
          command: command,
          stdout: _decodeOutput(result.stdout),
          stderr: _decodeOutput(result.stderr),
          exitCode: result.exitCode,
          duration: DateTime.now().difference(start),
        );
      } catch (e2) {
        return CommandResult(
          command: command, stdout: '',
          stderr: 'Perintah tidak ditemukan: $exe\n$e2',
          exitCode: 127,
          duration: DateTime.now().difference(start),
        );
      }
    }
  }

  String _decodeOutput(dynamic raw) {
    if (raw is String) return raw;
    if (raw is List<int>) {
      try { return utf8.decode(raw, allowMalformed: true); }
      catch (_) { return String.fromCharCodes(raw); }
    }
    return raw.toString();
  }

  // ── Resolve executable path dari PATH ─────────────────────────────────────
  Future<String?> _resolveExe(String exe) async {
    if (exe.startsWith('/')) {
      return File(exe).existsSync() ? exe : null;
    }
    final pathDirs = (_env['PATH'] ?? '').split(':');
    for (final dir in pathDirs) {
      final full = '$dir/$exe';
      if (File(full).existsSync()) return full;
    }
    return null;
  }

  // ── Built-in commands (Dart native, selalu tersedia) ─────────────────────
  Future<String?> _handleBuiltin(String cmd, List<String> args, String full) async {
    switch (cmd) {
      case 'cd':
        final target = args.isEmpty ? _env['HOME'] ?? _cwd.path : _resolvePath(args[0]);
        final dir = Directory(target);
        if (dir.existsSync()) {
          _cwd = dir;
          _env['PWD'] = _cwd.path;
          return '';
        }
        return 'bash: cd: $target: No such file or directory';

      case 'pwd':    return _cwd.path;
      case 'echo':   return _expandVars(args.join(' '));
      case 'clear':  return '\x1b[2J\x1b[H';
      case 'history':
        return _history.asMap().entries
            .map((e) => '  ${e.key + 1}  ${e.value}').join('\n');

      case 'ls':     return _ls(args);
      case 'cat':    return args.isEmpty ? 'Usage: cat <file>' : _cat(args[0]);
      case 'mkdir':
        for (final d in args.where((a) => !a.startsWith('-'))) {
          Directory(_resolvePath(d)).createSync(recursive: true);
        }
        return '';

      case 'touch':
        for (final f in args) {
          File(_resolvePath(f)).createSync(recursive: true);
        }
        return '';

      case 'rm':     return _rm(args);
      case 'cp':     return args.length < 2 ? 'Usage: cp <src> <dst>' : _cp(args[0], args[1]);
      case 'mv':     return args.length < 2 ? 'Usage: mv <src> <dst>' : _mv(args[0], args[1]);
      case 'head':   return _head(args);
      case 'tail':   return _tail(args);
      case 'wc':     return _wc(args);
      case 'grep':   return _grep(args);
      case 'find':   return _find(args);
      case 'tree':   return _tree(_cwd, '', 0);
      case 'env':    return _env.entries.map((e) => '${e.key}=${e.value}').join('\n');

      case 'export':
        if (args.isEmpty) return '';
        for (final a in args) {
          final eq = a.indexOf('=');
          if (eq > 0) {
            final k = a.substring(0, eq);
            final v = a.substring(eq + 1);
            _env[k] = v;
          }
        }
        return '';

      case 'which':
        if (args.isEmpty) return '';
        final found = await _resolveExe(args[0]);
        return found ?? '${args[0]}: not found';

      case 'help':   return _helpText();

      // Alias umum
      case 'dir':    return _ls(['-la']);
      case 'type':   return args.isEmpty ? '' : await _resolveExe(args[0]) ?? '${args[0]}: not found';

      // ── Package manager — route ke Termux jika tersedia ────────────────
      case 'apt':
      case 'apt-get':
      case 'pkg':
        return _handlePkgCommand(full, cmd, args);

      case 'install-claude':
        return await _handleInstallClaude(args);

      case 'claude-status':
        return await _handleClaudeStatus();

      case 'llama-server':
      case 'kanmon-server':
        return await _handleLlamaServer(args);

      default:       return null; // lanjut ke Process.run
    }
  }

  // ── Built-in: install-claude ──────────────────────────────────────────────
  Future<String> _handleInstallClaude(List<String> args) async {
    final sb = StringBuffer();
    await for (final event in ClaudeCodeInstaller.instance.install()) {
      sb.writeln('[${event.step.name}] ${event.message}');
      if (event.isError) sb.writeln('❌ Install failed.');
      if (event.step == ClaudeInstallStep.done) sb.writeln('✅ Done!');
    }
    return sb.toString();
  }

  // ── Built-in: claude-status ───────────────────────────────────────────────
  Future<String> _handleClaudeStatus() async {
    final installed = await ClaudeCodeInstaller.instance.checkInstalled();
    if (!installed) {
      return '🔴 Claude Code not installed.\nRun: install-claude';
    }
    final path       = ClaudeCodeInstaller.instance.claudeCodePath;
    final port       = LlamaHttpServer.instance.port;
    final serverRunning = LlamaHttpServer.instance.isRunning;
    return '🟢 Claude Code installed\n'
        '   Path: ${path ?? "auto-detect"}\n'
        '   Server: ${serverRunning ? "running on port $port" : "stopped (run: llama-server start)"}\n'
        '   Launch: ${ClaudeCodeInstaller.instance.getLaunchCommand(serverPort: port ?? 8080)}';
  }

  // ── Built-in: llama-server ────────────────────────────────────────────────
  Future<String> _handleLlamaServer(List<String> args) async {
    final sub = args.isEmpty ? 'status' : args[0].toLowerCase();
    switch (sub) {
      case 'start':
        final port = await LlamaHttpServer.instance.start();
        return '✅ llama.cpp HTTP server started on port $port\n'
               'Endpoint: http://localhost:$port/v1/chat/completions\n'
               'Models:   http://localhost:$port/v1/models';
      case 'stop':
        await LlamaHttpServer.instance.stop();
        return '⏹ llama.cpp HTTP server stopped.';
      case 'status':
        final s = LlamaHttpServer.instance;
        if (s.isRunning) {
          return '🟢 Running on port ${s.port}\n'
                 '   http://localhost:${s.port}/v1/chat/completions';
        }
        return '🔴 Not running. Use: llama-server start';
      default:
        return 'Usage: llama-server [start|stop|status]';
    }
  }

  // ── Built-in ls ──────────────────────────────────────────────────────────
  String _ls(List<String> args) {
    final showHidden = args.any((a) => a.contains('a'));
    final longFmt    = args.any((a) => a.contains('l'));
    final pathArgs   = args.where((a) => !a.startsWith('-')).toList();
    final dir = pathArgs.isEmpty
        ? _cwd
        : Directory(_resolvePath(pathArgs[0]));

    if (!dir.existsSync()) return 'ls: ${dir.path}: No such file or directory';

    final entries = dir.listSync()
      ..sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
        return a.path.compareTo(b.path);
      });

    if (!longFmt) {
      final cols = entries
          .where((e) => showHidden || !p.basename(e.path).startsWith('.'))
          .map((e) {
            final name = p.basename(e.path);
            return e is Directory ? '\x1b[1;34m$name/\x1b[0m' : name;
          }).join('  ');
      return cols;
    }

    final sb = StringBuffer();
    for (final e in entries) {
      final name = p.basename(e.path);
      if (!showHidden && name.startsWith('.')) continue;
      final isDir  = e is Directory;
      final size   = isDir ? '       -' : _fmtSizePad(File(e.path).lengthSync());
      final type   = isDir ? 'd' : '-';
      final perm   = isDir ? 'rwxr-xr-x' : 'rw-r--r--';
      final disp   = isDir ? '\x1b[1;34m$name/\x1b[0m' : name;
      sb.writeln('$type$perm  1 kanmon  $size  $disp');
    }
    return sb.toString().trim();
  }

  // ── Built-in cat ─────────────────────────────────────────────────────────
  String _cat(String filename) {
    try {
      final path = _resolvePath(filename);
      final file = File(path);
      if (!file.existsSync()) return 'cat: $filename: No such file or directory';
      final size = file.lengthSync();
      if (size > 5 * 1024 * 1024) return '[File terlalu besar: ${_fmtSize(size)}. Gunakan head/tail]';
      return file.readAsStringSync();
    } catch (e) { return 'cat: $e'; }
  }

  // ── Built-in rm ──────────────────────────────────────────────────────────
  String _rm(List<String> args) {
    final recursive = args.contains('-r') || args.contains('-rf') ||
        args.contains('-Rf') || args.contains('-fr');
    final force = args.contains('-f') || args.contains('-rf') || args.contains('-fr');
    for (final a in args.where((a) => !a.startsWith('-'))) {
      final path = _resolvePath(a);
      try {
        if (FileSystemEntity.isDirectorySync(path)) {
          if (recursive) Directory(path).deleteSync(recursive: true);
          else return 'rm: $a: is a directory';
        } else {
          final f = File(path);
          if (f.existsSync()) f.deleteSync();
          else if (!force) return 'rm: $a: No such file or directory';
        }
      } catch (e) { return 'rm: $e'; }
    }
    return '';
  }

  // ── Built-in head/tail/wc/grep/find ──────────────────────────────────────
  String _head(List<String> args) {
    int n = 10;
    String? filename;
    for (int i = 0; i < args.length; i++) {
      if ((args[i] == '-n') && i + 1 < args.length) n = int.tryParse(args[i + 1]) ?? 10;
      else if (!args[i].startsWith('-')) filename = args[i];
    }
    if (filename == null) return 'Usage: head [-n N] <file>';
    return _cat(filename).split('\n').take(n).join('\n');
  }

  String _tail(List<String> args) {
    int n = 10;
    String? filename;
    for (int i = 0; i < args.length; i++) {
      if ((args[i] == '-n') && i + 1 < args.length) n = int.tryParse(args[i + 1]) ?? 10;
      else if (!args[i].startsWith('-')) filename = args[i];
    }
    if (filename == null) return 'Usage: tail [-n N] <file>';
    final lines = _cat(filename).split('\n');
    return lines.skip((lines.length - n).clamp(0, lines.length)).join('\n');
  }

  String _wc(List<String> args) {
    if (args.isEmpty) return 'Usage: wc <file>';
    final file = args.firstWhere((a) => !a.startsWith('-'), orElse: () => '');
    if (file.isEmpty) return 'Usage: wc <file>';
    final content = _cat(file);
    return '${content.split('\n').length}\t${content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length}\t${content.length}\t$file';
  }

  String _grep(List<String> args) {
    final ignoreCase  = args.contains('-i');
    final recursive   = args.contains('-r') || args.contains('-R');
    final lineNumber  = args.contains('-n');
    final filtered    = args.where((a) => !a.startsWith('-')).toList();
    if (filtered.isEmpty) return 'Usage: grep [-i] [-n] [-r] <pattern> [file]';

    final pattern = filtered[0];
    final target  = filtered.length > 1 ? filtered[1] : '.';
    final regex   = RegExp(pattern, caseSensitive: !ignoreCase);

    String grepFile(String path) {
      try {
        final content = File(path).readAsStringSync();
        final lines   = content.split('\n');
        final results = <String>[];
        for (int i = 0; i < lines.length; i++) {
          if (regex.hasMatch(lines[i])) {
            results.add(lineNumber ? '${i+1}:${lines[i]}' : lines[i]);
          }
        }
        return results.join('\n');
      } catch (_) { return ''; }
    }

    if (recursive) {
      final dir = Directory(_resolvePath(target));
      final sb  = StringBuffer();
      if (dir.existsSync()) {
        for (final e in dir.listSync(recursive: true)) {
          if (e is File) {
            final out = grepFile(e.path);
            if (out.isNotEmpty) sb.writeln('${e.path}:\n$out');
          }
        }
      }
      return sb.toString().trim();
    }

    if (filtered.length < 2) return 'Usage: grep <pattern> <file>';
    return grepFile(_resolvePath(target));
  }

  String _find(List<String> args) {
    final dirArg  = args.isEmpty || args[0].startsWith('-') ? '.' : args[0];
    final nameIdx = args.indexOf('-name');
    final typeIdx = args.indexOf('-type');
    final pattern = nameIdx >= 0 && nameIdx + 1 < args.length ? args[nameIdx + 1] : '';
    final typeFilter = typeIdx >= 0 && typeIdx + 1 < args.length ? args[typeIdx + 1] : '';
    final sb = StringBuffer();
    _findRecursive(Directory(_resolvePath(dirArg)), pattern, typeFilter, sb, 0);
    return sb.toString().trim();
  }

  void _findRecursive(Directory dir, String pat, String type, StringBuffer sb, int depth) {
    if (depth > 8) return;
    try {
      for (final e in dir.listSync()) {
        final name = p.basename(e.path);
        final isDir = e is Directory;
        final matchType = type.isEmpty
            || (type == 'f' && !isDir) || (type == 'd' && isDir);
        final matchPat = pat.isEmpty || _globMatch(name, pat);
        if (matchType && matchPat) sb.writeln(e.path.replaceFirst(_cwd.path, '.'));
        if (isDir) _findRecursive(e as Directory, pat, type, sb, depth + 1);
      }
    } catch (_) {}
  }

  bool _globMatch(String name, String pattern) {
    final regexStr = RegExp.escape(pattern)
        .replaceAll(r'\*', '.*')
        .replaceAll(r'\?', '.');
    return RegExp('^$regexStr\$').hasMatch(name);
  }

  String _tree(Directory dir, String prefix, int depth) {
    if (depth > 5) return '';
    final sb = StringBuffer();
    try {
      final entries = dir.listSync()..sort((a,b) => a.path.compareTo(b.path));
      for (int i = 0; i < entries.length; i++) {
        final e      = entries[i];
        final isLast = i == entries.length - 1;
        final name   = p.basename(e.path);
        final isDir  = e is Directory;
        final branch = isLast ? '└── ' : '├── ';
        final disp   = isDir ? '\x1b[1;34m$name/\x1b[0m' : name;
        sb.writeln('$prefix$branch$disp');
        if (isDir) {
          sb.write(_tree(e as Directory,
              '$prefix${isLast ? "    " : "│   "}', depth + 1));
        }
      }
    } catch (_) {}
    return sb.toString();
  }

  // ── cp / mv ───────────────────────────────────────────────────────────────
  String _cp(String src, String dst) {
    try {
      final srcPath = _resolvePath(src);
      final dstPath = _resolvePath(dst);
      if (FileSystemEntity.isDirectorySync(srcPath)) {
        _copyDir(Directory(srcPath), Directory(dstPath));
      } else {
        File(srcPath).copySync(dstPath);
      }
      return '';
    } catch (e) { return 'cp: $e'; }
  }

  void _copyDir(Directory src, Directory dst) {
    dst.createSync(recursive: true);
    for (final e in src.listSync()) {
      final name = p.basename(e.path);
      if (e is Directory) _copyDir(e, Directory('${dst.path}/$name'));
      else File(e.path).copySync('${dst.path}/$name');
    }
  }

  String _mv(String src, String dst) {
    try {
      final srcPath = _resolvePath(src);
      final dstPath = _resolvePath(dst);
      if (FileSystemEntity.isDirectorySync(srcPath)) {
        Directory(srcPath).renameSync(dstPath);
      } else {
        File(srcPath).renameSync(dstPath);
      }
      return '';
    } catch (e) { return 'mv: $e'; }
  }

  // ── Resolve path ──────────────────────────────────────────────────────────
  String _resolvePath(String path) {
    if (path == '~') return _env['HOME'] ?? _cwd.path;
    if (path.startsWith('~/')) return p.join(_env['HOME'] ?? _cwd.path, path.substring(2));
    if (path.startsWith('/')) return path;
    return p.normalize(p.join(_cwd.path, path));
  }

  String _expandVars(String text) {
    return text.replaceAllMapped(
      RegExp(r'\$\{?(\w+)\}?'),
      (m) => _env[m.group(1)] ?? '',
    );
  }

  // ── Write / Read file ─────────────────────────────────────────────────────
  Future<void> writeFile(String filename, String content) async {
    await init();
    final file = File(_resolvePath(filename));
    file.parent.createSync(recursive: true);
    await file.writeAsString(content);
  }

  Future<String> readFile(String filename) async {
    await init();
    final file = File(_resolvePath(filename));
    if (!file.existsSync()) throw Exception('File tidak ditemukan: $filename');
    return file.readAsString();
  }

  // ── Download ──────────────────────────────────────────────────────────────
  Stream<DlProgress> download(String url, {String? savePath}) async* {
    await init();
    final filename = savePath ?? Uri.parse(url).pathSegments.last;
    final destPath = _resolvePath(filename);
    File(destPath).parent.createSync(recursive: true);

    yield DlProgress(filename: filename, received: 0, total: 0);

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      final req  = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'KanMonGO/1.0');
      final resp = await req.close();

      if (resp.statusCode != 200) {
        yield DlProgress(filename: filename, received: 0, total: 0,
            error: 'HTTP ${resp.statusCode}');
        return;
      }

      final total = resp.contentLength;
      int received = 0;
      final sink = File(destPath).openWrite();

      await for (final chunk in resp) {
        sink.add(chunk);
        received += chunk.length;
        yield DlProgress(
          filename: filename,
          received: received,
          total: total > 0 ? total : received * 2,
        );
      }
      await sink.close();
      client.close();

      yield DlProgress(filename: filename,
          received: received, total: received, done: true);
    } catch (e) {
      yield DlProgress(filename: filename, received: 0, total: 0, error: e.toString());
    }
  }

  // ── List files ────────────────────────────────────────────────────────────
  Future<List<FileSystemEntity>> listFiles({String? subdir}) async {
    await init();
    final dir = subdir != null ? Directory(_resolvePath(subdir)) : _cwd;
    if (!dir.existsSync()) return [];
    return dir.listSync()..sort((a, b) {
      final aIsDir = a is Directory;
      final bIsDir = b is Directory;
      if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
      return a.path.compareTo(b.path);
    });
  }

  // ── Package manager: apt / apt-get / pkg ─────────────────────────────────
  // Dipanggil dari _handleBuiltin — mengembalikan null jika harus dieksekusi
  // via Process.run (Termux tersedia), atau pesan error jika tidak ada Termux.
  String? _handlePkgCommand(String fullCmd, String pkgMgr, List<String> args) {
    if (!_termuxAvailable || _termuxPrefix == null) {
      final subCmd = args.isNotEmpty ? args[0] : '';
      return '❌ Perintah "$pkgMgr $subCmd" tidak tersedia.\n\n'
          '📱 KanMon Terminal berjalan di mode Android Shell (/system/bin).\n'
          '   Mode ini TIDAK mendukung apt/pkg/dnf/yum karena Android\n'
          '   bukan distribusi Linux biasa — tidak ada package manager bawaan.\n\n'
          '✅ Solusi: Install Termux dari F-Droid\n'
          '   https://f-droid.org/packages/com.termux/\n\n'
          'Setelah Termux terinstall & buka sekali, KanMon akan otomatis\n'
          'mendeteksi Termux dan perintah berikut akan tersedia:\n'
          '  pkg install ffmpeg       # media tools\n'
          '  pkg install python       # Python 3\n'
          '  pkg install nodejs       # Node.js\n'
          '  pkg install git          # Git\n'
          '  pkg install imagemagick  # image processing\n'
          '  apt install <package>    # alias pkg install\n\n'
          'Perintah yang TERSEDIA di mode Android Shell saat ini:\n'
          '  ls, cd, pwd, cat, grep, find, echo, env, mkdir, rm, cp, mv\n'
          '  head, tail, wc, tree, which, history, clear\n'
          '  /download <url>  — download file\n'
          '  /ai              — mode AI untuk bantuan\n';
    }
    // Termux tersedia — return null agar Process.run yang handle
    // dengan PATH yang sudah include Termux bin
    return null;
  }

  // ── Install package dengan streaming output ───────────────────────────────
  Stream<String> installPackageStream(
    String packageName, {
    bool update = true,
  }) async* {
    await init();

    if (!_termuxAvailable || _termuxPrefix == null) {
      yield '❌ Termux tidak ditemukan.\n'
            'Install Termux dari F-Droid untuk menginstall package.\n';
      return;
    }

    if (update) {
      yield '🔄 Updating package list...\n';
      yield* runStream(
        'DEBIAN_FRONTEND=noninteractive apt-get update -y',
        timeout: const Duration(minutes: 3),
      );
      yield '\n';
    }

    yield '📦 Installing $packageName...\n';

    // Coba apt-get dulu, fallback ke pkg
    final aptBin = '$_termuxPrefix/bin/apt-get';
    final pkgBin = '$_termuxPrefix/bin/pkg';

    final installer = File(aptBin).existsSync()
        ? 'DEBIAN_FRONTEND=noninteractive $aptBin install -y $packageName'
        : '$pkgBin install -y $packageName';

    yield* runStream(installer, timeout: const Duration(minutes: 10));

    // Verifikasi
    final check = await run('which $packageName',
        timeout: const Duration(seconds: 5));
    if (check.isSuccess && check.stdout.trim().isNotEmpty) {
      yield '\n✅ $packageName berhasil terinstall: ${check.stdout.trim()}\n';
    } else {
      yield '\n⚠️ Verifikasi gagal — coba: pkg install $packageName\n';
    }
  }

  // ── Script runner ─────────────────────────────────────────────────────────
  Future<CommandResult> runScript(String scriptContent, {String ext = 'sh'}) async {
    await init();
    final filename = '.ai_script_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final filepath = _resolvePath(filename);
    await File(filepath).writeAsString(scriptContent);
    final chmodResult = await run('chmod +x $filename');
    debugPrint('[Terminal] chmod: ${chmodResult.output}');
    final result = await run('sh $filename',
        timeout: const Duration(minutes: 5));
    try { File(filepath).deleteSync(); } catch (_) {}
    return result;
  }

  // ── Parse command ─────────────────────────────────────────────────────────
  List<String> _parseCommand(String cmd) {
    final parts   = <String>[];
    final current = StringBuffer();
    bool inDouble = false;
    bool inSingle = false;
    bool escaped  = false;

    for (int i = 0; i < cmd.length; i++) {
      final c = cmd[i];
      if (escaped) { current.write(c); escaped = false; continue; }
      if (c == '\\' && !inSingle) { escaped = true; continue; }
      if (c == '"' && !inSingle)  { inDouble = !inDouble; continue; }
      if (c == "'" && !inDouble)  { inSingle = !inSingle; continue; }
      if (c == ' ' && !inDouble && !inSingle) {
        if (current.isNotEmpty) { parts.add(current.toString()); current.clear(); }
        continue;
      }
      current.write(c);
    }
    if (current.isNotEmpty) parts.add(current.toString());
    return parts;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _fmtSize(int b) {
    if (b < 1024) return '${b}B';
    if (b < 1024*1024) return '${(b/1024).toStringAsFixed(0)}KB';
    return '${(b/(1024*1024)).toStringAsFixed(1)}MB';
  }

  String _fmtSizePad(int b) {
    final s = _fmtSize(b);
    return s.padLeft(8);
  }

  // ── checkInternet (spec Sesi 4 → diperbarui Sesi 7B) ─────────────────────
  Future<bool> checkInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (e) {
      debugPrint('[TerminalService] checkInternet error: $e');
      return false;
    }
  }

  // ── _addToHistory (Sesi 7B) ───────────────────────────────────────────────
  void _addToHistory(String command) {
    if (command.trim().isEmpty) return;
    _commandHistory.remove(command); // hindari duplikat berurutan
    _commandHistory.insert(0, command);
    if (_commandHistory.length > _maxHistory) {
      _commandHistory.removeLast();
    }
  }

  // ── detectType (spec Sesi 4 → diperbarui Sesi 7B) ────────────────────────
  TerminalCommandType detectType(String command) {
    final cmd = command.trim().toLowerCase();
    final packageInstallers = [
      'pip install', 'pip3 install',
      'npm install', 'npm i ',
      'dart pub add', 'flutter pub add',
      'apt install', 'apt-get install',
      'pkg install',
      'gem install',
      'cargo install',
      'go get',
      'composer require',
      'yarn add',
      'brew install',
    ];
    for (final prefix in packageInstallers) {
      if (cmd.startsWith(prefix) || cmd.contains(' $prefix')) {
        return TerminalCommandType.packageInstall;
      }
    }
    if (cmd.startsWith('python ') || cmd.startsWith('python3 ') ||
        cmd.startsWith('node ') || cmd.startsWith('dart run ') ||
        cmd.startsWith('java ') || cmd.startsWith('kotlin ')) {
      return TerminalCommandType.codeRun;
    }
    if (cmd.startsWith('cd ') || cmd.startsWith('ls') || cmd.startsWith('cat ') ||
        cmd.startsWith('echo ') || cmd.startsWith('pwd') || cmd.startsWith('mkdir ') ||
        cmd.startsWith('rm ') || cmd.startsWith('cp ') || cmd.startsWith('mv ') ||
        cmd.startsWith('chmod ') || cmd.startsWith('grep ')) {
      return TerminalCommandType.shell;
    }
    return TerminalCommandType.general;
  }

  // ── executeStream — STREAMING REAL (Sesi 7B) ─────────────────────────────
  /// Streaming output real-time dari command execution.
  /// Cek internet otomatis sebelum package install command.
  Stream<String> executeStream(String command) async* {
    final cmd = command.trim();
    if (cmd.isEmpty) return;

    _addToHistory(cmd);
    final start = DateTime.now();

    // Cek internet jika package install
    if (detectType(cmd) == TerminalCommandType.packageInstall) {
      yield '🔍 Memeriksa koneksi internet...\n';
      final hasNet = await checkInternet();
      if (!hasNet) {
        yield '❌ Tidak ada koneksi internet.\n';
        yield 'Instalasi paket memerlukan internet aktif.\n';
        yield 'Saran: aktifkan WiFi atau data seluler, lalu coba lagi.\n';
        return;
      }
      yield '✅ Internet tersedia. Melanjutkan instalasi...\n';
    }

    // Sinkronisasi status Termux via TermuxBridge
    await initialize();

    if (_termuxAvailable) {
      yield '⏳ Menjalankan di Termux...\n';
      final res = await TermuxBridge.instance.run(
        cmd,
        timeout: const Duration(minutes: 5),
      );
      if (res.combinedOutput.isNotEmpty) yield res.combinedOutput;
      yield '\n[Exit: ${res.exitCode}] [${DateTime.now().difference(start).inSeconds}s]\n';
    } else {
      // Fallback: Process.start — streaming output baris per baris
      yield '⚠️ Termux tidak tersedia — menggunakan shell terbatas.\n';
      try {
        final process = await Process.start(
          'sh', ['-c', cmd],
          runInShell: true,
        );

        await for (final data in process.stdout.transform(utf8.decoder)) {
          yield data;
        }
        await for (final data in process.stderr.transform(utf8.decoder)) {
          if (data.trim().isNotEmpty) yield '⚠️ $data';
        }

        final exitCode = await process.exitCode;
        yield '\n[Exit: $exitCode] [${DateTime.now().difference(start).inSeconds}s]\n';
      } catch (e) {
        yield '❌ Error menjalankan command: $e\n';
      }
    }
  }

  // ── execute — non-streaming wrapper (Sesi 7B backward compat) ────────────
  Future<TerminalResult> execute(String command) async {
    final buffer = StringBuffer();
    int exitCode = 0;

    await for (final chunk in executeStream(command)) {
      buffer.write(chunk);
      if (chunk.contains('[Exit: ')) {
        final match = RegExp(r'\[Exit: (-?\d+)\]').firstMatch(chunk);
        if (match != null) exitCode = int.tryParse(match.group(1) ?? '0') ?? 0;
      }
    }

    return TerminalResult(
      output: buffer.toString(),
      exitCode: exitCode,
      success: exitCode == 0,
    );
  }

  // ── Dispose ───────────────────────────────────────────────────────────────
  void dispose() {
    try { _shell?.kill(); } catch (_) {}
    _outputController.close();
  }

  // ── Help text ─────────────────────────────────────────────────────────────
  String _helpText() => '''
KanMon Terminal — Shell Commands
${_termuxAvailable ? "✅ Termux terdeteksi — semua tool Termux tersedia!\n" : "⚠️  Termux tidak terdeteksi — install Termux untuk fitur penuh\n"}
BUILT-IN (selalu tersedia):
  ls [-la]          List file dengan warna
  cd <dir>          Ganti direktori  
  pwd               Print working directory
  mkdir [-p] <dir>  Buat folder
  touch <file>      Buat file kosong
  rm [-rf] <path>   Hapus file/folder
  cp <src> <dst>    Copy file/folder
  mv <src> <dst>    Pindah/rename
  cat <file>        Tampilkan isi file
  head/tail [-n]    Baris pertama/terakhir
  grep [-i] [-r]    Cari teks dalam file
  find [-name][-type] Cari file/folder
  tree              Tampilkan struktur folder
  echo <text>       Print teks
  env               Tampilkan environment
  export K=V        Set environment variable
  which <cmd>       Lokasi executable
  history           Riwayat perintah
  clear             Bersihkan layar
  help              Bantuan ini

${_termuxAvailable ? """TERMUX COMMANDS (tersedia):
  pkg install <pkg>  Install package
  pkg update         Update repository  
  apt install <pkg>  Alias pkg install
  pip install <pkg>  Install Python package
  npm install <pkg>  Install Node package
  git clone/pull/push Git operations
  ssh / scp          Remote access
  curl / wget        HTTP requests
  python3 / node     Scripting
  gcc / clang        Compiler
  vim / nano         Text editor
  bash / zsh         Shell alternatives
  ...dan semua package Termux lainnya!
""" : """NETWORK (via sistem):
  curl <url>         HTTP request
  wget <url>         Download file
  /download <url>    Download dengan progress

TIPS:
  Install Termux dari F-Droid untuk fitur penuh:
  • apt install / pkg install
  • git, python, node, ssh, dll
  • Semua tool seperti Termux!
"""}
AI COMMANDS:
  /ai               Toggle mode AI
  /ask <pertanyaan>  Tanya AI langsung
  /edit <file>       Edit file dengan AI
  /script <task>     AI buat & jalankan script
  /download <url>    Download dengan progress
  install-claude    Install Claude Code CLI
  claude-status     Check Claude Code status
  kanmon-claude     Launch Claude Code (after install)
''';
}

// ── StreamGroup helper (merge multiple streams) ───────────────────────────────
class StreamGroup {
  static Stream<T> merge<T>(List<Stream<T>> streams) {
    final controller = StreamController<T>.broadcast();
    var active = streams.length;
    for (final stream in streams) {
      stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: () { if (--active == 0) controller.close(); },
      );
    }
    return controller.stream;
  }
}
