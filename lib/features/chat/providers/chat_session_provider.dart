// lib/features/chat/providers/chat_session_provider.dart
// KanMonAI — Chat Session Provider (Sesi 1)
// Riverpod state management untuk active chat session + history list
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kanmongo/data/models/chat_models.dart';
import 'package:kanmongo/data/services/ai/ai_service.dart' show AiMode;
import 'package:kanmongo/data/services/content/history_service.dart';

// ── Provider pilihan sumber AI ─────────────────────────────────────────────────
final aiSourceProvider       = StateProvider<AiSourceChoice?>((ref) => null);
// alias untuk backward-compat
final aiSourceChoiceProvider = aiSourceProvider;

// ── Provider utama chat session ────────────────────────────────────────────────
final chatSessionProvider =
    StateNotifierProvider<ChatSessionNotifier, ChatSession>(
  (ref) => ChatSessionNotifier(),
);

// ── Provider daftar riwayat (future) ──────────────────────────────────────────
final chatHistoryProvider = FutureProvider<List<ChatSession>>(
  (ref) => HistoryService.instance.loadAllChatSessions(),
);

// ── ChatSessionNotifier ────────────────────────────────────────────────────────
class ChatSessionNotifier extends StateNotifier<ChatSession> {
  ChatSessionNotifier() : super(ChatSession.empty());

  // 1. Tambah pesan baru ke sesi aktif
  void addMessage(ChatMessage msg) {
    state = state.copyWith(
      messages: [...state.messages, msg],
      updatedAt: DateTime.now(),
    );
  }

  // 2. Append token streaming ke konten pesan assistant terakhir
  void updateLastAssistantMessage(String token) {
    if (state.messages.isEmpty) return;
    final last = state.messages.last;
    if (!last.isAssistant) return;
    final updated = last.copyWith(content: last.content + token);
    final msgs = [
      ...state.messages.sublist(0, state.messages.length - 1),
      updated,
    ];
    state = state.copyWith(messages: msgs);
  }

  // 3. Replace pesan terakhir (setelah streaming selesai, set isStreaming=false)
  // Overload menerima ChatMessage langsung
  void replaceLastAssistantMessage(
    Object msgOrContent, {
    dynamic stopReason, // ignored – kept for API compat; chat_models tidak pakai StopReason
  }) {
    if (state.messages.isEmpty) return;
    final ChatMessage msg;
    if (msgOrContent is ChatMessage) {
      msg = msgOrContent;
    } else {
      // msgOrContent adalah String
      final content = msgOrContent as String;
      final prev = state.messages.last;
      msg = prev.copyWith(
        content: content,
        isStreaming: false,
        isError: stopReason != null,
        error: stopReason != null ? content : null,
      );
    }
    final msgs = [
      ...state.messages.sublist(0, state.messages.length - 1),
      msg,
    ];
    state = state.copyWith(messages: msgs, updatedAt: DateTime.now());
  }

  // 4. Hapus satu pesan berdasarkan id
  void deleteMessage(String id) {
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != id).toList(),
      updatedAt: DateTime.now(),
    );
  }

  // 5. Reset ke sesi kosong baru
  void clearSession() {
    state = ChatSession.empty();
  }

  // 6. Load sesi dari history (untuk dilanjutkan)
  Future<void> loadSession(ChatSession session) async {
    state = session;
  }

  // 7. Simpan sesi aktif ke DB (auto-save setelah setiap pesan)
  Future<void> autoSave() async {
    if (state.messages.isEmpty) return;
    try {
      await HistoryService.instance.saveChatSession(state);
    } catch (e) {
      debugPrint('[ChatSessionNotifier] autoSave error: $e');
    }
  }

  // 8. Set judul sesi (update state + persist ke DB)
  void setTitle(String title) {
    state = state.copyWith(title: title, updatedAt: DateTime.now());
    HistoryService.instance
        .updateSessionTitle(state.id, title)
        .catchError((e) => debugPrint('[ChatSessionNotifier] setTitle error: $e'));
  }

  // 9. Generate judul otomatis dari pesan pertama user
  String generateTitleFromFirstMessage() {
    final firstUser = state.messages.firstWhere(
      (m) => m.isUser && m.content.isNotEmpty,
      orElse: () => state.messages.isNotEmpty
          ? state.messages.first
          : ChatMessage(
              id: '',
              role: 'user',
              content: 'Chat Baru',
              createdAt: DateTime.now(),
            ),
    );
    final raw = firstUser.content.trim().replaceAll('\n', ' ');
    return raw.length > 50 ? '${raw.substring(0, 50)}…' : raw;
  }

  // ── Helper: set lastAiMode pada state ─────────────────────────────────────
  void setLastAiInfo({required AiMode mode, String? modelName}) {
    state = state.copyWith(
      lastAiMode: mode,
      lastModelName: modelName,
      updatedAt: DateTime.now(),
    );
  }
}
