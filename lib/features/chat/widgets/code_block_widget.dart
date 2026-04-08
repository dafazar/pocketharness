// lib/features/chat/widgets/code_block_widget.dart
// KanMon GO — Code Block Widget (Sesi 4)
//
// Fitur:
//   • Header: label bahasa + tombol Salin / Edit / Export / Jalankan
//   • Mode view: SelectableText dengan syntax highlight sederhana (tanpa package)
//   • Mode edit: TextField + tombol Batalkan / Simpan ke File
//   • Export: share_plus XFile
//   • Jalankan: navigasi ke /terminal dengan command siap pakai
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

import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/features/chat/widgets/artifact_panel.dart';

class CodeBlockWidget extends StatefulWidget {
  final String code;
  final String language;
  final ArtifactPanelController? artifactCtrl;

  const CodeBlockWidget({
    super.key,
    required this.code,
    required this.language,
    this.artifactCtrl,
  });

  @override
  State<CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<CodeBlockWidget> {
  bool _isEditing = false;
  bool _isSaving  = false;
  late TextEditingController _editCtrl;

  static const _runnable = ['python', 'py', 'javascript', 'js', 'shell', 'sh', 'bash'];

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController(text: widget.code);
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _copyCode() {
    Clipboard.setData(ClipboardData(
      text: _isEditing ? _editCtrl.text : widget.code,
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kode disalin!'), duration: Duration(seconds: 2)),
    );
  }

  void _toggleEdit() {
    setState(() {
      if (!_isEditing) _editCtrl.text = widget.code;
      _isEditing = !_isEditing;
    });
  }

  Future<void> _exportCode() async {
    try {
      final lang  = widget.language.isNotEmpty ? widget.language : 'txt';
      final bytes = Uint8List.fromList(utf8.encode(widget.code));
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: 'code.$lang', mimeType: 'text/plain')],
        subject: 'Kode $lang',
      );
    } catch (e) {
      debugPrint('[CodeBlock] Export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export gagal: $e')),
        );
      }
    }
  }

  Future<void> _saveToFile() async {
    if (_isSaving) return;
    final lang = widget.language.isNotEmpty ? widget.language : 'txt';
    try {
      setState(() => _isSaving = true);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan kode sebagai',
        fileName: 'code.$lang',
      );
      if (path == null) return;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Konfirmasi'),
          content: Text('Timpa/buat file:\n$path ?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Simpan')),
          ],
        ),
      );
      if (confirm != true) return;

      await File(path).writeAsString(_editCtrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Disimpan ke $path')),
        );
        setState(() => _isEditing = false);
      }
    } catch (e) {
      debugPrint('[CodeBlock] SaveToFile error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal simpan: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _runCode() async {
    final lang = widget.language.toLowerCase();
    String cmd = '';
    try {
      if (['python', 'py'].contains(lang)) {
        final tmp = await getTemporaryDirectory();
        final f   = File('${tmp.path}/run_temp.py')..writeAsStringSync(widget.code);
        cmd = 'python3 ${f.path}';
      } else if (['js', 'javascript'].contains(lang)) {
        final tmp = await getTemporaryDirectory();
        final f   = File('${tmp.path}/run_temp.js')..writeAsStringSync(widget.code);
        cmd = 'node ${f.path}';
      } else if (['sh', 'bash', 'shell'].contains(lang)) {
        cmd = widget.code.split('\n').first.trim();
      }
    } catch (e) {
      debugPrint('[CodeBlock] RunCode prep error: $e');
    }
    if (!mounted) return;
    context.push('/terminal', extra: {'initialCommand': cmd, 'autoRun': true});
  }

  // ── Syntax highlight ──────────────────────────────────────────────────────

  static const _keywords = [
    'import', 'export', 'from', 'class', 'def', 'return', 'if', 'else', 'elif',
    'for', 'while', 'in', 'not', 'and', 'or', 'is', 'None', 'True', 'False',
    'final', 'const', 'var', 'let', 'async', 'await', 'void', 'bool', 'int',
    'String', 'double', 'List', 'Map', 'Set', 'null', 'true', 'false',
    'function', 'new', 'this', 'super', 'extends', 'implements', 'override',
    'static', 'private', 'public', 'protected', 'try', 'catch', 'throw',
    'break', 'continue', 'switch', 'case', 'default', 'yield', 'require',
  ];

  List<TextSpan> _highlight(String code) {
    final spans = <TextSpan>[];
    final lines = code.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (i > 0) spans.add(const TextSpan(text: '\n'));

      // Comment line
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//') || trimmed.startsWith('#')) {
        spans.add(TextSpan(
          text: line,
          style: const TextStyle(color: Color(0xFF6A9955)),
        ));
        continue;
      }

      // Token-level highlight
      spans.addAll(_highlightLine(line));
    }
    return spans;
  }

  List<TextSpan> _highlightLine(String line) {
    final spans  = <TextSpan>[];
    int pos = 0;

    while (pos < line.length) {
      // String literal " or '
      if (line[pos] == '"' || line[pos] == "'") {
        final q   = line[pos];
        final end = line.indexOf(q, pos + 1);
        if (end != -1) {
          spans.add(TextSpan(
            text: line.substring(pos, end + 1),
            style: const TextStyle(color: Color(0xFFCE9178)),
          ));
          pos = end + 1;
          continue;
        }
      }

      // Try to match a word
      if (RegExp(r'[a-zA-Z_]').hasMatch(line[pos])) {
        int end = pos;
        while (end < line.length && RegExp(r'[a-zA-Z0-9_]').hasMatch(line[end])) {
          end++;
        }
        final word = line.substring(pos, end);
        if (_keywords.contains(word)) {
          spans.add(TextSpan(
            text: word,
            style: const TextStyle(color: Color(0xFF569CD6)),
          ));
        } else {
          spans.add(TextSpan(text: word, style: const TextStyle(color: Colors.white)));
        }
        pos = end;
        continue;
      }

      // Number
      if (RegExp(r'[0-9]').hasMatch(line[pos])) {
        int end = pos;
        while (end < line.length && RegExp(r'[0-9.]').hasMatch(line[end])) end++;
        spans.add(TextSpan(
          text: line.substring(pos, end),
          style: const TextStyle(color: Color(0xFFB5CEA8)),
        ));
        pos = end;
        continue;
      }

      // Punctuation / operator — grey
      spans.add(TextSpan(
        text: line[pos],
        style: const TextStyle(color: Color(0xFFD4D4D4)),
      ));
      pos++;
    }
    return spans;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c    = KmColors.of(context);
    final lang = widget.language.isNotEmpty ? widget.language : 'code';
    final isRunnable = _runnable.contains(lang.toLowerCase());

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.accent.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
            child: Row(
              children: [
                Text(
                  lang,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                _HeaderBtn(Icons.content_copy_rounded,    'Salin',    _copyCode),
                _HeaderBtn(Icons.edit_rounded,            'Edit',     _toggleEdit),
                _HeaderBtn(Icons.ios_share_rounded,       'Export',   _exportCode),
                if (widget.artifactCtrl != null)
                  _HeaderBtn(
                    Icons.open_in_new_rounded,
                    'Panel',
                    () {
                      final lang  = widget.language.isNotEmpty ? widget.language : 'text';
                      final title = lang == 'html' ? 'preview.html'
                          : (lang == 'markdown' || lang == 'md') ? 'doc.md'
                          : 'code.$lang';
                      final mode  = (lang == 'html' || lang == 'markdown' || lang == 'md')
                          ? ArtifactMode.preview
                          : ArtifactMode.code;
                      widget.artifactCtrl!.push(ArtifactItem(
                        mode:     mode,
                        title:    title,
                        language: lang,
                        content:  widget.code,
                      ));
                    },
                  ),
                if (isRunnable)
                  _HeaderBtn(Icons.play_arrow_rounded,    'Jalankan', _runCode,
                      color: Colors.greenAccent),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),

          // ── Body ────────────────────────────────────────────────────────
          if (!_isEditing)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: SelectableText.rich(
                TextSpan(
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    height: 1.55,
                  ),
                  children: _highlight(widget.code.trimRight()),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _editCtrl,
                maxLines: null,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.55,
                  color: Colors.white,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _toggleEdit,
                    child: const Text('Batalkan',
                        style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveToFile,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_rounded, size: 16),
                    label: const Text('Simpan ke File'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Header button helper ─────────────────────────────────────────────────────

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final String   label;
  final VoidCallback onTap;
  final Color?   color;
  const _HeaderBtn(this.icon, this.label, this.onTap, {this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color ?? Colors.grey, size: 12),
            const SizedBox(width: 3),
            Text(label,
                style: TextStyle(
                    color: color ?? Colors.grey, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
