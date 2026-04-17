// lib/data/services/claude_code_service.dart
// KanMonAI — Claude Code CLI Process Manager
//
// Manages the Claude Code CLI process lifecycle:
//   • Detects active AI source (Online/BulkApi/Offline) automatically
//   • Launches Claude Code with correct env vars per AI source
//   • Streams typed output events to UI
//   • Handles stdin injection for user responses
//   • Parses output for tool use, file edits, prompts
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:kanmongo/data/services/claude_code_installer.dart';
import 'package:kanmongo/data/services/llama_http_server.dart';
import 'package:kanmongo/data/services/llama_service.dart';
import 'package:kanmongo/data/services/puter_ai_service.dart';
import 'package:kanmongo/data/services/bulk_api_service.dart';
import 'package:kanmongo/core/tools/tools_service.dart';

// ── Session State ─────────────────────────────────────────────────────────────

enum ClaudeCodeSessionState {
  idle,           // No process running
  starting,       // Process launching
  running,        // Process active, Claude is generating
  awaitingInput,  // Claude is waiting for user response (y/n, prompt, etc.)
  stopped,        // Process exited cleanly
  error,          // Process crashed or failed to start
}

// ── Output Types ──────────────────────────────────────────────────────────────

enum ClaudeOutputType {
  text,           // Regular AI response text
  toolUse,        // Claude is calling a tool (Bash/Edit/Write/Read)
  toolResult,     // Result returned from tool
  fileEdit,       // File being edited
  userPrompt,     // Claude asking user for input
  statusLine,     // Progress / thinking lines
  systemMessage,  // Claude Code system messages (cost, tokens, etc.)
  rawOutput,      // Unclassified stdout/stderr
  stderrOutput,   // stderr lines
}

// ── Output Event ──────────────────────────────────────────────────────────────

class ClaudeOutputEvent {
  final ClaudeOutputType type;
  final String text;
  final String? toolName;    // for toolUse: "Bash", "Edit", "Write", "Read"
  final String? toolInput;   // for toolUse: the input/command
  final String? filePath;    // for fileEdit: path being edited
  final bool isPartial;      // true while streaming, false when line complete
  final DateTime timestamp;

  const ClaudeOutputEvent({
    required this.type,
    required this.text,
    this.toolName,
    this.toolInput,
    this.filePath,
    this.isPartial = false,
    required this.timestamp,
  });

  @override
  String toString() =>
      '[${type.name}] $text'
      '${toolName != null ? " (tool: $toolName)" : ""}'
      '${filePath != null ? " (file: $filePath)" : ""}';
}

// ── Session ───────────────────────────────────────────────────────────────────

class ClaudeCodeSession {
  final String id;
  final String workDir;
  final DateTime startedAt;
  ClaudeCodeSessionState state;
  final List<ClaudeOutputEvent> history;

  ClaudeCodeSession({
    required this.id,
    required this.workDir,
    required this.startedAt,
    this.state = ClaudeCodeSessionState.starting,
  }) : history = [];
}

// ── ClaudeCodeService ─────────────────────────────────────────────────────────

class ClaudeCodeService {
  static final ClaudeCodeService instance = ClaudeCodeService._();
  ClaudeCodeService._();

  // ── Output patterns ──────────────────────────────────────────────────────────
  static final _toolPattern = RegExp(
    r'[⎿●]\s*(Bash|Edit|Write|Read|List|Glob|Grep|MultiEdit|NotebookRead|NotebookEdit)\s*[\(\[]?(.*)',
  );
  static final _promptPattern = RegExp(
    r'(\[Y/n\]|\[y/N\]|\(y/n\)|\(Y/N\)|Enter |Confirm |Do you |Would you |Should I )',
  );
  static final _statusPattern = RegExp(
    r'^[◯◉⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏✓✗⚡⏳🔄]',
  );
  static final _systemPattern = RegExp(
    r'(tokens|cost|\$[\d.]+|API usage|Context:)',
  );
  static final _filePattern = RegExp(
    r'(^|\s)([\./~][^\s]+\.(dart|kt|java|py|js|ts|json|yaml|yml|md|txt|sh|gradle|xml|html|css))',
  );

  // ── Private state ─────────────────────────────────────────────────────────────
  Process? _process;
  ClaudeCodeSession? _session;
  ClaudeCodeSessionState _state = ClaudeCodeSessionState.idle;

  final StreamController<ClaudeOutputEvent> _outputCtrl =
      StreamController<ClaudeOutputEvent>.broadcast();
  final StreamController<ClaudeCodeSessionState> _stateCtrl =
      StreamController<ClaudeCodeSessionState>.broadcast();

  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;

  // Retry tracking
  int _retryCount = 0;
  static const _maxRetries = 3;
  static const _retryDelay = Duration(seconds: 2);

  // Saved params for retry
  String? _lastWorkDir;
  String? _lastInitialPrompt;
  List<String> _lastExtraArgs = [];

  // Stdout line buffer for partial lines
  final StringBuffer _stdoutBuf = StringBuffer();
  final StringBuffer _stderrBuf = StringBuffer();

  // ── Public API ────────────────────────────────────────────────────────────────

  ClaudeCodeSession? get currentSession => _session;
  ClaudeCodeSessionState get state => _state;
  bool get isRunning =>
      _state == ClaudeCodeSessionState.running ||
      _state == ClaudeCodeSessionState.awaitingInput ||
      _state == ClaudeCodeSessionState.starting;

  Stream<ClaudeOutputEvent> get outputStream => _outputCtrl.stream;
  Stream<ClaudeCodeSessionState> get stateStream => _stateCtrl.stream;

  // ── Start ─────────────────────────────────────────────────────────────────────

  Future<ClaudeCodeSession> start({
    required String workDir,
    String? initialPrompt,
    List<String> extraArgs = const [],
  }) async {
    // Guard: already running
    if (_state != ClaudeCodeSessionState.idle &&
        _state != ClaudeCodeSessionState.stopped &&
        _state != ClaudeCodeSessionState.error) {
      throw StateError(
        'ClaudeCodeService already running. Call stop() first.',
      );
    }

    // Save params for potential retry
    _lastWorkDir = workDir;
    _lastInitialPrompt = initialPrompt;
    _lastExtraArgs = List.unmodifiable(extraArgs);

    _setState(ClaudeCodeSessionState.starting);
    debugPrint('[ClaudeCodeService] Starting in workDir: $workDir');

    // ── Deteksi AI source aktif & bangun environment ──────────────────────────
    final Map<String, String> env = await _buildAiEnvironment();

    // Get node invocation command
    final nodeCmd = ClaudeCodeInstaller.instance.getNodeInvocationCommand();
    if (nodeCmd == null) {
      _setState(ClaudeCodeSessionState.error);
      throw StateError('Claude Code not installed.');
    }

    // Parse "node /path/to/cli.js" → exe + args
    final parts = nodeCmd.trim().split(RegExp(r'\s+'));
    final exe = parts.first;
    final cmdArgs = [
      ...parts.skip(1),
      '--no-update',
      ...extraArgs,
    ];

    debugPrint('[ClaudeCodeService] Launching: $exe ${cmdArgs.join(' ')}');

    // Start process
    final Process proc;
    try {
      proc = await Process.start(
        exe,
        cmdArgs,
        workingDirectory: workDir,
        environment: env,
      );
    } catch (e) {
      debugPrint('[ClaudeCodeService] Process.start failed: $e');
      _setState(ClaudeCodeSessionState.error);
      rethrow;
    }

    _process = proc;

    // Create session
    final session = ClaudeCodeSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      workDir: workDir,
      startedAt: DateTime.now(),
      state: ClaudeCodeSessionState.running,
    );
    _session = session;
    _setState(ClaudeCodeSessionState.running);

    // Wire stdout
    _stdoutSub = proc.stdout.listen(
      _onStdoutData,
      onDone: _flushStdout,
      cancelOnError: false,
    );

    // Wire stderr
    _stderrSub = proc.stderr.listen(
      _onStderrData,
      onDone: _flushStderr,
      cancelOnError: false,
    );

    // Wire exit
    proc.exitCode.then(_onProcessExit);

    // Send initial prompt if provided
    if (initialPrompt != null && initialPrompt.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 500));
      await sendInput(initialPrompt);
    }

    debugPrint('[ClaudeCodeService] Session started: ${session.id}');
    return session;
  }

  // ── Deteksi AI source aktif → bangun env vars yang tepat ─────────────────────
  Future<Map<String, String>> _buildAiEnvironment() async {
    // Tentukan PATH dari bundled tools + Termux (jika tersedia)
    final binDir = ToolsService.instance.isReady
        ? ToolsService.instance.binDir
        : '/data/data/com.termux/files/usr/bin';
    final basePath =
        '$binDir:/data/data/com.termux/files/usr/bin:/system/bin:/system/xbin';

    final baseEnv = <String, String>{
      'HOME':             '/data/data/com.termux/files/home',
      'PATH':             basePath,
      'PREFIX':           '/data/data/com.termux/files/usr',
      'LD_LIBRARY_PATH':  '/data/data/com.termux/files/usr/lib',
      'TMPDIR':           '/data/data/com.termux/files/usr/tmp',
      'TERM':             'xterm-256color',
      'LANG':             'en_US.UTF-8',
    };

    // 1. Cek Online AI (Puter) — prioritas tertinggi
    final puter = PuterAiService.instance;
    await puter.load();
    if (puter.isEnabled) {
      debugPrint('[ClaudeCodeService] Using Online AI (Puter): ${puter.baseUrl}');
      return {
        ...baseEnv,
        'ANTHROPIC_BASE_URL': puter.baseUrl,
        'ANTHROPIC_API_KEY':  puter.apiKey.isNotEmpty ? puter.apiKey : 'kanmon-online',
        'ANTHROPIC_MODEL':    puter.selectedModel,
      };
    }

    // 2. Cek Bulk API — pakai key pertama yang aktif
    final bulk = BulkApiService.instance;
    await bulk.load();
    if (bulk.enabled && bulk.activeKeys.isNotEmpty) {
      final key = bulk.activeKeys.first;
      // Bulk API biasanya OpenAI-compatible — set base URL provider
      final providerUrl = key.provider.apiUrl.isNotEmpty
          ? key.provider.apiUrl
          : 'https://api.openai.com/v1';
      debugPrint('[ClaudeCodeService] Using Bulk API: $providerUrl model=${key.provider.defaultModel}');
      return {
        ...baseEnv,
        'ANTHROPIC_BASE_URL': providerUrl,
        'ANTHROPIC_API_KEY':  key.apiKey,
        'ANTHROPIC_MODEL':    key.provider.defaultModel,
      };
    }

    // 3. Fallback ke Offline AI (llama.cpp local server)
    if (!LlamaService.instance.isModelLoaded) {
      throw StateError(
        'Tidak ada sumber AI yang aktif.\n\n'
        'Aktifkan Online AI, Bulk API, atau muat model Offline AI di Settings.',
      );
    }

    debugPrint('[ClaudeCodeService] Using Offline AI (llama.cpp)');
    // Pastikan llama HTTP server berjalan
    await LlamaHttpServer.instance.start();
    await Future.delayed(const Duration(milliseconds: 300));

    return {
      ...baseEnv,
      'ANTHROPIC_BASE_URL': 'http://localhost:${LlamaHttpServer.instance.port}',
      'ANTHROPIC_API_KEY':  'kanmon-local-llama',
      'ANTHROPIC_MODEL':    'local',
    };
  }

  // ── Send Input ────────────────────────────────────────────────────────────────

  Future<void> sendInput(String text) async {
    if (_process == null) {
      throw StateError(
        'No Claude Code process running. Call start() first.',
      );
    }
    final payload = text.endsWith('\n') ? text : '$text\n';
    _process!.stdin.add(utf8.encode(payload));
    await _process!.stdin.flush();
    debugPrint('[ClaudeCodeService] Sent input: ${payload.trim()}');
    if (_state == ClaudeCodeSessionState.awaitingInput) {
      _setState(ClaudeCodeSessionState.running);
    }
  }

  Future<void> confirmYes() => sendInput('y');
  Future<void> confirmNo()  => sendInput('n');

  // ── Stop ──────────────────────────────────────────────────────────────────────

  Future<void> stop() async {
    debugPrint('[ClaudeCodeService] stop() called');
    // Set to stopped so the exit handler does not retry
    _retryCount = _maxRetries;
    _setState(ClaudeCodeSessionState.stopped);
    _session?.state = ClaudeCodeSessionState.stopped;
    await _cancelSubscriptions();
    _process?.kill(ProcessSignal.sigterm);
    _process = null;
  }

  // ── Dispose ───────────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    debugPrint('[ClaudeCodeService] dispose() called');
    await stop();
    if (!_outputCtrl.isClosed) await _outputCtrl.close();
    if (!_stateCtrl.isClosed)  await _stateCtrl.close();
  }

  // ── Private helpers ───────────────────────────────────────────────────────────

  void _setState(ClaudeCodeSessionState newState) {
    _state = newState;
    _session?.state = newState;
    if (!_stateCtrl.isClosed) {
      _stateCtrl.add(newState);
    }
    debugPrint('[ClaudeCodeService] State → ${newState.name}');
  }

  void _emit(ClaudeOutputEvent event) {
    _session?.history.add(event);
    if (!_outputCtrl.isClosed) {
      _outputCtrl.add(event);
    }
  }

  Future<void> _cancelSubscriptions() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
  }

  // ── Stdout handling ───────────────────────────────────────────────────────────

  void _onStdoutData(List<int> data) {
    final chunk = utf8.decode(data, allowMalformed: true);
    _stdoutBuf.write(chunk);
    _processBuffer(_stdoutBuf, isStderr: false);
  }

  void _flushStdout() {
    final remaining = _stdoutBuf.toString();
    if (remaining.isNotEmpty) {
      _onStdoutLine(remaining);
      _stdoutBuf.clear();
    }
  }

  void _processBuffer(StringBuffer buf, {required bool isStderr}) {
    final content = buf.toString();
    final lines = content.split('\n');
    // All lines except the last are complete; last may be partial
    for (int i = 0; i < lines.length - 1; i++) {
      final line = lines[i];
      if (isStderr) {
        _onStderrLine(line);
      } else {
        _onStdoutLine(line);
      }
    }
    buf.clear();
    buf.write(lines.last); // retain partial line
  }

  // ── Stderr handling ───────────────────────────────────────────────────────────

  void _onStderrData(List<int> data) {
    final chunk = utf8.decode(data, allowMalformed: true);
    _stderrBuf.write(chunk);
    _processBuffer(_stderrBuf, isStderr: true);
  }

  void _flushStderr() {
    final remaining = _stderrBuf.toString();
    if (remaining.isNotEmpty) {
      _onStderrLine(remaining);
      _stderrBuf.clear();
    }
  }

  void _onStderrLine(String line) {
    if (line.isEmpty) return;
    debugPrint('[ClaudeCodeService] stderr: $line');
    _emit(ClaudeOutputEvent(
      type: ClaudeOutputType.stderrOutput,
      text: line,
      timestamp: DateTime.now(),
    ));
  }

  // ── Line classifier ───────────────────────────────────────────────────────────

  void _onStdoutLine(String line) {
    if (line.isEmpty) return;
    debugPrint('[ClaudeCodeService] stdout: $line');

    final now = DateTime.now();

    // 1. Tool use
    final toolMatch = _toolPattern.firstMatch(line);
    if (toolMatch != null) {
      final toolName  = toolMatch.group(1) ?? '';
      final toolInput = toolMatch.group(2) ?? '';
      // Try to extract file path from toolInput
      String? filePath;
      final fMatch = _filePattern.firstMatch(toolInput);
      if (fMatch != null) filePath = fMatch.group(2);

      _emit(ClaudeOutputEvent(
        type:      ClaudeOutputType.toolUse,
        text:      line,
        toolName:  toolName,
        toolInput: toolInput.trim(),
        filePath:  filePath,
        timestamp: now,
      ));

      // If it's a file-editing tool, also emit fileEdit
      if (toolName == 'Edit' || toolName == 'Write' || toolName == 'MultiEdit') {
        _emit(ClaudeOutputEvent(
          type:      ClaudeOutputType.fileEdit,
          text:      line,
          toolName:  toolName,
          toolInput: toolInput.trim(),
          filePath:  filePath,
          timestamp: now,
        ));
      }
      return;
    }

    // 2. User prompt / awaiting input
    if (_promptPattern.hasMatch(line) || line.trimRight().endsWith('?')) {
      _emit(ClaudeOutputEvent(
        type:      ClaudeOutputType.userPrompt,
        text:      line,
        timestamp: now,
      ));
      _setState(ClaudeCodeSessionState.awaitingInput);
      return;
    }

    // 3. Status / spinner lines
    if (_statusPattern.hasMatch(line)) {
      _emit(ClaudeOutputEvent(
        type:      ClaudeOutputType.statusLine,
        text:      line,
        timestamp: now,
      ));
      return;
    }

    // 4. System / cost lines
    if (_systemPattern.hasMatch(line)) {
      _emit(ClaudeOutputEvent(
        type:      ClaudeOutputType.systemMessage,
        text:      line,
        timestamp: now,
      ));
      return;
    }

    // 5. Prose text vs raw output
    final hasProse = line.trim().split(' ').length > 2;
    _emit(ClaudeOutputEvent(
      type:      hasProse ? ClaudeOutputType.text : ClaudeOutputType.rawOutput,
      text:      line,
      timestamp: now,
    ));
  }

  // ── Process exit handler ──────────────────────────────────────────────────────

  Future<void> _onProcessExit(int exitCode) async {
    debugPrint('[ClaudeCodeService] Process exited with code $exitCode');
    await _cancelSubscriptions();
    _flushStdout();
    _flushStderr();
    _process = null;

    // Clean exit or user-initiated stop
    if (exitCode == 0 || _state == ClaudeCodeSessionState.stopped) {
      _setState(ClaudeCodeSessionState.stopped);
      _session?.state = ClaudeCodeSessionState.stopped;
      _retryCount = 0;
      return;
    }

    // Unexpected crash — attempt retry
    if (_retryCount < _maxRetries) {
      _retryCount++;
      final msg =
          'Process exited unexpectedly (code $exitCode). '
          'Retrying $_retryCount/$_maxRetries...';
      debugPrint('[ClaudeCodeService] $msg');
      _emit(ClaudeOutputEvent(
        type:      ClaudeOutputType.systemMessage,
        text:      msg,
        timestamp: DateTime.now(),
      ));
      _setState(ClaudeCodeSessionState.idle);
      await Future.delayed(_retryDelay);
      try {
        await start(
          workDir:       _lastWorkDir!,
          initialPrompt: _lastInitialPrompt,
          extraArgs:     _lastExtraArgs,
        );
      } catch (e) {
        debugPrint('[ClaudeCodeService] Retry failed: $e');
        _setState(ClaudeCodeSessionState.error);
      }
    } else {
      debugPrint('[ClaudeCodeService] Max retries reached, giving up.');
      _setState(ClaudeCodeSessionState.error);
      _session?.state = ClaudeCodeSessionState.error;
      _retryCount = 0;
    }
  }
}
