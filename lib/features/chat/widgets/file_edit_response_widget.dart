// lib/features/chat/widgets/file_edit_response_widget.dart
// KanMonAI — File Edit Response Widget (Enhanced v2.0) [EDITED]
//
// PERUBAHAN dari v1.0:
//   • Save path → /storage/emulated/0/Download/ompre/  (bukan KanMonAI)
//   • Bubble animasi muncul setelah AI selesai edit file (ScaleTransition elasticOut)
//   • Tombol Simpan ke Download/ompre + Salin + Bagikan
//   • State: idle → saving → saved (dengan path info) / error (retry)
//   • Fallback path: /sdcard/Download/ompre/ → app documents/exports/ompre/

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/shared/utils/top_snack.dart';

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
// WIDGET — Save/Download Bubble (Animated)
// ─────────────────────────────────────────────────────────────────────────────

class FileEditResponseWidget extends StatefulWidget {
  final FileEditResult result;
  const FileEditResponseWidget({super.key, required this.result});

  @override
  State<FileEditResponseWidget> createState() => _FileEditResponseWidgetState();
}

class _FileEditResponseWidgetState extends State<FileEditResponseWidget>
    with SingleTickerProviderStateMixin {
  _SaveState _state = _SaveState.idle;
  String? _savedPath;
  String? _errorMsg;
  late AnimationController _bubbleAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _bubbleAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _scaleAnim = CurvedAnimation(parent: _bubbleAnim, curve: Curves.elasticOut);
    // [EDITED] Auto-show bubble dengan animasi setelah frame pertama
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bubbleAnim.forward();
    });
  }

  @override
  void dispose() {
    _bubbleAnim.dispose();
    super.dispose();
  }

  // ── [EDITED] Output directory: /storage/emulated/0/Download/ompre/ ────────

  Future<Directory> _resolveOutputDirectory() async {
    // Primary: /storage/emulated/0/Download/ompre/
    try {
      final dir = Directory('/storage/emulated/0/Download/ompre');
      if (!dir.existsSync()) await dir.create(recursive: true);
      final testFile = File(
          '${dir.path}/.wtest_${DateTime.now().millisecondsSinceEpoch}');
      await testFile.writeAsString('ok');
      await testFile.delete();
      return dir;
    } catch (_) {}

    // Fallback 1: /sdcard/Download/ompre/
    try {
      final dir = Directory('/sdcard/Download/ompre');
      if (!dir.existsSync()) await dir.create(recursive: true);
      final testFile = File(
          '${dir.path}/.wtest_${DateTime.now().millisecondsSinceEpoch}');
      await testFile.writeAsString('ok');
      await testFile.delete();
      return dir;
    } catch (_) {}

    // Fallback 2: App documents/exports/ompre/
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/exports/ompre');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _saveFile() async {
    if (_state == _SaveState.saving) return;
    if (!mounted) return;
    setState(() {
      _state = _SaveState.saving;
      _errorMsg = null;
    });
    try {
      final outDir = await _resolveOutputDirectory();
      final base =
          p.basenameWithoutExtension(widget.result.originalFilename);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final name = '${base}_edited_$ts.${widget.result.outputExtension}';
      final path = p.join(outDir.path, name);
      final file = File(path);

      if (widget.result.binaryContent != null) {
        await file.writeAsBytes(widget.result.binaryContent!);
      } else {
        await file.writeAsString(widget.result.textContent!, flush: true);
      }

      if (mounted) {
        setState(() {
          _state = _SaveState.saved;
          _savedPath = path;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _SaveState.error;
          _errorMsg = e.toString();
        });
      }
    }
  }

  Future<void> _shareFile() async {
    final path = _savedPath;
    if (path == null) return;
    try {
      await Share.shareXFiles(
        [XFile(path)],
        subject: widget.result.description,
      );
    } catch (e) {
      if (mounted) showTopSnack(context, 'Gagal berbagi: $e', isError: true);
    }
  }

  Future<void> _copyContent() async {
    final text = widget.result.textContent;
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showTopSnack(context, '✅ Konten disalin ke clipboard');
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return ScaleTransition(
      scale: _scaleAnim,
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _state == _SaveState.saved
                ? c.correct.withOpacity(0.5)
                : c.accent.withOpacity(0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: switch (_state) {
          _SaveState.idle => _buildIdle(c),
          _SaveState.saving => _buildSaving(c),
          _SaveState.saved => _buildSaved(c),
          _SaveState.error => _buildError(c),
        },
      ),
    );
  }

  // ── STATE VIEWS ────────────────────────────────────────────────────────────

  Widget _buildIdle(KmColors c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.file_present_rounded, size: 15, color: c.accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.result.originalFilename,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: _saveFile,
                icon: const Icon(Icons.download_rounded, size: 15),
                label: const Text('💾 Simpan ke Download/ompre',
                    style: TextStyle(fontSize: 13)),
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (widget.result.textContent != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _copyContent,
                  icon: Icon(Icons.copy_rounded, size: 14, color: c.accent),
                  label: Text('Salin',
                      style: TextStyle(fontSize: 12, color: c.accent)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.accent,
                    side: BorderSide(color: c.accent.withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 4),
            child: Text(
              widget.result.description,
              style: TextStyle(color: c.textSub, fontSize: 11),
            ),
          ),
        ],
      );

  Widget _buildSaving(KmColors c) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: c.accent)),
            const SizedBox(width: 8),
            Text('Menyimpan ke ompre...',
                style: TextStyle(color: c.textSub, fontSize: 13)),
          ],
        ),
      );

  Widget _buildSaved(KmColors c) => Container(
        margin: const EdgeInsets.only(top: 6, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: c.correct.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.correct.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline_rounded,
                    color: c.correct, size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    p.basename(_savedPath ?? ''),
                    style: TextStyle(
                        color: c.correct,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 24),
              child: Text(
                'Tersimpan di: Download/ompre/',
                style: TextStyle(color: c.textSub, fontSize: 10),
              ),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: _shareFile,
              icon: Icon(Icons.share_rounded, size: 15, color: c.accent),
              label: Text('Bagikan',
                  style: TextStyle(color: c.accent, fontSize: 12)),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
              Icon(Icons.error_outline_rounded, color: c.wrong, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Gagal menyimpan ke ompre',
                  style: TextStyle(
                    color: c.wrong,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (_errorMsg != null)
            Padding(
              padding: const EdgeInsets.only(top: 3, bottom: 6),
              child: Text(
                _errorMsg!,
                style: TextStyle(color: c.textSub, fontSize: 10),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: _saveFile,
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label:
                    const Text('Coba Lagi', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (widget.result.textContent != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _copyContent,
                  icon: Icon(Icons.copy_rounded, size: 14, color: c.accent),
                  label: Text('Salin',
                      style: TextStyle(fontSize: 12, color: c.accent)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.accent,
                    side: BorderSide(color: c.accent.withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ],
          ),
        ],
      );
}

enum _SaveState { idle, saving, saved, error }
