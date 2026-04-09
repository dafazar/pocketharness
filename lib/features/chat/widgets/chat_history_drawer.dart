// lib/features/chat/widgets/chat_history_drawer.dart
// KanMonAI — Chat History Drawer
// Fix D-003 (Pagination), D-005 (Confirm+deleteAll), E-005 (Empty State), E-009 (Search)
// =============================================================================

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/data/models/chat_models.dart';
import 'package:kanmongo/data/services/ai/ai_service.dart';
import 'package:kanmongo/data/services/content/history_service.dart';

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
  // ── D-003: Pagination state ───────────────────────────────────────────────
  final List<ChatSession> _sessions = [];
  int _offset = 0;
  bool _hasMore = true;
  bool _loadingMore = false;
  late final ScrollController _listScrollCtrl;

  // ── E-009: Search state ───────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  // Grouped by label (only used when not searching)
  LinkedHashMap<String, List<ChatSession>> _grouped = LinkedHashMap();

  @override
  void initState() {
    super.initState();
    _listScrollCtrl = ScrollController()
      ..addListener(() {
        if (_listScrollCtrl.position.pixels >=
                _listScrollCtrl.position.maxScrollExtent - 200 &&
            !_loadingMore &&
            _hasMore &&
            _searchQuery.isEmpty) {
          _loadMore();
        }
      });
    _loadMore();
  }

  @override
  void dispose() {
    _listScrollCtrl.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ── D-003: Pagination methods ─────────────────────────────────────────────

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _searchQuery.isNotEmpty) return;
    setState(() => _loadingMore = true);
    final newSessions = await HistoryService.instance.loadChatSessionsPaged(
      offset: _offset,
    );
    if (mounted) {
      setState(() {
        _sessions.addAll(newSessions);
        _offset += newSessions.length;
        _hasMore = newSessions.length == HistoryService.kPageSize;
        _grouped = _groupByDate(_sessions);
        _loadingMore = false;
      });
    }
  }

  Future<void> _refreshList() async {
    setState(() {
      _sessions.clear();
      _offset = 0;
      _hasMore = true;
      _grouped = LinkedHashMap();
    });
    if (_searchQuery.isNotEmpty) {
      await _performSearch(_searchQuery);
    } else {
      await _loadMore();
    }
  }

  // ── E-009: Search methods ─────────────────────────────────────────────────

  Future<void> _performSearch(String query) async {
    setState(() {
      _sessions.clear();
      _offset = 0;
      _hasMore = false;
      _loadingMore = true;
    });
    final results = await HistoryService.instance.searchChatSessions(query);
    if (mounted) {
      setState(() {
        _sessions.addAll(results);
        _offset = results.length;
        _hasMore = query.trim().isEmpty &&
            results.length == HistoryService.kPageSize;
        _grouped = _groupByDate(_sessions);
        _loadingMore = false;
      });
    }
  }

  // ── Grouping ──────────────────────────────────────────────────────────────

  LinkedHashMap<String, List<ChatSession>> _groupByDate(
      List<ChatSession> sessions) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));
    final monthAgo = today.subtract(const Duration(days: 30));

    final result = LinkedHashMap<String, List<ChatSession>>();
    for (final s in sessions) {
      final d = DateTime(s.updatedAt.year, s.updatedAt.month, s.updatedAt.day);
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

  // ── Session actions ───────────────────────────────────────────────────────

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
        await HistoryService.instance.updateSessionTitle(s.id, ctrl.text.trim());
        _refreshList();
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
        _refreshList();
      } catch (e) {
        debugPrint('[ChatHistoryDrawer] delete error: $e');
      }
    }
  }

  // D-005: Konfirmasi + gunakan deleteAllSessions()
  Future<void> _confirmClearAllHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Semua Riwayat?'),
        content: const Text(
          'Semua riwayat chat akan dihapus permanen dan tidak dapat dipulihkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus Semua'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await HistoryService.instance.deleteAllSessions();
      widget.onNewChat.call();
      if (mounted) {
        setState(() {
          _sessions.clear();
          _offset = 0;
          _hasMore = false;
          _grouped = LinkedHashMap();
        });
      }
    } catch (e) {
      debugPrint('[ChatHistoryDrawer] deleteAll error: $e');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    final maxWidth = MediaQuery.sizeOf(context).width * 0.82;
    final drawerWidth = maxWidth > 320.0 ? 320.0 : maxWidth;

    return Drawer(
      width: drawerWidth,
      backgroundColor: c.bg,
      child: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    icon: Icon(Icons.edit_rounded, color: c.textMuted, size: 20),
                    tooltip: 'Chat Baru',
                    onPressed: () {
                      widget.onNewChat();
                      Navigator.pop(context);
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: c.textMuted, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // ── Tombol Chat Baru ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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

            // ── E-009: Search bar ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Cari riwayat...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                            _refreshList();
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: c.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 0,
                    horizontal: 16,
                  ),
                ),
                onChanged: (val) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(
                    const Duration(milliseconds: 350),
                    () {
                      setState(() => _searchQuery = val);
                      _performSearch(val);
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 4),

            // ── Daftar Sesi ─────────────────────────────────────────────────
            Expanded(
              child: _loadingMore && _sessions.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _sessions.isEmpty
                      // E-005: Empty state informatif
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _searchQuery.isNotEmpty
                                      ? Icons.search_off_rounded
                                      : Icons.chat_bubble_outline_rounded,
                                  size: 64,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'Tidak ada hasil untuk "$_searchQuery"'
                                      : 'Belum ada riwayat chat',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                if (_searchQuery.isEmpty)
                                  Text(
                                    'Mulai chat baru untuk melihat riwayat di sini.',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline,
                                        ),
                                  ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _listScrollCtrl,
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: _searchQuery.isNotEmpty
                              ? _sessions.length
                              : _sessions.length + (_hasMore ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            // Pagination loader
                            if (_searchQuery.isEmpty && i == _sessions.length) {
                              return _loadingMore
                                  ? const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Center(
                                          child: CircularProgressIndicator()),
                                    )
                                  : const SizedBox.shrink();
                            }
                            // Session tile (flat list when searching, grouped otherwise)
                            if (_searchQuery.isNotEmpty) {
                              return _SessionTile(
                                session: _sessions[i],
                                isSelected:
                                    _sessions[i].id == widget.currentSession.id,
                                relativeTime:
                                    _relativeTime(_sessions[i].updatedAt),
                                onTap: () {
                                  widget.onSessionSelected(_sessions[i]);
                                  Navigator.pop(context);
                                },
                                onRename: () => _renameSession(_sessions[i]),
                                onDelete: () => _deleteSession(_sessions[i]),
                              );
                            }
                            // Grouped: build from _grouped
                            int idx = 0;
                            for (final entry in _grouped.entries) {
                              // section header
                              if (i == idx) {
                                return _SectionHeader(label: entry.key);
                              }
                              idx++;
                              for (final session in entry.value) {
                                if (i == idx) {
                                  return _SessionTile(
                                    session: session,
                                    isSelected:
                                        session.id == widget.currentSession.id,
                                    relativeTime:
                                        _relativeTime(session.updatedAt),
                                    onTap: () {
                                      widget.onSessionSelected(session);
                                      Navigator.pop(context);
                                    },
                                    onRename: () => _renameSession(session),
                                    onDelete: () => _deleteSession(session),
                                  );
                                }
                                idx++;
                              }
                            }
                            return const SizedBox.shrink();
                          },
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
                  onPressed: _confirmClearAllHistory,
                ),
              ),
          ],
        ),
      ),
    );
  }
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
                const Icon(Icons.delete_outlined, size: 18, color: Colors.red),
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
