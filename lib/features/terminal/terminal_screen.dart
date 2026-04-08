// lib/features/terminal/terminal_screen.dart
// KanMonAI — Terminal Screen (Sesi 7C-i)
// Model data, state, initState, execute, dan history navigation.
// UI penuh akan diimplementasi di Sesi 7C-ii.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/services/terminal_service.dart';
import '../../data/services/termux_bridge.dart'; // digunakan TerminalService secara internal
import '../../data/services/ai_service.dart';

// ── Model internal ────────────────────────────────────────────────────────────

enum _EntryType { command, output, error, system }

class _TerminalEntry {
  final String text;
  final _EntryType type;
  const _TerminalEntry(this.text, this.type);
}

// ── Widget ────────────────────────────────────────────────────────────────────

class TerminalScreen extends StatefulWidget {
  final String? initialCommand;
  final bool autoRun;

  const TerminalScreen({
    super.key,
    this.initialCommand,
    this.autoRun = false,
  });

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final List<_TerminalEntry> _entries = [];
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  bool _isRunning = false;
  int _historyIndex = -1;
  bool _termuxAvailable = false;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initTerminal();
  }

  Future<void> _initTerminal() async {
    await TerminalService.instance.initialize();
    if (!mounted) return;

    setState(() {
      _termuxAvailable = TerminalService.instance.isTermuxAvailable;
    });

    _addEntry('🖥️ Terminal KanMonAI siap.', _EntryType.system);

    if (_termuxAvailable) {
      _addEntry('✅ Termux terdeteksi — shell penuh tersedia.', _EntryType.system);
    } else {
      _addEntry(
        '⚠️ Termux tidak terdeteksi — shell terbatas.\n'
        'Install Termux dari F-Droid untuk akses shell penuh.',
        _EntryType.system,
      );
    }

    if (widget.initialCommand != null && widget.autoRun) {
      await _executeCommand(widget.initialCommand!);
    } else if (widget.initialCommand != null) {
      _inputCtrl.text = widget.initialCommand!;
      _inputFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  // ── Helper methods ──────────────────────────────────────────────────────────

  void _addEntry(String text, _EntryType type) {
    if (!mounted) return;
    setState(() => _entries.add(_TerminalEntry(text, type)));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  void _clearTerminal() {
    setState(() => _entries.clear());
    _addEntry('🖥️ Terminal dibersihkan.', _EntryType.system);
  }

  String get _helpText => '''
Perintah yang tersedia:
  clear         — Bersihkan terminal
  help          — Tampilkan bantuan ini
  echo [teks]   — Cetak teks
  pwd           — Direktori kerja
  ls            — List file (terbatas)
  date          — Tampilkan tanggal/waktu

Untuk shell penuh: install Termux dari F-Droid.
Ketuk ikon Termux di AppBar untuk membuka Termux langsung.
''';

  // ── Command execution ───────────────────────────────────────────────────────

  Future<void> _executeCommand(String command) async {
    final cmd = command.trim();
    if (cmd.isEmpty) return;
    if (_isRunning) return;

    _inputCtrl.clear();
    _historyIndex = -1;
    _addEntry('$ $cmd', _EntryType.command);
    setState(() => _isRunning = true);

    // Built-in commands (dihandle langsung di UI layer)
    switch (cmd) {
      case 'clear':
        _clearTerminal();
        setState(() => _isRunning = false);
        return;
      case 'help':
        _addEntry(_helpText, _EntryType.system);
        setState(() => _isRunning = false);
        return;
    }

    if (cmd.startsWith('cd ')) {
      _addEntry('cd: tidak didukung di terminal terbatas ini.', _EntryType.error);
      setState(() => _isRunning = false);
      return;
    }

    // Eksekusi nyata via streaming TerminalService
    try {
      await for (final chunk in TerminalService.instance.executeStream(cmd)) {
        if (!mounted) break;
        final isError = chunk.startsWith('❌') || chunk.startsWith('⚠️');
        _addEntry(chunk, isError ? _EntryType.error : _EntryType.output);
      }
    } catch (e) {
      _addEntry('❌ Error tidak terduga: $e', _EntryType.error);
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  // ── History navigation ──────────────────────────────────────────────────────

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final history = TerminalService.instance.commandHistory;
    if (history.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _historyIndex = (_historyIndex + 1).clamp(0, history.length - 1);
      _inputCtrl.text = history[_historyIndex];
      _inputCtrl.selection =
          TextSelection.collapsed(offset: _inputCtrl.text.length);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_historyIndex <= 0) {
        _historyIndex = -1;
        _inputCtrl.clear();
      } else {
        _historyIndex--;
        _inputCtrl.text = history[_historyIndex];
        _inputCtrl.selection =
            TextSelection.collapsed(offset: _inputCtrl.text.length);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ── Stubs (akan diisi di Sesi 7C-ii dan 7D) ────────────────────────────────

  void _showCommandHistory() {
    final history = TerminalService.instance.commandHistory;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (_) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Riwayat Perintah',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          Expanded(
            child: history.isEmpty
                ? const Center(
                    child: Text('Belum ada riwayat', style: TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    itemCount: history.length,
                    itemBuilder: (_, i) => ListTile(
                      title: Text(
                        history[i],
                        style: const TextStyle(
                          color: Colors.green,
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                      onTap: () {
                        _inputCtrl.text = history[i];
                        _inputCtrl.selection = TextSelection.collapsed(
                          offset: history[i].length,
                        );
                        Navigator.pop(context);
                        _inputFocus.requestFocus();
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showAiCommandSuggest() {
    final textCtrl = TextEditingController();
    String suggestedCommand = '';
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16, right: 16, top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Bantuan AI — Saran Command',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Apa yang ingin kamu lakukan? (misal: install library http)',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      filled: true,
                      fillColor: Colors.grey[800],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                    ),
                    onPressed: isLoading ? null : () async {
                      final query = textCtrl.text.trim();
                      if (query.isEmpty) return;
                      setModalState(() { isLoading = true; suggestedCommand = ''; });
                      try {
                        final result = await AiService.instance.generate(
                          prompt: 'Berikan 1 perintah shell/terminal yang tepat untuk: $query\n'
                                  'Jawab HANYA dengan perintah saja, tanpa penjelasan, tanpa pagar kode (```), tanpa spasi tambahan.',
                        );
                        setModalState(() {
                          suggestedCommand = result.trim();
                          isLoading = false;
                        });
                      } catch (e) {
                        setModalState(() {
                          suggestedCommand = '❌ Error: $e';
                          isLoading = false;
                        });
                      }
                    },
                    child: isLoading
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Tanya AI'),
                  ),
                  if (suggestedCommand.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withOpacity(0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Command disarankan:',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            suggestedCommand,
                            style: const TextStyle(
                              color: Colors.green,
                              fontFamily: 'monospace',
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.black,
                      ),
                      icon: const Icon(Icons.check),
                      label: const Text('Gunakan Command Ini'),
                      onPressed: () {
                        _inputCtrl.text = suggestedCommand;
                        _inputCtrl.selection = TextSelection.collapsed(
                          offset: suggestedCommand.length,
                        );
                        Navigator.pop(context);
                        _inputFocus.requestFocus();
                      },
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.green,
        title: const Text(
          'Terminal',
          style: TextStyle(
            fontFamily: 'monospace',
            color: Colors.green,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services_rounded, color: Colors.green),
            tooltip: 'Bersihkan',
            onPressed: _clearTerminal,
          ),
          IconButton(
            icon: const Icon(Icons.terminal_rounded, color: Colors.green),
            tooltip: 'Buka Termux',
            onPressed: () => TermuxBridge.instance.openTermux(),
          ),
          PopupMenuButton<String>(
            color: Colors.grey[900],
            icon: const Icon(Icons.more_vert, color: Colors.green),
            onSelected: (val) {
              if (val == 'history') _showCommandHistory();
              if (val == 'ai') _showAiCommandSuggest();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'history',
                child: Text('Riwayat Perintah', style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: 'ai',
                child: Text('Bantuan AI', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(8),
              itemCount: _entries.length,
              itemBuilder: (_, i) => _TerminalLine(entry: _entries[i]),
            ),
          ),
          Divider(height: 1, color: Colors.grey[800]),
          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                const Text(
                  '\$ ',
                  style: TextStyle(
                    color: Colors.green,
                    fontFamily: 'monospace',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: Focus(
                    onKeyEvent: _handleKeyEvent,
                    child: TextField(
                      controller: _inputCtrl,
                      focusNode: _inputFocus,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 14,
                      ),
                      cursorColor: Colors.green,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Masukkan perintah...',
                        hintStyle: TextStyle(color: Colors.grey[600], fontFamily: 'monospace'),
                      ),
                      onSubmitted: _executeCommand,
                    ),
                  ),
                ),
                if (_isRunning)
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    onPressed: () => _executeCommand(_inputCtrl.text),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── _TerminalLine widget ───────────────────────────────────────────────────────

class _TerminalLine extends StatelessWidget {
  final _TerminalEntry entry;
  const _TerminalLine({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.type) {
      _EntryType.command => Colors.green,
      _EntryType.error   => Colors.red[300]!,
      _EntryType.system  => Colors.grey[500]!,
      _EntryType.output  => Colors.white,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        entry.text,
        style: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }
}
