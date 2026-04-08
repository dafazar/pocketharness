// lib/features/chat/widgets/file_edit_response_widget.dart
// KanMon GO — File Edit Response Widget (Session 06)
//
// Two widgets in one file:
//   1. FileEditResult      — data class holding the AI-produced content to save
//   2. FileEditResponseWidget — UI button shown below the last AI message bubble
//      when the AI has produced text that can be saved back as a file.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:kanmongo/core/theme/km_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DATA CLASS
// ─────────────────────────────────────────────────────────────────────────────

/// Holds the result of an AI file-edit operation that can be saved to disk.
class FileEditResult {
  final String originalFilename;
  final String? textContent;
  final Uint8List? binaryContent;
  final String outputExtension;
  final String description;

  const FileEditResult({
    required this.originalFilename,
    this.textContent,
    this.binaryContent,
    required this.outputExtension,
    required this.description,
  }) : assert(
          textContent != null || binaryContent != null,
          'Either textContent or binaryContent must be provided',
        );
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class FileEditResponseWidget extends StatefulWidget {
  final FileEditResult result;
  const FileEditResponseWidget({super.key, required this.result});

  @override
  State<FileEditResponseWidget> createState() => _FileEditResponseWidgetState();
}

class _FileEditResponseWidgetState extends State<FileEditResponseWidget> {
  _SaveState _state = _SaveState.idle;
  String? _savedPath;
  String? _errorMsg;

  Future<void> _saveFile() async {
    if (_state == _SaveState.saving) return;
    setState(() { _state = _SaveState.saving; _errorMsg = null; });
    try {
      final outDir = await _resolveOutputDirectory();
      final base   = p.basenameWithoutExtension(widget.result.originalFilename);
      final ts     = DateTime.now().millisecondsSinceEpoch;
      final name   = '${base}_edited_$ts.${widget.result.outputExtension}';
      final path   = p.join(outDir.path, name);
      final file   = File(path);
      if (widget.result.binaryContent != null) {
        await file.writeAsBytes(widget.result.binaryContent!);
      } else {
        await file.writeAsString(widget.result.textContent!, flush: true);
      }
      if (mounted) setState(() { _state = _SaveState.saved; _savedPath = path; });
    } catch (e) {
      if (mounted) setState(() { _state = _SaveState.error; _errorMsg = e.toString(); });
    }
  }

  Future<Directory> _resolveOutputDirectory() async {
    try {
      final dir = Directory('/storage/emulated/0/Download/KanMonAI');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final t = File(p.join(dir.path, '.wtest'));
      t.writeAsStringSync('ok');
      t.deleteSync();
      return dir;
    } catch (_) {
      final docs = await getApplicationDocumentsDirectory();
      final dir  = Directory(p.join(docs.path, 'exports'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    }
  }

  Future<void> _shareFile() async {
    final path = _savedPath;
    if (path == null) return;
    try {
      await Share.shareXFiles([XFile(path)], subject: widget.result.description);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membagikan: $e')),
        );
      }
    }
  }

  Future<void> _copyContent() async {
    final text = widget.result.textContent;
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konten disalin ke clipboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = KMColors.of(context);
    return switch (_state) {
      _SaveState.saved  => _buildSaved(c),
      _SaveState.error  => _buildError(c),
      _SaveState.saving => _buildSaving(c),
      _SaveState.idle   => _buildIdle(c),
    };
  }

  Widget _buildIdle(KMColors c) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: _saveFile,
              icon: const Icon(Icons.save_alt_rounded, size: 16),
              label: const Text('💾 Simpan Hasil Edit', style: TextStyle(fontSize: 13)),
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            if (widget.result.textContent != null) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _copyContent,
                icon: Icon(Icons.copy_rounded, size: 14, color: c.accent),
                label: Text('Salin', style: TextStyle(fontSize: 12, color: c.accent)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.accent,
                  side: BorderSide(color: c.accent.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 2, top: 4),
          child: Text(widget.result.description,
              style: TextStyle(color: c.textSecondary, fontSize: 11)),
        ),
      ],
    ),
  );

  Widget _buildSaving(KMColors c) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 14, height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)),
        const SizedBox(width: 8),
        Text('Menyimpan...', style: TextStyle(color: c.textSecondary, fontSize: 13)),
      ],
    ),
  );

  Widget _buildSaved(KMColors c) => Container(
    margin: const EdgeInsets.only(top: 6, bottom: 2),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: c.correct.withOpacity(0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: c.correct.withOpacity(0.3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_outline_rounded, color: c.correct, size: 18),
        const SizedBox(width: 6),
        Flexible(
          child: Text(p.basename(_savedPath ?? ''),
              style: TextStyle(color: c.correct, fontSize: 12),
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 10),
        TextButton.icon(
          onPressed: _shareFile,
          icon: Icon(Icons.share_rounded, size: 15, color: c.accent),
          label: Text('Bagikan', style: TextStyle(color: c.accent, fontSize: 12)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    ),
  );

  Widget _buildError(KMColors c) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('⚠️ Gagal menyimpan: ${_errorMsg ?? "unknown"}',
            style: TextStyle(color: c.wrong, fontSize: 12)),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: _saveFile,
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text('Coba Lagi', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            if (widget.result.textContent != null) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _copyContent,
                icon: Icon(Icons.copy_rounded, size: 14, color: c.accent),
                label: Text('Salin', style: TextStyle(fontSize: 12, color: c.accent)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.accent,
                  side: BorderSide(color: c.accent.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

enum _SaveState { idle, saving, saved, error }
