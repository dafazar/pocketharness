// lib/features/chat/widgets/file_output_card.dart
// PocketHarness — Smart File Output Card
//
// Displays a list of SmartFileOutput items extracted from AI responses.
// Each item can be saved to Download/ompre/, copied, or shared.
// Shows animated entry, save state (idle/saving/saved/error).
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'package:pocketharness/core/theme/km_colors.dart';
import 'package:pocketharness/data/services/smart_file_output_service.dart';
import 'package:pocketharness/shared/utils/top_snack.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MAIN CARD
// ─────────────────────────────────────────────────────────────────────────────

class FileOutputCard extends StatefulWidget {
  final List<SmartFileOutput> outputs;

  const FileOutputCard({super.key, required this.outputs});

  @override
  State<FileOutputCard> createState() => _FileOutputCardState();
}

class _FileOutputCardState extends State<FileOutputCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _scale = CurvedAnimation(parent: _anim, curve: Curves.elasticOut);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _anim.forward();
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return ScaleTransition(
      scale: _scale,
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 4),
        decoration: BoxDecoration(
          color: c.surface.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.accent.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  Icon(Icons.file_download_outlined, size: 16, color: c.accent),
                  const SizedBox(width: 6),
                  Text(
                    widget.outputs.length == 1
                        ? 'File siap diunduh'
                        : '${widget.outputs.length} file siap diunduh',
                    style: TextStyle(
                      color: c.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.5),
            // Output items
            ...widget.outputs.map((output) => _FileOutputItem(output: output)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SINGLE FILE ITEM
// ─────────────────────────────────────────────────────────────────────────────

enum _ItemState { idle, saving, saved, error }

class _FileOutputItem extends StatefulWidget {
  final SmartFileOutput output;
  const _FileOutputItem({required this.output});

  @override
  State<_FileOutputItem> createState() => _FileOutputItemState();
}

class _FileOutputItemState extends State<_FileOutputItem> {
  _ItemState _state = _ItemState.idle;
  String? _savedPath;
  String? _errorMsg;

  // ── Icon per language ──────────────────────────────────────────────────────

  IconData _langIcon(String lang) {
    switch (lang) {
      case 'dart':       return Icons.flutter_dash;
      case 'python':
      case 'py':         return Icons.code;
      case 'javascript':
      case 'js':
      case 'typescript':
      case 'ts':         return Icons.javascript;
      case 'html':       return Icons.html;
      case 'css':        return Icons.css;
      case 'json':
      case 'yaml':
      case 'yml':        return Icons.data_object;
      case 'sql':        return Icons.storage;
      case 'shell':
      case 'bash':
      case 'sh':         return Icons.terminal;
      case 'markdown':
      case 'md':         return Icons.article_outlined;
      default:           return Icons.insert_drive_file_outlined;
    }
  }

  // ── Save to Download/ompre/ ────────────────────────────────────────────────

  Future<void> _saveFile() async {
    if (_state == _ItemState.saving) return;
    if (!mounted) return;
    setState(() {
      _state    = _ItemState.saving;
      _errorMsg = null;
    });
    try {
      final dir = await SmartFileOutputService.instance.resolveOutputDirectory();
      final ts   = DateTime.now().millisecondsSinceEpoch;
      final base = p.basenameWithoutExtension(widget.output.filename);
      final ext  = widget.output.extension;
      final name = '${base}_$ts.$ext';
      final path = p.join(dir.path, name);
      await File(path).writeAsString(widget.output.content, flush: true);
      if (mounted) setState(() { _state = _ItemState.saved; _savedPath = path; });
    } catch (e) {
      if (mounted) setState(() { _state = _ItemState.error; _errorMsg = e.toString(); });
    }
  }

  Future<void> _copyContent() async {
    await Clipboard.setData(ClipboardData(text: widget.output.content));
    if (mounted) showTopSnack(context, '✅ Kode disalin ke clipboard');
  }

  Future<void> _shareFile() async {
    final path = _savedPath;
    if (path == null) return;
    try {
      await Share.shareXFiles(
        [XFile(path)],
        subject: widget.output.filename,
      );
    } catch (e) {
      if (mounted) showTopSnack(context, 'Gagal berbagi: $e', isError: true);
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: switch (_state) {
        _ItemState.idle    => _buildIdle(c),
        _ItemState.saving  => _buildSaving(c),
        _ItemState.saved   => _buildSaved(c),
        _ItemState.error   => _buildError(c),
      },
    );
  }

  Widget _buildIdle(KmColors c) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // File icon + info
          Icon(_langIcon(widget.output.language), size: 20, color: c.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.output.filename,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${widget.output.language.toUpperCase()}  •  '
                  '${widget.output.content.split('\n').length} baris',
                  style: TextStyle(color: c.textSub, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Copy button
          InkWell(
            onTap: _copyContent,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.copy_rounded, size: 16, color: c.textSub),
            ),
          ),
          const SizedBox(width: 4),
          // Save button
          FilledButton.icon(
            onPressed: _saveFile,
            icon: const Icon(Icons.download_rounded, size: 14),
            label: const Text('Simpan', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      );

  Widget _buildSaving(KmColors c) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
          ),
          const SizedBox(width: 8),
          Text(
            'Menyimpan ${widget.output.filename}…',
            style: TextStyle(color: c.textSub, fontSize: 12),
          ),
        ],
      );

  Widget _buildSaved(KmColors c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: c.correct.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.correct.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: c.correct, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.basename(_savedPath ?? widget.output.filename),
                    style: TextStyle(
                      color: c.correct,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Download/ompre/',
                    style: TextStyle(color: c.textSub, fontSize: 10),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: _shareFile,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.share_rounded, size: 16, color: c.accent),
              ),
            ),
          ],
        ),
      );

  Widget _buildError(KmColors c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: c.wrong, size: 15),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Gagal menyimpan',
                  style: TextStyle(
                      color: c.wrong, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (_errorMsg != null)
            Text(
              _errorMsg!,
              style: TextStyle(color: c.textSub, fontSize: 10),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: _saveFile,
                icon: const Icon(Icons.refresh_rounded, size: 13),
                label: const Text('Coba Lagi', style: TextStyle(fontSize: 11)),
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _copyContent,
                icon: Icon(Icons.copy_rounded, size: 13, color: c.accent),
                label: Text('Salin', style: TextStyle(color: c.accent, fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: c.accent.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ],
      );
}
