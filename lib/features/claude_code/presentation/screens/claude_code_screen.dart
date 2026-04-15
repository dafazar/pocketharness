// lib/features/claude_code/presentation/screens/claude_code_screen.dart
// KanMonAI — Claude Code Screen
//
// UI for running Claude Code CLI with KanMonAI's local llama.cpp backend.
// Three states:
//   1. SETUP: Claude Code not installed → show install wizard
//   2. PREREQ: Model not loaded or server not running → show fix panel
//   3. MAIN: Running interface with output + input
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:kanmongo/data/services/claude_code_service.dart';
import 'package:kanmongo/data/services/claude_code_installer.dart';
import 'package:kanmongo/data/services/claude_code_file_context.dart';
import 'package:kanmongo/data/services/llama_service.dart';
import 'package:kanmongo/data/services/llama_http_server.dart';
import 'package:kanmongo/data/services/terminal_service.dart';

// ── Screen mode ───────────────────────────────────────────────────────────────

enum _ScreenMode { checking, needsInstall, installing, needsPrereqs, ready }

// ── Providers ─────────────────────────────────────────────────────────────────

final _sessionStateProvider = StateProvider<ClaudeCodeSessionState>(
  (ref) => ClaudeCodeSessionState.idle,
);

final _outputProvider =
    StateProvider<List<ClaudeOutputEvent>>((ref) => const []);

final _installModeProvider =
    StateProvider<_ScreenMode>((ref) => _ScreenMode.checking);

// ── Screen widget ─────────────────────────────────────────────────────────────

class ClaudeCodeScreen extends ConsumerStatefulWidget {
  /// Optional list of file paths to pre-attach as context
  final List<String> attachedFiles;

  /// Optional initial prompt to send once started
  final String? initialPrompt;

  const ClaudeCodeScreen({
    super.key,
    this.attachedFiles = const [],
    this.initialPrompt,
  });

  @override
  ConsumerState<ClaudeCodeScreen> createState() => _ClaudeCodeScreenState();
}

class _ClaudeCodeScreenState extends ConsumerState<ClaudeCodeScreen> {
  final _inputCtrl   = TextEditingController();
  final _workDirCtrl = TextEditingController();
  final _scroll      = ScrollController();
  final _inputFocus  = FocusNode();

  final _svc       = ClaudeCodeService.instance;
  final _installer = ClaudeCodeInstaller.instance;

  StreamSubscription<ClaudeOutputEvent>?      _outputSub;
  StreamSubscription<ClaudeCodeSessionState>? _stateSub;
  StreamSubscription<ClaudeInstallEvent>?     _installSub;
  StreamSubscription<FileWatchEvent>?         _fileWatchSub;

  bool _busy = false;
  String _workDir = '';
  List<String> _attachedFiles = [];
  final List<ClaudeInstallEvent> _installLog = [];
  double _installProgress = 0.0;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _attachedFiles = List<String>.from(widget.attachedFiles);
    _workDir = TerminalService.instance.cwdPath;
    _workDirCtrl.text = _workDir;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSetup());
  }

  @override
  void dispose() {
    _outputSub?.cancel();
    _stateSub?.cancel();
    _installSub?.cancel();
    _fileWatchSub?.cancel();
    ClaudeCodeFileContext.instance.stopWatching();
    _inputCtrl.dispose();
    _workDirCtrl.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    if (_svc.isRunning) _svc.stop();
    super.dispose();
  }

  // ── Setup check ──────────────────────────────────────────────────────────────

  Future<void> _checkSetup() async {
    ref.read(_installModeProvider.notifier).state = _ScreenMode.checking;

    final installed = await _installer.checkInstalled();

    if (!mounted) return;

    if (!installed) {
      ref.read(_installModeProvider.notifier).state = _ScreenMode.needsInstall;
      return;
    }

    final modelLoaded = LlamaService.instance.isModelLoaded;
    if (!modelLoaded) {
      ref.read(_installModeProvider.notifier).state = _ScreenMode.needsPrereqs;
      return;
    }

    ref.read(_installModeProvider.notifier).state = _ScreenMode.ready;
    _subscribeToService();
  }

  void _subscribeToService() {
    _outputSub?.cancel();
    _stateSub?.cancel();

    _outputSub = _svc.outputStream.listen((event) {
      if (!mounted) return;
      final current = ref.read(_outputProvider);
      ref.read(_outputProvider.notifier).state = [...current, event];
      _scrollToBottom();
    });

    _stateSub = _svc.stateStream.listen((state) {
      if (!mounted) return;
      ref.read(_sessionStateProvider.notifier).state = state;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Install ──────────────────────────────────────────────────────────────────

  Future<void> _startInstall() async {
    ref.read(_installModeProvider.notifier).state = _ScreenMode.installing;
    setState(() {
      _installLog.clear();
      _installProgress = 0.0;
    });

    _installSub?.cancel();
    _installSub = _installer.install().listen(
      (event) {
        if (!mounted) return;
        setState(() {
          _installLog.add(event);
          _installProgress = event.progress;
        });
        _scrollToBottom();
        if (event.isError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Install error: ${event.message}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      onDone: () {
        if (mounted) _checkSetup();
      },
      onError: (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Installation failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
        ref.read(_installModeProvider.notifier).state =
            _ScreenMode.needsInstall;
      },
    );
  }

  // ── Session ──────────────────────────────────────────────────────────────────

  Future<void> _startSession({String? userPrompt}) async {
    if (_busy) return;
    if (mounted) setState(() => _busy = true);
    try {
      String? prompt = widget.initialPrompt;

      // Process attached files if any
      if (_attachedFiles.isNotEmpty) {
        final contextFiles = await ClaudeCodeFileContext.instance.processFiles(
          _attachedFiles,
          workDir: _workDir,
        );
        final preamble = ClaudeCodeFileContext.instance.buildPreamble(contextFiles);
        prompt = prompt != null ? '$preamble\n\n$prompt' : preamble;
      }

      // Append userPrompt from _send() if provided
      if (userPrompt != null && userPrompt.isNotEmpty) {
        prompt = prompt != null ? '$prompt\n\n$userPrompt' : userPrompt;
      }

      await _svc.start(workDir: _workDir, initialPrompt: prompt);

      // Start watching for file changes
      if (_fileWatchSub == null) {
        _fileWatchSub = ClaudeCodeFileContext.instance
            .watchDirectory(_workDir)
            .listen(_onFileChanged);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onFileChanged(FileWatchEvent e) {
    final filename = e.path.split('/').last;
    final event = e.event;
    String msg;
    if (event is FileSystemModifyEvent) {
      msg = '📝 Modified: $filename';
    } else if (event is FileSystemCreateEvent) {
      msg = '✨ Created: $filename';
    } else if (event is FileSystemDeleteEvent) {
      msg = '🗑️ Deleted: $filename';
    } else {
      msg = '📁 Changed: $filename';
    }
    ref.read(_outputProvider.notifier).update((s) => [
      ...s,
      ClaudeOutputEvent(
        type: ClaudeOutputType.systemMessage,
        text: msg,
        timestamp: DateTime.now(),
      ),
    ]);
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();

    if (!_svc.isRunning) {
      await _startSession(userPrompt: text);
      return;
    }
    await _svc.sendInput(text);
  }

  // ── Working directory ────────────────────────────────────────────────────────

  Future<void> _browseWorkDir() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select working directory',
    );
    if (dir != null && mounted) {
      setState(() {
        _workDir = dir;
        _workDirCtrl.text = dir;
      });
    }
  }

  // ── Attach files ─────────────────────────────────────────────────────────────

  Future<void> _attachFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null && mounted) {
      setState(() {
        for (final f in result.files) {
          if (f.path != null && !_attachedFiles.contains(f.path)) {
            _attachedFiles.add(f.path!);
          }
        }
      });
    }
  }

  // ── File emoji ────────────────────────────────────────────────────────────────

  String _fileEmoji(String filename) {
    final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'dart'                                       => '🎯',
      'kt' || 'kts'                                => '☕',
      'java'                                       => '☕',
      'py'                                         => '🐍',
      'js' || 'mjs' || 'ts' || 'tsx'              => '📜',
      'json'                                       => '📋',
      'yaml' || 'yml'                              => '📋',
      'xml'                                        => '📋',
      'md' || 'markdown'                           => '📝',
      'sh' || 'bash'                               => '🖥️',
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' => '🖼️',
      'mp4' || 'mov' || 'avi' || 'mkv'            => '🎬',
      'mp3' || 'wav' || 'aac' || 'flac' || 'ogg'  => '🎵',
      'pdf'                                        => '📕',
      'zip' || 'tar' || 'gz' || 'rar'             => '📦',
      'gguf' || 'ggml'                             => '🤖',
      _                                            => '📄',
    };
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(_installModeProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: _buildAppBar(mode),
      body: switch (mode) {
        _ScreenMode.checking     => _buildChecking(),
        _ScreenMode.needsInstall => _buildNeedsInstall(),
        _ScreenMode.installing   => _buildInstalling(),
        _ScreenMode.needsPrereqs => _buildNeedsPrereqs(),
        _ScreenMode.ready        => _buildMain(),
      },
    );
  }

  // ── AppBar ───────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(_ScreenMode mode) {
    final sessionState = ref.watch(_sessionStateProvider);
    final modelName =
        LlamaService.instance.currentModel?.name ?? 'No model';
    final dot = _stateDotColor(sessionState);

    return AppBar(
      backgroundColor: const Color(0xFF1A1A1A),
      foregroundColor: Colors.white,
      titleSpacing: 0,
      title: Row(
        children: [
          const SizedBox(width: 4),
          const Text('🤖', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Claude Code',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                modelName,
                style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
        ],
      ),
      actions: [
        if (_svc.isRunning)
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
            tooltip: 'Stop session',
            onPressed: () => _svc.stop(),
          ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: Color(0xFF999999)),
          tooltip: 'Model settings',
          onPressed: () => context.go('/settings/offline-ai'),
        ),
      ],
    );
  }

  Color _stateDotColor(ClaudeCodeSessionState s) {
    return switch (s) {
      ClaudeCodeSessionState.running        => Colors.green,
      ClaudeCodeSessionState.awaitingInput  => const Color(0xFFFFA500),
      ClaudeCodeSessionState.starting       => const Color(0xFF4FC3F7),
      ClaudeCodeSessionState.error          => Colors.red,
      _                                     => const Color(0xFF555555),
    };
  }

  // ── Checking ─────────────────────────────────────────────────────────────────

  Widget _buildChecking() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Color(0xFFE53935)),
          SizedBox(height: 16),
          Text(
            'Checking setup...',
            style: TextStyle(color: Color(0xFF999999), fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Needs Install ─────────────────────────────────────────────────────────────

  Widget _buildNeedsInstall() {
    final hasTermux = TerminalService.instance.hasTermux;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text('📦', style: TextStyle(fontSize: 64)),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Claude Code not installed',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'Install Claude Code CLI to use AI coding agent natively on your phone.',
              style: TextStyle(color: Color(0xFF999999), fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          _SectionCard(
            title: 'Requirements',
            child: Column(
              children: [
                _ReqRow(
                  label: 'Termux',
                  ok: hasTermux,
                  okLabel: 'installed',
                  failLabel: 'needed',
                ),
                const SizedBox(height: 8),
                _ReqRow(
                  label: 'Node.js (auto-installed)',
                  ok: true,
                  okLabel: 'will be installed',
                  failLabel: '',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: hasTermux ? _startInstall : null,
              child: const Text(
                'Install Claude Code',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          if (!hasTermux) ...[
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'Install Termux from F-Droid first.',
                style: TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Center(
            child: Text(
              '~5–10 minutes on first install',
              style: TextStyle(color: Color(0xFF666666), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ── Installing ────────────────────────────────────────────────────────────────

  Widget _buildInstalling() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Installing Claude Code...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _installProgress,
                backgroundColor: const Color(0xFF2A2A2A),
                color: const Color(0xFFE53935),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 6),
              Text(
                '${(_installProgress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Color(0xFF999999), fontSize: 12),
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF2A2A2A), height: 1),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            itemCount: _installLog.length,
            itemBuilder: (_, i) {
              final e = _installLog[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _stepEmoji(e.step),
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.message,
                        style: TextStyle(
                          color: e.isError
                              ? Colors.red
                              : const Color(0xFFCCCCCC),
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _stepEmoji(ClaudeInstallStep step) => switch (step) {
        ClaudeInstallStep.checkingTermux       => '🔍',
        ClaudeInstallStep.checkingNode         => '🔍',
        ClaudeInstallStep.installingNode       => '📦',
        ClaudeInstallStep.checkingNpm          => '🔍',
        ClaudeInstallStep.installingClaudeCode => '🤖',
        ClaudeInstallStep.writingWrapperScript  => '📝',
        ClaudeInstallStep.writingSettings       => '⚙️',
        ClaudeInstallStep.verifying             => '✔️',
        ClaudeInstallStep.done                  => '✅',
        ClaudeInstallStep.error                 => '❌',
      };

  // ── Needs Prereqs ─────────────────────────────────────────────────────────────

  Widget _buildNeedsPrereqs() {
    final modelLoaded   = LlamaService.instance.isModelLoaded;
    final modelName     = LlamaService.instance.currentModel?.name ?? '';
    final serverRunning = LlamaHttpServer.instance.isRunning;
    final serverPort    = LlamaHttpServer.instance.port;
    final bothMet       = modelLoaded && serverRunning;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Prerequisites',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Claude Code needs the following to start.',
            style: TextStyle(color: Color(0xFF888888), fontSize: 13),
          ),
          const SizedBox(height: 16),

          // Card 1: AI Model
          _SectionCard(
            title: 'AI Model Required',
            child: modelLoaded
                ? _StatusRow(ok: true, text: modelName)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _StatusRow(
                        ok: false,
                        text: 'No model loaded. Load a GGUF model in Settings.',
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE53935),
                          side: const BorderSide(color: Color(0xFFE53935)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => context.go('/settings/offline-ai'),
                        child: const Text('Open Model Settings'),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),

          // Card 2: AI Server
          _SectionCard(
            title: 'Local AI Server',
            child: serverRunning
                ? _StatusRow(ok: true, text: 'Running on port $serverPort')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _StatusRow(
                        ok: false,
                        text: 'Server not started.',
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF4FC3F7),
                          side: const BorderSide(color: Color(0xFF4FC3F7)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: modelLoaded
                            ? () async {
                                await LlamaHttpServer.instance.start();
                                await _checkSetup();
                              }
                            : null,
                        child: const Text('Start Server'),
                      ),
                    ],
                  ),
          ),

          const SizedBox(height: 24),
          if (bothMet)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  ref.read(_installModeProvider.notifier).state =
                      _ScreenMode.ready;
                  _subscribeToService();
                },
                child: const Text(
                  'Continue',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _checkSetup,
              child: const Text(
                'Re-check',
                style: TextStyle(color: Color(0xFF888888)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Main chat ─────────────────────────────────────────────────────────────────

  Widget _buildMain() {
    final sessionState = ref.watch(_sessionStateProvider);
    final output       = ref.watch(_outputProvider);

    return Column(
      children: [
        // Working directory row
        _buildWorkDirRow(),

        // Attached file chips
        if (_attachedFiles.isNotEmpty) _buildAttachedChips(),

        // Output area
        Expanded(
          child: output.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: output.length,
                  itemBuilder: (_, i) => _buildOutputItem(output[i]),
                ),
        ),

        // Quick reply bar
        if (sessionState == ClaudeCodeSessionState.awaitingInput)
          _buildQuickReplyBar(),

        const Divider(color: Color(0xFF2A2A2A), height: 1),

        // Input row
        _buildInputRow(sessionState),
      ],
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🤖', style: TextStyle(fontSize: 48)),
          SizedBox(height: 12),
          Text(
            'Type a message to start a Claude Code session.',
            style: TextStyle(color: Color(0xFF666666), fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildWorkDirRow() {
    return Container(
      height: 44,
      color: const Color(0xFF161616),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined, color: Color(0xFF888888), size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _workDirCtrl,
              style: const TextStyle(
                color: Color(0xFFCCCCCC),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: '/path/to/project',
                hintStyle: TextStyle(color: Color(0xFF555555), fontSize: 12),
              ),
              onChanged: (v) => _workDir = v,
              onSubmitted: (v) => _workDir = v,
            ),
          ),
          GestureDetector(
            onTap: _browseWorkDir,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Browse',
                style: TextStyle(color: Color(0xFF888888), fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachedChips() {
    return Container(
      height: 36,
      color: const Color(0xFF121212),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: _attachedFiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final path  = _attachedFiles[i];
          final name  = path.split('/').last;
          final emoji = _fileEmoji(name);
          return GestureDetector(
            onTap: () => setState(() => _attachedFiles.removeAt(i)),
            onLongPress: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(path),
                  duration: const Duration(seconds: 3),
                  backgroundColor: const Color(0xFF1E2A1E),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2A1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2E4A2E)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 11)),
                  const SizedBox(width: 4),
                  Text(
                    name,
                    style: const TextStyle(
                      color: Color(0xFF88CC88),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.close, size: 12, color: Color(0xFF668866)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Output item ───────────────────────────────────────────────────────────────

  Widget _buildOutputItem(ClaudeOutputEvent e) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: switch (e.type) {
        ClaudeOutputType.toolUse       => _ToolUseCard(event: e),
        ClaudeOutputType.toolResult    => _ToolResultCard(event: e),
        ClaudeOutputType.fileEdit      => _FileEditCard(event: e),
        ClaudeOutputType.userPrompt    => _UserPromptLine(event: e),
        ClaudeOutputType.statusLine    => _buildStatusLine(e),
        ClaudeOutputType.systemMessage => _buildSystemLine(e),
        ClaudeOutputType.stderrOutput  => _buildStderrLine(e),
        ClaudeOutputType.rawOutput     => _buildRawLine(e),
        ClaudeOutputType.text          => _buildTextLine(e),
        _                              => _buildRawLine(e),
      },
    );
  }

  Widget _buildTextLine(ClaudeOutputEvent e) => SelectableText(
        e.text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontFamily: 'monospace',
        ),
      );

  Widget _buildStatusLine(ClaudeOutputEvent e) => Text(
        e.text,
        style: const TextStyle(
          color: Color(0xFF666666),
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      );

  Widget _buildSystemLine(ClaudeOutputEvent e) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ℹ️', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              e.text,
              style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
            ),
          ),
        ],
      );

  Widget _buildStderrLine(ClaudeOutputEvent e) => Text(
        e.text,
        style: const TextStyle(
          color: Color(0xFFFF6B6B),
          fontSize: 12,
          fontFamily: 'monospace',
        ),
      );

  Widget _buildRawLine(ClaudeOutputEvent e) => Text(
        e.text,
        style: const TextStyle(
          color: Color(0xFF777777),
          fontSize: 12,
          fontFamily: 'monospace',
        ),
      );

  // ── Quick reply ───────────────────────────────────────────────────────────────

  Widget _buildQuickReplyBar() {
    return Container(
      color: const Color(0xFF161616),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          _QuickReplyBtn(label: '✅ Yes', onTap: () => _svc.confirmYes()),
          const SizedBox(width: 8),
          _QuickReplyBtn(label: '❌ No', onTap: () => _svc.confirmNo()),
          const SizedBox(width: 8),
          _QuickReplyBtn(label: '⏭ Skip', onTap: () => _svc.sendInput('skip')),
          const SizedBox(width: 8),
          _QuickReplyBtn(label: '🛑 Stop', onTap: () => _svc.stop()),
        ],
      ),
    );
  }

  // ── Input row ─────────────────────────────────────────────────────────────────

  Widget _buildInputRow(ClaudeCodeSessionState sessionState) {
    final isWaiting = sessionState == ClaudeCodeSessionState.awaitingInput;
    return Container(
      color: const Color(0xFF0D0D0D),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Row(
        children: [
          const Text(
            '>',
            style: TextStyle(
              color: Color(0xFF44FF88),
              fontSize: 16,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isWaiting
                      ? const Color(0xFFFFD700)
                      : const Color(0xFF2A2A2A),
                  width: isWaiting ? 1.5 : 1,
                ),
              ),
              child: TextField(
                controller: _inputCtrl,
                focusNode: _inputFocus,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  hintText: 'Send message to Claude Code...',
                  hintStyle: TextStyle(
                    color: Color(0xFF444444),
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Attach button
          IconButton(
            icon: const Icon(Icons.attach_file, size: 20),
            color: const Color(0xFF888888),
            onPressed: _attachFiles,
            tooltip: 'Attach files',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          // Send button
          IconButton(
            icon: const Icon(Icons.send_rounded, size: 20),
            color: _busy
                ? const Color(0xFF444444)
                : const Color(0xFFE53935),
            onPressed: _busy ? null : _send,
            tooltip: 'Send',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}

// ── Private widgets ───────────────────────────────────────────────────────────

class _QuickReplyBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickReplyBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF3A3A3A)),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ReqRow extends StatelessWidget {
  final String label;
  final bool ok;
  final String okLabel;
  final String failLabel;

  const _ReqRow({
    required this.label,
    required this.ok,
    required this.okLabel,
    required this.failLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(ok ? '✅' : '❌', style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Text(
          '$label (${ok ? okLabel : failLabel})',
          style: TextStyle(
            color: ok ? const Color(0xFF88CC88) : Colors.red,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  final bool ok;
  final String text;

  const _StatusRow({required this.ok, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(ok ? '✅' : '⚠️', style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: ok ? const Color(0xFF88CC88) : const Color(0xFFCCCCCC),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _ToolUseCard extends StatelessWidget {
  final ClaudeOutputEvent event;

  const _ToolUseCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final name  = event.toolName  ?? '';
    final input = event.toolInput ?? '';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1A1F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00BCD4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🔧', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text(
                name,
                style: const TextStyle(
                  color: Color(0xFF00BCD4),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (input.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              input,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF999999),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ToolResultCard extends StatefulWidget {
  final ClaudeOutputEvent event;

  const _ToolResultCard({required this.event});

  @override
  State<_ToolResultCard> createState() => _ToolResultCardState();
}

class _ToolResultCardState extends State<_ToolResultCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('📋', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                const Text(
                  'Result',
                  style: TextStyle(color: Color(0xFF888888), fontSize: 13),
                ),
                const Spacer(),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: const Color(0xFF555555),
                  size: 16,
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 6),
              Text(
                widget.event.text,
                style: const TextStyle(
                  color: Color(0xFF777777),
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FileEditCard extends StatelessWidget {
  final ClaudeOutputEvent event;

  const _FileEditCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final path = event.filePath ?? event.toolInput ?? '';
    final name = path.split('/').last;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1400),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber, width: 1),
      ),
      child: Row(
        children: [
          const Text('✏️', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isNotEmpty ? name : 'File edit',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (path.isNotEmpty)
                  Text(
                    path,
                    style: const TextStyle(
                      color: Color(0xFF887744),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserPromptLine extends StatelessWidget {
  final ClaudeOutputEvent event;

  const _UserPromptLine({required this.event});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1800),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFFD700)),
      ),
      child: Text(
        event.text,
        style: const TextStyle(
          color: Color(0xFFFFD700),
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
