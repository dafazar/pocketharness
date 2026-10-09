// lib/features/history/presentation/screens/history_screen.dart
// Pocket Harness — History Screen (AI App Edition)
// Sesi 3: Tambah TabBar 2 tab — "Chat" (ChatSession) & "Aktivitas" (AiHistoryEntry lama)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:pocketharness/core/theme/km_colors.dart';
import 'package:pocketharness/data/models/chat_models.dart';
import 'package:pocketharness/data/services/ai_service.dart';
import 'package:pocketharness/data/services/history_service.dart';
import 'package:pocketharness/features/chat/chat_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  List<ChatSession> _chatSessions = [];
  bool _loadingChat = true;

  List<AiHistoryEntry> _entries = [];
  bool _loadingActivity = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadChat();
    _loadActivity();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadChat() async {
    try {
      final data = await HistoryService.instance.loadAllChatSessions();
      if (mounted) setState(() { _chatSessions = data; _loadingChat = false; });
    } catch (e) {
      debugPrint('[HistoryScreen] _loadChat error: $e');
      if (mounted) setState(() => _loadingChat = false);
    }
  }

  Future<void> _loadActivity() async {
    try {
      final data = await HistoryService.instance.getAll();
      if (mounted) setState(() { _entries = data; _loadingActivity = false; });
    } catch (e) {
      debugPrint('[HistoryScreen] _loadActivity error: $e');
      if (mounted) setState(() => _loadingActivity = false);
    }
  }

  Future<void> _clearAllChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Semua Chat?'),
        content: const Text('Seluruh riwayat chat akan dihapus permanen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      for (final s in _chatSessions) {
        await HistoryService.instance.deleteChatSession(s.id);
      }
      _loadChat();
    }
  }

  Future<void> _clearAllActivity() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Semua Aktivitas?'),
        content: const Text('Seluruh riwayat aktivitas akan dihapus permanen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await HistoryService.instance.clearAll();
      _loadActivity();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        title: Text('Riwayat',
            style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
        actions: [
          AnimatedBuilder(
            animation: _tabCtrl,
            builder: (_, __) {
              final onChat = _tabCtrl.index == 0;
              final hasData = onChat ? _chatSessions.isNotEmpty : _entries.isNotEmpty;
              if (!hasData) return const SizedBox.shrink();
              return IconButton(
                icon: Icon(Icons.delete_sweep_rounded, color: c.textMuted),
                onPressed: onChat ? _clearAllChat : _clearAllActivity,
                tooltip: 'Hapus Semua',
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: c.accent,
          unselectedLabelColor: c.textMuted,
          indicatorColor: c.accent,
          tabs: const [
            Tab(text: 'Chat'),
            Tab(text: 'Aktivitas'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildChatTab(c),
          _buildActivityTab(c),
        ],
      ),
    );
  }

  Widget _buildChatTab(KmColors c) {
    if (_loadingChat) return const Center(child: CircularProgressIndicator());
    if (_chatSessions.isEmpty) return _buildEmptyChat(c);
    return RefreshIndicator(
      onRefresh: _loadChat,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _chatSessions.length,
        itemBuilder: (ctx, i) {
          final s = _chatSessions[i];
          return _ChatSessionCard(
            session: s,
            c: c,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => ChatScreen(initialSession: s))),
            onDelete: () async {
              await HistoryService.instance.deleteChatSession(s.id);
              _loadChat();
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyChat(KmColors c) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.chat_bubble_outline_rounded, size: 64, color: c.textMuted),
        const SizedBox(height: 16),
        Text('Belum ada riwayat chat',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.text)),
        const SizedBox(height: 8),
        Text('Percakapan AI akan tersimpan di sini.',
            style: TextStyle(color: c.textMuted, fontSize: 14),
            textAlign: TextAlign.center),
      ],
    ),
  );

  Widget _buildActivityTab(KmColors c) {
    if (_loadingActivity) return const Center(child: CircularProgressIndicator());
    if (_entries.isEmpty) return _buildEmptyActivity(c);
    final Map<String, List<AiHistoryEntry>> grouped = {};
    for (final e in _entries) {
      grouped.putIfAbsent(_dateLabel(e.date), () => []).add(e);
    }
    return RefreshIndicator(
      onRefresh: _loadActivity,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final entry in grouped.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text(entry.key,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                      color: c.textMuted, letterSpacing: 0.5)),
            ),
            for (final item in entry.value)
              _HistoryCard(item: item, c: c, onDelete: () async {
                await HistoryService.instance.deleteEntry(item.id);
                _loadActivity();
              }),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyActivity(KmColors c) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.history_rounded, size: 64, color: c.textMuted),
        const SizedBox(height: 16),
        Text('Belum ada riwayat',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.text)),
        const SizedBox(height: 8),
        Text('Riwayat penggunaan AI akan muncul di sini.',
            style: TextStyle(color: c.textMuted, fontSize: 14),
            textAlign: TextAlign.center),
      ],
    ),
  );

  String _dateLabel(DateTime d) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date  = DateTime(d.year, d.month, d.day);
    if (date == today) return 'Hari ini';
    if (date == today.subtract(const Duration(days: 1))) return 'Kemarin';
    return '${d.day}/${d.month}/${d.year}';
  }
}

class _ChatSessionCard extends StatelessWidget {
  final ChatSession session;
  final KmColors c;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _ChatSessionCard({required this.session, required this.c,
      required this.onTap, required this.onDelete});

  String _aiModeEmoji(AiMode? mode) {
    switch (mode) {
      case AiMode.offline: return '💾';
      case AiMode.online:  return '🌐';
      case AiMode.bulkApi: return '⚡';
      default:             return '💬';
    }
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mnt lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    if (diff.inDays == 1) return 'Kemarin';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Text(_aiModeEmoji(session.lastAiMode),
            style: const TextStyle(fontSize: 22)),
        title: Text(session.title,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (session.preview.isNotEmpty)
              Text(session.preview,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.textMuted)),
            Text(_relativeTime(session.updatedAt),
                style: TextStyle(fontSize: 11, color: c.textMuted)),
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline_rounded, color: c.textMuted, size: 18),
          onPressed: onDelete,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final AiHistoryEntry item;
  final KmColors c;
  final VoidCallback onDelete;
  const _HistoryCard({required this.item, required this.c, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconData = item.feature == 'ocr'
        ? Icons.document_scanner_rounded
        : item.feature == 'reader'
            ? Icons.chrome_reader_mode_rounded
            : Icons.smart_toy_rounded;
    final color = item.feature == 'ocr'
        ? const Color(0xFF0EA5E9)
        : item.feature == 'reader'
            ? const Color(0xFF14B8A6)
            : const Color(0xFF6366F1);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(iconData, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.featureLabel,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
            const SizedBox(height: 3),
            Text(item.summary,
              style: TextStyle(fontSize: 12, color: c.textMuted),
              maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('${item.date.hour.toString().padLeft(2,'0')}:${item.date.minute.toString().padLeft(2,'0')}',
              style: TextStyle(fontSize: 11, color: c.textMuted)),
          ]),
        ),
        IconButton(
          icon: Icon(Icons.delete_outline_rounded, color: c.textMuted, size: 18),
          onPressed: onDelete,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    );
  }
}
