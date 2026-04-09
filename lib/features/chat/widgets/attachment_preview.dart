// lib/features/chat/widgets/attachment_preview.dart
// KanMonAI — Attachment Preview Widget (Sesi 2)
// Merender setiap jenis attachment secara berbeda
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';

import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/data/models/chat_models.dart';
import 'package:kanmongo/shared/utils/top_snack.dart';

class AttachmentPreview extends StatelessWidget {
  final ChatAttachment attachment;
  final bool isUserBubble;

  const AttachmentPreview({
    super.key,
    required this.attachment,
    this.isUserBubble = true,
  });

  @override
  Widget build(BuildContext context) {
    switch (attachment.type) {
      case AttachmentType.image:
        return _ImagePreview(attachment: attachment);
      case AttachmentType.video:
        return _VideoPreview(attachment: attachment);
      case AttachmentType.audio:
        return _AudioPreview(attachment: attachment);
      case AttachmentType.pdf:
      case AttachmentType.word:
      case AttachmentType.excel:
      case AttachmentType.powerpoint:
        return _DocumentPreview(attachment: attachment);
      case AttachmentType.code:
        return _CodePreview(attachment: attachment);
      case AttachmentType.text:
        return _TextPreview(attachment: attachment);
      case AttachmentType.archive:
        return _ArchivePreview(attachment: attachment);
      case AttachmentType.other:
        return _OtherPreview(attachment: attachment);
    }
  }
}

// ── Image Preview ──────────────────────────────────────────────────────────────

class _ImagePreview extends StatelessWidget {
  final ChatAttachment attachment;
  const _ImagePreview({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final kfc   = KmColors.of(context);
    final thumb = attachment.thumbnailBytes;

    return GestureDetector(
      onTap: () => _openFullscreen(context),
      child: Hero(
        tag: 'img_${attachment.id}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 220,
            height: 160,
            child: Stack(
              fit: StackFit.expand,
              children: [
                thumb != null
                    ? Image.memory(thumb, fit: BoxFit.cover)
                    : Container(
                        color: kfc.surface,
                        child: Icon(
                          Icons.image_not_supported_rounded,
                          color: kfc.textSub,
                          size: 40,
                        ),
                      ),
                // Gradient overlay at bottom
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.5),
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            attachment.filename,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.open_in_full_rounded,
                            color: Colors.white.withValues(alpha: 0.8),
                            size: 14),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _FullscreenImageViewer(attachment: attachment),
    ));
  }
}

// ── Fullscreen Image Viewer ────────────────────────────────────────────────────

class _FullscreenImageViewer extends StatefulWidget {
  final ChatAttachment attachment;
  const _FullscreenImageViewer({required this.attachment});

  @override
  State<_FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<_FullscreenImageViewer> {
  final _transformCtrl = TransformationController();
  bool _showUI = true;

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thumb = widget.attachment.thumbnailBytes;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showUI = !_showUI),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Zoomable image
            Center(
              child: Hero(
                tag: 'img_${widget.attachment.id}',
                child: InteractiveViewer(
                  transformationController: _transformCtrl,
                  minScale: 0.5,
                  maxScale: 8.0,
                  child: thumb != null
                      ? Image.memory(thumb, fit: BoxFit.contain)
                      : const Icon(Icons.broken_image_rounded,
                            color: Colors.white54, size: 80),
                ),
              ),
            ),
            // Top bar
            AnimatedOpacity(
              opacity: _showUI ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: SafeArea(
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        widget.attachment.filename,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Reset zoom
                    IconButton(
                      icon: const Icon(Icons.fit_screen_rounded,
                          color: Colors.white),
                      tooltip: 'Reset zoom',
                      onPressed: () =>
                          _transformCtrl.value = Matrix4.identity(),
                    ),
                    // Open with system app
                    if (widget.attachment.path.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.open_in_new_rounded,
                            color: Colors.white),
                        tooltip: 'Buka dengan aplikasi lain',
                        onPressed: () =>
                            OpenFile.open(widget.attachment.path),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Video Preview ──────────────────────────────────────────────────────────────

class _VideoPreview extends StatelessWidget {
  final ChatAttachment attachment;
  const _VideoPreview({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final kfc      = KmColors.of(context);
    final thumb    = attachment.thumbnailBytes;
    final duration = attachment.videoDuration;

    return GestureDetector(
      onTap: () {
        if (attachment.path.isNotEmpty) {
          OpenFile.open(attachment.path);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 220,
          height: 130,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Thumbnail or fallback
              thumb != null
                  ? Image.memory(thumb, fit: BoxFit.cover)
                  : Container(
                      color: kfc.surface,
                      child: Icon(Icons.videocam_rounded,
                          color: kfc.textMuted, size: 40),
                    ),
              // Dark overlay
              Container(color: Colors.black.withValues(alpha: 0.3)),
              // Play button (center)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 28),
                ),
              ),
              // Duration badge (bottom right)
              if (duration != null)
                Positioned(
                  bottom: 6,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      duration,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              // Filename (bottom left)
              Positioned(
                bottom: 6,
                left: 8,
                right: duration != null ? 56 : 8,
                child: Text(
                  attachment.filename,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Audio Preview ──────────────────────────────────────────────────────────────

class _AudioPreview extends StatelessWidget {
  final ChatAttachment attachment;
  const _AudioPreview({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final kfc = KmColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kfc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kfc.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.audiotrack_rounded, color: kfc.accent, size: 28),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.filename,
                  style: TextStyle(
                    color: kfc.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  attachment.sizeLabel,
                  style: TextStyle(color: kfc.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (attachment.path.isNotEmpty) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.open_in_new_rounded, color: kfc.textSub, size: 18),
              onPressed: () => OpenFile.open(attachment.path),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Document Preview (PDF, Word, Excel, PowerPoint) ───────────────────────────

class _DocumentPreview extends StatelessWidget {
  final ChatAttachment attachment;
  const _DocumentPreview({required this.attachment});

  IconData get _icon {
    switch (attachment.type) {
      case AttachmentType.pdf:
        return Icons.picture_as_pdf_rounded;
      case AttachmentType.word:
        return Icons.description_rounded;
      case AttachmentType.excel:
        return Icons.table_chart_rounded;
      case AttachmentType.powerpoint:
        return Icons.slideshow_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _iconColor(KmColors kfc) {
    switch (attachment.type) {
      case AttachmentType.pdf:
        return Colors.red;
      case AttachmentType.word:
        return Colors.blue;
      case AttachmentType.excel:
        return Colors.green;
      case AttachmentType.powerpoint:
        return Colors.orange;
      default:
        return kfc.textSub;
    }
  }

  String get _typeLabel {
    switch (attachment.type) {
      case AttachmentType.pdf:
        return 'PDF';
      case AttachmentType.word:
        return 'Word';
      case AttachmentType.excel:
        return 'Excel';
      case AttachmentType.powerpoint:
        return 'PowerPoint';
      default:
        return 'Dokumen';
    }
  }

  @override
  Widget build(BuildContext context) {
    final kfc = KmColors.of(context);
    return Card(
      color: kfc.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: kfc.border),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, color: _iconColor(kfc), size: 32),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    attachment.filename,
                    style: TextStyle(
                      color: kfc.text,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${attachment.sizeLabel} • $_typeLabel',
                    style: TextStyle(color: kfc.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (attachment.path.isNotEmpty) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.open_in_new_rounded, color: kfc.textSub, size: 18),
                onPressed: () => OpenFile.open(attachment.path),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Code Preview ───────────────────────────────────────────────────────────────

class _CodePreview extends StatelessWidget {
  final ChatAttachment attachment;
  const _CodePreview({required this.attachment});

  String get _language {
    final ext = attachment.filename.split('.').last.toLowerCase();
    const langMap = {
      'dart': 'Dart', 'py': 'Python', 'js': 'JavaScript',
      'ts': 'TypeScript', 'java': 'Java', 'kt': 'Kotlin',
      'cpp': 'C++', 'c': 'C', 'h': 'C/C++ Header',
      'json': 'JSON', 'xml': 'XML', 'yaml': 'YAML', 'yml': 'YAML',
      'toml': 'TOML', 'sh': 'Shell', 'bash': 'Bash',
    };
    return langMap[ext] ?? ext.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final kfc = KmColors.of(context);
    final text = attachment.extractedText ?? '';
    final lines = text.split('\n');
    final preview = lines.take(5).join('\n');
    final hasMore = lines.length > 5;

    return Container(
      decoration: BoxDecoration(
        color: kfc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kfc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: kfc.card,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Icon(Icons.code_rounded, color: kfc.accent, size: 14),
                const SizedBox(width: 6),
                Text(
                  _language,
                  style: TextStyle(
                    color: kfc.textSub,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: text));
                    showTopSnack(context, 'Disalin ke clipboard', duration: const Duration(seconds: 1));
                  },
                  child: Icon(Icons.copy_rounded, color: kfc.textSub, size: 14),
                ),
              ],
            ),
          ),
          // Code preview
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              preview.isEmpty ? '(kosong)' : preview,
              style: TextStyle(
                fontFamily: 'monospace',
                color: kfc.text,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
          // "Lihat semua" tombol
          if (hasMore)
            TextButton(
              onPressed: () => _showFullCode(context, text, kfc),
              child: Text(
                'Lihat semua (${lines.length} baris)',
                style: TextStyle(color: kfc.accent, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  void _showFullCode(BuildContext context, String text, KmColors kfc) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: kfc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      attachment.filename,
                      style: TextStyle(
                        color: kfc.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: kfc.textSub),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: kfc.text,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Text Preview ───────────────────────────────────────────────────────────────

class _TextPreview extends StatelessWidget {
  final ChatAttachment attachment;
  const _TextPreview({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final kfc = KmColors.of(context);
    final text = attachment.extractedText ?? '';
    final lines = text.split('\n');
    final preview = lines.take(3).join('\n');
    final hasMore = lines.length > 3;

    return Container(
      decoration: BoxDecoration(
        color: kfc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kfc.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.article_rounded, color: kfc.textSub, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  attachment.filename,
                  style: TextStyle(
                    color: kfc.textSub,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            preview.isEmpty ? '(kosong)' : preview,
            style: TextStyle(color: kfc.text, fontSize: 13, height: 1.4),
          ),
          if (hasMore)
            TextButton(
              onPressed: () => _showFull(context, text, kfc),
              child: Text(
                'Lihat semua',
                style: TextStyle(color: kfc.accent, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  void _showFull(BuildContext context, String text, KmColors kfc) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: kfc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      attachment.filename,
                      style: TextStyle(
                        color: kfc.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: kfc.textSub),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  text,
                  style: TextStyle(color: kfc.text, fontSize: 14, height: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Archive Preview ────────────────────────────────────────────────────────────

class _ArchivePreview extends StatelessWidget {
  final ChatAttachment attachment;
  const _ArchivePreview({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final kfc = KmColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kfc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kfc.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_zip_outlined, color: kfc.gold, size: 28),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.filename,
                  style: TextStyle(
                    color: kfc.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  attachment.sizeLabel,
                  style: TextStyle(color: kfc.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Other Preview ──────────────────────────────────────────────────────────────

class _OtherPreview extends StatelessWidget {
  final ChatAttachment attachment;
  const _OtherPreview({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final kfc = KmColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kfc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kfc.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined, color: kfc.textSub, size: 28),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.filename,
                  style: TextStyle(
                    color: kfc.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  attachment.sizeLabel,
                  style: TextStyle(color: kfc.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
