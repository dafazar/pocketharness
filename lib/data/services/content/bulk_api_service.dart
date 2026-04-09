// lib/data/services/content/bulk_api_service.dart
// KanMon GO — Bulk API Key Manager
//
// Mengelola banyak API key untuk berbagai provider AI (Claude, Groq, Gemini, dll)
// dengan mode Fallback (auto-rotate saat limit) atau Select (pilih manual).
// =============================================================================

import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// ── Provider AI yang didukung ─────────────────────────────────────────────────
enum BulkApiProvider {
  anthropic,   // Claude
  groq,        // Groq (free, fast: Llama, Mixtral, Gemma)
  gemini,      // Google Gemini
  openai,      // OpenAI
  together,    // Together.ai
  mistral,     // Mistral AI
  openrouter,  // OpenRouter (akses banyak model via 1 key)
  custom,      // Custom endpoint
}

extension BulkApiProviderX on BulkApiProvider {
  String get label {
    switch (this) {
      case BulkApiProvider.anthropic:  return 'Claude (Anthropic)';
      case BulkApiProvider.groq:       return 'Groq (Free)';
      case BulkApiProvider.gemini:     return 'Gemini (Google)';
      case BulkApiProvider.openai:     return 'OpenAI';
      case BulkApiProvider.together:   return 'Together.ai';
      case BulkApiProvider.mistral:    return 'Mistral AI';
      case BulkApiProvider.openrouter: return 'OpenRouter';
      case BulkApiProvider.custom:     return 'Custom';
    }
  }

  String get emoji {
    switch (this) {
      case BulkApiProvider.anthropic:  return '🤖';
      case BulkApiProvider.groq:       return '⚡';
      case BulkApiProvider.gemini:     return '✨';
      case BulkApiProvider.openai:     return '🧠';
      case BulkApiProvider.together:   return '🤝';
      case BulkApiProvider.mistral:    return '🌬️';
      case BulkApiProvider.openrouter: return '🔀';
      case BulkApiProvider.custom:     return '⚙️';
    }
  }

  String get defaultModel {
    switch (this) {
      case BulkApiProvider.anthropic:  return 'claude-3-haiku-20240307';
      case BulkApiProvider.groq:       return 'llama-3.3-70b-versatile';
      case BulkApiProvider.gemini:     return 'gemini-1.5-flash';
      case BulkApiProvider.openai:     return 'gpt-4o-mini';
      case BulkApiProvider.together:   return 'meta-llama/Llama-3.3-70B-Instruct-Turbo-Free';
      case BulkApiProvider.mistral:    return 'mistral-small-latest';
      case BulkApiProvider.openrouter: return 'meta-llama/llama-3.3-70b-instruct:free';
      case BulkApiProvider.custom:     return 'custom';
    }
  }

  String get apiUrl {
    switch (this) {
      case BulkApiProvider.anthropic:  return 'https://api.anthropic.com/v1/messages';
      case BulkApiProvider.groq:       return 'https://api.groq.com/openai/v1/chat/completions';
      case BulkApiProvider.gemini:     return 'https://generativelanguage.googleapis.com/v1beta/models';
      case BulkApiProvider.openai:     return 'https://api.openai.com/v1/chat/completions';
      case BulkApiProvider.together:   return 'https://api.together.xyz/v1/chat/completions';
      case BulkApiProvider.mistral:    return 'https://api.mistral.ai/v1/chat/completions';
      case BulkApiProvider.openrouter: return 'https://openrouter.ai/api/v1/chat/completions';
      case BulkApiProvider.custom:     return '';
    }
  }

  bool get isFree {
    switch (this) {
      case BulkApiProvider.groq:
      case BulkApiProvider.together:
      case BulkApiProvider.openrouter:
        return true;
      default:
        return false;
    }
  }

  String get getKeyUrl {
    switch (this) {
      case BulkApiProvider.anthropic:  return 'https://console.anthropic.com/keys';
      case BulkApiProvider.groq:       return 'https://console.groq.com/keys';
      case BulkApiProvider.gemini:     return 'https://aistudio.google.com/app/apikey';
      case BulkApiProvider.openai:     return 'https://platform.openai.com/api-keys';
      case BulkApiProvider.together:   return 'https://api.together.xyz/settings/api-keys';
      case BulkApiProvider.mistral:    return 'https://console.mistral.ai/api-keys';
      case BulkApiProvider.openrouter: return 'https://openrouter.ai/keys';
      case BulkApiProvider.custom:     return '';
    }
  }
}

// ── Mode load key ─────────────────────────────────────────────────────────────
enum BulkLoadMode {
  fallback, // Auto-rotate ke key berikutnya saat rate limit / error
  select,   // User pilih key mana yang aktif
  roundRobin, // Bergantian setiap request
}

extension BulkLoadModeX on BulkLoadMode {
  String get label {
    switch (this) {
      case BulkLoadMode.fallback:    return 'Fallback';
      case BulkLoadMode.select:      return 'Select';
      case BulkLoadMode.roundRobin:  return 'Round Robin';
    }
  }
  String get description {
    switch (this) {
      case BulkLoadMode.fallback:   return 'Auto-ganti key berikutnya jika limit/error';
      case BulkLoadMode.select:     return 'Pilih manual key mana yang dipakai';
      case BulkLoadMode.roundRobin: return 'Bergantian setiap request (distribusi merata)';
    }
  }
}

// ── Attachment payload untuk multimodal AI requests ──────────────────────────
class ChatAttachmentPayload {
  final String filename;
  final String mimeType;
  final String? base64Data;   // non-null untuk image ≤ 5MB
  final String? textContent;  // non-null untuk text/code files
  final int sizeBytes;

  const ChatAttachmentPayload({
    required this.filename,
    required this.mimeType,
    this.base64Data,
    this.textContent,
    required this.sizeBytes,
  });

  bool get isImage =>
      mimeType.startsWith('image/') ||
      ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp']
          .contains(filename.split('.').last.toLowerCase());

  bool get isText => textContent != null && textContent!.isNotEmpty;
}

// ── Model satu API key ────────────────────────────────────────────────────────
class BulkApiKey {
  final String id;
  final BulkApiProvider provider;
  String apiKey;
  String label;
  String customUrl; // Untuk provider=custom
  String customModel;
  bool isActive;
  bool isLimitReached;
  DateTime? limitReachedAt;
  int successCount;
  int failCount;
  DateTime? lastUsed;

  // ── Firebase config (opsional, diisi saat import google-services.json) ────
  // Menyimpan semua field dari google-services.json / GoogleService-Info.plist
  // agar app bisa menggunakan info project Firebase secara lengkap.
  Map<String, String> firebaseConfig;

  BulkApiKey({
    String? id,
    required this.provider,
    required this.apiKey,
    this.label = '',
    this.customUrl = '',
    this.customModel = '',
    this.isActive = true,
    this.isLimitReached = false,
    this.limitReachedAt,
    this.successCount = 0,
    this.failCount = 0,
    this.lastUsed,
    Map<String, String>? firebaseConfig,
  })  : id = id ?? const Uuid().v4(),
        firebaseConfig = firebaseConfig ?? {};

  String get displayLabel =>
      label.isNotEmpty ? label : '${provider.emoji} Key ${apiKey.substring(0, apiKey.length.clamp(0, 8))}...';

  String get statusEmoji {
    if (!isActive) return '⛔';
    if (isLimitReached) return '🔴';
    return '🟢';
  }

  /// True jika key ini hanya berisi Firebase config — BUKAN Gemini API key.
  /// Gemini API key selalu diawali "AIza" dan panjangnya 39 karakter.
  /// Firebase Project ID / config bukan API key dan tidak bisa digunakan untuk memanggil Gemini.
  bool get isFirebaseOnly =>
      apiKey == '__firebase_config__' ||
      apiKey.isEmpty ||
      (provider == BulkApiProvider.gemini && !apiKey.startsWith('AIza'));

  bool get canUse => isActive && !isLimitReached && !isFirebaseOnly;

  /// Getter untuk model — gunakan customModel jika ada, atau fallback ke default provider
  String get model => customModel.isNotEmpty ? customModel : provider.defaultModel;

  // Auto-reset limit setelah 1 jam
  bool get isLimitExpired {
    if (limitReachedAt == null) return true;
    return DateTime.now().difference(limitReachedAt!).inMinutes > 60;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'provider': provider.name,
    'apiKey': apiKey,
    'label': label,
    'customUrl': customUrl,
    'customModel': customModel,
    'isActive': isActive,
    'isLimitReached': isLimitReached && !isLimitExpired,
    'limitReachedAt': limitReachedAt?.millisecondsSinceEpoch,
    'successCount': successCount,
    'failCount': failCount,
    'lastUsed': lastUsed?.millisecondsSinceEpoch,
    'firebaseConfig': firebaseConfig,
  };

  factory BulkApiKey.fromJson(Map<String, dynamic> j) {
    final provider = BulkApiProvider.values.firstWhere(
      (p) => p.name == j['provider'],
      orElse: () => BulkApiProvider.custom,
    );
    // Parse firebaseConfig — backward-compat: field mungkin tidak ada di data lama
    Map<String, String> fbConfig = {};
    if (j['firebaseConfig'] is Map) {
      (j['firebaseConfig'] as Map).forEach((k, v) {
        if (k is String && v is String) fbConfig[k] = v;
      });
    }
    return BulkApiKey(
      id: j['id'] as String,
      provider: provider,
      apiKey: j['apiKey'] as String? ?? '',
      label: j['label'] as String? ?? '',
      customUrl: j['customUrl'] as String? ?? '',
      customModel: j['customModel'] as String? ?? '',
      isActive: j['isActive'] as bool? ?? true,
      isLimitReached: j['isLimitReached'] as bool? ?? false,
      limitReachedAt: j['limitReachedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(j['limitReachedAt'] as int)
          : null,
      successCount: j['successCount'] as int? ?? 0,
      failCount: j['failCount'] as int? ?? 0,
      lastUsed: j['lastUsed'] != null
          ? DateTime.fromMillisecondsSinceEpoch(j['lastUsed'] as int)
          : null,
      firebaseConfig: fbConfig,
    );
  }
}

// ── Hasil chat dari bulk API ──────────────────────────────────────────────────
class BulkApiResult {
  final bool success;
  final String content;
  final String? error;
  final String? usedKeyId;
  final BulkApiProvider? usedProvider;

  const BulkApiResult({
    required this.success,
    this.content = '',
    this.error,
    this.usedKeyId,
    this.usedProvider,
  });
}

// ── Service utama ─────────────────────────────────────────────────────────────
class BulkApiService {
  BulkApiService._();
  static final BulkApiService instance = BulkApiService._();

  static const _prefsKey   = 'bulk_api_keys_v2';
  static const _modeKey    = 'bulk_api_mode';
  static const _enabledKey = 'bulk_api_enabled';
  static const _selKeyKey  = 'bulk_api_selected_key';
  static const _rrIndexKey = 'bulk_api_rr_index';

  final List<BulkApiKey> _keys = [];
  BulkLoadMode _mode = BulkLoadMode.fallback;
  bool _enabled = false;
  String? _selectedKeyId;
  int _rrIndex = 0;

  List<BulkApiKey> get keys => List.unmodifiable(_keys);
  BulkLoadMode get mode => _mode;
  bool get enabled => _enabled;
  String? get selectedKeyId => _selectedKeyId;

  List<BulkApiKey> keysForProvider(BulkApiProvider p) =>
      _keys.where((k) => k.provider == p).toList();

  List<BulkApiKey> get activeKeys =>
      _keys.where((k) => k.canUse || k.isLimitExpired).toList();

  // ── Load / Save ───────────────────────────────────────────────────────────
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? false;
      _mode = BulkLoadMode.values.firstWhere(
        (m) => m.name == (prefs.getString(_modeKey) ?? ''),
        orElse: () => BulkLoadMode.fallback,
      );
      _selectedKeyId = prefs.getString(_selKeyKey);
      _rrIndex = prefs.getInt(_rrIndexKey) ?? 0;

      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _keys.clear();
        for (final item in list) {
          final key = BulkApiKey.fromJson(item as Map<String, dynamic>);
          // Auto-reset expired limits
          if (key.isLimitReached && key.isLimitExpired) {
            key.isLimitReached = false;
            key.limitReachedAt = null;
          }
          _keys.add(key);
        }
      }
      debugPrint('[BulkApi] Loaded ${_keys.length} keys, mode=$_mode, enabled=$_enabled');
    } catch (e) {
      debugPrint('[BulkApi] Load error: $e');
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_keys.map((k) => k.toJson()).toList()));
      await prefs.setString(_modeKey, _mode.name);
      await prefs.setBool(_enabledKey, _enabled);
      if (_selectedKeyId != null) {
        await prefs.setString(_selKeyKey, _selectedKeyId!);
      }
      await prefs.setInt(_rrIndexKey, _rrIndex);
    } catch (e) {
      debugPrint('[BulkApi] Save error: $e');
    }
  }

  // ── Manage keys ───────────────────────────────────────────────────────────
  Future<BulkApiKey> addKey({
    required BulkApiProvider provider,
    required String apiKey,
    String label = '',
    String customUrl = '',
    String customModel = '',
    Map<String, String>? firebaseConfig,
  }) async {
    final key = BulkApiKey(
      provider: provider,
      apiKey: apiKey,
      label: label,
      customUrl: customUrl,
      customModel: customModel,
      firebaseConfig: firebaseConfig,
    );
    _keys.add(key);
    await save();
    return key;
  }

  Future<void> removeKey(String id) async {
    _keys.removeWhere((k) => k.id == id);
    if (_selectedKeyId == id) _selectedKeyId = null;
    await save();
  }

  Future<void> updateKey(BulkApiKey key) async {
    final i = _keys.indexWhere((k) => k.id == key.id);
    if (i >= 0) _keys[i] = key;
    await save();
  }

  Future<void> setMode(BulkLoadMode mode) async {
    _mode = mode;
    await save();
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    await save();
  }

  Future<void> setSelectedKey(String? id) async {
    _selectedKeyId = id;
    await save();
  }

  Future<void> markKeyLimited(String id) async {
    final key = _keys.firstWhere((k) => k.id == id, orElse: () => throw Exception('Key not found'));
    key.isLimitReached = true;
    key.limitReachedAt = DateTime.now();
    key.failCount++;
    await save();
    debugPrint('[BulkApi] Key $id marked as rate-limited');
  }

  Future<void> markKeySuccess(String id) async {
    try {
      final key = _keys.firstWhere((k) => k.id == id);
      key.successCount++;
      key.lastUsed = DateTime.now();
      await save();
    } catch (_) {}
  }

  Future<void> resetAllLimits() async {
    for (final k in _keys) {
      k.isLimitReached = false;
      k.limitReachedAt = null;
    }
    await save();
  }

  // ── Pilih key aktif berdasarkan mode ─────────────────────────────────────
  BulkApiKey? getNextKey(BulkApiProvider? preferredProvider) {
    List<BulkApiKey> candidates;

    if (preferredProvider != null) {
      candidates = _keys.where((k) => k.provider == preferredProvider && k.canUse).toList();
      // Auto-reset expired limits
      if (candidates.isEmpty) {
        final expired = _keys.where((k) => k.provider == preferredProvider && k.isLimitExpired && k.isActive).toList();
        for (final k in expired) {
          k.isLimitReached = false;
          k.limitReachedAt = null;
        }
        candidates = _keys.where((k) => k.provider == preferredProvider && k.canUse).toList();
      }
    } else {
      candidates = _keys.where((k) => k.canUse).toList();
    }

    if (candidates.isEmpty) return null;

    switch (_mode) {
      case BulkLoadMode.select:
        if (_selectedKeyId != null) {
          return candidates.firstWhere((k) => k.id == _selectedKeyId, orElse: () => candidates.first);
        }
        return candidates.first;

      case BulkLoadMode.roundRobin:
        if (_rrIndex >= candidates.length) _rrIndex = 0;
        final key = candidates[_rrIndex % candidates.length];
        _rrIndex = (_rrIndex + 1) % candidates.length;
        save();
        return key;

      case BulkLoadMode.fallback:
      default:
        return candidates.first;
    }
  }

  // ── Kirim chat ke provider ────────────────────────────────────────────────
  Future<BulkApiResult> sendChat({
    required String userMessage,
    String systemPrompt = '',
    List<Map<String, String>> history = const [],
    BulkApiProvider? preferredProvider,
    String? preferredKeyId,
    int maxTokens = 1024,
    double temperature = 0.7,
    List<ChatAttachmentPayload> attachments = const [],
  }) async {
    if (!_enabled) {
      return const BulkApiResult(success: false, error: 'Bulk API tidak aktif');
    }

    // Collect candidate keys
    List<BulkApiKey> candidates;
    if (preferredKeyId != null) {
      candidates = _keys.where((k) => k.id == preferredKeyId && k.canUse).toList();
    } else if (preferredProvider != null) {
      candidates = _keys.where((k) => k.provider == preferredProvider && k.canUse).toList();
    } else {
      candidates = _keys.where((k) => k.canUse).toList();
    }

    if (candidates.isEmpty) {
      // Try to reset expired limits
      for (final k in _keys) {
        if (k.isLimitReached && k.isLimitExpired) {
          k.isLimitReached = false;
          k.limitReachedAt = null;
        }
      }
      candidates = preferredProvider != null
          ? _keys.where((k) => k.provider == preferredProvider && k.canUse).toList()
          : _keys.where((k) => k.canUse).toList();
    }

    if (candidates.isEmpty) {
      // Cek apakah ada key Firebase-only yang mungkin menyebabkan kebingungan
      final hasFirebaseOnly = _keys.any((k) => k.isFirebaseOnly && k.isActive);
      final msg = hasFirebaseOnly
          ? 'Tidak ada Gemini API Key yang valid.\n\n'
            '⚠️ Terdeteksi Firebase config — bukan Gemini API Key.\n\n'
            'Gemini API Key harus diambil dari:\n'
            '→ https://aistudio.google.com/app/apikey\n\n'
            'Format: AIzaSy... (39 karakter)\n'
            'Bukan Project ID atau App ID Firebase.'
          : 'Tidak ada API key yang tersedia. Semua key sudah mencapai limit.';
      return BulkApiResult(success: false, error: msg);
    }

    // Try each key
    for (final key in candidates) {
      try {
        final result = await _callProvider(
          key: key,
          userMessage: userMessage,
          systemPrompt: systemPrompt,
          history: history,
          maxTokens: maxTokens,
          temperature: temperature,
          attachments: attachments,
        );

        if (result.success) {
          await markKeySuccess(key.id);
          return result;
        }

        // Rate limit → mark and try next (only in fallback/roundRobin mode)
        if (result.error?.contains('429') == true ||
            result.error?.contains('rate') == true ||
            result.error?.contains('limit') == true ||
            result.error?.contains('quota') == true) {
          await markKeyLimited(key.id);
          debugPrint('[BulkApi] Key ${key.id} rate limited, trying next...');
          if (_mode == BulkLoadMode.select) {
            return result; // In select mode, don't auto-rotate
          }
          continue; // In fallback mode, try next key
        }

        // Other error
        return result;
      } catch (e) {
        debugPrint('[BulkApi] Key ${key.id} error: $e');
        if (_mode != BulkLoadMode.select) continue;
        return BulkApiResult(success: false, error: e.toString());
      }
    }

    return const BulkApiResult(
      success: false,
      error: 'Semua API key gagal. Coba reset limit atau tambah key baru.',
    );
  }

  // ── Internal: call API berdasarkan provider ───────────────────────────────
  Future<BulkApiResult> _callProvider({
    required BulkApiKey key,
    required String userMessage,
    required String systemPrompt,
    required List<Map<String, String>> history,
    required int maxTokens,
    required double temperature,
    List<ChatAttachmentPayload> attachments = const [],
  }) async {
    switch (key.provider) {
      case BulkApiProvider.anthropic:
        return _callAnthropic(key, userMessage, systemPrompt, history, maxTokens, temperature, attachments);
      case BulkApiProvider.gemini:
        return _callGemini(key, userMessage, systemPrompt, history, maxTokens, temperature, attachments);
      case BulkApiProvider.groq:
      case BulkApiProvider.openai:
      case BulkApiProvider.together:
      case BulkApiProvider.mistral:
      case BulkApiProvider.openrouter:
        return _callOpenAiCompat(key, userMessage, systemPrompt, history, maxTokens, temperature, attachments);
      case BulkApiProvider.custom:
        return _callCustom(key, userMessage, systemPrompt, history, maxTokens, temperature);
    }
  }

  // ── Anthropic API ─────────────────────────────────────────────────────────
  Future<BulkApiResult> _callAnthropic(
    BulkApiKey key, String userMsg, String sysPrompt,
    List<Map<String, String>> history, int maxTokens, double temp,
    List<ChatAttachmentPayload> attachments,
  ) async {
    final messages = <Map<String, dynamic>>[];
    for (final h in history) {
      messages.add({'role': h['role'], 'content': h['content']});
    }

    // Build multimodal user content
    final List<Map<String, dynamic>> userContent = [];
    for (final att in attachments) {
      if (att.isImage && att.base64Data != null) {
        userContent.add({
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': att.mimeType,
            'data': att.base64Data,
          },
        });
      } else if (att.isText && att.textContent != null) {
        userContent.add({
          'type': 'text',
          'text': '### File: ${att.filename}\n```\n${att.textContent}\n```\n',
        });
      } else if (att.textContent != null) {
        userContent.add({'type': 'text', 'text': att.textContent!});
      }
    }
    userContent.add({'type': 'text', 'text': userMsg});

    messages.add({
      'role': 'user',
      'content': attachments.isEmpty ? userMsg : userContent,
    });

    final body = <String, dynamic>{
      'model': key.customModel.isNotEmpty ? key.customModel : key.provider.defaultModel,
      'max_tokens': maxTokens,
      'temperature': temp,
      'messages': messages,
    };
    if (sysPrompt.isNotEmpty) body['system'] = sysPrompt;

    final resp = await http.post(
      Uri.parse(key.provider.apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': key.apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 60));

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final content = (data['content'] as List).first['text'] as String;
      return BulkApiResult(success: true, content: content, usedKeyId: key.id, usedProvider: key.provider);
    }

    final errMsg = '${resp.statusCode}: ${resp.body}';
    return BulkApiResult(success: false, error: errMsg, usedKeyId: key.id, usedProvider: key.provider);
  }

  // ── OpenAI-compatible (Groq, Together, Mistral, OpenRouter, OpenAI) ───────
  Future<BulkApiResult> _callOpenAiCompat(
    BulkApiKey key, String userMsg, String sysPrompt,
    List<Map<String, String>> history, int maxTokens, double temp,
    List<ChatAttachmentPayload> attachments,
  ) async {
    final messages = <Map<String, dynamic>>[];
    if (sysPrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': sysPrompt});
    }
    for (final h in history) {
      messages.add({'role': h['role'], 'content': h['content']});
    }

    dynamic userContent;
    if (attachments.isEmpty) {
      userContent = userMsg;
    } else {
      final parts = <Map<String, dynamic>>[];
      for (final att in attachments) {
        if (att.isImage && att.base64Data != null) {
          parts.add({
            'type': 'image_url',
            'image_url': {'url': 'data:${att.mimeType};base64,${att.base64Data}'},
          });
        } else if (att.isText && att.textContent != null) {
          parts.add({
            'type': 'text',
            'text': '### File: ${att.filename}\n```\n${att.textContent}\n```\n',
          });
        } else if (att.textContent != null) {
          parts.add({'type': 'text', 'text': att.textContent!});
        }
      }
      parts.add({'type': 'text', 'text': userMsg});
      userContent = parts;
    }
    messages.add({'role': 'user', 'content': userContent});

    final body = {
      'model': key.customModel.isNotEmpty ? key.customModel : key.provider.defaultModel,
      'max_tokens': maxTokens,
      'temperature': temp,
      'messages': messages,
    };

    final url = key.provider == BulkApiProvider.custom && key.customUrl.isNotEmpty
        ? key.customUrl
        : key.provider.apiUrl;

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${key.apiKey}',
    };

    // OpenRouter needs additional headers
    if (key.provider == BulkApiProvider.openrouter) {
      headers['HTTP-Referer'] = 'https://kanmongo.app';
      headers['X-Title'] = 'KanMon GO';
    }

    final resp = await http.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 60));

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final content = data['choices'][0]['message']['content'] as String;
      return BulkApiResult(success: true, content: content, usedKeyId: key.id, usedProvider: key.provider);
    }

    final errMsg = '${resp.statusCode}: ${resp.body}';
    return BulkApiResult(success: false, error: errMsg, usedKeyId: key.id, usedProvider: key.provider);
  }

  // ── Gemini API ────────────────────────────────────────────────────────────
  Future<BulkApiResult> _callGemini(
    BulkApiKey key, String userMsg, String sysPrompt,
    List<Map<String, String>> history, int maxTokens, double temp,
    List<ChatAttachmentPayload> attachments,
  ) async {
    final model = key.customModel.isNotEmpty ? key.customModel : key.provider.defaultModel;
    final url = '${key.provider.apiUrl}/$model:generateContent?key=${key.apiKey}';

    final contents = <Map<String, dynamic>>[];
    for (final h in history) {
      contents.add({
        'role': h['role'] == 'assistant' ? 'model' : 'user',
        'parts': [{'text': h['content']}],
      });
    }

    // Build multimodal user parts
    final userParts = <Map<String, dynamic>>[];
    for (final att in attachments) {
      if (att.isText && att.textContent != null) {
        userParts.add({'text': '### File: ${att.filename}\n```\n${att.textContent}\n```\n'});
      } else if (att.textContent != null) {
        userParts.add({'text': att.textContent!});
      }
    }
    for (final att in attachments) {
      if (att.isImage && att.base64Data != null) {
        userParts.add({
          'inlineData': {'mimeType': att.mimeType, 'data': att.base64Data},
        });
      }
    }
    userParts.add({'text': userMsg});
    contents.add({'role': 'user', 'parts': userParts});

    final body = <String, dynamic>{
      'contents': contents,
      'generationConfig': {
        'maxOutputTokens': maxTokens,
        'temperature': temp,
      },
    };

    if (sysPrompt.isNotEmpty) {
      body['systemInstruction'] = {'parts': [{'text': sysPrompt}]};
    }

    final resp = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 60));

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final content = data['candidates'][0]['content']['parts'][0]['text'] as String;
      return BulkApiResult(success: true, content: content, usedKeyId: key.id, usedProvider: key.provider);
    }

    final errMsg = '${resp.statusCode}: ${resp.body}';
    return BulkApiResult(success: false, error: errMsg, usedKeyId: key.id, usedProvider: key.provider);
  }

  // ── Custom endpoint ───────────────────────────────────────────────────────
  Future<BulkApiResult> _callCustom(
    BulkApiKey key, String userMsg, String sysPrompt,
    List<Map<String, String>> history, int maxTokens, double temp,
  ) async {
    if (key.customUrl.isEmpty) {
      return const BulkApiResult(success: false, error: 'Custom URL tidak diset');
    }
    // Gunakan format OpenAI-compatible untuk custom endpoint
    return _callOpenAiCompat(key, userMsg, sysPrompt, history, maxTokens, temp, const []);
  }

  // ── Test koneksi key ──────────────────────────────────────────────────────
  Future<BulkApiResult> testKey(BulkApiKey key) async {
    return _callProvider(
      key: key,
      userMessage: 'Balas hanya "OK" tanpa teks lain.',
      systemPrompt: 'Kamu adalah asisten.',
      history: [],
      maxTokens: 10,
      temperature: 0.1,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TRUE SSE STREAMING — token real-time dari server
  // Menggunakan http.Client.send() + StreamedResponse agar token mengalir
  // langsung dari server tanpa menunggu response penuh selesai.
  // ══════════════════════════════════════════════════════════════════════════

  Stream<String> sendChatStream({
    required String userMessage,
    String systemPrompt = '',
    List<Map<String, String>> history = const [],
    BulkApiProvider? preferredProvider,
    List<ChatAttachmentPayload> attachments = const [],
  }) async* {
    if (!_enabled) {
      yield '❌ Bulk API belum diaktifkan.\n\nPergi ke **Settings → Bulk API Key**.';
      return;
    }

    // Pilih key kandidat
    List<BulkApiKey> candidates;
    if (preferredProvider != null) {
      candidates = _keys.where((k) => k.provider == preferredProvider && k.canUse).toList();
    } else {
      candidates = _keys.where((k) => k.canUse).toList();
    }

    // Auto-reset expired limits
    if (candidates.isEmpty) {
      for (final k in _keys) {
        if (k.isLimitReached && k.isLimitExpired) {
          k.isLimitReached = false;
          k.limitReachedAt = null;
        }
      }
      candidates = preferredProvider != null
          ? _keys.where((k) => k.provider == preferredProvider && k.canUse).toList()
          : _keys.where((k) => k.canUse).toList();
    }

    if (candidates.isEmpty) {
      final hasFirebaseOnly = _keys.any((k) => k.isFirebaseOnly && k.isActive);
      if (hasFirebaseOnly) {
        yield '❌ Tidak ada Gemini API Key yang valid.\n\n'
            '⚠️ Terdeteksi Firebase config — ini bukan Gemini API Key.\n\n'
            'Ambil Gemini API Key dari:\n'
            '→ https://aistudio.google.com/app/apikey\n\n'
            'Format yang benar: **AIzaSy...** (39 karakter)\n'
            'Bukan Project ID atau App ID Firebase.';
      } else {
        yield '❌ Tidak ada API key yang tersedia.\n\nPergi ke **Settings → Bulk API Key** untuk menambah key.';
      }
      return;
    }

    // Coba setiap key (fallback mode)
    String? lastError;
    for (final key in candidates) {
      bool gotContent = false;
      try {
        await for (final token in _streamFromKey(
          key: key,
          userMessage: userMessage,
          systemPrompt: systemPrompt,
          history: history,
          attachments: attachments,
        )) {
          gotContent = true;
          yield token;
        }
        if (gotContent) {
          await markKeySuccess(key.id);
          return; // sukses, selesai
        }
      } catch (e) {
        final err = e.toString();
        lastError = err;
        debugPrint('[BulkApi] Stream key ${key.id} error: $err');
        // Rate limit → coba key berikutnya (hanya di mode fallback/roundRobin)
        if (err.contains('429') || err.contains('rate') ||
            err.contains('limit') || err.contains('quota')) {
          await markKeyLimited(key.id);
          if (_mode == BulkLoadMode.select) {
            yield '❌ Rate limit tercapai: $err';
            return;
          }
          continue; // coba key berikutnya
        }
        // Error lain → langsung return
        yield '❌ Error: $err';
        return;
      }
    }

    yield '❌ Semua API key gagal. Error terakhir: ${lastError ?? 'Unknown'}';
  }

  // ── Internal: stream token dari satu key ─────────────────────────────────
  Stream<String> _streamFromKey({
    required BulkApiKey key,
    required String userMessage,
    required String systemPrompt,
    required List<Map<String, String>> history,
    int maxTokens = 1024,
    double temperature = 0.7,
    List<ChatAttachmentPayload> attachments = const [],
  }) {
    switch (key.provider) {
      case BulkApiProvider.anthropic:
        return _streamAnthropic(key, userMessage, systemPrompt, history, maxTokens, temperature, attachments);
      case BulkApiProvider.gemini:
        return _streamGemini(key, userMessage, systemPrompt, history, maxTokens, temperature, attachments);
      case BulkApiProvider.groq:
      case BulkApiProvider.openai:
      case BulkApiProvider.together:
      case BulkApiProvider.mistral:
      case BulkApiProvider.openrouter:
      case BulkApiProvider.custom:
        return _streamOpenAiCompat(key, userMessage, systemPrompt, history, maxTokens, temperature, attachments);
    }
  }

  // ── Helper: parse satu baris SSE dan ekstrak teks token ──────────────────
  // Format SSE: "data: {json}\n" atau "data: [DONE]\n"
  String? _parseOpenAiSseLine(String line) {
    if (!line.startsWith('data:')) return null;
    final data = line.substring(5).trim();
    if (data == '[DONE]') return null;
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final choices = json['choices'] as List?;
      if (choices == null || choices.isEmpty) return null;
      final delta = choices[0]['delta'] as Map<String, dynamic>?;
      return delta?['content'] as String?;
    } catch (_) {
      return null;
    }
  }

  String? _parseAnthropicSseLine(String line) {
    if (!line.startsWith('data:')) return null;
    final data = line.substring(5).trim();
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      if (json['type'] == 'content_block_delta') {
        final delta = json['delta'] as Map<String, dynamic>?;
        if (delta?['type'] == 'text_delta') {
          return delta?['text'] as String?;
        }
      }
    } catch (_) {}
    return null;
  }

  // ── OpenAI-compatible SSE stream ─────────────────────────────────────────
  Stream<String> _streamOpenAiCompat(
    BulkApiKey key, String userMsg, String sysPrompt,
    List<Map<String, String>> history, int maxTokens, double temp,
    List<ChatAttachmentPayload> attachments,
  ) async* {
    final messages = <Map<String, dynamic>>[];
    if (sysPrompt.isNotEmpty) messages.add({'role': 'system', 'content': sysPrompt});
    for (final h in history) messages.add({'role': h['role'], 'content': h['content']});

    // Build user content: plain string or multimodal array
    dynamic userContent;
    if (attachments.isEmpty) {
      userContent = userMsg;
    } else {
      final parts = <Map<String, dynamic>>[];
      for (final att in attachments) {
        if (att.isImage && att.base64Data != null) {
          parts.add({
            'type': 'image_url',
            'image_url': {'url': 'data:${att.mimeType};base64,${att.base64Data}'},
          });
        } else if (att.isText && att.textContent != null) {
          parts.add({
            'type': 'text',
            'text': '### File: ${att.filename}\n```\n${att.textContent}\n```\n',
          });
        } else if (att.textContent != null) {
          // video / binary placeholder
          parts.add({'type': 'text', 'text': att.textContent!});
        }
      }
      parts.add({'type': 'text', 'text': userMsg});
      userContent = parts;
    }
    messages.add({'role': 'user', 'content': userContent});

    final url = (key.provider == BulkApiProvider.custom && key.customUrl.isNotEmpty)
        ? key.customUrl
        : key.provider.apiUrl;

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${key.apiKey}',
      'Accept': 'text/event-stream',
    };
    if (key.provider == BulkApiProvider.openrouter) {
      headers['HTTP-Referer'] = 'https://kanmongo.app';
      headers['X-Title'] = 'KanMon GO';
    }

    final body = jsonEncode({
      'model': key.customModel.isNotEmpty ? key.customModel : key.provider.defaultModel,
      'max_tokens': maxTokens,
      'temperature': temp,
      'messages': messages,
      'stream': true, // ← KUNCI: aktifkan SSE streaming
    });

    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(url))
        ..headers.addAll(headers)
        ..body = body;

      final streamedResp = await client.send(request).timeout(const Duration(seconds: 30));

      if (streamedResp.statusCode != 200) {
        final errBody = await streamedResp.stream.bytesToString();
        throw Exception('${streamedResp.statusCode}: $errBody');
      }

      // Buffer untuk menangani SSE lines yang terpotong
      String buffer = '';
      await for (final chunk in streamedResp.stream.transform(const Utf8Decoder(allowMalformed: true))) {
        buffer += chunk;
        // Proses setiap baris yang sudah lengkap (diakhiri \n)
        final lines = buffer.split('\n');
        buffer = lines.last; // sisa yang belum ada \n-nya
        for (final line in lines.sublist(0, lines.length - 1)) {
          final token = _parseOpenAiSseLine(line.trim());
          if (token != null && token.isNotEmpty) yield token;
        }
      }
      // Proses sisa buffer jika ada
      if (buffer.isNotEmpty) {
        final token = _parseOpenAiSseLine(buffer.trim());
        if (token != null && token.isNotEmpty) yield token;
      }
    } finally {
      client.close();
    }
  }

  // ── Anthropic SSE stream ──────────────────────────────────────────────────
  Stream<String> _streamAnthropic(
    BulkApiKey key, String userMsg, String sysPrompt,
    List<Map<String, String>> history, int maxTokens, double temp,
    List<ChatAttachmentPayload> attachments,
  ) async* {
    final messages = <Map<String, dynamic>>[];
    for (final h in history) messages.add({'role': h['role'], 'content': h['content']});

    // Build multimodal user content array
    final List<Map<String, dynamic>> userContent = [];
    for (final att in attachments) {
      if (att.isImage && att.base64Data != null) {
        userContent.add({
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': att.mimeType,
            'data': att.base64Data,
          },
        });
      } else if (att.isText && att.textContent != null) {
        userContent.add({
          'type': 'text',
          'text': '### File: ${att.filename}\n```\n${att.textContent}\n```\n',
        });
      } else if (att.textContent != null) {
        userContent.add({'type': 'text', 'text': att.textContent!});
      }
    }
    userContent.add({'type': 'text', 'text': userMsg});
    messages.add({'role': 'user', 'content': userContent});

    final bodyMap = <String, dynamic>{
      'model': key.customModel.isNotEmpty ? key.customModel : key.provider.defaultModel,
      'max_tokens': maxTokens,
      'temperature': temp,
      'messages': messages,
      'stream': true, // ← SSE streaming Anthropic
    };
    if (sysPrompt.isNotEmpty) bodyMap['system'] = sysPrompt;

    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(key.provider.apiUrl))
        ..headers.addAll({
          'Content-Type': 'application/json',
          'x-api-key': key.apiKey,
          'anthropic-version': '2023-06-01',
          'Accept': 'text/event-stream',
        })
        ..body = jsonEncode(bodyMap);

      final streamedResp = await client.send(request).timeout(const Duration(seconds: 30));

      if (streamedResp.statusCode != 200) {
        final errBody = await streamedResp.stream.bytesToString();
        throw Exception('${streamedResp.statusCode}: $errBody');
      }

      String buffer = '';
      await for (final chunk in streamedResp.stream.transform(const Utf8Decoder(allowMalformed: true))) {
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.last;
        for (final line in lines.sublist(0, lines.length - 1)) {
          final token = _parseAnthropicSseLine(line.trim());
          if (token != null && token.isNotEmpty) yield token;
        }
      }
      if (buffer.isNotEmpty) {
        final token = _parseAnthropicSseLine(buffer.trim());
        if (token != null && token.isNotEmpty) yield token;
      }
    } finally {
      client.close();
    }
  }

  // ── Gemini SSE stream ─────────────────────────────────────────────────────
  // Gemini streaming menggunakan endpoint :streamGenerateContent
  Stream<String> _streamGemini(
    BulkApiKey key, String userMsg, String sysPrompt,
    List<Map<String, String>> history, int maxTokens, double temp,
    List<ChatAttachmentPayload> attachments,
  ) async* {
    final model = key.customModel.isNotEmpty ? key.customModel : key.provider.defaultModel;
    final url = 'https://generativelanguage.googleapis.com/v1beta/models/$model:streamGenerateContent?alt=sse&key=${key.apiKey}';

    final contents = <Map<String, dynamic>>[];
    for (final h in history) {
      contents.add({
        'role': h['role'] == 'assistant' ? 'model' : 'user',
        'parts': [{'text': h['content']}],
      });
    }

    // Build parts for user turn
    final userParts = <Map<String, dynamic>>[];
    for (final att in attachments) {
      if (att.isText && att.textContent != null) {
        userParts.add({'text': '### File: ${att.filename}\n```\n${att.textContent}\n```\n'});
      } else if (att.textContent != null) {
        userParts.add({'text': att.textContent!});
      }
    }
    for (final att in attachments) {
      if (att.isImage && att.base64Data != null) {
        userParts.add({
          'inlineData': {'mimeType': att.mimeType, 'data': att.base64Data},
        });
      }
    }
    userParts.add({'text': userMsg});
    contents.add({'role': 'user', 'parts': userParts});

    final bodyMap = <String, dynamic>{
      'contents': contents,
      'generationConfig': {'maxOutputTokens': maxTokens, 'temperature': temp},
    };
    if (sysPrompt.isNotEmpty) {
      bodyMap['systemInstruction'] = {'parts': [{'text': sysPrompt}]};
    }

    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(url))
        ..headers.addAll({'Content-Type': 'application/json', 'Accept': 'text/event-stream'})
        ..body = jsonEncode(bodyMap);

      final streamedResp = await client.send(request).timeout(const Duration(seconds: 30));

      if (streamedResp.statusCode != 200) {
        final errBody = await streamedResp.stream.bytesToString();
        throw Exception('${streamedResp.statusCode}: $errBody');
      }

      String buffer = '';
      await for (final chunk in streamedResp.stream.transform(const Utf8Decoder(allowMalformed: true))) {
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.last;
        for (final line in lines.sublist(0, lines.length - 1)) {
          final trimmed = line.trim();
          if (!trimmed.startsWith('data:')) continue;
          final data = trimmed.substring(5).trim();
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final candidates = json['candidates'] as List?;
            if (candidates == null || candidates.isEmpty) continue;
            final parts = (candidates[0]['content']?['parts'] as List?);
            if (parts == null || parts.isEmpty) continue;
            final text = parts[0]['text'] as String?;
            if (text != null && text.isNotEmpty) yield text;
          } catch (_) {}
        }
      }
    } finally {
      client.close();
    }
  }
}
