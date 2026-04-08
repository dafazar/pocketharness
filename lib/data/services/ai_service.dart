// lib/data/services/ai_service.dart
// KanMon GO — AI Service (Offline + Online/Puter.js)
//
// Mode AI:
//   1. Offline — model GGUF/TFLite lokal via LlamaService (llama.cpp JNI)
//               OfflineAiService tetap berfungsi sebagai alias backward-compatible
//   2. Online  — model cloud via PuterAiService (Puter.js REST API)
//   3. BulkApi — multi-provider API key (Groq, Gemini, Claude, dll)
//
// Prioritas:
//   - Jika force_offline = true → selalu offline
//   - Jika puter.enabled = true && ada internet → pakai online
//   - Fallback ke offline jika model lokal tersedia
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math' show min;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:kanmongo/core/ai/llama_context.dart';
import 'package:kanmongo/data/models/chat_models.dart' as cm;
import 'package:kanmongo/data/services/llama_service.dart';
import 'package:kanmongo/data/services/offline_ai_service.dart';
import 'package:kanmongo/data/services/puter_ai_service.dart';
import 'package:kanmongo/data/services/ai_persona_service.dart';
import 'package:kanmongo/data/services/file_processor_service.dart';
import 'package:kanmongo/data/services/model_manager_service.dart';
import 'package:kanmongo/data/services/media_edit_service.dart';
import 'package:kanmongo/data/services/tool_installer_service.dart';
import 'package:kanmongo/data/services/bulk_api_service.dart';
import 'package:kanmongo/data/services/terminal_service.dart';
import 'package:kanmongo/data/services/web_research_service.dart';

// ── Adaptive Edit Pipeline Events ────────────────────────────────────────────

enum AdaptiveEditPhase {
  analyzing,   // Analyzing attached files
  researching, // Web research for best approach
  planning,    // Building comprehensive prompt
  executing,   // AI generating the edit
  done,        // Complete
  error,       // Fatal error
}

class AdaptiveEditEvent {
  final AdaptiveEditPhase phase;
  final String? statusText;  // Human-readable status for UI
  final String? token;       // Streaming token from AI (phase = executing)
  final String? errorText;

  const AdaptiveEditEvent._({
    required this.phase,
    this.statusText,
    this.token,
    this.errorText,
  });

  factory AdaptiveEditEvent.analyzing(String msg) =>
      AdaptiveEditEvent._(phase: AdaptiveEditPhase.analyzing, statusText: msg);

  factory AdaptiveEditEvent.researching(String msg) =>
      AdaptiveEditEvent._(phase: AdaptiveEditPhase.researching, statusText: msg);

  factory AdaptiveEditEvent.planning(String msg) =>
      AdaptiveEditEvent._(phase: AdaptiveEditPhase.planning, statusText: msg);

  factory AdaptiveEditEvent.executing(String token) =>
      AdaptiveEditEvent._(phase: AdaptiveEditPhase.executing, token: token);

  factory AdaptiveEditEvent.done() =>
      AdaptiveEditEvent._(phase: AdaptiveEditPhase.done);

  factory AdaptiveEditEvent.error(String msg) =>
      AdaptiveEditEvent._(phase: AdaptiveEditPhase.error, errorText: msg);
}

// ── Web Research Stream Types ────────────────────────────────────────────────

enum WebResearchEventType { status, sources, token, done }

class WebResearchStreamEvent {
  final WebResearchEventType type;
  final String? statusText;
  final List<ResearchSource>? sources;
  final String? tokenText;

  const WebResearchStreamEvent._({
    required this.type,
    this.statusText,
    this.sources,
    this.tokenText,
  });

  factory WebResearchStreamEvent.status(String text) =>
      WebResearchStreamEvent._(
          type: WebResearchEventType.status, statusText: text);

  factory WebResearchStreamEvent.sources(List<ResearchSource> srcs) =>
      WebResearchStreamEvent._(
          type: WebResearchEventType.sources, sources: srcs);

  factory WebResearchStreamEvent.token(String t) =>
      WebResearchStreamEvent._(type: WebResearchEventType.token, tokenText: t);

  factory WebResearchStreamEvent.done() =>
      WebResearchStreamEvent._(type: WebResearchEventType.done);
}

// ── Enum mode AI ──────────────────────────────────────────────────────────────
enum AiMode {
  offline, // Gunakan model lokal (llama.cpp via LlamaService)
  online,  // Gunakan Puter.js cloud AI
  bulkApi, // Gunakan Bulk API Key (Groq, Gemini, Claude, dll)
  none,    // Tidak ada model tersedia
}

class AiService {
  AiService._();
  static final AiService instance = AiService._();

  static const _maxHistory = 12;

  // ── Source override dari AI Source Picker ─────────────────────────────────
  AiMode? _forcedMode;
  String? _forcedBulkKeyId;
  BulkApiProvider? _forcedBulkProvider;

  void setSource(dynamic choice) {
    // choice = AiSourceChoice | null
    if (choice == null) {
      _forcedMode = null;
      _forcedBulkKeyId = null;
      _forcedBulkProvider = null;
    } else {
      _forcedMode = choice.mode as AiMode;
      _forcedBulkKeyId = choice.bulkKeyId as String?;
      _forcedBulkProvider = choice.bulkProvider as BulkApiProvider?;
    }
    debugPrint('[AiService] Source override → $_forcedMode');
  }

  // ── Connectivity cache ─────────────────────────────────────────────────────
  bool _cachedOnline   = true;
  DateTime _lastCheck  = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription? _connectSub;

  bool get forceOfflineMode => OfflineAiService.instance.forceOfflineMode;

  // ── Mode saat ini ──────────────────────────────────────────────────────────
  AiMode get currentMode {
    // 1. Jika user override via AI Source Picker
    if (_forcedMode != null) {
      // Validasi: pastikan sumber masih valid
      switch (_forcedMode!) {
        case AiMode.online:
          if (PuterAiService.instance.isEnabled &&
              PuterAiService.instance.apiKey.isNotEmpty &&
              isOnline) return AiMode.online;
          break;
        case AiMode.bulkApi:
          if (BulkApiService.instance.enabled &&
              BulkApiService.instance.activeKeys.isNotEmpty) return AiMode.bulkApi;
          break;
        case AiMode.offline:
          // isModelLoaded (LlamaService) atau isLoading masih valid
          if (LlamaService.instance.isModelLoaded ||
              OfflineAiService.instance.isReady ||
              OfflineAiService.instance.isLoading ||
              ModelManagerService.instance.activeModel != null) return AiMode.offline;
          break;
        case AiMode.none:
          break;
      }
      // Fallthrough jika sumber tidak valid lagi
    }

    if (forceOfflineMode) return AiMode.offline;

    // 2. Auto: cek online sources
    final puterReady = PuterAiService.instance.isEnabled &&
        PuterAiService.instance.apiKey.isNotEmpty &&
        isOnline;

    if (puterReady) return AiMode.online;

    // Bulk API sebagai alternatif online
    if (BulkApiService.instance.enabled &&
        BulkApiService.instance.activeKeys.isNotEmpty &&
        isOnline) return AiMode.bulkApi;

    // 3. Offline — cek LlamaService terlebih dahulu (arsitektur baru)
    if (LlamaService.instance.isModelLoaded) return AiMode.offline;
    if (OfflineAiService.instance.isReady) return AiMode.offline;
    if (OfflineAiService.instance.isLoading) return AiMode.offline;
    if (ModelManagerService.instance.activeModel != null) return AiMode.offline;

    return AiMode.none;
  }

  /// Label mode untuk UI
  String get modeLabelShort {
    switch (currentMode) {
      case AiMode.online:  return '🌐 ${PuterAiService.instance.selectedModel?.name ?? 'Online'}';
      case AiMode.bulkApi: return '🔑 Bulk API';
      case AiMode.offline: return '📱 Offline';
      case AiMode.none:    return '❌ Tidak ada model';
    }
  }

  Future<void> syncOfflineSettings() async {
    await ModelManagerService.instance.load();
    await OfflineAiService.instance.loadSettings();
    await PuterAiService.instance.loadSettings();
    await BulkApiService.instance.load();
    // Auto-load model aktif jika belum dimuat (cek LlamaService dulu)
    if (!LlamaService.instance.isModelLoaded &&
        !OfflineAiService.instance.isReady &&
        ModelManagerService.instance.activeModel != null) {
      try {
        await OfflineAiService.instance.loadActiveModel();
      } catch (e) {
        debugPrint('[AiService] syncOfflineSettings auto-load error: $e');
      }
    }
    debugPrint('[AiService] settings synced — mode=$currentMode');
  }

  void initConnectivityWatcher() {
    _connectSub = Connectivity().onConnectivityChanged.listen((results) {
      _cachedOnline = results.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet);
      _lastCheck = DateTime.now();
    });
    _refreshConnectivity();
  }

  Future<void> _refreshConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      _cachedOnline = results.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet);
      _lastCheck = DateTime.now();
    } catch (_) {}
  }

  bool get isOnline {
    if (DateTime.now().difference(_lastCheck).inSeconds > 30) {
      _refreshConnectivity();
    }
    return _cachedOnline;
  }

  void dispose() => _connectSub?.cancel();

  // ── Warm-up ────────────────────────────────────────────────────────────────
  Future<void> warmUp() async {
    await AiPersonaService.instance.load();
    await PuterAiService.instance.loadSettings();
    debugPrint('[AiService] Warm-up complete — mode=$currentMode');
  }

  static const _fallbackSystemPrompt =
      'Kamu adalah AI Chat — asisten AI yang cerdas dan membantu. '
      'Jawab dalam Bahasa Indonesia kecuali diminta lain. '
      'Jawab ringkas, jelas, dan langsung ke inti.';

  static String get _defaultSystemPrompt =>
      AiPersonaService.instance.activePersona.systemPrompt.isNotEmpty
          ? AiPersonaService.instance.activePersona.systemPrompt
          : _fallbackSystemPrompt;

  /// Apakah ada model yang siap atau sudah terdaftar (offline atau online)
  bool get hasModel =>
      LlamaService.instance.isModelLoaded ||
      OfflineAiService.instance.isReady ||
      ModelManagerService.instance.activeModel != null ||
      (PuterAiService.instance.isEnabled &&
       PuterAiService.instance.apiKey.isNotEmpty) ||
      (BulkApiService.instance.enabled &&
       BulkApiService.instance.activeKeys.isNotEmpty);

  static String get _noModelMsg {
    final offlineError = OfflineAiService.instance.error;
    if (offlineError != null && offlineError.isNotEmpty) {
      return '🤖 Belum ada model AI yang aktif.\n\n'
          '❌ **Error saat load model:**\n$offlineError\n\n'
          '**Pilihan AI:**\n\n'
          '📱 **AI Offline** — Import/download model GGUF:\n'
          '_Settings → Model Manager atau Settings → AI Offline_\n\n'
          '🌐 **AI Online (Puter.js)** — Akses Claude, Gemini, Grok & lainnya:\n'
          '_Settings → AI Online & Setup Puter.js_\n\n'
          '_Tap ikon ⚙️ di pojok kanan atas untuk pilihan model._';
    }
    return '🤖 Belum ada model AI yang aktif.\n\n'
        '**Pilihan AI:**\n\n'
        '📱 **AI Offline** — Import/download model GGUF:\n'
        '_Settings → Model Manager atau Settings → AI Offline_\n\n'
        '🌐 **AI Online (Puter.js)** — Akses Claude, Gemini, Grok & lainnya:\n'
        '_Settings → AI Online & Setup Puter.js_\n\n'
        '_Tap ikon ⚙️ di pojok kanan atas untuk pilihan model._';
  }

  // ── Streaming chat ─────────────────────────────────────────────────────────
  Stream<String> sendChatStream({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required String userMessage,
    double temperature = 0.7,
    int maxTokens = 1024,
  }) async* {
    final mode = currentMode;

    if (mode == AiMode.none) {
      yield AiService._noModelMsg;
      return;
    }

    if (mode == AiMode.online) {
      yield* _onlineChatStream(systemPrompt, history, userMessage);
    } else if (mode == AiMode.bulkApi) {
      yield* _bulkApiChatStream(systemPrompt, history, userMessage, maxTokens, temperature);
    } else {
      yield* _offlineChatStream(
        systemPrompt, history, userMessage,
        maxTokens: maxTokens,
        temperature: temperature,
      );
    }
  }

  // ── Multi-turn chat dengan List<ChatMessage> (arsitektur baru) ───────────
  // Digunakan oleh ChatScreen baru yang memakai LlamaService langsung.
  // Backward compatible — fallback ke OfflineAiService jika LlamaService
  // belum memuat model.
  Stream<String> generateMultiTurn({
    required List<ChatMessage> messages,
    required AiMode mode,
    InferenceConfig? config,
    String? systemPrompt,
  }) async* {
    switch (mode) {
      case AiMode.offline:
        // Gunakan LlamaService (arsitektur PocketPal baru)
        final cfg = config ?? InferenceConfig.defaultConfig;
        yield* LlamaService.instance.generateStream(
          messages: messages,
          config: cfg,
          systemPromptOverride: systemPrompt,
        );
        break;

      case AiMode.online:
        // Konversi List<ChatMessage> ke format PuterAiService
        final lastUser = messages.lastWhere(
          (m) => m.role == ChatRole.user,
          orElse: () => ChatMessage.user(''),
        );
        final historyMaps = messages
            .where((m) => m.role != ChatRole.system)
            .map((m) => {
                  'role': m.role == ChatRole.user ? 'user' : 'assistant',
                  'content': m.content,
                })
            .toList();
        yield* PuterAiService.instance.chatStream(
          systemPrompt: systemPrompt ?? _defaultSystemPrompt,
          history: historyMaps,
          userMessage: lastUser.content,
        );
        break;

      case AiMode.bulkApi:
        // Konversi List<ChatMessage> ke format BulkApiService
        final lastUser = messages.lastWhere(
          (m) => m.role == ChatRole.user,
          orElse: () => ChatMessage.user(''),
        );
        final historyMaps = messages
            .where((m) => m.role != ChatRole.system)
            .map((m) => {
                  'role': m.role == ChatRole.user ? 'user' : 'assistant',
                  'content': m.content,
                })
            .toList();
        final cfg = config ?? InferenceConfig.defaultConfig;
        final result = await BulkApiService.instance.sendChat(
          userMessage: lastUser.content,
          systemPrompt: systemPrompt ?? _defaultSystemPrompt,
          history: historyMaps,
          preferredKeyId: _forcedBulkKeyId,
          preferredProvider: _forcedBulkProvider,
          maxTokens: cfg.maxNewTokens,
          temperature: cfg.temperature,
        );
        if (result.success) {
          yield result.content;
        } else {
          yield '❌ Bulk API Error: ${result.error}';
        }
        break;

      case AiMode.none:
        yield AiService._noModelMsg;
        break;
    }
  }

  // ── Bulk API stream — first-class mode ───────────────────────────────────
  Stream<String> _bulkApiChatStream(
    String systemPrompt,
    List<Map<String, String>> history,
    String userMessage,
    int maxTokens,
    double temperature,
  ) async* {
    try {
      final bulk = BulkApiService.instance;
      if (!bulk.enabled) {
        yield '❌ Bulk API belum diaktifkan.\n\n'
            'Pergi ke **Settings → Bulk API Key** untuk mengaktifkan dan menambah API key.';
        return;
      }
      if (bulk.keys.isEmpty) {
        yield '❌ Belum ada API key di Bulk API.\n\n'
            'Pergi ke **Settings → Bulk API Key** untuk menambah key.';
        return;
      }

      final trimmed = history.length > _maxHistory
          ? history.sublist(history.length - _maxHistory)
          : history;

      final result = await bulk.sendChat(
        userMessage: userMessage,
        systemPrompt: systemPrompt,
        history: trimmed,
        preferredKeyId: _forcedBulkKeyId,
        preferredProvider: _forcedBulkProvider,
        maxTokens: maxTokens,
        temperature: temperature,
      );

      if (result.success) {
        yield result.content;
      } else {
        yield '❌ Bulk API Error: ${result.error}\n\n'
            'Cek Settings → Bulk API Key untuk detail dan test koneksi.';
      }
    } catch (e) {
      debugPrint('[AiService] Bulk API stream error: $e');
      yield '❌ Error Bulk API: ${e.toString()}';
    }
  }

  // ── Online stream via Puter.js dengan Bulk API fallback ───────────────────
  Stream<String> _onlineChatStream(
    String systemPrompt,
    List<Map<String, String>> history,
    String userMessage,
  ) async* {
    try {
      final trimmed = history.length > _maxHistory
          ? history.sublist(history.length - _maxHistory)
          : history;

      yield* PuterAiService.instance.chatStream(
        systemPrompt: systemPrompt,
        history:      trimmed,
        userMessage:  userMessage,
      );
    } catch (e) {
      debugPrint('[AiService] Online error: $e');

      // Coba Bulk API jika aktif
      final bulk = BulkApiService.instance;
      if (bulk.enabled && bulk.activeKeys.isNotEmpty) {
        yield '⚠️ Puter.js error, mencoba Bulk API...\n\n';
        try {
          final result = await bulk.sendChat(
            userMessage: userMessage,
            systemPrompt: systemPrompt,
            history: history,
          );
          if (result.success) {
            yield result.content;
            return;
          } else {
            yield '❌ Bulk API juga gagal: ${result.error}\n\n';
          }
        } catch (bulkErr) {
          debugPrint('[AiService] Bulk API error: $bulkErr');
        }
      } else {
        yield '❌ Error online AI: ${e.toString()}\n\n';
      }

      if (OfflineAiService.instance.isReady || LlamaService.instance.isModelLoaded) {
        yield '⚠️ Fallback ke AI offline...\n\n';
        yield* _offlineChatStream(systemPrompt, history, userMessage,
            maxTokens: 1024, temperature: 0.7);
      }
    }
  }

  // ── Offline stream via LlamaService (arsitektur baru) ─────────────────────
  Stream<String> _offlineChatStream(
    String systemPrompt,
    List<Map<String, String>> history,
    String userMessage, {
    int maxTokens = 1024,
    double temperature = 0.7,
  }) async* {
    try {
      debugPrint('[AiService] _offlineChatStream called — maxTokens=$maxTokens');
      debugPrint('[AiService] LlamaService.isModelLoaded=${LlamaService.instance.isModelLoaded}');
      debugPrint('[AiService] OfflineAiService.isReady=${OfflineAiService.instance.isReady}');
      debugPrint('[AiService] isLoading=${OfflineAiService.instance.isLoading}');

      // Tunggu jika model sedang proses load dari tempat lain
      if (OfflineAiService.instance.isLoading) {
        yield '⏳ Model sedang dimuat, harap tunggu...\n\n';
        int waited = 0;
        while (OfflineAiService.instance.isLoading && waited < 60) {
          await Future.delayed(const Duration(seconds: 1));
          waited++;
        }
      }

      // Auto-load model jika sudah terdaftar tapi belum dimuat
      if (!LlamaService.instance.isModelLoaded &&
          !OfflineAiService.instance.isReady &&
          ModelManagerService.instance.activeModel != null) {
        yield '⏳ Memuat model AI, harap tunggu...\n\n';
        try {
          await OfflineAiService.instance.loadSettings();
          await OfflineAiService.instance.loadActiveModel();
        } catch (loadErr) {
          debugPrint('[AiService] Auto-load error: $loadErr');
        }
        if (!LlamaService.instance.isModelLoaded && !OfflineAiService.instance.isReady) {
          final err = OfflineAiService.instance.error;
          yield '❌ Gagal memuat model: ${err ?? 'Unknown error'}\n\n'
              'Coba aktifkan ulang model di **Settings → Model Manager**.';
          return;
        }
        yield '✅ Model siap!\n\n';
      }

      // Validasi akhir — salah satu harus siap
      final ready = LlamaService.instance.isModelLoaded || OfflineAiService.instance.isReady;
      if (!ready) {
        yield '⚠️ Model offline belum siap.\n\n'
            'Pergi ke **Settings → Model Manager**, pilih model lalu tap **Aktifkan**.';
        return;
      }

      final trimmed = history.length > _maxHistory
          ? history.sublist(history.length - _maxHistory)
          : history;

      // Gunakan LlamaService jika model sudah dimuat via arsitektur baru
      if (LlamaService.instance.isModelLoaded) {
        // Konversi history Map ke List<ChatMessage>
        final chatMessages = <ChatMessage>[];
        for (final h in trimmed) {
          final role = h['role'] == 'user' ? ChatRole.user : ChatRole.assistant;
          if (role == ChatRole.user) {
            chatMessages.add(ChatMessage.user(h['content'] ?? ''));
          } else {
            chatMessages.add(ChatMessage.assistant(h['content'] ?? ''));
          }
        }
        chatMessages.add(ChatMessage.user(userMessage));

        final config = InferenceConfig(
          temperature: temperature,
          maxNewTokens: maxTokens,
        );

        debugPrint('[AiService] Delegating to LlamaService.generateStream...');
        bool gotAnyChunk = false;
        yield* LlamaService.instance.generateStream(
          messages: chatMessages,
          config: config,
          systemPromptOverride: systemPrompt,
        ).map((chunk) {
          if (!gotAnyChunk) {
            gotAnyChunk = true;
            debugPrint('[AiService] First chunk received ✓');
          }
          return chunk;
        });
        debugPrint('[AiService] LlamaService stream done — gotAnyChunk=$gotAnyChunk');

        if (!gotAnyChunk) {
          debugPrint('[AiService] WARNING: 0 chunks dari LlamaService!');
          yield '⚠️ AI tidak menghasilkan respons.\n\n'
              'Coba:\n'
              '• Restart aplikasi\n'
              '• Reload model di Settings → Model Manager\n'
              '• Mulai chat baru (context mungkin penuh)';
        }
        return;
      }

      // Fallback ke OfflineAiService (backward compatible)
      debugPrint('[AiService] Delegating to OfflineAiService.chatStream (fallback)...');
      bool gotAnyChunk = false;
      yield* OfflineAiService.instance.chatStream(
        systemPrompt: systemPrompt,
        history:      trimmed,
        userMessage:  userMessage,
        maxTokens:    maxTokens,
        temperature:  temperature,
      ).map((chunk) {
        if (!gotAnyChunk) {
          gotAnyChunk = true;
          debugPrint('[AiService] First chunk received ✓');
        }
        return chunk;
      });
      debugPrint('[AiService] chatStream done — gotAnyChunk=$gotAnyChunk');

      if (!gotAnyChunk) {
        debugPrint('[AiService] WARNING: 0 chunks dari offline AI!');
        yield '⚠️ AI tidak menghasilkan respons.\n\n'
            'Coba:\n'
            '• Restart aplikasi\n'
            '• Reload model di Settings → Model Manager\n'
            '• Mulai chat baru (context mungkin penuh)';
      }
    } catch (e) {
      debugPrint('[AiService] _offlineChatStream error: $e');
      yield '❌ Error: ${e.toString()}';
    }
  }

  // ── Streaming chat dengan file attachment ──────────────────────────────────
  Stream<String> sendChatWithFileStream({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required String userMessage,
    required ProcessedFile file,
    double temperature = 0.7,
    int maxTokens = 2048,
  }) async* {
    if (currentMode == AiMode.none) {
      yield AiService._noModelMsg;
      return;
    }

    if (file.isError) {
      yield '❌ File error: ${file.error}';
      return;
    }

    String combinedMessage = userMessage;
    if (file.hasText && file.textContent != null) {
      final header = '=== FILE: ${file.filename} ===\n\n';
      final body = file.textContent!.length > 80000
          ? '${file.textContent!.substring(0, 80000)}\n... [terpotong]'
          : file.textContent!;
      combinedMessage = '$header$body\n\n=== INSTRUKSI ===\n'
          '${userMessage.isNotEmpty ? userMessage : 'Analisis file ini secara detail.'}';
    }

    yield* sendChatStream(
      systemPrompt: systemPrompt,
      history: history,
      userMessage: combinedMessage,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  // ── Edit file ──────────────────────────────────────────────────────────────
  Stream<String> editFileStream({
    required ProcessedFile file,
    required String editInstruction,
  }) async* {
    const systemPrompt =
        'Kamu adalah editor profesional. '
        'Berikan hasil edit yang diminta langsung tanpa penjelasan panjang.';

    yield* sendChatWithFileStream(
      systemPrompt: systemPrompt,
      history: [],
      userMessage: editInstruction,
      file: file,
      temperature: 0.3,
      maxTokens: 4096,
    );
  }

  // ── Non-streaming sendChat ─────────────────────────────────────────────────
  Future<String> sendChat({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required String userMessage,
    double temperature = 0.7,
    int maxTokens = 1024,
  }) async {
    final sb = StringBuffer();
    await for (final chunk in sendChatStream(
      systemPrompt: systemPrompt,
      history: history,
      userMessage: userMessage,
      temperature: temperature,
      maxTokens: maxTokens,
    )) {
      sb.write(chunk);
    }
    return sb.toString();
  }

  // ── Generate single prompt ─────────────────────────────────────────────────
  Future<String> generate({
    required String prompt,
    double temperature = 0.3,
    int maxTokens = 512,
  }) async {
    final mode = currentMode;
    if (mode == AiMode.online) {
      return PuterAiService.instance.generate(
        systemPrompt: 'Jawab singkat dan langsung.',
        history: [],
        userMessage: prompt,
      );
    }
    // Gunakan LlamaService jika model sudah dimuat
    if (mode == AiMode.offline && LlamaService.instance.isModelLoaded) {
      final sb = StringBuffer();
      final config = InferenceConfig(
        temperature: temperature,
        maxNewTokens: maxTokens,
      );
      await for (final chunk in LlamaService.instance.generateStream(
        messages: [ChatMessage.user(prompt)],
        config: config,
      )) {
        sb.write(chunk);
      }
      return sb.toString();
    }
    // Fallback ke OfflineAiService
    if (mode == AiMode.offline && OfflineAiService.instance.isReady) {
      return OfflineAiService.instance.generate(prompt);
    }
    return 'Tidak ada model AI yang aktif.';
  }

  // ── Generate JSON ──────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> generateJson({required String prompt}) async {
    try {
      final result = await generate(prompt: prompt);
      if (result.isEmpty) return null;
      final clean = result
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      return Map<String, dynamic>.from(jsonDecode(clean) as Map);
    } catch (e) {
      debugPrint('[AiService.generateJson] $e');
      return null;
    }
  }

  // ── Send dengan attachment (Vision API) ───────────────────────────────────
  Stream<String> sendWithAttachments({
    required String userText,
    required List<cm.ChatAttachment> attachments,
    required List<Map<String, String>> history,
    AiMode? forceMode,
    String? forceBulkKeyId,
    BulkApiProvider? forceProvider,
  }) async* {
    try {
      final imageAtts = attachments
          .where((a) => a.type == cm.AttachmentType.image && a.thumbnailBytes != null)
          .toList();
      final textAtts = attachments.where((a) => a.hasText).toList();

      // Build augmented text from text-based attachments
      String augmentedText = userText;
      for (final att in textAtts) {
        final preview =
            att.extractedText!.substring(0, min(8000, att.extractedText!.length));
        augmentedText += '\n\n---\n📎 [${att.filename}]\n```\n$preview\n```';
      }

      final mode = forceMode ?? currentMode;

      if (imageAtts.isEmpty) {
        yield* _dispatchText(augmentedText, history, mode, forceBulkKeyId, forceProvider);
        return;
      }

      // Has images — dispatch to vision API
      switch (mode) {
        case AiMode.bulkApi:
          final provider = forceProvider ??
              BulkApiService.instance.getNextKey(null)?.provider ??
              BulkApiProvider.gemini;
          if (provider == BulkApiProvider.gemini) {
            yield* _sendGeminiVision(augmentedText, imageAtts, history, forceBulkKeyId);
          } else {
            yield* _sendOpenAiVision(augmentedText, imageAtts, history, forceBulkKeyId, provider);
          }
          break;
        case AiMode.online:
          yield* _sendOpenAiVision(augmentedText, imageAtts, history, null, BulkApiProvider.openai);
          break;
        case AiMode.offline:
          // Offline doesn't support vision → OCR fallback
          String ocrText = '';
          for (final att in imageAtts) {
            try {
              final inputImage = InputImage.fromFilePath(att.path);
              final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
              final result = await recognizer.processImage(inputImage);
              await recognizer.close();
              if (result.text.isNotEmpty) {
                ocrText += '\n\n[OCR: ${att.filename}]\n${result.text}';
              }
            } catch (e) {
              ocrText += '\n\n[Gagal OCR: ${att.filename}]';
              debugPrint('[AiService] OCR error: $e');
            }
          }
          yield* _dispatchText(augmentedText + ocrText, history, AiMode.offline, null, null);
          break;
        default:
          yield '❌ Mode AI tidak mendukung lampiran gambar.';
      }
    } catch (e) {
      debugPrint('[AiService] sendWithAttachments error: $e');
      yield '❌ Error: $e';
    }
  }

  Stream<String> _dispatchText(
    String text,
    List<Map<String, String>> history,
    AiMode mode,
    String? forceBulkKeyId,
    BulkApiProvider? forceProvider,
  ) async* {
    final sys = _defaultSystemPrompt;
    switch (mode) {
      case AiMode.online:
        yield* _onlineChatStream(sys, history, text);
        break;
      case AiMode.bulkApi:
        yield* _bulkApiChatStream(sys, history, text, 1024, 0.7);
        break;
      case AiMode.offline:
        yield* _offlineChatStream(sys, history, text, maxTokens: 1024, temperature: 0.7);
        break;
      default:
        yield _noModelMsg;
    }
  }

  // Gemini multipart vision
  Stream<String> _sendGeminiVision(
    String text,
    List<cm.ChatAttachment> images,
    List<Map<String, String>> history,
    String? preferredKeyId,
  ) async* {
    try {
      final key = BulkApiService.instance.getNextKey(BulkApiProvider.gemini);
      if (key == null) {
        yield '❌ Tidak ada Gemini API key tersedia.';
        return;
      }
      final model = key.model.isNotEmpty ? key.model : 'gemini-1.5-flash';
      final url =
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=${key.apiKey}';

      // Build contents
      final contents = <Map<String, dynamic>>[];
      // Add history
      for (final h in history) {
        contents.add({
          'role': h['role'] == 'user' ? 'user' : 'model',
          'parts': [{'text': h['content'] ?? ''}],
        });
      }

      // Build parts for current user message
      final parts = <Map<String, dynamic>>[];
      if (text.isNotEmpty) parts.add({'text': text});
      for (final img in images) {
        final bytes = img.thumbnailBytes!;
        final b64 = base64Encode(bytes);
        parts.add({
          'inline_data': {
            'mime_type': 'image/jpeg',
            'data': b64,
          },
        });
      }
      contents.add({'role': 'user', 'parts': parts});

      final body = jsonEncode({'contents': contents});
      final resp = await http
          .post(Uri.parse(url),
              headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 60));

      if (resp.statusCode != 200) {
        yield '❌ Gemini Vision error ${resp.statusCode}: ${resp.body}';
        return;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        yield '❌ Gemini tidak menghasilkan respons.';
        return;
      }
      final parts2 = (candidates[0]['content']?['parts'] as List?);
      if (parts2 == null || parts2.isEmpty) {
        yield '❌ Gemini Vision: respons kosong.';
        return;
      }
      yield parts2[0]['text'] as String? ?? '';
    } catch (e) {
      debugPrint('[AiService] _sendGeminiVision error: $e');
      yield '❌ Gemini Vision error: $e';
    }
  }

  // OpenAI-compatible vision (Groq, OpenAI, OpenRouter, dll)
  Stream<String> _sendOpenAiVision(
    String text,
    List<cm.ChatAttachment> images,
    List<Map<String, String>> history,
    String? preferredKeyId,
    BulkApiProvider provider,
  ) async* {
    try {
      final key = BulkApiService.instance.getNextKey(provider);
      if (key == null) {
        yield '❌ Tidak ada API key untuk ${provider.label} tersedia.';
        return;
      }

      final model = key.model.isNotEmpty ? key.model : 'gpt-4o';
      final baseUrl = key.provider == BulkApiProvider.custom && key.customUrl.isNotEmpty
          ? key.customUrl
          : key.provider.apiUrl;

      // Build messages
      final messages = <Map<String, dynamic>>[];
      messages.add({'role': 'system', 'content': _defaultSystemPrompt});
      for (final h in history) {
        messages.add({'role': h['role'] ?? 'user', 'content': h['content'] ?? ''});
      }

      // Build content array for vision
      final contentArr = <Map<String, dynamic>>[];
      if (text.isNotEmpty) contentArr.add({'type': 'text', 'text': text});
      for (final img in images) {
        final bytes = img.thumbnailBytes!;
        final b64 = base64Encode(bytes);
        contentArr.add({
          'type': 'image_url',
          'image_url': {'url': 'data:image/jpeg;base64,$b64'},
        });
      }
      messages.add({'role': 'user', 'content': contentArr});

      final body = jsonEncode({
        'model': model,
        'messages': messages,
        'max_tokens': 1024,
        'stream': false,
      });

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${key.apiKey}',
      };

      final resp = await http
          .post(Uri.parse(baseUrl),
              headers: headers, body: body)
          .timeout(const Duration(seconds: 60));

      if (resp.statusCode != 200) {
        yield '❌ Vision API error ${resp.statusCode}: ${resp.body}';
        return;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        yield '❌ Vision: tidak ada respons dari model.';
        return;
      }
      yield choices[0]['message']?['content'] as String? ?? '';
    } catch (e) {
      debugPrint('[AiService] _sendOpenAiVision error: $e');
      yield '❌ Vision error: $e';
    }
  }

  // ── Web Research Stream ────────────────────────────────────────────────────
  /// Stream web research + AI response.
  /// Yields: status → sources → token(s)... → done
  Stream<WebResearchStreamEvent> sendWithWebResearch({
    required String userQuery,
    required List<Map<String, dynamic>> history,
    void Function(String)? onResearchProgress,
    String searchEngine = 'ddg',
    bool fetchContent = true,
    AiMode? forceMode,
    String? forceBulkKeyId,
    BulkApiProvider? forceProvider,
  }) async* {
    yield WebResearchStreamEvent.status('🔍 Memulai web research...');

    // Cek internet SEBELUM research
    final hasInternet = await TerminalService.instance.checkInternet();
    if (!hasInternet) {
      yield WebResearchStreamEvent.token(
          '❌ Web research memerlukan koneksi internet. '
          'Jawaban berikut berdasarkan pengetahuan AI saja.\n\n');
      yield* _dispatchTextAsEvents(
          userQuery, history, forceMode, forceBulkKeyId, forceProvider);
      yield WebResearchStreamEvent.done();
      return;
    }

    // Lakukan research
    ResearchResult? research;
    try {
      research = await WebResearchService.instance.research(
        userQuery,
        onProgress: (s) {
          onResearchProgress?.call(s);
        },
        engine: searchEngine,
        fetchContent: fetchContent,
      );
    } catch (e) {
      debugPrint('[AiService] web research error: $e');
      yield WebResearchStreamEvent.token(
          '⚠️ Web research gagal ($e). Menjawab dari pengetahuan AI...\n\n');
      yield* _dispatchTextAsEvents(
          userQuery, history, forceMode, forceBulkKeyId, forceProvider);
      yield WebResearchStreamEvent.done();
      return;
    }

    // Emit sumber ke UI
    yield WebResearchStreamEvent.sources(research.sources);

    if (research.hasError || research.isEmpty) {
      yield WebResearchStreamEvent.token(
          '⚠️ Tidak ada hasil web research. Menjawab dari pengetahuan AI...\n\n');
      yield* _dispatchTextAsEvents(
          userQuery, history, forceMode, forceBulkKeyId, forceProvider);
      yield WebResearchStreamEvent.done();
      return;
    }

    yield WebResearchStreamEvent.status(
        '🧠 Menganalisis ${research.sources.length} sumber...');

    // Build augmented prompt berdasarkan mode
    final mode = forceMode ?? currentMode;
    final String context;
    if (mode == AiMode.offline) {
      context = WebResearchService.instance.buildOfflineContext(research);
    } else {
      context = research.contextForAi;
    }

    final augmentedPrompt = '''$context

=== PERTANYAAN USER ===
$userQuery

Jawab berdasarkan web research di atas. Gunakan bahasa Indonesia natural.
Cantumkan [nomor] saat mengutip sumber spesifik.''';

    yield WebResearchStreamEvent.status('🤖 Memproses dengan AI...');

    // Dispatch ke AI engine
    try {
      yield* _dispatchTextAsEvents(
          augmentedPrompt, history, forceMode, forceBulkKeyId, forceProvider);
    } catch (e) {
      yield WebResearchStreamEvent.token('❌ Error AI: $e');
    }

    yield WebResearchStreamEvent.done();
  }

  /// Helper: wrap text stream ke WebResearchStreamEvent.token
  Stream<WebResearchStreamEvent> _dispatchTextAsEvents(
    String text,
    List<Map<String, dynamic>> history,
    AiMode? forceMode,
    String? bulkKeyId,
    BulkApiProvider? forceProvider,
  ) async* {
    final mode = forceMode ?? currentMode;

    // Konversi history Map<String, dynamic> → Map<String, String>
    final historyStr = history
        .map((m) => <String, String>{
              'role': (m['role'] as String?) ?? 'user',
              'content': (m['content'] as String?) ?? '',
            })
        .toList();

    switch (mode) {
      case AiMode.bulkApi:
        yield* BulkApiService.instance
            .sendChatStream(
              userMessage: text,
              systemPrompt: _defaultSystemPrompt,
              history: historyStr,
              preferredProvider: forceProvider,
            )
            .map((t) => WebResearchStreamEvent.token(t));
        break;

      case AiMode.online:
        yield* PuterAiService.instance
            .chatStream(
              systemPrompt: _defaultSystemPrompt,
              history: historyStr,
              userMessage: text,
            )
            .map((t) => WebResearchStreamEvent.token(t));
        break;

      case AiMode.offline:
        final messages = <ChatMessage>[];
        for (final h in historyStr.take(_maxHistory)) {
          if (h['role'] == 'user') {
            messages.add(ChatMessage.user(h['content'] ?? ''));
          } else {
            messages.add(ChatMessage.assistant(h['content'] ?? ''));
          }
        }
        messages.add(ChatMessage.user(text));

        if (LlamaService.instance.isModelLoaded) {
          yield* LlamaService.instance
              .generateStream(
                messages: messages,
                config: InferenceConfig.defaultConfig,
                systemPromptOverride: _defaultSystemPrompt,
              )
              .map((t) => WebResearchStreamEvent.token(t));
        } else {
          // Fallback ke _offlineChatStream via sendChatStream
          yield* _offlineChatStream(
            _defaultSystemPrompt,
            historyStr,
            text,
          ).map((t) => WebResearchStreamEvent.token(t));
        }
        break;

      default:
        yield WebResearchStreamEvent.token(
            '❌ Tidak ada mode AI aktif. Aktifkan model terlebih dahulu.');
    }
  }

  /// Build prompt sederhana untuk offline inference (history + current message)
  String _buildOfflinePrompt(
      String text, List<Map<String, dynamic>> history) {
    final buf = StringBuffer();
    for (final msg in history.take(10)) {
      final role = msg['role'] == 'user' ? 'User' : 'Assistant';
      buf.writeln('$role: ${msg['content']}');
    }
    buf.writeln('User: $text');
    buf.writeln('Assistant:');
    return buf.toString();
  }

  // ── Adaptive Edit Pipeline ────────────────────────────────────────────────
  /// Full adaptive edit pipeline: analyze → web research → plan → execute.
  ///
  /// [userRequest]  — what the user wants to do (from chat input)
  /// [attachments]  — list of attached files (code, image, video, etc.)
  /// [history]      — current conversation history for context
  Stream<AdaptiveEditEvent> executeAdaptiveEdit({
    required String userRequest,
    required List<cm.ChatAttachment> attachments,
    required List<Map<String, String>> history,
  }) async* {
    try {
      // ── PHASE 1: Analyze attached files ──────────────────────────────────
      yield AdaptiveEditEvent.analyzing('📂 Menganalisis file yang dilampirkan...');

      final fileContextParts = <String>[];
      final imageAttachments = <cm.ChatAttachment>[];

      for (final att in attachments) {
        switch (att.type) {
          case cm.AttachmentType.image:
            imageAttachments.add(att);
            fileContextParts.add('[Gambar: ${att.filename} — ${att.sizeLabel}]');
            break;
          case cm.AttachmentType.video:
            final dur = att.videoDuration != null
                ? ', durasi: ${att.videoDuration}'
                : '';
            fileContextParts.add('[Video: ${att.filename}${dur}]');
            break;
          case cm.AttachmentType.audio:
            fileContextParts.add('[Audio: ${att.filename} — ${att.sizeLabel}]');
            break;
          case cm.AttachmentType.code:
          case cm.AttachmentType.text:
            if (att.extractedText != null) {
              final lines = att.extractedText!.split('\n').length;
              fileContextParts.add('[Kode/Teks: ${att.filename} — $lines baris]');
            }
            break;
          default:
            fileContextParts.add('[File: ${att.filename} — ${att.sizeLabel}]');
        }
      }

      yield AdaptiveEditEvent.analyzing(
          '📂 Ditemukan ${attachments.length} file: '
          '${fileContextParts.join(", ")}');

      // ── PHASE 2: Web Research ─────────────────────────────────────────────
      final hasInternet = await TerminalService.instance.checkInternet();
      String researchContext = '';

      if (hasInternet) {
        yield AdaptiveEditEvent.researching('🔍 Mencari praktik terbaik...');

        final fileTypes = attachments
            .map((a) => _attachmentTypeLabel(a.type))
            .toSet()
            .join(', ');
        final searchQuery = attachments.isNotEmpty
            ? '${userRequest.length > 60 ? userRequest.substring(0, 60) : userRequest} $fileTypes best practices'
            : userRequest;

        try {
          final research = await WebResearchService.instance.research(
            searchQuery,
            onProgress: (s) {},
            engine: 'ddg',
            fetchContent: true,
          );

          if (!research.isEmpty) {
            researchContext = research.contextForAi;
            yield AdaptiveEditEvent.researching(
                '🔍 Ditemukan ${research.sources.length} referensi terkait');
          } else {
            yield AdaptiveEditEvent.researching(
                '🔍 Tidak ada hasil web research — lanjut tanpa referensi');
          }
        } catch (e) {
          debugPrint('[AiService.adaptiveEdit] research error: $e');
          yield AdaptiveEditEvent.researching(
              '🔍 Web research gagal ($e) — lanjut tanpa referensi');
        }
      } else {
        yield AdaptiveEditEvent.researching('📴 Offline — melewati web research');
      }

      // ── PHASE 3: Build comprehensive plan/prompt ──────────────────────────
      yield AdaptiveEditEvent.planning('🧠 Membangun rencana eksekusi...');

      final sb = StringBuffer();

      sb.writeln('You are an expert AI editor and developer.');
      sb.writeln('The user has attached files and wants you to edit/transform them.');
      sb.writeln('Your job is to EXECUTE the edit directly — not describe what you will do.');
      sb.writeln('');

      if (researchContext.isNotEmpty) {
        sb.writeln('=== WEB RESEARCH CONTEXT ===');
        sb.writeln(researchContext.length > 6000
            ? researchContext.substring(0, 6000) + '\n...[truncated]'
            : researchContext);
        sb.writeln('=== END RESEARCH ===');
        sb.writeln('');
      }

      if (attachments.isNotEmpty) {
        sb.writeln('=== ATTACHED FILES ===');
        for (final att in attachments) {
          if (att.extractedText != null && att.extractedText!.isNotEmpty) {
            final content = att.extractedText!;
            final truncated = content.length > 12000
                ? '${content.substring(0, 12000)}\n...[truncated — ${content.length} total chars]'
                : content;
            sb.writeln('--- File: ${att.filename} ---');
            sb.writeln('```');
            sb.writeln(truncated);
            sb.writeln('```');
          } else if (att.type == cm.AttachmentType.image) {
            sb.writeln('--- Image: ${att.filename} (${att.sizeLabel}) ---');
            sb.writeln('[Image attached — analyze visually if vision is supported]');
          } else if (att.type == cm.AttachmentType.video) {
            final dur = att.videoDuration != null
                ? ', duration: ${att.videoDuration}'
                : '';
            sb.writeln('--- Video: ${att.filename}${dur} ---');
            sb.writeln('File path: ${att.path}');
            sb.writeln('[Provide the exact ffmpeg command to execute this edit]');
          } else {
            sb.writeln('--- File: ${att.filename} (${att.sizeLabel}) ---');
          }
        }
        sb.writeln('=== END FILES ===');
        sb.writeln('');
      }

      sb.writeln('=== USER REQUEST ===');
      sb.writeln(userRequest);
      sb.writeln('=== END REQUEST ===');
      sb.writeln('');

      final hasCode = attachments.any((a) =>
          a.type == cm.AttachmentType.code ||
          a.type == cm.AttachmentType.text);
      final hasVideo = attachments.any((a) => a.type == cm.AttachmentType.video);
      final hasImg = attachments.any((a) => a.type == cm.AttachmentType.image);

      if (hasCode) {
        sb.writeln('INSTRUCTIONS:');
        sb.writeln('- Output the COMPLETE modified file content');
        sb.writeln('- Wrap the code in triple backticks with language identifier');
        sb.writeln('- Do NOT truncate — output every line');
        sb.writeln('- After the code, add a brief summary of changes made');
      } else if (hasVideo) {
        sb.writeln('INSTRUCTIONS:');
        sb.writeln('- Provide the exact ffmpeg shell command to execute this edit');
        sb.writeln('- Use the file path shown above as input');
        sb.writeln('- Choose output format appropriate for the operation');
        sb.writeln('- Explain what the command does in one sentence');
      } else if (hasImg) {
        sb.writeln('INSTRUCTIONS:');
        sb.writeln('- Analyze the image thoroughly');
        sb.writeln('- Execute the requested edit/analysis directly');
        sb.writeln('- If editing is requested, provide specific transformation steps');
      } else {
        sb.writeln('INSTRUCTIONS:');
        sb.writeln('- Execute the user request directly and completely');
        sb.writeln('- Provide all output without truncation');
      }

      final finalPrompt = sb.toString();
      yield AdaptiveEditEvent.planning('🧠 Rencana siap — memulai eksekusi AI...');

      // ── PHASE 4: Execute via AI ───────────────────────────────────────────
      yield AdaptiveEditEvent.executing('');

      final mode = currentMode;
      bool gotAnyToken = false;

      try {
        if (imageAttachments.isNotEmpty &&
            (mode == AiMode.bulkApi || mode == AiMode.online)) {
          yield* sendWithAttachments(
            userText: finalPrompt,
            attachments: imageAttachments,
            history: history,
          ).map((token) {
            gotAnyToken = true;
            return AdaptiveEditEvent.executing(token);
          });
        } else {
          yield* sendChatStream(
            systemPrompt: 'You are an expert AI editor. Execute edits directly.',
            history: history,
            userMessage: finalPrompt,
            temperature: 0.2,
            maxTokens: 4096,
          ).map((token) {
            gotAnyToken = true;
            return AdaptiveEditEvent.executing(token);
          });
        }

        if (!gotAnyToken) {
          yield AdaptiveEditEvent.error(
              '❌ AI tidak menghasilkan respons. Pastikan model aktif.');
          return;
        }
      } catch (e) {
        debugPrint('[AiService.adaptiveEdit] execute error: $e');
        yield AdaptiveEditEvent.error('❌ Error eksekusi: $e');
        return;
      }

      // ── PHASE 5: Done ─────────────────────────────────────────────────────
      yield AdaptiveEditEvent.done();
    } catch (e, stack) {
      debugPrint('[AiService.adaptiveEdit] fatal error: $e\n$stack');
      yield AdaptiveEditEvent.error('❌ Fatal error di adaptive edit pipeline: $e');
    }
  }

  /// Human-readable label for attachment type (used in search query)
  String _attachmentTypeLabel(cm.AttachmentType type) {
    switch (type) {
      case cm.AttachmentType.image:   return 'image editing';
      case cm.AttachmentType.video:   return 'video editing ffmpeg';
      case cm.AttachmentType.audio:   return 'audio processing';
      case cm.AttachmentType.code:    return 'code refactoring';
      case cm.AttachmentType.text:    return 'text editing';
      case cm.AttachmentType.pdf:     return 'PDF processing';
      case cm.AttachmentType.archive: return 'archive extraction';
      default:                        return 'file processing';
    }
  }

  // ── Edit media + kirim hasil ke user ─────────────────────────────────────
  // Dipanggil dari chat screen ketika user kirim file + minta edit.
  // Yield token teks dulu (penjelasan AI), lalu yield token khusus
  // "FILE_OUTPUT:<path>" di akhir agar UI bisa render tombol download.
  Stream<String> editMediaAndReply({
    required String filePath,
    required String userRequest,
    required String systemPrompt,
    required List<Map<String, String>> history,
  }) async* {
    // 1. Minta AI parse operasi dari request
    yield '🤔 Menganalisis permintaan edit...\n\n';

    final parsePrompt = '''
User ingin mengedit file media: "$filePath"
Request: "$userRequest"

Tentukan operasi yang tepat. Balas HANYA dengan JSON berikut (tidak ada teks lain):
{
  "operation": "<salah satu: resize|crop|rotate|flip|compress|trim|convert|watermark|thumbnail|grayscale|brightness|contrast|blur|speed|volume|extract_audio>",
  "params": {
    // parameter relevan untuk operasi tersebut
  },
  "explanation": "<penjelasan singkat apa yang akan dilakukan>"
}
''';

    Map<String, dynamic>? parsed;
    try {
      parsed = await generateJson(prompt: parsePrompt);
    } catch (_) {}

    if (parsed == null || parsed['operation'] == null) {
      yield '❌ Tidak bisa memahami permintaan edit. Tolong lebih spesifik.\n\n'
            'Contoh: "resize jadi 720p", "potong 0-30 detik", "kompres video", '
            '"rotasi 90 derajat", "extract audio"\n';
      return;
    }

    final operation = parsed['operation'] as String;
    final params    = Map<String, dynamic>.from(parsed['params'] as Map? ?? {});
    final explain   = parsed['explanation'] as String? ?? 'Memproses...';

    yield '✏️ $explain\n\n';

    // 2. Cek tool yang dibutuhkan
    yield '🔍 Memeriksa tool yang dibutuhkan...\n';
    final toolCheck = await ToolInstallerService.instance
        .ensureToolForOperation(operation);
    if (!toolCheck.success) {
      yield '⬇️ Menginstall tool yang dibutuhkan...\n';
      yield* ToolInstallerService.instance.installToolStream('ffmpeg');
      // Cek ulang setelah install
      final recheck = await ToolInstallerService.instance
          .ensureToolForOperation(operation);
      if (!recheck.success) {
        yield '\n❌ Tool tidak berhasil diinstall: ${recheck.installHint}\n';
        return;
      }
    }
    yield '✅ Tool siap.\n\n';

    // 3. Jalankan edit
    yield '⚙️ Mengedit file...\n';
    final editResult = await MediaEditService.instance.edit(
      inputPath: filePath,
      operation: operation,
      params:    params,
    );

    if (!editResult.success) {
      yield '\n❌ Edit gagal: ${editResult.error}\n';
      return;
    }

    yield '✅ ${editResult.details}\n\n';

    // 4. Kirim token khusus agar UI render tombol download
    yield 'FILE_OUTPUT:${editResult.outputPath}\n';
  }
}
