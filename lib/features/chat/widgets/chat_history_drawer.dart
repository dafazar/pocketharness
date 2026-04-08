// lib/features/chat/widgets/chat_history_drawer.dart
// KanMonAI — Chat History Drawer (Sesi 3)
// Menampilkan daftar sesi chat tersimpan, dikelompokkan per waktu.
// Mendukung: tap untuk load, rename, delete, hapus semua.
// =============================================================================

import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/data/models/chat_models.dart';
import 'package:kanmongo/data/services/ai_service.dart';
import 'package:kanmongo/data/services/history_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ChatHistoryDrawer
// ─────────────────────────────────────────────────────────────────────────────

class ChatHistoryDrawer extends StatefulWidget {
  final ChatSession currentSession;
  final void Function(ChatSession) onSessionSelected;
  final VoidCallback onNewChat;

  const ChatHistoryDrawer({
    super.key,
    required this.currentSession,
    required this.onSessionSelected,
    required this.onNewChat,
  });

  @override
  State<ChatHistoryDrawer> createState() => _ChatHistoryDrawerState();
}

class _ChatHistoryDrawerState extends State<ChatHistoryDrawer> {
  List<ChatSession> _sessions = [];
  bool _isLoading = true;
  // Grouped by label: LinkedHashMap agar urutan terjaga
  LinkedHashMap<String, List<ChatSession>> _grouped = LinkedHashMap();

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final sessions = await HistoryService.instance.loadAllChatSessions();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _grouped = _groupByDate(sessions);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[ChatHistoryDrawer] _loadSessions error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  LinkedHashMap<String, List<ChatSession>> _groupByDate(
      List<ChatSession> sessions) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));
    final monthAgo = today.subtract(const Duration(days: 30));

    final result = LinkedHashMap<String, List<ChatSession>>();
    for (final s in sessions) {
      final d = DateTime(
          s.updatedAt.year, s.updatedAt.month, s.updatedAt.day);
      String key;
      if (d == today) {
        key = 'Hari Ini';
      } else if (d == yesterday) {
        key = 'Kemarin';
      } else if (d.isAfter(weekAgo)) {
        key = 'Minggu Ini';
      } else if (d.isAfter(monthAgo)) {
        key = 'Bulan Ini';
      } else {
        key = 'Lebih Lama';
      }
      result.putIfAbsent(key, () => []).add(s);
    }
    return result;
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mnt lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    if (diff.inDays == 1) return 'Kemarin';
    return DateFormat('d MMM yyyy', 'id_ID').format(dt);
  }

  Future<void> _renameSession(ChatSession s) async {
    final ctrl = TextEditingController(text: s.title);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ganti Nama Sesi'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Nama sesi...',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (confirmed == true && ctrl.text.trim().isNotEmpty) {
      try {
        await HistoryService.instance
            .updateSessionTitle(s.id, ctrl.text.trim());
        _loadSessions();
      } catch (e) {
        debugPrint('[ChatHistoryDrawer] rename error: $e');
      }
    }
    ctrl.dispose();
  }

  Future<void> _deleteSession(ChatSession s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Sesi?'),
        content: Text('Sesi "${s.title}" akan dihapus permanen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await HistoryService.instance.deleteChatSession(s.id);
        _loadSessions();
      } catch (e) {
        debugPrint('[ChatHistoryDrawer] delete error: $e');
      }
    }
  }

  Future<void> _confirmDeleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Semua Riwayat?'),
        content: const Text(
            'Seluruh riwayat chat akan dihapus permanen dan tidak bisa dikembalikan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus Semua'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        for (final s in _sessions) {
          await HistoryService.instance.deleteChatSession(s.id);
        }
        _loadSessions();
      } catch (e) {
        debugPrint('[ChatHistoryDrawer] deleteAll error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    final maxWidth =
        MediaQuery.sizeOf(context).width * 0.82;
    final drawerWidth = maxWidth > 320.0 ? 320.0 : maxWidth;

    return Drawer(
      width: drawerWidth,
      backgroundColor: c.bg,
      child: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text(
                    'Riwayat Chat',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: c.text,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.edit_rounded, color: c.textMuted,
                        size: 20),
                    tooltip: 'Chat Baru',
                    onPressed: () {
                      widget.onNewChat();
                      Navigator.pop(context);
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: c.textMuted,
                        size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // ── Tombol Chat Baru ────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add_comment_rounded, size: 18),
                label: const Text('Mulai Chat Baru'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  widget.onNewChat();
                  Navigator.pop(context);
                },
              ),
            ),

            Divider(color: c.border, height: 16),

            // ── Daftar Sesi ─────────────────────────────────────────────────
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _sessions.isEmpty
                      ? _buildEmptyState(c)
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 8),
                          children: [
                            for (final entry in _grouped.entries) ...[
                              _SectionHeader(label: entry.key),
                              for (final session in entry.value)
                                _SessionTile(
                                  session: session,
                                  isSelected: session.id ==
                                      widget.currentSession.id,
                                  relativeTime: _relativeTime(
                                      session.updatedAt),
                                  onTap: () {
                                    widget.onSessionSelected(session);
                                    Navigator.pop(context);
                                  },
                                  onRename: () => _renameSession(session),
                                  onDelete: () => _deleteSession(session),
                                ),
                            ],
                          ],
                        ),
            ),

            Divider(color: c.border, height: 1),

            // ── Footer: Hapus Semua ─────────────────────────────────────────
            if (_sessions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton.icon(
                  icon: const Icon(Icons.delete_sweep_rounded,
                      color: Colors.red, size: 18),
                  label: const Text(
                    'Hapus Semua Riwayat',
                    style: TextStyle(color: Colors.red),
                  ),
                  onPressed: _confirmDeleteAll,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(KmColors c) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded,
                size: 52, color: c.textMuted),
            const SizedBox(height: 12),
            Text('Belum ada riwayat',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.text)),
            const SizedBox(height: 6),
            Text('Percakapan akan tersimpan di sini.',
                style: TextStyle(color: c.textMuted, fontSize: 13)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _SectionHeader
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: c.textMuted,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SessionTile
// ─────────────────────────────────────────────────────────────────────────────

class _SessionTile extends StatelessWidget {
  final ChatSession session;
  final bool isSelected;
  final String relativeTime;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _SessionTile({
    required this.session,
    required this.isSelected,
    required this.relativeTime,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        selected: isSelected,
        selectedColor: c.accent,
        selectedTileColor: c.accent.withOpacity(0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Text(
          _aiModeEmoji(session.lastAiMode),
          style: const TextStyle(fontSize: 18),
        ),
        title: Text(
          session.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: c.text,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (session.preview.isNotEmpty)
              Text(
                session.preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.textMuted),
              ),
            Text(
              relativeTime,
              style: TextStyle(fontSize: 11, color: c.textMuted),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: c.textMuted, size: 18),
          padding: EdgeInsets.zero,
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'rename',
              child: Row(children: [
                Icon(Icons.drive_file_rename_outline_rounded,
                    size: 18, color: c.text),
                const SizedBox(width: 10),
                const Text('Ganti Nama'),
              ]),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(children: [
                const Icon(Icons.delete_outlined, size: 18,
                    color: Colors.red),
                const SizedBox(width: 10),
                const Text('Hapus', style: TextStyle(color: Colors.red)),
              ]),
            ),
          ],
          onSelected: (val) {
            if (val == 'rename') onRename();
            if (val == 'delete') onDelete();
          },
        ),
        onTap: onTap,
      ),
    );
  }

  String _aiModeEmoji(AiMode? mode) {
    switch (mode) {
      case AiMode.offline:
        return '💾';
      case AiMode.online:
        return '🌐';
      case AiMode.bulkApi:
        return '⚡';
      case AiMode.none:
      case null:
        return '💬';
    }
  }
}
