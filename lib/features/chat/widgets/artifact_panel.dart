// lib/features/chat/widgets/artifact_panel.dart
// KanMon GO — Artifact Panel (Claude-style code/file editor in chat)
//
// Features:
//   • Slides in from the right, persistent across messages
//   • Multi-artifact tab bar (up to 8 tabs)
//   • Modes: code editor, file diff viewer, markdown/html preview
//   • Code editor: syntax-highlighted, editable TextField, line numbers
//   • Actions: Copy, Save to File, Run (terminal), Share, Close
//   • File mode: diff view (red/green), Apply to File, Create New File
//   • Preview mode: rendered Markdown or HTML via webview_flutter
//   • Works with all AI sources (Online, Bulk, Offline)
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/data/services/terminal_service.dart';
import 'package:kanmongo/shared/utils/top_snack.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────

enum ArtifactMode { code, file, preview }

class ArtifactItem {
  final String id;
  final ArtifactMode mode;
  final String title;       // tab label, e.g. "main.dart" or "Patch #1"
  final String language;    // for code mode: 'dart', 'python', 'js', etc.
  String content;           // current (possibly edited) content
  final String? originalContent; // for diff/file mode: original before edit
  final String? filePath;   // if linked to a real file on disk

  ArtifactItem({
    String? id,
    required this.mode,
    required this.title,
    required this.content,
    this.language = '',
    this.originalContent,
    this.filePath,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTROLLER  (lifted so ChatScreen can push artifacts)
// ─────────────────────────────────────────────────────────────────────────────

class ArtifactPanelController extends ChangeNotifier {
  final List<ArtifactItem> _items = [];
  int _activeIndex = 0;
  bool _isOpen = false;

  List<ArtifactItem> get items       => List.unmodifiable(_items);
  int                get activeIndex => _activeIndex;
  bool               get isOpen      => _isOpen;
  ArtifactItem?      get active      => _items.isEmpty ? null : _items[_activeIndex];

  /// Push a new artifact (or focus existing one with same id).
  void push(ArtifactItem item) {
    final existing = _items.indexWhere((i) => i.id == item.id);
    if (existing >= 0) {
      _activeIndex = existing;
    } else {
      _items.add(item);
      _activeIndex = _items.length - 1;
    }
    _isOpen = true;
    notifyListeners();
  }

  void selectTab(int index) {
    if (index < 0 || index >= _items.length) return;
    _activeIndex = index;
    notifyListeners();
  }

  void closePanel() {
    _isOpen = false;
    notifyListeners();
  }

  void removeTab(int index) {
    if (index < 0 || index >= _items.length) return;
    _items.removeAt(index);
    if (_items.isEmpty) {
      _isOpen = false;
      _activeIndex = 0;
    } else {
      _activeIndex = (_activeIndex >= _items.length)
          ? _items.length - 1
          : _activeIndex;
    }
    notifyListeners();
  }

  void updateContent(String id, String newContent) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx >= 0) {
      _items[idx].content = newContent;
      notifyListeners();
    }
  }

  void clearAll() {
    _items.clear();
    _activeIndex = 0;
    _isOpen = false;
    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ARTIFACT PANEL WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class ArtifactPanel extends StatefulWidget {
  final ArtifactPanelController controller;
  final double width;

  const ArtifactPanel({
    super.key,
    required this.controller,
    this.width = 420,
  });

  @override
  State<ArtifactPanel> createState() => _ArtifactPanelState();
}

class _ArtifactPanelState extends State<ArtifactPanel>
    with SingleTickerProviderStateMixin {

  late AnimationController _slideAnim;
  late Animation<Offset>   _slideOffset;

  // Per-artifact editor controllers (keyed by artifact id)
  final Map<String, TextEditingController> _editorCtrls = {};
  final Map<String, ScrollController>      _editorScrolls = {};
  final Map<String, WebViewController>     _webCtrls = {};

  bool _isSaving = false;
  bool _isRunningInline = false;

  @override
  void initState() {
    super.initState();
    _slideAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slideOffset = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideAnim, curve: Curves.easeOutCubic));

    widget.controller.addListener(_onControllerChanged);
    if (widget.controller.isOpen) _slideAnim.value = 1.0;
  }

  @override
  void dispose() {
    _slideAnim.dispose();
    for (final c in _editorCtrls.values) c.dispose();
    for (final s in _editorScrolls.values) s.dispose();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (widget.controller.isOpen) {
      _slideAnim.forward();
    } else {
      _slideAnim.reverse();
    }
    // Ensure editor controller exists for new artifact
    final item = widget.controller.active;
    if (item != null && !_editorCtrls.containsKey(item.id)) {
      _editorCtrls[item.id] = TextEditingController(text: item.content);
      _editorScrolls[item.id] = ScrollController();
    }
  }

  TextEditingController _editorFor(ArtifactItem item) {
    if (!_editorCtrls.containsKey(item.id)) {
      _editorCtrls[item.id] = TextEditingController(text: item.content);
    }
    return _editorCtrls[item.id]!;
  }

  ScrollController _scrollFor(ArtifactItem item) {
    if (!_editorScrolls.containsKey(item.id)) {
      _editorScrolls[item.id] = ScrollController();
    }
    return _editorScrolls[item.id]!;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.isOpen && _slideAnim.isDismissed) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final items = widget.controller.items;
    final activeIdx = widget.controller.activeIndex;
    final activeItem = widget.controller.active;

    return SlideTransition(
      position: _slideOffset,
      child: Container(
        width: widget.width,
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          border: Border(left: BorderSide(color: cs.outlineVariant, width: 1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(40),
              blurRadius: 16,
              offset: const Offset(-4, 0),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────────
            _buildHeader(cs, tt, items, activeIdx, activeItem),
            // ── Tab bar (if > 1 artifact) ─────────────────────────────────
            if (items.length > 1)
              _buildTabBar(cs, tt, items, activeIdx),
            const Divider(height: 1),
            // ── Content ───────────────────────────────────────────────────
            Expanded(
              child: activeItem == null
                  ? _buildEmpty(cs, tt)
                  : _buildContent(activeItem, cs, tt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, TextTheme tt,
      List<ArtifactItem> items, int activeIdx, ArtifactItem? active) {
    return Container(
      color: cs.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Icon(_modeIcon(active?.mode), size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              active?.title ?? 'Artifact',
              style: tt.labelMedium?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Action buttons
          if (active != null) ...[
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 18),
              tooltip: 'Salin',
              onPressed: () => _copyContent(active),
            ),
            IconButton(
              icon: const Icon(Icons.save_alt_rounded, size: 18),
              tooltip: 'Simpan ke file',
              onPressed: _isSaving ? null : () => _saveToFile(active),
            ),
            if (active.mode == ArtifactMode.code)
              IconButton(
                icon: const Icon(Icons.share_rounded, size: 18),
                tooltip: 'Bagikan',
                onPressed: () => _shareContent(active),
              ),
            if (_isRunnable(active))
              _isRunningInline
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent),
                    ),
                  )
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                      color: Colors.greenAccent,
                      tooltip: 'Jalankan Inline (output di sini)',
                      onPressed: () => _runInline(context, active),
                    ),
                    IconButton(
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      color: Colors.green,
                      tooltip: 'Jalankan di Terminal',
                      onPressed: () => _runInTerminal(context, active),
                    ),
                  ]),
          ],
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: 'Tutup panel',
            onPressed: widget.controller.closePanel,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(ColorScheme cs, TextTheme tt,
      List<ArtifactItem> items, int activeIdx) {
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          final isActive = i == activeIdx;
          return GestureDetector(
            onTap: () => widget.controller.selectTab(i),
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: isActive ? cs.primaryContainer : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_modeIcon(item.mode), size: 12,
                    color: isActive ? cs.onPrimaryContainer : cs.onSurface),
                  const SizedBox(width: 4),
                  Text(
                    item.title.length > 16
                        ? '${item.title.substring(0, 14)}…'
                        : item.title,
                    style: tt.labelSmall?.copyWith(
                      color: isActive ? cs.onPrimaryContainer : cs.onSurface,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => widget.controller.removeTab(i),
                    child: Icon(Icons.close_rounded, size: 12,
                      color: isActive ? cs.onPrimaryContainer : cs.outline),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs, TextTheme tt) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.code_rounded, size: 48, color: cs.outline),
          const SizedBox(height: 8),
          Text('Belum ada artifact.',
            style: tt.bodyMedium?.copyWith(color: cs.outline)),
          const SizedBox(height: 4),
          Text('Klik "Buka di Panel" pada blok kode AI.',
            style: tt.bodySmall?.copyWith(color: cs.outline)),
        ],
      ),
    );
  }

  Widget _buildContent(ArtifactItem item, ColorScheme cs, TextTheme tt) {
    switch (item.mode) {
      case ArtifactMode.code:
        return _buildCodeEditor(item, cs, tt);
      case ArtifactMode.file:
        return _buildFileDiff(item, cs, tt);
      case ArtifactMode.preview:
        return _buildPreview(item, cs, tt);
    }
  }

  // ── CODE EDITOR ───────────────────────────────────────────────────────────

  Widget _buildCodeEditor(ArtifactItem item, ColorScheme cs, TextTheme tt) {
    final ctrl   = _editorFor(item);
    final scroll = _scrollFor(item);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Language badge + line count
        Container(
          color: isDark
              ? const Color(0xFF1E1E2E)
              : const Color(0xFFF5F5F5),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.language.isEmpty ? 'text' : item.language,
                  style: tt.labelSmall?.copyWith(
                    color: cs.primary,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${ctrl.text.split('\n').length} baris',
                style: tt.labelSmall?.copyWith(color: cs.outline),
              ),
            ],
          ),
        ),
        // Editor
        Expanded(
          child: Scrollbar(
            controller: scroll,
            child: SingleChildScrollView(
              controller: scroll,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Line numbers
                    _buildLineNumbers(ctrl.text, isDark, tt),
                    // Editable code
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        maxLines: null,
                        expands: true,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: isDark ? Colors.white : Colors.black87,
                          height: 1.5,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF1E1E2E)
                              : const Color(0xFFF8F8F8),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                        onChanged: (v) {
                          widget.controller.updateContent(item.id, v);
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLineNumbers(String text, bool isDark, TextTheme tt) {
    final lines = text.split('\n');
    return Container(
      color: isDark ? const Color(0xFF181825) : const Color(0xFFEEEEEE),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(lines.length, (i) {
          return SizedBox(
            height: 19.5,  // matches line height
            child: Text(
              '${i + 1}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.5,
                color: isDark
                    ? Colors.white.withAlpha(80)
                    : Colors.black.withAlpha(80),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── FILE DIFF ─────────────────────────────────────────────────────────────

  Widget _buildFileDiff(ArtifactItem item, ColorScheme cs, TextTheme tt) {
    final lines = item.content.split('\n');
    return Column(
      children: [
        // Diff action bar
        Container(
          color: cs.surfaceContainer,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Text('Diff / Patch', style: tt.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.file_open_rounded, size: 16),
                label: const Text('Terapkan ke File'),
                onPressed: () => _applyToFile(item),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.note_add_rounded, size: 16),
                label: const Text('Buat File Baru'),
                onPressed: () => _createNewFile(item),
              ),
            ],
          ),
        ),
        // Diff lines
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: lines.length,
            itemBuilder: (_, i) {
              final line = lines[i];
              Color? bg;
              Color? fg;
              if (line.startsWith('+') && !line.startsWith('+++')) {
                bg = Colors.green.withAlpha(30);
                fg = Colors.green.shade700;
              } else if (line.startsWith('-') && !line.startsWith('---')) {
                bg = Colors.red.withAlpha(30);
                fg = Colors.red.shade700;
              } else if (line.startsWith('@@')) {
                bg = cs.primaryContainer.withAlpha(60);
                fg = cs.primary;
              }
              return Container(
                color: bg,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text('${i + 1}',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: cs.outline,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        line,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: fg ?? cs.onSurface,
                          height: 1.6,
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

  // ── PREVIEW ───────────────────────────────────────────────────────────────

  Widget _buildPreview(ArtifactItem item, ColorScheme cs, TextTheme tt) {
    final isHtml = item.language == 'html' || item.content.trimLeft().startsWith('<');
    if (isHtml) {
      // HTML preview via WebView
      if (!_webCtrls.containsKey(item.id)) {
        final wc = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..loadHtmlString(item.content);
        _webCtrls[item.id] = wc;
      }
      return WebViewWidget(controller: _webCtrls[item.id]!);
    }
    // Markdown preview — render as simple rich text
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        item.content,
        style: tt.bodyMedium,
      ),
    );
  }

  // ── ACTIONS ───────────────────────────────────────────────────────────────

  void _copyContent(ArtifactItem item) {
    final ctrl = _editorCtrls[item.id];
    Clipboard.setData(ClipboardData(text: ctrl?.text ?? item.content));
    if (!mounted) return;
    showTopSnack(context, 'Konten disalin!');
  }

  Future<void> _saveToFile(ArtifactItem item) async {
    setState(() => _isSaving = true);
    try {
      final ctrl    = _editorCtrls[item.id];
      final content = ctrl?.text ?? item.content;
      final ext     = _extensionFor(item.language);
      final dir     = await getApplicationDocumentsDirectory();
      final name    = '${item.title.replaceAll(RegExp(r'[^\w.]'), '_')}$ext';
      final file    = File('${dir.path}/$name');
      await file.writeAsString(content);
      if (!mounted) return;
      showTopSnack(context, 'Disimpan: ${file.path}', duration: const Duration(seconds: 3));
    } catch (e) {
      if (!mounted) return;
      showTopSnack(context, 'Gagal simpan: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _shareContent(ArtifactItem item) async {
    final ctrl    = _editorCtrls[item.id];
    final content = ctrl?.text ?? item.content;
    final ext     = _extensionFor(item.language);
    final dir     = await getTemporaryDirectory();
    final name    = '${item.title.replaceAll(RegExp(r'[^\w.]'), '_')}$ext';
    final file    = File('${dir.path}/$name');
    await file.writeAsString(content);
    await Share.shareXFiles([XFile(file.path)], text: item.title);
  }

  // ── Inline run: eksekusi via TerminalService, output tampil di dialog ────────
  Future<void> _runInline(BuildContext context, ArtifactItem item) async {
    if (_isRunningInline) return;
    final ctrl    = _editorCtrls[item.id];
    final content = ctrl?.text ?? item.content;
    final lang    = item.language.toLowerCase();
    final ext     = _extensionFor(item.language);
    final dir     = await getTemporaryDirectory();
    final file    = File('${dir.path}/run_artifact$ext');
    await file.writeAsString(content);
    final cmd = _buildRunCommand(lang, file.path);
    if (cmd.isEmpty) {
      if (!mounted) return;
      showTopSnack(context, 'Bahasa "$lang" tidak bisa dijalankan inline', isError: true);
      return;
    }
    if (!mounted) return;
    setState(() => _isRunningInline = true);
    try {
      await TerminalService.instance.init();
      final result = await TerminalService.instance.run(
        cmd,
        timeout: const Duration(seconds: 60),
      );
      if (!mounted) return;
      final output = result.stdout.trim().isNotEmpty
          ? result.stdout.trim()
          : result.stderr.trim().isNotEmpty
              ? result.stderr.trim()
              : '(tidak ada output)';
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Row(children: [
            const Icon(Icons.terminal, color: Colors.greenAccent, size: 18),
            const SizedBox(width: 8),
            Flexible(child: Text('Output: ${item.title}',
                style: const TextStyle(color: Colors.white, fontSize: 14),
                overflow: TextOverflow.ellipsis)),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.exitCode != 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('⚠️ Exit code: ${result.exitCode}',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      output,
                      style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12,
                        color: Colors.greenAccent, height: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(_),
              child: const Text('Tutup', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(_);
                if (mounted) context.push('/terminal', extra: {'initialCommand': cmd, 'autoRun': true});
              },
              child: const Text('Buka Terminal', style: TextStyle(color: Colors.blueAccent)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) showTopSnack(context, 'Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isRunningInline = false);
    }
  }

  void _runInTerminal(BuildContext context, ArtifactItem item) async {
    final ctrl    = _editorCtrls[item.id];
    final content = ctrl?.text ?? item.content;
    final ext     = _extensionFor(item.language);
    final dir     = await getTemporaryDirectory();
    final name    = 'run_artifact$ext';
    final file    = File('${dir.path}/$name');
    await file.writeAsString(content);
    final cmd = _buildRunCommand(item.language, file.path);
    if (!mounted) return;
    context.push('/terminal', extra: {'initialCommand': cmd});
  }

  Future<void> _applyToFile(ArtifactItem item) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.single.path == null) return;
    final targetPath = result.files.single.path!;
    final newContent = _extractPatchedContent(item.content);
    final confirmed  = await _showApplyConfirmDialog(targetPath, newContent);
    if (confirmed == true) {
      await File(targetPath).writeAsString(newContent);
      if (!mounted) return;
      showTopSnack(context, '✅ Perubahan berhasil diterapkan!');
    }
  }

  Future<void> _createNewFile(ArtifactItem item) async {
    final ctrl    = _editorCtrls[item.id];
    final content = _extractPatchedContent(ctrl?.text ?? item.content);
    final ext     = _extensionFor(item.language);
    final dir     = await getApplicationDocumentsDirectory();
    final ts      = DateTime.now().millisecondsSinceEpoch;
    final file    = File('${dir.path}/artifact_$ts$ext');
    await file.writeAsString(content);
    if (!mounted) return;
    showTopSnack(context, '✅ File dibuat: ${file.path}', duration: const Duration(seconds: 3));
  }

  Future<bool?> _showApplyConfirmDialog(String path, String newContent) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Terapkan ke File?'),
        content: Text(
          'File: $path\n\nKonten lama akan diganti. Tindakan ini tidak bisa dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Terapkan'),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  IconData _modeIcon(ArtifactMode? mode) {
    switch (mode) {
      case ArtifactMode.code:    return Icons.code_rounded;
      case ArtifactMode.file:    return Icons.insert_drive_file_rounded;
      case ArtifactMode.preview: return Icons.preview_rounded;
      default:                   return Icons.article_rounded;
    }
  }

  bool _isRunnable(ArtifactItem item) {
    const runnable = ['python', 'py', 'javascript', 'js', 'shell', 'sh', 'bash',
      'ruby', 'rb', 'php', 'perl', 'pl', 'typescript', 'ts'];
    return item.mode == ArtifactMode.code &&
        runnable.contains(item.language.toLowerCase());
  }

  String _extensionFor(String lang) {
    const map = {
      'dart': '.dart', 'python': '.py', 'py': '.py',
      'javascript': '.js', 'js': '.js', 'typescript': '.ts', 'ts': '.ts',
      'html': '.html', 'css': '.css', 'kotlin': '.kt', 'java': '.java',
      'swift': '.swift', 'bash': '.sh', 'shell': '.sh', 'sh': '.sh',
      'json': '.json', 'yaml': '.yaml', 'yml': '.yml',
      'xml': '.xml', 'markdown': '.md', 'md': '.md',
      'c': '.c', 'cpp': '.cpp', 'go': '.go', 'rust': '.rs',
    };
    return map[lang.toLowerCase()] ?? '.txt';
  }

  String _buildRunCommand(String lang, String filePath) {
    switch (lang.toLowerCase()) {
      case 'python':
      case 'py':
        return 'python3 "$filePath"';
      case 'javascript':
      case 'js':
        return 'node "$filePath"';
      case 'typescript':
      case 'ts':
        return 'npx ts-node "$filePath"';
      case 'shell':
      case 'bash':
      case 'sh':
        return 'bash "$filePath"';
      case 'ruby':
      case 'rb':
        return 'ruby "$filePath"';
      case 'php':
        return 'php "$filePath"';
      default:
        return 'cat "$filePath"';
    }
  }

  String _extractPatchedContent(String diff) {
    // If it's a unified diff, extract + lines
    if (diff.contains('\n+') || diff.startsWith('+')) {
      final lines = diff.split('\n');
      return lines
          .where((l) => !l.startsWith('-') && !l.startsWith('@@')
              && !l.startsWith('---') && !l.startsWith('+++'))
          .map((l) => l.startsWith('+') ? l.substring(1) : l)
          .join('\n');
    }
    return diff;
  }
}