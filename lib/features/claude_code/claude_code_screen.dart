// lib/features/claude_code/claude_code_screen.dart
// PocketHarness — Claude Code Terminal Screen (Functional, Native)
//
// Architecture:
//   • Cek ToolsService.isReady → jika tidak ada bundle → tampilkan info
//   • Cek ClaudeCodeInstaller status → jika belum install → setup pipeline
//   • Jika siap → terminal UI: input bar + streaming output dari ClaudeCodeService
//   • Output di-render per tipe: text, toolUse, fileEdit, userPrompt, systemMessage
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pocketharness/core/theme/km_colors.dart';
import 'package:pocketharness/core/tools/tools_service.dart';
import 'package:pocketharness/data/services/claude_code_installer.dart';
import 'package:pocketharness/data/services/claude_code_service.dart';

enum _Phase { checking, noBundle, setupNeeded, installing, ready, running, error }

// ── Public entry point ────────────────────────────────────────────────────────
class ClaudeCodeTerminalScreen extends ConsumerStatefulWidget {
  final String? workingDirectory;
  const ClaudeCodeTerminalScreen({super.key, this.workingDirectory});
  @override
  ConsumerState<ClaudeCodeTerminalScreen> createState() => _ClaudeCodeTerminalScreenState();
}

class _ClaudeCodeTerminalScreenState extends ConsumerState<ClaudeCodeTerminalScreen> {
  _Phase _phase = _Phase.checking;
  String _statusMsg = 'Memeriksa...';
  double _progress = 0;
  String? _errMsg;

  final _ccSvc = ClaudeCodeService.instance;
  final _installer = ClaudeCodeInstaller.instance;

  final List<ClaudeOutputEvent> _events = [];
  StreamSubscription<ClaudeOutputEvent>? _outputSub;
  StreamSubscription<ClaudeCodeSessionState>? _stateSub;

  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  bool _awaitingInput = false;
  String _workDir = '';
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initWorkDir();
    _checkStatus();
  }

  @override
  void dispose() {
    _outputSub?.cancel();
    _stateSub?.cancel();
    _ccSvc.stop();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _initWorkDir() async {
    if (widget.workingDirectory != null) {
      _workDir = widget.workingDirectory!;
    } else {
      final dir = await getApplicationDocumentsDirectory();
      _workDir = '${dir.path}/claude_projects';
      await Directory(_workDir).create(recursive: true);
    }
  }

  Future<void> _checkStatus() async {
    setState(() { _phase = _Phase.checking; _statusMsg = 'Memeriksa bundle tools...'; _progress = 0; });

    // Always try to init — idempotent & fast if already extracted
    if (!ToolsService.instance.isReady) {
      try { await ToolsService.instance.initialize(); } catch (_) {}
    }

    if (!mounted) return;
    if (!ToolsService.instance.isReady) {
      setState(() { _phase = _Phase.noBundle; });
      return;
    }
    final installed = await _installer.checkInstalled();
    if (!mounted) return;
    if (!installed) {
      setState(() { _phase = _Phase.setupNeeded; _statusMsg = 'Bundle ditemukan. Siap setup.'; });
    } else {
      setState(() { _phase = _Phase.ready; _statusMsg = 'Claude Code siap.'; });
    }
  }

  Future<void> _runInstall() async {
    setState(() { _phase = _Phase.installing; _statusMsg = 'Memulai setup...'; _progress = 0.05; _errMsg = null; });
    await for (final e in _installer.install()) {
      if (!mounted) return;
      setState(() {
        _statusMsg = e.message; _progress = e.progress;
        if (e.isError) { _phase = _Phase.error; _errMsg = e.message; }
        else if (e.step == ClaudeInstallStep.done) { _phase = _Phase.ready; }
      });
    }
  }

  Future<void> _startSession([String? initialPrompt]) async {
    if (_workDir.isEmpty) await _initWorkDir();
    setState(() { _events.clear(); _phase = _Phase.running; _awaitingInput = false; _isProcessing = true; });
    _outputSub = _ccSvc.outputStream.listen(_onOutput);
    _stateSub = _ccSvc.stateStream.listen(_onStateChange);
    try {
      await _ccSvc.start(workDir: _workDir, initialPrompt: initialPrompt);
    } catch (e) {
      if (!mounted) return;
      setState(() { _phase = _Phase.error; _errMsg = 'Gagal memulai Claude Code:\n$e'; });
    }
  }

  void _onOutput(ClaudeOutputEvent e) {
    if (!mounted) return;
    setState(() { _events.add(e); });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _onStateChange(ClaudeCodeSessionState s) {
    if (!mounted) return;
    setState(() {
      _awaitingInput = s == ClaudeCodeSessionState.awaitingInput;
      _isProcessing = s == ClaudeCodeSessionState.running || s == ClaudeCodeSessionState.starting;
      if (s == ClaudeCodeSessionState.stopped || s == ClaudeCodeSessionState.error) {
        _isProcessing = false; _awaitingInput = false;
      }
    });
    if (s == ClaudeCodeSessionState.awaitingInput) _inputFocus.requestFocus();
  }

  void _sendInput() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    _ccSvc.sendInput(text);
    setState(() {
      _events.add(ClaudeOutputEvent(type: ClaudeOutputType.rawOutput, text: '> $text', timestamp: DateTime.now()));
      _awaitingInput = false; _isProcessing = true;
    });
  }

  Future<void> _stopSession() async {
    await _ccSvc.stop();
    _outputSub?.cancel(); _outputSub = null;
    _stateSub?.cancel(); _stateSub = null;
    if (!mounted) return;
    setState(() { _phase = _Phase.ready; _awaitingInput = false; _isProcessing = false; });
  }

  @override
  Widget build(BuildContext context) {
    final kmc = KmColors.of(context);
    final isTerminal = _phase == _Phase.running;
    return Scaffold(
      backgroundColor: isTerminal ? const Color(0xFF0D1117) : kmc.bg,
      appBar: AppBar(
        backgroundColor: isTerminal ? const Color(0xFF161B22) : kmc.bg,
        foregroundColor: isTerminal ? const Color(0xFF10B981) : kmc.text,
        elevation: 0, surfaceTintColor: Colors.transparent,
        title: Row(children: [
          Icon(Icons.smart_toy_outlined, size: 18, color: isTerminal ? const Color(0xFF10B981) : kmc.text),
          const SizedBox(width: 8),
          Text('Claude Code', style: TextStyle(color: isTerminal ? const Color(0xFF10B981) : kmc.text, fontSize: 17, fontWeight: FontWeight.w600)),
          if (isTerminal && _isProcessing) ...[
            const SizedBox(width: 10),
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: const Color(0xFF10B981))),
          ],
        ]),
        actions: [
          if (isTerminal) ...[
            IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 20), color: const Color(0xFF8B949E),
              onPressed: () => setState(() => _events.clear()), tooltip: 'Bersihkan'),
            IconButton(icon: const Icon(Icons.stop_circle_outlined, size: 20, color: Color(0xFFEF4444)),
              onPressed: _stopSession, tooltip: 'Stop'),
          ],
        ],
      ),
      body: _buildBody(kmc),
    );
  }

  Widget _buildBody(KmColors kmc) {
    const green = Color(0xFF10B981);
    switch (_phase) {
      case _Phase.checking:
        return _Loading(kmc: kmc, msg: _statusMsg, color: green);
      case _Phase.noBundle:
        return _NoBundle(kmc: kmc);
      case _Phase.setupNeeded:
        return _Action(kmc: kmc, color: green,
          title: 'Claude Code', subtitle: 'AI Coding Assistant · Terminal',
          msg: 'Bundle tools ditemukan.\nSetup sekali untuk mengaktifkan Claude Code CLI.',
          btnLabel: 'Setup Claude Code', onTap: _runInstall);
      case _Phase.installing:
        return _Progress(kmc: kmc, color: green, title: 'Menyiapkan Claude Code...', msg: _statusMsg, progress: _progress);
      case _Phase.ready:
        return _ReadyTerminal(kmc: kmc, color: green, onStart: _startSession);
      case _Phase.running:
        return _TerminalView(
          kmc: kmc, events: _events, scrollCtrl: _scrollCtrl,
          inputCtrl: _inputCtrl, inputFocus: _inputFocus,
          awaitingInput: _awaitingInput, isProcessing: _isProcessing,
          onSend: _sendInput,
          onYes: () => _ccSvc.confirmYes(),
          onNo: () => _ccSvc.confirmNo(),
        );
      case _Phase.error:
        return _Error(kmc: kmc, color: green, errMsg: _errMsg ?? 'Kesalahan.', onRetry: _checkStatus);
    }
  }
}

// ── Terminal View ─────────────────────────────────────────────────────────────
class _TerminalView extends StatelessWidget {
  final KmColors kmc;
  final List<ClaudeOutputEvent> events;
  final ScrollController scrollCtrl;
  final TextEditingController inputCtrl;
  final FocusNode inputFocus;
  final bool awaitingInput, isProcessing;
  final VoidCallback onSend, onYes, onNo;
  const _TerminalView({required this.kmc, required this.events, required this.scrollCtrl,
    required this.inputCtrl, required this.inputFocus, required this.awaitingInput,
    required this.isProcessing, required this.onSend, required this.onYes, required this.onNo});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: ListView.builder(
          controller: scrollCtrl,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: events.length,
          itemBuilder: (_, i) => _EventTile(event: events[i]),
        ),
      ),
      if (awaitingInput)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF161B22),
          child: Row(children: [
            const Text('Claude menunggu:', style: TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
            const Spacer(),
            _QuickBtn(label: 'y (Ya)', color: const Color(0xFF10B981), onTap: onYes),
            const SizedBox(width: 8),
            _QuickBtn(label: 'n (Tidak)', color: const Color(0xFFEF4444), onTap: onNo),
          ]),
        ),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: const BoxDecoration(
          color: Color(0xFF161B22),
          border: Border(top: BorderSide(color: Color(0xFF30363D))),
        ),
        child: Row(children: [
          const Text('\$', style: TextStyle(color: Color(0xFF10B981), fontSize: 14, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: inputCtrl, focusNode: inputFocus,
              style: const TextStyle(color: Color(0xFFE6EDF3), fontSize: 13, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                border: InputBorder.none, isDense: true,
                hintText: 'Ketik prompt atau perintah...',
                hintStyle: TextStyle(color: Color(0xFF484F58), fontSize: 13),
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => onSend(),
              textInputAction: TextInputAction.send,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSend,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isProcessing ? const Color(0xFF30363D) : const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(isProcessing ? Icons.hourglass_empty_rounded : Icons.send_rounded, color: Colors.white, size: 16),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _EventTile extends StatelessWidget {
  final ClaudeOutputEvent event;
  const _EventTile({required this.event});
  @override
  Widget build(BuildContext context) {
    switch (event.type) {
      case ClaudeOutputType.toolUse:
        return _ToolTile(event: event);
      case ClaudeOutputType.fileEdit:
        return _FileTile(event: event);
      case ClaudeOutputType.userPrompt:
        return _PromptTile(event: event);
      case ClaudeOutputType.systemMessage:
        return Padding(padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(event.text, style: const TextStyle(color: Color(0xFF484F58), fontSize: 11, fontFamily: 'monospace')));
      case ClaudeOutputType.stderrOutput:
        return Padding(padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(event.text, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontFamily: 'monospace')));
      case ClaudeOutputType.rawOutput:
        if (event.text.startsWith('> ')) {
          return Padding(padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(event.text, style: const TextStyle(color: Color(0xFF10B981), fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.bold)));
        }
        return Padding(padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(event.text, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12, fontFamily: 'monospace')));
      default:
        return Padding(padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(event.text, style: const TextStyle(color: Color(0xFFE6EDF3), fontSize: 13, fontFamily: 'monospace', height: 1.5)));
    }
  }
}

class _ToolTile extends StatelessWidget {
  final ClaudeOutputEvent event;
  const _ToolTile({required this.event});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 4),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: const Color(0xFF1C2128), borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFF388BFD).withValues(alpha: 0.4))),
    child: Row(children: [
      const Icon(Icons.build_outlined, size: 14, color: Color(0xFF388BFD)),
      const SizedBox(width: 6),
      Text(event.toolName ?? 'Tool', style: const TextStyle(color: Color(0xFF388BFD), fontSize: 12, fontWeight: FontWeight.w600)),
      if (event.toolInput != null) ...[
        const SizedBox(width: 8),
        Expanded(child: Text(event.toolInput!, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11, fontFamily: 'monospace'), maxLines: 2, overflow: TextOverflow.ellipsis)),
      ],
    ]),
  );
}

class _FileTile extends StatelessWidget {
  final ClaudeOutputEvent event;
  const _FileTile({required this.event});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 4),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: const Color(0xFF1C2128), borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFD29922).withValues(alpha: 0.4))),
    child: Row(children: [
      const Icon(Icons.insert_drive_file_outlined, size: 14, color: Color(0xFFD29922)),
      const SizedBox(width: 6),
      Expanded(child: Text(event.filePath ?? event.text, style: const TextStyle(color: Color(0xFFD29922), fontSize: 12, fontFamily: 'monospace'), maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]),
  );
}

class _PromptTile extends StatelessWidget {
  final ClaudeOutputEvent event;
  const _PromptTile({required this.event});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 4),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: const Color(0xFF161B22), borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5))),
    child: Text(event.text, style: const TextStyle(color: Color(0xFF10B981), fontSize: 13, fontFamily: 'monospace')),
  );
}

class _QuickBtn extends StatelessWidget {
  final String label; final Color color; final VoidCallback onTap;
  const _QuickBtn({required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.5))),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    ),
  );
}

class _ReadyTerminal extends StatefulWidget {
  final KmColors kmc; final Color color; final void Function([String?]) onStart;
  const _ReadyTerminal({required this.kmc, required this.color, required this.onStart});
  @override
  State<_ReadyTerminal> createState() => _ReadyTerminalState();
}

class _ReadyTerminalState extends State<_ReadyTerminal> {
  final _ctrl = TextEditingController();
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _IconBox(icon: Icons.smart_toy_outlined, color: widget.color),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Claude Code', style: TextStyle(color: widget.kmc.text, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('AI Coding Assistant · Terminal', style: TextStyle(color: widget.kmc.textSub, fontSize: 13)),
          ])),
        ]),
        const SizedBox(height: 24),
        Text('Mulai dengan template:', style: TextStyle(color: widget.kmc.textSub, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _TemplateChip(label: 'Review kode', icon: Icons.search_rounded, color: widget.color, onTap: () => widget.onStart('Review kode di direktori ini dan berikan saran perbaikan.')),
          _TemplateChip(label: 'Buat file baru', icon: Icons.add_circle_outline, color: widget.color, onTap: () => widget.onStart('Buat file baru sesuai kebutuhan saya.')),
          _TemplateChip(label: 'Perbaiki bug', icon: Icons.bug_report_outlined, color: widget.color, onTap: () => widget.onStart('Temukan dan perbaiki bug yang ada.')),
          _TemplateChip(label: 'Jelaskan kode', icon: Icons.help_outline_rounded, color: widget.color, onTap: () => widget.onStart('Jelaskan kode di direktori ini.')),
        ]),
        const SizedBox(height: 24),
        Text('Atau ketik prompt kustom:', style: TextStyle(color: widget.kmc.textSub, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: widget.kmc.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: widget.kmc.border)),
          child: TextField(
            controller: _ctrl, maxLines: 3,
            style: TextStyle(color: widget.kmc.text, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Ketik instruksi untuk Claude Code...',
              hintStyle: TextStyle(color: widget.kmc.textSub),
              contentPadding: const EdgeInsets.all(14), border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, height: 48,
          child: ElevatedButton.icon(
            onPressed: () => widget.onStart(_ctrl.text.trim().isNotEmpty ? _ctrl.text.trim() : null),
            icon: const Icon(Icons.play_arrow_rounded, size: 20, color: Colors.white),
            label: const Text('Mulai Sesi', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
            style: ElevatedButton.styleFrom(backgroundColor: widget.color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
          ),
        ),
      ]),
    );
  }
}

class _TemplateChip extends StatelessWidget {
  final String label; final IconData icon; final Color color; final VoidCallback onTap;
  const _TemplateChip({required this.label, required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.30))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

class _Loading extends StatelessWidget {
  final KmColors kmc; final String msg; final Color color;
  const _Loading({required this.kmc, required this.msg, required this.color});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    CircularProgressIndicator(color: color, strokeWidth: 2.5),
    const SizedBox(height: 16),
    Text(msg, style: TextStyle(color: kmc.textSub, fontSize: 13)),
  ]));
}

class _NoBundle extends StatelessWidget {
  final KmColors kmc;
  const _NoBundle({required this.kmc});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
    _IconBox(icon: Icons.smart_toy_outlined, color: const Color(0xFF10B981)),
    const SizedBox(height: 20),
    Text('Claude Code', style: TextStyle(color: kmc.text, fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 6),
    Text('AI Coding Assistant · Terminal', style: TextStyle(color: kmc.textSub, fontSize: 13)),
    const SizedBox(height: 28),
    Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: kmc.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: kmc.border)),
      child: Text(
        'APK ini tidak menyertakan bundle tools.\n\nBuild APK melalui GitHub Actions dengan workflow build.yml agar Claude Code CLI ter-bundle.',
        style: TextStyle(color: kmc.textSub, fontSize: 13.5, height: 1.65), textAlign: TextAlign.center,
      ),
    ),
  ])));
}

class _Action extends StatelessWidget {
  final KmColors kmc; final Color color;
  final String title, subtitle, msg, btnLabel; final VoidCallback onTap;
  const _Action({required this.kmc, required this.color, required this.title, required this.subtitle, required this.msg, required this.btnLabel, required this.onTap});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
    _IconBox(icon: Icons.smart_toy_outlined, color: color),
    const SizedBox(height: 20),
    Text(title, style: TextStyle(color: kmc.text, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.3)),
    const SizedBox(height: 6),
    Text(subtitle, style: TextStyle(color: kmc.textSub, fontSize: 13)),
    const SizedBox(height: 28),
    Container(padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: kmc.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: kmc.border)),
      child: Text(msg, style: TextStyle(color: kmc.textSub, fontSize: 13.5, height: 1.65), textAlign: TextAlign.center)),
    const SizedBox(height: 28),
    SizedBox(width: double.infinity, height: 50,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.play_arrow_rounded, size: 20, color: Colors.white),
        label: Text(btnLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
        style: ElevatedButton.styleFrom(backgroundColor: color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
      )),
  ])));
}

class _Progress extends StatelessWidget {
  final KmColors kmc; final Color color; final String title, msg; final double progress;
  const _Progress({required this.kmc, required this.color, required this.title, required this.msg, required this.progress});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
    _IconBox(icon: Icons.smart_toy_outlined, color: color),
    const SizedBox(height: 24),
    Text(title, style: TextStyle(color: kmc.text, fontSize: 18, fontWeight: FontWeight.bold)),
    const SizedBox(height: 20),
    ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: progress > 0 ? progress : null, minHeight: 6, backgroundColor: kmc.border, color: color)),
    const SizedBox(height: 14),
    Text(msg, style: TextStyle(color: kmc.textSub, fontSize: 13, height: 1.5), textAlign: TextAlign.center),
  ])));
}

class _Error extends StatelessWidget {
  final KmColors kmc; final Color color; final String errMsg; final VoidCallback onRetry;
  const _Error({required this.kmc, required this.color, required this.errMsg, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
    _IconBox(icon: Icons.error_outline_rounded, color: const Color(0xFFEF4444)),
    const SizedBox(height: 20),
    Text('Terjadi Kesalahan', style: TextStyle(color: kmc.text, fontSize: 18, fontWeight: FontWeight.bold)),
    const SizedBox(height: 16),
    Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFEF4444).withValues(alpha: 0.07), borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25))),
      child: Text(errMsg, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13, height: 1.6), textAlign: TextAlign.center)),
    const SizedBox(height: 24),
    SizedBox(width: double.infinity, height: 48,
      child: OutlinedButton.icon(
        onPressed: onRetry,
        icon: Icon(Icons.refresh_rounded, size: 18, color: color),
        label: Text('Coba Lagi', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(side: BorderSide(color: color), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      )),
  ])));
}

class _IconBox extends StatelessWidget {
  final IconData icon; final Color color;
  const _IconBox({required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: 88, height: 88,
    decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(24),
      border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5)),
    child: Icon(icon, color: color, size: 44),
  );
}
