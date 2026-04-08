// lib/features/chat/widgets/file_edit_response_widget.dart
// KanMon GO — File Edit Response Widget (Sesi 4)
//
// Deteksi pola diff / REPLACE-WITH dalam respons AI dan render:
//   • Diff view berwarna merah/hijau
//   • Tombol: Salin Kode / Terapkan ke File / Buat File Baru
// =============================================================================

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/features/chat/widgets/artifact_panel.dart';

// ── Satu baris diff ───────────────────────────────────────────────────────────
class _DiffLine {
  final String text;
  final int    type; // -1 hapus, 0 konteks, 1 tambah
  const _DiffLine(this.text, this.type);
}

// ── Widget utama ──────────────────────────────────────────────────────────────
class FileEditResponseWidget extends StatelessWidget {
  final String aiResponse;
  final ArtifactPanelController? artifactCtrl;

  const FileEditResponseWidget({
    super.key,
    required this.aiResponse,
    this.artifactCtrl,
  });

  static final _diffRegex    = RegExp(r'```diff\n([\s\S]+?)```',     multiLine: true);
  static final _fileRegex    = RegExp(r'(?:\/\/|#)\s*File:\s*(.+)\n', multiLine: true);
  static final _replaceRegex = RegExp(
    r'REPLACE:\n([\s\S]+?)\nWITH:\n([\s\S]+?)(?:\n---|$)',
    multiLine: true,
  );

  // ── Parse diff ────────────────────────────────────────────────────────────
  static List<_DiffLine> _parseDiff(String diffContent) {
    return diffContent.split('\n').map((line) {
      if (line.startsWith('+')) return _DiffLine(line, 1);
      if (line.startsWith('-')) return _DiffLine(line, -1);
      return _DiffLine(line, 0);
    }).toList();
  }

  // ── Extract code to apply ─────────────────────────────────────────────────
  // Returns the "new" content: lines from diff with '+', or 'WITH' block.
  static String _extractNewContent(String response) {
    // Try diff first
    final diffMatch = _diffRegex.firstMatch(response);
    if (diffMatch != null) {
      final lines = diffMatch.group(1)!.split('\n');
      return lines
          .where((l) => !l.startsWith('-') && !l.startsWith('@@'))
          .map((l) => l.startsWith('+') ? l.substring(1) : l)
          .join('\n');
    }
    // Try REPLACE/WITH
    final replMatch = _replaceRegex.firstMatch(response);
    if (replMatch != null) {
      return replMatch.group(2) ?? '';
    }
    // Fallback: return entire response
    return response;
  }

  // ── Apply to file ─────────────────────────────────────────────────────────
  Future<void> _applyToFile(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result == null || result.files.single.path == null) return;
      final path    = result.files.single.path!;
      final oldText = await File(path).readAsString();
      final newText = _extractNewContent(aiResponse);

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Terapkan Perubahan'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('File: $path', style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                const Text('Sebelum:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: SingleChildScrollView(
                    child: Text(
                      oldText.length > 500 ? '${oldText.substring(0, 500)}...' : oldText,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Sesudah:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: SingleChildScrollView(
                    child: Text(
                      newText.length > 500 ? '${newText.substring(0, 500)}...' : newText,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Terapkan'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      await File(path).writeAsString(newText);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Berhasil diterapkan ke $path')),
        );
      }
    } catch (e) {
      debugPrint('[FileEditWidget] _applyToFile error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Gagal: $e')),
        );
      }
    }
  }

  // ── Save as new file ──────────────────────────────────────────────────────
  Future<void> _saveAsNewFile(BuildContext context) async {
    try {
      final newText = _extractNewContent(aiResponse);
      final path    = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan sebagai file baru',
        fileName: 'edited_file.txt',
      );
      if (path == null) return;
      await File(path).writeAsString(newText);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Disimpan ke $path')),
        );
      }
    } catch (e) {
      debugPrint('[FileEditWidget] _saveAsNewFile error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Gagal: $e')),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);

    // Deteksi apakah ada diff atau replace pattern
    final hasDiff    = _diffRegex.hasMatch(aiResponse);
    final hasReplace = _replaceRegex.hasMatch(aiResponse);

    if (!hasDiff && !hasReplace) return const SizedBox.shrink();

    // Ambil nama file dari komentar jika ada
    final fileMatch = _fileRegex.firstMatch(aiResponse);
    final fileName  = fileMatch?.group(1)?.trim();

    // Parse diff lines jika ada
    List<_DiffLine> diffLines = [];
    if (hasDiff) {
      final dm = _diffRegex.firstMatch(aiResponse);
      if (dm != null) diffLines = _parseDiff(dm.group(1)!);
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(
              children: [
                Icon(Icons.edit_document, color: c.accent, size: 18),
                const SizedBox(width: 8),
                Text(
                  '📝 Perubahan Disarankan',
                  style: TextStyle(
                    color: c.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                if (fileName != null)
                  Text(
                    fileName,
                    style: TextStyle(
                      color: c.accent,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Diff view ─────────────────────────────────────────────────
          if (diffLines.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: diffLines.map((dl) {
                    Color bg;
                    Color fg;
                    switch (dl.type) {
                      case 1:
                        bg = Colors.green.withOpacity(0.15);
                        fg = const Color(0xFF6EBF8B);
                        break;
                      case -1:
                        bg = Colors.red.withOpacity(0.15);
                        fg = const Color(0xFFFF7070);
                        break;
                      default:
                        bg = Colors.transparent;
                        fg = c.onSurface.withOpacity(0.75);
                    }
                    return Container(
                      color: bg,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
                      child: Text(
                        dl.text,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: fg,
                          height: 1.5,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            )
          else if (hasReplace)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Text(
                'Pola REPLACE/WITH terdeteksi.',
                style: TextStyle(color: c.onSurface.withOpacity(0.6), fontSize: 12),
              ),
            ),

          const Divider(height: 1),

          // ── Footer buttons ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: _extractNewContent(aiResponse)));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Kode disalin!'),
                          duration: Duration(seconds: 2)),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: const Text('Salin Kode'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.onSurface,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _applyToFile(context),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 14),
                  label: const Text('Terapkan ke File'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _saveAsNewFile(context),
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 14),
                  label: const Text('Buat File Baru'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
                if (artifactCtrl != null)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: const Text('Buka di Panel'),
                    onPressed: () {
                      final isDiff = _diffRegex.hasMatch(aiResponse);
                      final content = isDiff
                          ? (_diffRegex.firstMatch(aiResponse)?.group(1) ?? aiResponse)
                          : aiResponse;
                      final filename = _fileRegex.firstMatch(aiResponse)?.group(1)?.trim()
                          ?? 'patch_${DateTime.now().millisecondsSinceEpoch}.diff';
                      artifactCtrl!.push(ArtifactItem(
                        mode:     ArtifactMode.file,
                        title:    filename.split('/').last,
                        language: 'diff',
                        content:  content,
                      ));
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
