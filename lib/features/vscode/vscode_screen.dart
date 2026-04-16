// lib/features/vscode/vscode_screen.dart
// SESSION 03 — VS Code WebView Screen
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:kanmongo/core/tools/code_server_service.dart';
import 'package:kanmongo/core/tools/tools_provider.dart';
import 'package:kanmongo/shared/widgets/back_handler.dart';
import 'package:kanmongo/core/theme/km_colors.dart';

class VscodeScreen extends ConsumerStatefulWidget {
  final String? initialPath;
  const VscodeScreen({super.key, this.initialPath});

  @override
  ConsumerState<VscodeScreen> createState() => _VscodeScreenState();
}

class _VscodeScreenState extends ConsumerState<VscodeScreen> {
  late WebViewController _webViewController;
  bool _serverStarted = false;
  bool _webViewLoaded = false;
  String? _errorMessage;
  static const int _csPort = 8080;

  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF1E1E1E))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => _webViewLoaded = true),
        onWebResourceError: (error) {
          if (error.errorCode != -2) {
            setState(() => _errorMessage = error.description);
          }
        },
        onNavigationRequest: (request) {
          if (request.url.startsWith('http://127.0.0.1')) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
      ));
    _startServer();
  }

  Future<void> _startServer() async {
    final toolsReady = ref.read(toolsReadyProvider).valueOrNull ?? false;
    if (!toolsReady) {
      setState(() => _errorMessage = 'Tools not ready. Please wait for extraction to complete.');
      return;
    }
    final workspaceDir = widget.initialPath ?? await _getDefaultWorkspace();
    try {
      await CodeServerService.instance.start(workspaceDir: workspaceDir, port: _csPort);
      setState(() => _serverStarted = true);
      _webViewController.loadRequest(Uri.parse(
        'http://127.0.0.1:$_csPort'
        '${widget.initialPath != null ? '/?folder=${Uri.encodeComponent(widget.initialPath!)}' : ''}',
      ));
    } catch (e) {
      setState(() => _errorMessage = 'Failed to start code-server: $e');
    }
  }

  Future<String> _getDefaultWorkspace() async {
    final dir = await getApplicationDocumentsDirectory();
    final workspace = Directory('${dir.path}/workspace');
    await workspace.create(recursive: true);
    return workspace.path;
  }

  @override
  void dispose() {
    CodeServerService.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return ConfirmExitBack(
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
          title: Row(children: [
            const Icon(Icons.code, size: 18, color: Colors.blueAccent),
            const SizedBox(width: 8),
            const Text('VS Code',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            if (_serverStarted && _webViewLoaded)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.green.withOpacity(0.5)),
                ),
                child: const Text('running',
                    style: TextStyle(fontSize: 10, color: Colors.green)),
              ),
          ]),
          actions: [
            if (_serverStarted)
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Reload',
                onPressed: () {
                  _webViewController.reload();
                  setState(() => _webViewLoaded = false);
                },
              ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: 'Close VS Code',
              onPressed: () async {
                await CodeServerService.instance.stop();
                if (mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return _ErrorView(message: _errorMessage!, onRetry: () {
        setState(() { _errorMessage = null; _serverStarted = false; });
        _startServer();
      });
    }
    if (!_serverStarted) return const _LoadingView(message: 'Starting VS Code server...');
    return Stack(children: [
      WebViewWidget(controller: _webViewController),
      if (!_webViewLoaded) const _LoadingView(message: 'Loading VS Code...'),
    ]);
  }
}

class _LoadingView extends StatelessWidget {
  final String message;
  const _LoadingView({required this.message});
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFF1E1E1E),
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const CircularProgressIndicator(color: Colors.blueAccent),
      const SizedBox(height: 16),
      Text(message, style: const TextStyle(color: Colors.white70, fontSize: 14)),
    ])),
  );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFF1E1E1E),
    padding: const EdgeInsets.all(24),
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
      const SizedBox(height: 16),
      Text(message, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blueAccent,
          foregroundColor: Colors.white,
        ),
      ),
    ])),
  );
}
