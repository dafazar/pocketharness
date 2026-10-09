// lib/features/chat/widgets/attachment_chip_row.dart
// PocketHarness — Attachment Chip Row (SESI 6B-i)
//
// Fitur:
//   • AnimatedList: slide-in dari kanan (250ms easeOut)
//   • Hapus: SizeTransition + FadeTransition (200ms easeIn)
//   • Overflow: tampil 4 chip + chip "+N lagi" jika > 5 attachment
//   • Long press gambar → fullscreen preview (Scaffold hitam)
//   • Chip gambar: thumbnail Image.file 40×40 radius 4
//   • Chip non-gambar: icon emoji + nama truncate 15 char
//   • Tombol X per chip dengan animasi keluar
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:pocketharness/core/theme/km_colors.dart';
import 'package:pocketharness/data/models/chat_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AttachmentChipRow
// ─────────────────────────────────────────────────────────────────────────────

class AttachmentChipRow extends StatefulWidget {
  final List<ChatAttachment> attachments;
  final void Function(int index) onRemove;

  const AttachmentChipRow({
    super.key,
    required this.attachments,
    required this.onRemove,
  });

  @override
  State<AttachmentChipRow> createState() => AttachmentChipRowState();
}

class AttachmentChipRowState extends State<AttachmentChipRow> {
  final _listKey = GlobalKey<AnimatedListState>();

  // ── Tambah item dengan animasi slide-in ────────────────────────────────────
  void addItem(int index) {
    _listKey.currentState?.insertItem(
      index,
      duration: const Duration(milliseconds: 250),
    );
  }

  // ── Hapus item dengan animasi shrink + fade ────────────────────────────────
  void removeItem(int index, ChatAttachment attachment) {
    _listKey.currentState?.removeItem(
      index,
      (context, animation) => _buildRemovedChip(context, attachment, animation),
      duration: const Duration(milliseconds: 200),
    );
  }

  Widget _buildRemovedChip(
    BuildContext context,
    ChatAttachment attachment,
    Animation<double> animation,
  ) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeIn),
      axis: Axis.horizontal,
      child: FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
        child: _buildChipContent(context, attachment, -1, isRemoving: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.attachments.length;
    // Tentukan berapa chip yang ditampilkan via AnimatedList
    final displayCount = total > 5 ? 4 : total;
    final overflowCount = total > 5 ? total - 4 : 0;

    return SizedBox(
      height: 72,
      child: Row(
        children: [
          Expanded(
            child: AnimatedList(
              key: _listKey,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              initialItemCount: displayCount,
              itemBuilder: (context, index, animation) {
                if (index >= displayCount) return const SizedBox.shrink();
                final attachment = widget.attachments[index];
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOut,
                  )),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _buildChipContent(context, attachment, index),
                  ),
                );
              },
            ),
          ),
          // Chip "+N lagi" jika overflow
          if (overflowCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
              child: _OverflowChip(count: overflowCount),
            ),
        ],
      ),
    );
  }

  Widget _buildChipContent(
    BuildContext context,
    ChatAttachment attachment,
    int index, {
    bool isRemoving = false,
  }) {
    final kfc = KmColors.of(context);
    final isImage = attachment.type == AttachmentType.image;

    return GestureDetector(
      onLongPress: isImage && !isRemoving
          ? () => _openFullscreen(context, attachment)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: kfc.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kfc.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thumbnail atau icon
            if (isImage)
              _ImageThumbnail(path: attachment.path)
            else
              Text(attachment.icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            // Nama file truncated
            Text(
              _truncate(attachment.filename),
              style: TextStyle(
                color: kfc.text,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 2),
            // Tombol X
            if (!isRemoving)
              GestureDetector(
                onTap: () => widget.onRemove(index),
                child: Icon(Icons.close, size: 14, color: kfc.textSub),
              ),
          ],
        ),
      ),
    );
  }

  String _truncate(String name) {
    return name.length > 15 ? '${name.substring(0, 13)}…' : name;
  }

  void _openFullscreen(BuildContext context, ChatAttachment attachment) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullscreenImagePreview(path: attachment.path),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Image Thumbnail (40×40, radius 4)
// ─────────────────────────────────────────────────────────────────────────────

class _ImageThumbnail extends StatelessWidget {
  final String path;
  const _ImageThumbnail({required this.path});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 40,
        height: 40,
        child: path.isNotEmpty
            ? Image.file(
                File(path),
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_rounded,
                  size: 20,
                ),
              )
            : const Icon(Icons.image_rounded, size: 20),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overflow Chip "+N lagi"
// ─────────────────────────────────────────────────────────────────────────────

class _OverflowChip extends StatelessWidget {
  final int count;
  const _OverflowChip({required this.count});

  @override
  Widget build(BuildContext context) {
    final kfc = KmColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: kfc.accent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '+$count lagi',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fullscreen Image Preview
// ─────────────────────────────────────────────────────────────────────────────

class _FullscreenImagePreview extends StatelessWidget {
  final String path;
  const _FullscreenImagePreview({required this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Center(
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.broken_image_rounded,
            color: Colors.white,
            size: 64,
          ),
        ),
      ),
    );
  }
}
