// lib/features/claude_code/claude_code_screen.dart
// SESSION 03 — Claude Code Terminal Screen
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanmongo/core/tools/claude_code_service.dart';
import 'package:kanmongo/core/tools/preload_prompt.dart';
import 'package:kanmongo/core/tools/tools_service.dart';
import 'package:kanmongo/data/services/llama_service.dart';
import 'package:kanmongo/shared/widgets/back_handler.dart';
import 'package:kanmongo/core/theme/km_colors.dart';

class ClaudeCodeTerminalScreen extends StatefulWidget {
  final String? workingDirectory;
  const ClaudeCodeTerminalScreen({super.key, this.workingDirectory});

  @override
  State<ClaudeCodeTerminalScreen> createState() => _ClaudeCodeTerminalScreenState();
}

class _ClaudeCodeTerminalScreenState extends State<ClaudeCodeTerminalScreen> {
  final _lines = <_TerminalLine>[];
  final _scrollCtrl = ScrollController();
  final _inputCtrl = TextEditingController();
  final _inputFocus = FocusNode();
  StreamSubscription<String>? _outSub;
  StreamSubscription<String>? _errSub;
  bool _isRunning = false;
  bool _isStarting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  Future<void> _startSession() async {
    setState(() { _isStarting = true; _errorMessage = null; });
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('anthropic_api_key') ?? '';
    if (apiKey.isEmpty) {
      setState(() {
        _isStarting = false;
        _errorMessage = 'Anthropic API key tidak ditemukan.\nBuka Pengaturan → Online AI untuk menambahkan API key.';
      });
      return;
    }
    final workDir = widget.workingDirectory ?? '/data/data/com.kanmongo.app/files';
    final preloadPrompt = buildClaudeCodePreloadPrompt(
      projectRoot: workDir,
      offlineModelName: LlamaService.instance.currentModel?.name,
      nodeVersion: ToolsService.instance.manifest?.nodeVersion,
    );
    _outSub = ClaudeCodeService.instance.outputStream.listen((line) {
      if (mounted) setState(() => _lines.add(_TerminalLine(text: line, isError: false)));
      _scrollToBottom();
    });
    _errSub = ClaudeCodeService.instance.errorStream.listen((line) {
      if (mounted) setState(() => _lines.add(_TerminalLine(text: line, isError: true)));
      _scrollToBottom();
    });
    try {
      await ClaudeCodeService.instance.start(
        workingDir: workDir,
        apiKey: apiKey,
        initialPrompt: preloadPrompt,
      );
      if (mounted) setState(() { _isRunning = true; _isStarting = false; });
    } catch (e) {
      if (mounted) setState(() { _isStarting = false; _errorMessage = 'Gagal memulai Claude Code: $e'; });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendInput() {
    final text = _inputCtrl.text;
    if (text.isEmpty || !_isRunning) return;
    ClaudeCodeService.instance.sendInput(text);
    setState(() => _lines.add(_TerminalLine(text: '> $text', isError: false)));
    _inputCtrl.clear();
    _inputFocus.requestFocus();
    _scrollToBottom();
  }

  void _interrupt() {
    ClaudeCodeService.instance.interrupt();
    setState(() => _lines.add(_TerminalLine(text: '^C', isError: true)));
  }

  Future<void> _stopSession() async {
    _outSub?.cancel();
    _errSub?.cancel();
    await ClaudeCodeService.instance.stop();
    if (mounted) setState(() { _isRunning = false; });
  }

  @override
  void dispose() {
    _stopSession();
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return ConfirmExitBack(
      onWillPop: () async {
        await _stopSession();
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        appBar: AppBar(
          backgroundColor: const Color(0xFF161B22),
          foregroundColor: Colors.white,
          title: Row(children: [
            const Icon(Icons.smart_toy_outlined, size: 18, color: Colors.greenAccent),
            const SizedBox(width: 8),
            const Text('Claude Code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (_isRunning ? Colors.green : Colors.grey).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: (_isRunning ? Colors.green : Colors.grey).withOpacity(0.5)),
              ),
              child: Text(
                _isStarting ? 'starting...' : (_isRunning ? 'running' : 'stopped'),
                style: TextStyle(
                  fontSize: 10,
                  color: _isRunning ? Colors.greenAccent : Colors.grey,
                ),
              ),
            ),
          ]),
          actions: [
            if (_isRunning)
              IconButton(
                icon: const Icon(Icons.stop_circle_outlined, size: 20, color: Colors.redAccent),
                tooltip: 'Interrupt (Ctrl+C)',
                onPressed: _interrupt,
              ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: 'Close',
              onPressed: () async {
                await _stopSession();
                if (mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ),
        body: _errorMessage != null
            ? _buildErrorView()
            : Column(children: [
                Expanded(child: _buildTerminalOutput()),
                _buildInputBar(c),
              ]),
      ),
    );
  }

  Widget _buildErrorView() => Container(
    color: const Color(0xFF0D1117),
    padding: const EdgeInsets.all(24),
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
      const SizedBox(height: 16),
      Text(_errorMessage!,
          style: const TextStyle(color: Colors.white70),
          textAlign: TextAlign.center),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: () { setState(() => _errorMessage = null); _startSession(); },
        icon: const Icon(Icons.refresh),
        label: const Text('Coba Lagi'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.greenAccent,
          foregroundColor: Colors.black,
        ),
      ),
    ])),
  );

  Widget _buildTerminalOutput() => Container(
    color: const Color(0xFF0D1117),
    child: _isStarting && _lines.isEmpty
        ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: Colors.greenAccent),
            SizedBox(height: 12),
            Text('Memulai Claude Code...', style: TextStyle(color: Colors.white54, fontSize: 13)),
          ]))
        : ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(12),
            itemCount: _lines.length,
            itemBuilder: (_, i) {
              final line = _lines[i];
              return Text(
                line.text,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: line.isError ? Colors.redAccent : Colors.greenAccent.shade100,
                  height: 1.4,
                ),
              );
            },
          ),
  );

  Widget _buildInputBar(KmColors c) => Container(
    color: const Color(0xFF161B22),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Row(children: [
      const Text('>', style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 14)),
      const SizedBox(width: 8),
      Expanded(
        child: TextField(
          controller: _inputCtrl,
          focusNode: _inputFocus,
          enabled: _isRunning,
          style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: 'Ketik perintah...',
            hintStyle: TextStyle(color: Colors.white30, fontSize: 12),
            isDense: true,
          ),
          onSubmitted: (_) => _sendInput(),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.send, size: 18, color: Colors.greenAccent),
        onPressed: _isRunning ? _sendInput : null,
      ),
    ]),
  );
}

class _TerminalLine {
  final String text;
  final bool isError;
  const _TerminalLine({required this.text, required this.isError});
}
