import 'dart:async';
import 'dart:io';
import 'tools_service.dart';

/// Manages the bundled code-server (VS Code in browser) subprocess.
class CodeServerService {
  CodeServerService._();
  static final CodeServerService instance = CodeServerService._();

  Process? _process;
  bool _isRunning = false;
  int _port = 8080;

  bool get isRunning => _isRunning;
  int get port => _port;

  /// URL to open in WebView once server is running.
  String get serverUrl => 'http://127.0.0.1:$_port';

  /// Starts code-server serving [workspaceDir] on [port].
  Future<void> start({
    required String workspaceDir,
    int port = 8080,
  }) async {
    if (_isRunning) return;
    _port = port;

    final tools = ToolsService.instance;
    if (!tools.isReady) {
      throw StateError('ToolsService not ready.');
    }

    final env = {
      ...Platform.environment,
      'PATH': '${tools.binDir}:${Platform.environment['PATH'] ?? ''}',
      'NODE_PATH': '${tools.toolsRoot}/${tools.abi}/npm_modules',
      'HOME': workspaceDir,
      'NODE_NO_WARNINGS': '1',
      'CS_DISABLE_GETTING_STARTED_OVERRIDE': '1',
    };

    _process = await Process.start(
      tools.nodePath,
      [
        tools.codeServerCliPath,
        '--bind-addr', '127.0.0.1:$_port',
        '--auth', 'none',
        '--disable-telemetry',
        '--disable-update-check',
        workspaceDir,
      ],
      workingDirectory: workspaceDir,
      environment: env,
    );

    _isRunning = true;

    // Redirect stderr to debug log — code-server prints "HTTP server listening"
    _process!.stderr.listen((data) {
      // ignore stderr in production
    });

    _process!.exitCode.then((_) => _isRunning = false);

    // Wait for server to be ready
    await _waitForPort(port);
  }

  /// Stops code-server.
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

  Future<void> _waitForPort(int port, {int maxAttempts = 20}) async {
    for (var i = 0; i < maxAttempts; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        final socket = await Socket.connect('127.0.0.1', port,
            timeout: const Duration(milliseconds: 300));
        await socket.close();
        return; // port is open
      } catch (_) {
        // not ready yet
      }
    }
    // Proceed anyway — WebView will retry
  }
}
