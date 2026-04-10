// lib/features/terminal/presentation/screens/terminal_screen.dart
// KanMon GO — Terminal Screen (Full Shell Emulator)
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/data/services/terminal_service.dart';
import 'package:kanmongo/data/services/ai_service.dart';
import 'package:kanmongo/data/services/file_processor_service.dart';

// ── Terminal entry ────────────────────────────────────────────────────────────
enum TermType { prompt, output, error, ai, download, system, info }

class TermEntry {
  final TermType type;
  final String text;
  final DlProgress? progress;
  const TermEntry(this.type, this.text, {this.progress});
}

final _entriesProvider = StateProvider<List<TermEntry>>((ref) => const []);

// ── Terminal Screen ───────────────────────────────────────────────────────────
class TerminalScreen extends ConsumerStatefulWidget {
  final String? initialCommand;
  final bool autoRun;
  const TerminalScreen({
    super.key,
    this.initialCommand,
    this.autoRun = false,
  });
  @override
  ConsumerState<TerminalScreen> createState() => _TerminalState();
}

class _TerminalState extends ConsumerState<TerminalScreen>
    with TickerProviderStateMixin {

  final _inputCtrl  = TextEditingController();
  final _scroll     = ScrollController();
  final _svc        = TerminalService.instance;
  final _ai         = AiService.instance;
  late  TabController _tabs;
  final _inputFocus = FocusNode();

  bool   _busy        = false;
  bool   _aiMode      = false;
  bool   _streaming   = false;
  String? _editTarget;
  String? _editOrig;
  String? _pendingSavePath;
  String? _pendingSaveContent;
  final _cmdHistory   = <String>[];
  int    _histIdx     = -1;
  bool   _initialized = false;

  static const _quickCmds = [
    ('ls -la',     '📂 ls'),
    ('pwd',        '📍 pwd'),
    ('env',        '🌍 env'),
    ('ps',         '⚙️ ps'),
    ('df -h',      '💾 df'),
    ('free',       '🧠 free'),
    ('uname -a',   '🖥️ uname'),
    ('id',         '👤 id'),
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _svc.init();
    if (!mounted) return;
    if (mounted) setState(() => _initialized = true);

    final hasTermux = _svc.hasTermux;
    _push(TermEntry(TermType.info,
      'KanMon Terminal\n'
      '${hasTermux ? "✅ Termux terdeteksi — semua tool tersedia!" : "ℹ️  Mode Android shell (/system/bin)"}\n'
      'Shell: ${_svc.shellInfo}\n'
      'Ketik help untuk daftar perintah | /ai untuk mode AI\n'));

    if (hasTermux) {
      // Tampilkan versi pkg manager
      final ver = await _svc.run('pkg --version');
      if (ver.stdout.isNotEmpty) {
        _push(TermEntry(TermType.system, 'pkg: ${ver.stdout.trim()}'));
      }
    }

    // Handle initialCommand dari route extra
    final initCmd = widget.initialCommand;
    if (initCmd != null && initCmd.isNotEmpty) {
      if (widget.autoRun) {
        await _handle(initCmd);
      } else {
        _inputCtrl.text = initCmd;
        _inputCtrl.selection = TextSelection.collapsed(offset: initCmd.length);
        _inputFocus.requestFocus();
      }
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scroll.dispose();
    _tabs.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _push(TermEntry e) {
    ref.read(_entriesProvider.notifier).update((s) => [...s, e]);
    _scrollToBottom();
  }

  void _updateLast(TermEntry e) {
    ref.read(_entriesProvider.notifier).update((s) {
      if (s.isEmpty) return [...s, e];
      return [...s.sublist(0, s.length - 1), e];
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
      }
    });
  }

  // ── Main input handler ────────────────────────────────────────────────────
  Future<void> _handle(String raw) async {
    final input = raw.trim();
    if (input.isEmpty) return;
    _inputCtrl.clear();
    _cmdHistory.insert(0, input);
    _histIdx = -1;
    if (mounted) setState(() => _busy = true);

    _push(TermEntry(TermType.prompt,
        '\x1b[32m${_svc.cwdRelative}\x1b[0m\$ $input'));

    // Pending save confirmation
    if (_pendingSavePath != null) {
      if (input.toLowerCase() == 'yes' || input.toLowerCase() == 'y') {
        await _svc.writeFile(_pendingSavePath!, _pendingSaveContent!);
        _push(TermEntry(TermType.output, '✅ Disimpan: $_pendingSavePath'));
      } else {
        _push(const TermEntry(TermType.info, 'Edit dibatalkan.'));
      }
      if (mounted) setState(() { _pendingSavePath = null; _pendingSaveContent = null; _busy = false; });
      return;
    }

    // Pending edit instruction
    if (_editTarget != null) {
      await _doEdit(input);
      if (mounted) setState(() => _busy = false);
      return;
    }

    // Special commands
    if (input == '/ai') {
      if (mounted) setState(() => _aiMode = !_aiMode);
      _push(TermEntry(TermType.info,
          _aiMode ? '🤖 Mode AI aktif. Ketik /ai untuk nonaktifkan.'
                  : '💻 Mode Shell aktif.'));
    } else if (input == 'clear' || input == '/clear') {
      ref.read(_entriesProvider.notifier).state = const [];
    } else if (input.startsWith('/ask ')) {
      await _doAsk(input.substring(5).trim());
    } else if (input.startsWith('/edit ')) {
      await _startEdit(input.substring(6).trim());
    } else if (input.startsWith('/script ')) {
      await _doScript(input.substring(8).trim());
    } else if (input.startsWith('/download ') ||
               input.startsWith('wget ') ||
               input.startsWith('curl -O ')) {
      String url = input;
      if (url.startsWith('/download '))   url = url.substring(10);
      else if (url.startsWith('wget '))   url = url.substring(5);
      else if (url.startsWith('curl -O ')) url = url.substring(8);
      await _doDownload(url.trim().split(' ').first);
    } else if (_aiMode) {
      await _doAsk(input);
    } else {
      await _doShell(input);
    }

    if (mounted) setState(() => _busy = false);
    _inputFocus.requestFocus();
  }

  // ── Shell execution — streaming output ────────────────────────────────────
  Future<void> _doShell(String cmd) async {
    // Perintah yang long-running: pakai streaming
    final longRunning = RegExp(
      r'^(apt|pkg|pip|pip3|npm|yarn|gem|cargo|go get|'
      r'git clone|git pull|git push|gradle|make|cmake|'
      r'wget|curl|adb|ssh|top|htop|ping)',
    ).hasMatch(cmd.trim());

    if (longRunning) {
      await _doShellStream(cmd);
      return;
    }

    final result = await _svc.run(cmd);

    // Update cwd setelah perintah
    if (mounted) setState(() {});

    final out = result.output.trim();
    if (out.isNotEmpty) {
      _push(TermEntry(
        result.isSuccess ? TermType.output : TermType.error,
        out,
      ));
    }

    if (!result.isSuccess && result.exitCode == 127) {
      // Command not found — tawarkan bantuan
      final cmd0 = cmd.split(' ').first;
      if (_svc.hasTermux) {
        _push(TermEntry(TermType.info,
            '💡 Coba: pkg install $cmd0'));
      } else {
        _push(TermEntry(TermType.info,
            '💡 Perintah tidak ditemukan. Install Termux untuk fitur lengkap.'));
      }
    }
  }

  // ── Streaming shell (untuk long-running commands) ─────────────────────────
  Future<void> _doShellStream(String cmd) async {
    if (mounted) setState(() => _streaming = true);
    _push(const TermEntry(TermType.output, ''));

    final sb = StringBuffer();
    await for (final chunk in _svc.runStream(cmd)) {
      sb.write(chunk);
      _updateLast(TermEntry(TermType.output, sb.toString().trim()));
    }

    if (mounted) setState(() { _streaming = false; });
  }

  // ── AI ask ────────────────────────────────────────────────────────────────
  Future<void> _doAsk(String question) async {
    final files = await _svc.listFiles();
    final fl = files.take(20).map((f) => p.basename(f.path)).join(', ');
    final hasTermux = _svc.hasTermux;

    final sp = 'Kamu adalah AI terminal assistant yang expert di Android shell'
        '${hasTermux ? " dan Termux" : ""}.\n'
        'CWD: ${_svc.cwdRelative}\nFiles: $fl\n'
        'Shell: ${_svc.shellInfo}\n'
        '${hasTermux ? "Termux tersedia — bisa gunakan apt/pkg, git, python, npm, dll.\n" : ""}'
        'Format perintah dalam ```sh code block```. Jawab Bahasa Indonesia.';

    _push(const TermEntry(TermType.ai, ''));
    final sb = StringBuffer();
    await for (final t in _ai.sendChatStream(
        systemPrompt: sp, history: [], userMessage: question)) {
      sb.write(t);
      _updateLast(TermEntry(TermType.ai, sb.toString()));
    }
  }

  // ── Edit file dengan AI ───────────────────────────────────────────────────
  Future<void> _startEdit(String filename) async {
    try {
      final content = await _svc.readFile(filename);
      if (mounted) setState(() { _editTarget = filename; _editOrig = content; });
      _push(TermEntry(TermType.info,
          '✏️ Edit "$filename" — Tulis instruksi edit kamu:'));
    } catch (e) {
      _push(TermEntry(TermType.error, 'File tidak ada: $filename'));
    }
  }

  Future<void> _doEdit(String instruction) async {
    final fn   = _editTarget!;
    final orig = _editOrig!;
    _editTarget = null; _editOrig = null;

    _push(TermEntry(TermType.info, '🤖 AI mengedit "$fn"...'));

    final file = ProcessedFile(
      filename: fn, mimeType: 'text/plain',
      category: FileCategory.code,
      textContent: orig, sizeBytes: orig.length,
    );

    _push(const TermEntry(TermType.ai, ''));
    final sb = StringBuffer();
    await for (final t in _ai.editFileStream(
        file: file, editInstruction: instruction)) {
      sb.write(t);
      _updateLast(TermEntry(TermType.ai, sb.toString()));
    }

    final edited = sb.toString();
    if (mounted) setState(() { _pendingSavePath = fn; _pendingSaveContent = edited; });
    _push(TermEntry(TermType.info, '💾 Simpan ke "$fn"? [yes/no]'));
  }

  // ── AI script generator ───────────────────────────────────────────────────
  Future<void> _doScript(String task) async {
    _push(TermEntry(TermType.info, '🤖 Membuat script untuk: $task'));

    final hasTermux = _svc.hasTermux;
    final sp = 'Kamu adalah shell script expert untuk Android'
        '${hasTermux ? " dengan Termux" : ""}.\n'
        'Buat script sh HANYA untuk task ini.\n'
        '${hasTermux ? "Bisa gunakan apt/pkg, python3, node, git, dll.\n" : "Hanya perintah /system/bin yang tersedia (busybox).\n"}'
        'Script harus aman. Balas HANYA kode script tanpa penjelasan, tanpa backtick.';

    final sb = StringBuffer();
    await for (final t in _ai.sendChatStream(
        systemPrompt: sp, history: [],
        userMessage: 'Script untuk: $task')) {
      sb.write(t);
    }

    final script = sb.toString()
        .replaceAll(RegExp(r'```\w*\n?'), '').replaceAll('```', '').trim();

    _push(TermEntry(TermType.output, '--- Script ---\n$script\n---'));
    _push(const TermEntry(TermType.info, '▶ Menjalankan...'));

    final result = await _svc.runScript(script);
    _push(TermEntry(
      result.isSuccess ? TermType.output : TermType.error,
      result.isSuccess
          ? '✅ Selesai:\n${result.stdout}'
          : '❌ Error:\n${result.stderr}',
    ));
  }

  // ── Download ──────────────────────────────────────────────────────────────
  Future<void> _doDownload(String url) async {
    if (!url.startsWith('http')) {
      _push(TermEntry(TermType.error, 'URL tidak valid: $url')); return;
    }
    _push(TermEntry(TermType.info, '⬇️ Download: $url'));
    _push(const TermEntry(TermType.download, '⬇️ Memulai...'));

    await for (final prog in _svc.download(url)) {
      if (prog.error != null) {
        _updateLast(TermEntry(TermType.error, '❌ Gagal: ${prog.error}')); return;
      }
      if (prog.done) {
        _updateLast(TermEntry(TermType.output, '✅ Selesai: ${prog.filename}')); return;
      }
      _updateLast(TermEntry(TermType.download,
          '⬇️ ${prog.filename}: ${prog.label}', progress: prog));
    }
  }

  // ── Build UI ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _streaming
                  ? Colors.orange
                  : _busy
                      ? Colors.amber
                      : _aiMode
                          ? const Color(0xFF00BFFF)
                          : const Color(0xFF00FF41),
            ),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _aiMode ? '🤖 AI Terminal' : '💻 Terminal',
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700,
                  fontFamily: 'monospace'),
            ),
            if (_initialized)
              Text(
                _svc.cwdRelative,
                style: const TextStyle(color: Colors.white38, fontSize: 10,
                    fontFamily: 'monospace'),
              ),
          ]),
        ]),
        actions: [
          // Termux badge
          if (_initialized && _svc.hasTermux)
            Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade900,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.shade700),
              ),
              child: const Text('TERMUX', style: TextStyle(
                  color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.w800)),
            ),
          IconButton(
            tooltip: 'Toggle AI Mode',
            icon: Icon(Icons.smart_toy_rounded,
                color: _aiMode ? const Color(0xFF00BFFF) : Colors.white38, size: 20),
            onPressed: () => _handle('/ai'),
          ),
          IconButton(
            tooltip: 'File Manager',
            icon: const Icon(Icons.folder_open_rounded, color: Colors.white54, size: 20),
            onPressed: () => _tabs.animateTo(1),
          ),
          IconButton(
            tooltip: 'Bersihkan',
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white38, size: 20),
            onPressed: () => ref.read(_entriesProvider.notifier).state = const [],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: const Color(0xFF00FF41),
          labelColor: const Color(0xFF00FF41),
          unselectedLabelColor: Colors.white38,
          indicatorWeight: 1,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              letterSpacing: 1, fontFamily: 'monospace'),
          tabs: const [Tab(text: 'TERMINAL'), Tab(text: 'FILES')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildTerminalTab(),
          _FileManager(svc: _svc, onCommand: _handle),
        ],
      ),
    );
  }

  Widget _buildTerminalTab() {
    final entries = ref.watch(_entriesProvider);
    return Column(children: [
      // Output area
      Expanded(
        child: GestureDetector(
          onTap: () => _inputFocus.requestFocus(),
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            itemCount: entries.length,
            itemBuilder: (_, i) => _Line(entries[i]),
          ),
        ),
      ),

      // Quick command bar
      _buildQuickBar(),

      // Path + status bar
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        color: const Color(0xFF0D0D0D),
        child: Row(children: [
          const Text('📂 ', style: TextStyle(fontSize: 11)),
          Expanded(
            child: Text(_initialized ? _svc.cwdRelative : '...',
              style: const TextStyle(color: Colors.white30, fontSize: 10,
                  fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis),
          ),
          if (_streaming)
            const Text('◼ STREAM',
              style: TextStyle(color: Colors.orange, fontSize: 9,
                  fontWeight: FontWeight.w800)),
          if (_editTarget != null)
            const Text('✏️ EDIT MODE',
              style: TextStyle(color: Colors.orange, fontSize: 10,
                  fontWeight: FontWeight.w700)),
          if (_pendingSavePath != null)
            const Text('💾 SAVE? [yes/no]',
              style: TextStyle(color: Colors.amber, fontSize: 10,
                  fontWeight: FontWeight.w700)),
        ]),
      ),

      // Input row
      _buildInput(),
    ]);
  }

  Widget _buildQuickBar() {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemCount: _quickCmds.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            // History button
            return _QuickBtn(
              label: '⬆️ hist',
              onTap: () {
                if (_cmdHistory.isEmpty) return;
                if (mounted) setState(() {
                  _histIdx = (_histIdx + 1).clamp(0, _cmdHistory.length - 1);
                  _inputCtrl.text = _cmdHistory[_histIdx];
                  _inputCtrl.selection = TextSelection.collapsed(
                      offset: _inputCtrl.text.length);
                });
              },
            );
          }
          final (cmd, label) = _quickCmds[i - 1];
          return _QuickBtn(
            label: label,
            onTap: () => _handle(cmd),
          );
        },
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          10, 8, 10, MediaQuery.of(context).viewInsets.bottom + 8),
      color: const Color(0xFF111111),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            _aiMode ? '🤖 ' : '> ',
            style: TextStyle(
              color: _aiMode ? const Color(0xFF00BFFF) : const Color(0xFF00FF41),
              fontSize: 14, fontFamily: 'monospace', fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              focusNode: _inputFocus,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 13,
                  fontFamily: 'monospace'),
              cursorColor: const Color(0xFF00FF41),
              cursorWidth: 2,
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: true,
                fillColor: const Color(0xFF111111),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                hintText: _editTarget != null
                    ? 'Instruksi edit...'
                    : _pendingSavePath != null
                        ? 'yes / no'
                        : _aiMode ? 'Tanya AI...' : 'perintah shell...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12,
                    fontFamily: 'monospace'),
              ),
              onSubmitted: _handle,
              textInputAction: TextInputAction.send,
              // Navigasi history dengan tombol keyboard
              onChanged: (_) => setState(() {}),
            ),
          ),
          // Tombol Tab (autocomplete real)
          GestureDetector(
            onTap: () async {
              final text = _inputCtrl.text;
              if (text.isEmpty) return;

              final parts = text.trim().split(' ');
              final lastWord = parts.last;

              try {
                final files = await _svc.listFiles();
                final matches = files
                    .map((f) => f.path.split('/').last)
                    .where((name) => name.toLowerCase().startsWith(lastWord.toLowerCase()))
                    .toList();

                if (matches.length == 1) {
                  parts[parts.length - 1] = matches.first;
                  if (mounted) setState(() {
                    _inputCtrl.text = parts.join(' ');
                    _inputCtrl.selection = TextSelection.collapsed(offset: _inputCtrl.text.length);
                  });
                } else if (matches.length > 1) {
                  _push(TermEntry(TermType.output, '\n${matches.join('  ')}\n\$ $text'));
                } else {
                  final result = await _svc.run(
                    'compgen -f "$lastWord" 2>/dev/null || ls -1 | grep "^$lastWord" 2>/dev/null || echo ""',
                    timeout: const Duration(seconds: 3),
                  );
                  if (result.stdout.trim().isNotEmpty) {
                    final shellMatches = result.stdout.trim().split('\n').where((s) => s.isNotEmpty).toList();
                    if (shellMatches.length == 1) {
                      parts[parts.length - 1] = shellMatches.first;
                      if (mounted) setState(() {
                        _inputCtrl.text = parts.join(' ');
                        _inputCtrl.selection = TextSelection.collapsed(offset: _inputCtrl.text.length);
                      });
                    } else {
                      _push(TermEntry(TermType.output, '\n${shellMatches.join('  ')}\n\$ $text'));
                    }
                  }
                }
              } catch (e) {
                debugPrint('[Terminal] Tab autocomplete error: $e');
              }
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('TAB',
                style: TextStyle(color: Colors.white54, fontSize: 10,
                    fontFamily: 'monospace')),
            ),
          ),
          if (_busy || _streaming)
            GestureDetector(
              onTap: () {
                // Stop streaming
                if (mounted) setState(() { _busy = false; _streaming = false; });
                _push(const TermEntry(TermType.info, '^C'));
              },
              child: const Text('■',
                style: TextStyle(color: Colors.red, fontSize: 18)),
            )
          else
            GestureDetector(
              onTap: () => _handle(_inputCtrl.text),
              child: const Icon(Icons.keyboard_return_rounded,
                  color: Color(0xFF00FF41), size: 18),
            ),
        ],
      ),
    );
  }
}

// ── Quick button ──────────────────────────────────────────────────────────────
class _QuickBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(label,
          style: const TextStyle(color: Colors.white60, fontSize: 10,
              fontFamily: 'monospace')),
      ),
    );
  }
}

// ── Terminal line renderer ────────────────────────────────────────────────────
class _Line extends StatelessWidget {
  final TermEntry e;
  const _Line(this.e);

  @override
  Widget build(BuildContext context) {
    if (e.text.isEmpty && e.type != TermType.download) return const SizedBox(height: 2);

    Color c;
    switch (e.type) {
      case TermType.prompt:   c = const Color(0xFF00FF41);
      case TermType.error:    c = const Color(0xFFFF5555);
      case TermType.ai:       c = const Color(0xFF87CEEB);
      case TermType.download: c = const Color(0xFFFFD700);
      case TermType.info:     c = const Color(0xFFAAAAAA);
      case TermType.system:   c = const Color(0xFF888888);
      default:                c = const Color(0xFFDDDDDD);
    }

    if (e.type == TermType.download && e.progress != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.text, style: TextStyle(color: c, fontSize: 11, fontFamily: 'monospace')),
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: e.progress!.fraction > 0 ? e.progress!.fraction : null,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation(Color(0xFFFFD700)),
              minHeight: 3,
            ),
          ),
        ]),
      );
    }

    // Strip ANSI escape codes untuk display (simplified)
    final cleaned = e.text.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: SelectableText(cleaned,
        style: TextStyle(color: c, fontSize: 11,
            fontFamily: 'monospace', height: 1.45)),
    );
  }
}

// ── File Manager ──────────────────────────────────────────────────────────────
class _FileManager extends StatefulWidget {
  final TerminalService svc;
  final Future<void> Function(String) onCommand;
  const _FileManager({required this.svc, required this.onCommand});
  @override
  State<_FileManager> createState() => _FileManagerState();
}

class _FileManagerState extends State<_FileManager> {
  List<FileSystemEntity> _files = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final f = await widget.svc.listFiles();
    if (mounted) setState(() { _files = f; _loading = false; });
  }

  Future<void> _import() async {
    final r = await FilePicker.platform.pickFiles();
    if (r == null || r.files.isEmpty) return;
    final path = r.files.single.path;
    if (path == null) return;
    final name = p.basename(path);
    final dest = '${widget.svc.cwdPath}/$name';
    await File(path).copy(dest);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00FF41)));

    return Column(children: [
      // Toolbar
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: const Color(0xFF111111),
        child: Row(children: [
          Expanded(child: Text(widget.svc.cwdRelative,
            style: const TextStyle(color: Colors.white54, fontSize: 11,
                fontFamily: 'monospace'),
            overflow: TextOverflow.ellipsis)),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white54, size: 18),
            onPressed: _load, padding: EdgeInsets.zero, constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.upload_file_rounded, color: Colors.white54, size: 18),
            onPressed: _import, padding: EdgeInsets.zero, constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () => widget.onCommand('cd ..').then((_) => _load()),
            child: const Text('.. (up)', style: TextStyle(color: Colors.white38,
                fontSize: 11, fontFamily: 'monospace')),
          ),
        ]),
      ),

      if (_files.isEmpty)
        Expanded(child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('📁', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 8),
            const Text('Workspace kosong', style: TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Import File'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF41),
                  foregroundColor: Colors.black),
            ),
          ]),
        ))
      else
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
            itemCount: _files.length,
            itemBuilder: (_, i) {
              final f    = _files[i];
              final name = p.basename(f.path);
              final isDir = f is Directory;
              String size = '';
              if (!isDir) {
                try {
                  final b = File(f.path).lengthSync();
                  if (b < 1024) size = '$b B';
                  else if (b < 1024*1024) size = '${(b/1024).toStringAsFixed(0)} KB';
                  else size = '${(b/(1024*1024)).toStringAsFixed(1)} MB';
                } catch (_) {}
              }

              return InkWell(
                onTap: () async {
                  if (isDir) {
                    await widget.onCommand('cd $name');
                    _load();
                  } else {
                    widget.onCommand('cat $name');
                  }
                },
                onLongPress: () => _fileMenu(context, f, name, isDir),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Text(_emoji(name, isDir), style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: TextStyle(
                          color: isDir ? const Color(0xFF87CEEB) : Colors.white,
                          fontSize: 13, fontFamily: 'monospace')),
                        if (size.isNotEmpty)
                          Text(size, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    )),
                    const Icon(Icons.more_vert_rounded, color: Colors.white24, size: 18),
                  ]),
                ),
              );
            },
          ),
        ),
    ]);
  }

  String _emoji(String name, bool isDir) {
    if (isDir) return '📁';
    final ext = p.extension(name).toLowerCase();
    if (['.jpg','.png','.gif','.webp'].contains(ext)) return '🖼️';
    if (['.mp4','.mov','.avi','.mkv'].contains(ext)) return '🎬';
    if (['.mp3','.wav','.aac','.flac'].contains(ext)) return '🎵';
    if (ext == '.pdf') return '📄';
    if (['.txt','.md'].contains(ext)) return '📝';
    if (['.dart','.py','.js','.ts','.java','.kt','.sh','.rb','.go'].contains(ext)) return '💻';
    if (['.zip','.rar','.tar','.gz'].contains(ext)) return '📦';
    if (['.json','.xml','.yaml','.yml','.toml'].contains(ext)) return '🗄️';
    if (['.gguf','.ggml','.task'].contains(ext)) return '🤖';
    return '📄';
  }

  void _fileMenu(BuildContext ctx, FileSystemEntity f, String name, bool isDir) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: const Color(0xFF1a1a1a),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            decoration: BoxDecoration(color: Colors.white24,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(name, style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w700, fontFamily: 'monospace'))),
          if (!isDir) ...[ 
            _MItem(Icons.visibility_rounded, 'Lihat isi',
                () => widget.onCommand('cat $name')),
            _MItem(Icons.edit_rounded, 'Edit dengan AI',
                () => widget.onCommand('/edit $name')),
            _MItem(Icons.copy_rounded, 'Copy path',
                () => Clipboard.setData(ClipboardData(text: f.path))),
            _MItem(Icons.content_copy_rounded, 'Copy nama',
                () => Clipboard.setData(ClipboardData(text: name))),
          ],
          if (isDir)
            _MItem(Icons.folder_open_rounded, 'Masuk folder',
                () async { await widget.onCommand('cd $name'); _load(); }),
          _MItem(Icons.delete_rounded, 'Hapus', () async {
            Navigator.pop(ctx);
            await widget.onCommand('rm ${isDir ? "-rf " : ""}$name');
            _load();
          }, color: Colors.red),
          const SizedBox(height: 8),
        ],
      )),
    );
  }
}

class _MItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _MItem(this.icon, this.label, this.onTap, {this.color});
  @override
  Widget build(BuildContext ctx) => ListTile(
    dense: true,
    leading: Icon(icon, color: color ?? Colors.white70, size: 20),
    title: Text(label, style: TextStyle(color: color ?? Colors.white, fontSize: 13)),
    onTap: () { Navigator.pop(ctx); onTap(); },
  );
}
