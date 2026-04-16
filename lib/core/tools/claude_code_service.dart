import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'tools_service.dart';

/// Manages a Claude Code CLI subprocess.
///
/// Wraps the bundled Node.js + Claude Code CLI. No Termux or external
/// installation required — uses [ToolsService] paths directly.
class ClaudeCodeService {
  ClaudeCodeService._();
  static final ClaudeCodeService instance = ClaudeCodeService._();

  Process? _process;
  final StreamController<String> _outputController =
      StreamController<String>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  /// Output lines from Claude Code stdout.
  Stream<String> get outputStream => _outputController.stream;

  /// Error lines from Claude Code stderr.
  Stream<String> get errorStream => _errorController.stream;

  /// Starts a Claude Code session in [workingDir] with the given [apiKey].
  ///
  /// [initialPrompt] is written to stdin after startup to preload the session.
  Future<void> start({
    required String workingDir,
    required String apiKey,
    String? initialPrompt,
    Map<String, String>? extraEnv,
  }) async {
    if (_isRunning) await stop();

    final tools = ToolsService.instance;
    if (!tools.isReady) {
      throw StateError('ToolsService not ready. Call initialize() first.');
    }

    final env = {
      ...Platform.environment,
      'PATH': '${tools.binDir}:${Platform.environment['PATH'] ?? ''}',
      'NODE_PATH': '${tools.toolsRoot}/${tools.abi}/npm_modules',
      'HOME': workingDir,
      'ANTHROPIC_API_KEY': apiKey,
      'NODE_NO_WARNINGS': '1',
      'CLAUDE_CODE_DISABLE_TELEMETRY': '1',
      ...?extraEnv,
    };

    _process = await Process.start(
      tools.nodePath,
      [tools.claudeCodeCliPath, '--dangerously-skip-permissions'],
      workingDirectory: workingDir,
      environment: env,
    );

    _isRunning = true;

    // Pipe stdout to output stream
    _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _outputController.add,
          onDone: () => _isRunning = false,
          cancelOnError: false,
        );

    // Pipe stderr to error stream
    _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _errorController.add,
          cancelOnError: false,
        );

    // Wait for the process to be ready (look for prompt indicator)
    await _waitForReady();

    // Send preload prompt if provided
    if (initialPrompt != null && initialPrompt.isNotEmpty) {
      sendInput(initialPrompt);
    }
  }

  /// Sends a line of input to the running Claude Code process.
  void sendInput(String text) {
    if (_isRunning && _process != null) {
      _process!.stdin.writeln(text);
    }
  }

  /// Sends a ctrl-C interrupt to the process.
  void interrupt() {
    _process?.kill(ProcessSignal.sigint);
  }

  /// Stops the Claude Code process.
  Future<void> stop() async {
    _isRunning = false;
    _process?.kill(ProcessSignal.sigterm);
    await _process?.exitCode.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        _process?.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    _process = null;
  }

  Future<void> _waitForReady({Duration timeout = const Duration(seconds: 10)}) async {
    // Claude Code outputs a prompt marker when ready for input.
    // We wait up to [timeout] for any output, then proceed.
    final completer = Completer<void>();
    late StreamSubscription<String> sub;
    sub = _outputController.stream.listen((line) {
      if (!completer.isCompleted) {
        completer.complete();
        sub.cancel();
      }
    });
    await completer.future.timeout(timeout, onTimeout: () {
      sub.cancel();
    });
  }
}
