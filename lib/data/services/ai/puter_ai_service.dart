// lib/data/services/ai/puter_ai_service.dart
// KanMon GO — Puter.js AI Service
//
// Mengelola integrasi dengan Puter.js untuk AI online:
//   - Claude (Anthropic)
//   - Gemini (Google)
//   - Grok (xAI)
//   - GPT-4o (OpenAI)
//   - Llama (Meta/Groq)
//   - Mistral, DeepSeek, dll
//
// Puter.js adalah platform cloud yang menyediakan akses ke berbagai model AI
// tanpa perlu API key sendiri (menggunakan akun Puter).
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── SharedPrefs keys ──────────────────────────────────────────────────────────
const _keyPuterEnabled    = 'puter.enabled';
const _keyPuterApiKey     = 'puter.api_key';       // opsional — custom API key
const _keyPuterBaseUrl    = 'puter.base_url';       // custom endpoint
const _keyPuterModel      = 'puter.selected_model';
const _keyPuterMaxTokens  = 'puter.max_tokens';
const _keyPuterTemp       = 'puter.temperature';
const _keyPuterStream     = 'puter.stream_mode';

// ── Model definition ──────────────────────────────────────────────────────────
class PuterAiModel {
  final String id;           // ID model untuk API
  final String name;         // Nama tampilan
  final String provider;     // Claude / Google / xAI / OpenAI / Meta / dll
  final String emoji;        // Emoji provider
  final String description;  // Deskripsi singkat
  final bool   isNew;        // Badge "NEW"
  final bool   isFast;       // Badge "FAST"
  final bool   isBest;       // Badge "BEST"
  final int    contextLength;// Max context (ribuan token)

  const PuterAiModel({
    required this.id,
    required this.name,
    required this.provider,
    required this.emoji,
    required this.description,
    this.isNew       = false,
    this.isFast      = false,
    this.isBest      = false,
    this.contextLength = 8,
  });
}

// ── Katalog model Puter.js ────────────────────────────────────────────────────
const kPuterModels = <PuterAiModel>[
  // ── Anthropic Claude ───────────────────────────────────────────────────────
  PuterAiModel(
    id: 'claude-sonnet-4-5',
    name: 'Claude Sonnet 4.5',
    provider: 'Anthropic',
    emoji: '🟣',
    description: 'Terbaik untuk tugas harian, cepat & cerdas',
    isBest: true,
    contextLength: 200,
  ),
  PuterAiModel(
    id: 'claude-opus-4-5',
    name: 'Claude Opus 4.5',
    provider: 'Anthropic',
    emoji: '🟣',
    description: 'Model Claude paling powerful',
    contextLength: 200,
  ),
  PuterAiModel(
    id: 'claude-haiku-4-5',
    name: 'Claude Haiku 4.5',
    provider: 'Anthropic',
    emoji: '🟣',
    description: 'Ultra cepat & ringan dari Anthropic',
    isFast: true,
    contextLength: 200,
  ),

  // ── Google Gemini ──────────────────────────────────────────────────────────
  PuterAiModel(
    id: 'gemini-2.0-flash',
    name: 'Gemini 2.0 Flash',
    provider: 'Google',
    emoji: '🔵',
    description: 'Gemini terbaru, cepat & multimodal',
    isNew: true,
    isFast: true,
    contextLength: 1000,
  ),
  PuterAiModel(
    id: 'gemini-2.0-flash-lite',
    name: 'Gemini 2.0 Flash Lite',
    provider: 'Google',
    emoji: '🔵',
    description: 'Versi ringan Gemini 2.0',
    isFast: true,
    contextLength: 1000,
  ),
  PuterAiModel(
    id: 'gemini-1.5-pro',
    name: 'Gemini 1.5 Pro',
    provider: 'Google',
    emoji: '🔵',
    description: 'Konteks panjang 1M token',
    contextLength: 1000,
  ),
  PuterAiModel(
    id: 'gemini-1.5-flash',
    name: 'Gemini 1.5 Flash',
    provider: 'Google',
    emoji: '🔵',
    description: 'Cepat & efisien dari Google',
    isFast: true,
    contextLength: 1000,
  ),

  // ── xAI Grok ───────────────────────────────────────────────────────────────
  PuterAiModel(
    id: 'grok-3',
    name: 'Grok 3',
    provider: 'xAI',
    emoji: '⚫',
    description: 'Model terbaru xAI, reasoning kuat',
    isNew: true,
    isBest: true,
    contextLength: 131,
  ),
  PuterAiModel(
    id: 'grok-3-mini',
    name: 'Grok 3 Mini',
    provider: 'xAI',
    emoji: '⚫',
    description: 'Versi ringan Grok 3, lebih cepat',
    isNew: true,
    isFast: true,
    contextLength: 131,
  ),
  PuterAiModel(
    id: 'grok-2',
    name: 'Grok 2',
    provider: 'xAI',
    emoji: '⚫',
    description: 'Model Grok generasi 2',
    contextLength: 131,
  ),

  // ── OpenAI GPT ─────────────────────────────────────────────────────────────
  PuterAiModel(
    id: 'gpt-4o',
    name: 'GPT-4o',
    provider: 'OpenAI',
    emoji: '🟢',
    description: 'Model flagship OpenAI, multimodal',
    isBest: true,
    contextLength: 128,
  ),
  PuterAiModel(
    id: 'gpt-4o-mini',
    name: 'GPT-4o Mini',
    provider: 'OpenAI',
    emoji: '🟢',
    description: 'Lebih cepat & murah dari GPT-4o',
    isFast: true,
    contextLength: 128,
  ),
  PuterAiModel(
    id: 'o1',
    name: 'o1',
    provider: 'OpenAI',
    emoji: '🟢',
    description: 'Reasoning mendalam OpenAI',
    contextLength: 200,
  ),
  PuterAiModel(
    id: 'o3-mini',
    name: 'o3-mini',
    provider: 'OpenAI',
    emoji: '🟢',
    description: 'o3 mini — reasoning cepat',
    isNew: true,
    isFast: true,
    contextLength: 200,
  ),

  // ── Meta Llama ─────────────────────────────────────────────────────────────
  PuterAiModel(
    id: 'meta-llama/llama-4-maverick',
    name: 'Llama 4 Maverick',
    provider: 'Meta',
    emoji: '🦙',
    description: 'Llama 4 open-source terbaru',
    isNew: true,
    contextLength: 1000,
  ),
  PuterAiModel(
    id: 'meta-llama/llama-3.3-70b-instruct',
    name: 'Llama 3.3 70B',
    provider: 'Meta',
    emoji: '🦙',
    description: 'Model open-source terbaik dari Meta',
    isBest: true,
    contextLength: 128,
  ),
  PuterAiModel(
    id: 'meta-llama/llama-3.1-8b-instruct',
    name: 'Llama 3.1 8B',
    provider: 'Meta',
    emoji: '🦙',
    description: 'Llama ringan & cepat',
    isFast: true,
    contextLength: 128,
  ),

  // ── Mistral ────────────────────────────────────────────────────────────────
  PuterAiModel(
    id: 'mistral-large-latest',
    name: 'Mistral Large',
    provider: 'Mistral',
    emoji: '🌀',
    description: 'Model terbesar Mistral AI',
    isBest: true,
    contextLength: 128,
  ),
  PuterAiModel(
    id: 'mistral-small-latest',
    name: 'Mistral Small',
    provider: 'Mistral',
    emoji: '🌀',
    description: 'Efisien & cepat untuk daily use',
    isFast: true,
    contextLength: 32,
  ),

  // ── DeepSeek ───────────────────────────────────────────────────────────────
  PuterAiModel(
    id: 'deepseek/deepseek-r1',
    name: 'DeepSeek R1',
    provider: 'DeepSeek',
    emoji: '🔴',
    description: 'Reasoning model open-source terkuat',
    isBest: true,
    contextLength: 64,
  ),
  PuterAiModel(
    id: 'deepseek/deepseek-chat',
    name: 'DeepSeek V3',
    provider: 'DeepSeek',
    emoji: '🔴',
    description: 'Chat model DeepSeek terbaik',
    contextLength: 64,
  ),

  // ── Cohere ─────────────────────────────────────────────────────────────────
  PuterAiModel(
    id: 'command-r-plus',
    name: 'Command R+',
    provider: 'Cohere',
    emoji: '🟠',
    description: 'RAG & retrieval terbaik',
    contextLength: 128,
  ),

  // ── Perplexity ─────────────────────────────────────────────────────────────
  PuterAiModel(
    id: 'sonar-pro',
    name: 'Sonar Pro',
    provider: 'Perplexity',
    emoji: '🔷',
    description: 'AI dengan web search real-time',
    contextLength: 200,
  ),
];

// ── Provider groups ───────────────────────────────────────────────────────────
const kPuterProviders = [
  'Semua',
  'Anthropic',
  'Google',
  'xAI',
  'OpenAI',
  'Meta',
  'Mistral',
  'DeepSeek',
  'Cohere',
  'Perplexity',
];

// ── Puter AI Service ──────────────────────────────────────────────────────────
class PuterAiService {
  PuterAiService._();
  static final PuterAiService instance = PuterAiService._();

  // ── State ──────────────────────────────────────────────────────────────────
  bool    _enabled        = false;
  String  _apiKey         = '';      // Custom API key (opsional)
  String  _baseUrl        = 'https://api.puter.com/puterai/openai/v1/chat/completions'; // default
  String  _selectedModel  = 'claude-sonnet-4-5';
  int     _maxTokens      = 1024;
  double  _temperature    = 0.7;
  bool    _streamMode     = true;

  // ── Public getters ─────────────────────────────────────────────────────────
  bool   get isEnabled       => _enabled;
  String get apiKey          => _apiKey;
  String get baseUrl         => _baseUrl;
  String get selectedModelId => _selectedModel;
  int    get maxTokens       => _maxTokens;
  double get temperature     => _temperature;
  bool   get streamMode      => _streamMode;

  List<PuterAiModel> get availableModels => kPuterModels;

  PuterAiModel? get selectedModel {
    try {
      return kPuterModels.firstWhere((m) => m.id == _selectedModel);
    } catch (_) {
      return kPuterModels.first;
    }
  }

  // ── Load settings ──────────────────────────────────────────────────────────
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled       = prefs.getBool(_keyPuterEnabled)   ?? false;
    _apiKey        = prefs.getString(_keyPuterApiKey)  ?? '';
    _baseUrl       = prefs.getString(_keyPuterBaseUrl) ??
        'https://api.puter.com/puterai/openai/v1/chat/completions';
    _selectedModel = prefs.getString(_keyPuterModel)   ?? 'claude-sonnet-4-5';
    _maxTokens     = prefs.getInt(_keyPuterMaxTokens)  ?? 1024;
    _temperature   = prefs.getDouble(_keyPuterTemp)    ?? 0.7;
    _streamMode    = prefs.getBool(_keyPuterStream)    ?? true;
    debugPrint('[PuterAI] Settings loaded — enabled=$_enabled, model=$_selectedModel');
  }

  // ── Save settings ──────────────────────────────────────────────────────────
  Future<void> saveSettings({
    bool?   enabled,
    String? apiKey,
    String? baseUrl,
    String? selectedModel,
    int?    maxTokens,
    double? temperature,
    bool?   streamMode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled       != null) { _enabled = enabled;             await prefs.setBool(_keyPuterEnabled, enabled); }
    if (apiKey        != null) { _apiKey  = apiKey;              await prefs.setString(_keyPuterApiKey, apiKey); }
    if (baseUrl       != null) { _baseUrl = baseUrl;             await prefs.setString(_keyPuterBaseUrl, baseUrl); }
    if (selectedModel != null) { _selectedModel = selectedModel; await prefs.setString(_keyPuterModel, selectedModel); }
    if (maxTokens     != null) { _maxTokens = maxTokens;         await prefs.setInt(_keyPuterMaxTokens, maxTokens); }
    if (temperature   != null) { _temperature = temperature;     await prefs.setDouble(_keyPuterTemp, temperature); }
    if (streamMode    != null) { _streamMode = streamMode;       await prefs.setBool(_keyPuterStream, streamMode); }
    debugPrint('[PuterAI] Settings saved');
  }

  // ── Send chat via Puter.js API ─────────────────────────────────────────────
  Stream<String> chatStream({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required String userMessage,
  }) async* {
    if (!_enabled) {
      yield '⚠️ AI Online belum diaktifkan.\n\n'
            'Pergi ke **Settings → AI Online** untuk mengatur Puter.js.';
      return;
    }

    if (_apiKey.isEmpty) {
      yield '🔑 API Key Puter belum diisi.\n\n'
            'Pergi ke **Settings → Setup Puter.js** dan masukkan API key kamu.\n\n'
            '**Cara mendapatkan token:**\n'
            '1. Buka **puter.com** di browser\n'
            '2. Login / daftar akun gratis\n'
            '3. Buka **Account Settings → API Keys**\n'
            '4. Generate & copy token, paste di Settings app ini';
      return;
    }

    // Build messages array (OpenAI format)
    final messages = <Map<String, dynamic>>[];
    if (systemPrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }
    for (final h in history) {
      messages.add({'role': h['role']!, 'content': h['content']!});
    }
    messages.add({'role': 'user', 'content': userMessage});

    final uri = Uri.parse(_baseUrl);
    final bodyMap = <String, dynamic>{
      'model':       _selectedModel,
      'messages':    messages,
      'max_tokens':  _maxTokens,
      'temperature': _temperature,
      'stream':      _streamMode,
    };
    final headers = {
      'Authorization': 'Bearer $_apiKey',
      'Content-Type':  'application/json',
      'Accept':        _streamMode ? 'text/event-stream' : 'application/json',
      'Connection':    'keep-alive',
    };

    final client = http.Client();
    try {
      if (_streamMode) {
        // ── Streaming SSE ───────────────────────────────────────────────────
        final request = http.Request('POST', uri)
          ..headers.addAll(headers)
          ..body = jsonEncode(bodyMap);

        final streamedResponse = await client.send(request)
            .timeout(const Duration(seconds: 30));

        if (streamedResponse.statusCode != 200) {
          final errBody = await streamedResponse.stream.bytesToString();
          debugPrint('[PuterAI] HTTP ${streamedResponse.statusCode}: $errBody');
          yield _httpErrorMsg(streamedResponse.statusCode, errBody);
          return;
        }

        // Parse SSE stream
        String buffer = '';
        bool gotAnyContent = false;

        await for (final chunk in streamedResponse.stream
            .transform(utf8.decoder)
            .timeout(const Duration(seconds: 120))) {
          buffer += chunk;

          // Proses per baris — SSE dipisah oleh \n\n atau \n
          while (true) {
            final newline = buffer.indexOf('\n');
            if (newline == -1) break;

            final line = buffer.substring(0, newline).trim();
            buffer = buffer.substring(newline + 1);

            if (line.isEmpty) continue;
            if (!line.startsWith('data:')) continue;

            final data = line.substring(5).trim();
            if (data == '[DONE]') return;
            if (data.isEmpty) continue;

            try {
              final json = jsonDecode(data) as Map<String, dynamic>;

              // Format 1: OpenAI-compatible streaming (choices[].delta.content)
              final choices = json['choices'];
              if (choices is List && choices.isNotEmpty) {
                final delta = choices[0]['delta'];
                if (delta is Map) {
                  final content = delta['content'];
                  if (content is String && content.isNotEmpty) {
                    gotAnyContent = true;
                    yield content;
                    continue;
                  }
                }
                // finish_reason = stop → end of stream
                final finishReason = choices[0]['finish_reason'];
                if (finishReason == 'stop') return;
              }

              // Format 2: message.content langsung
              final msgContent = json['message']?['content'] ??
                  json['content'] ?? json['text'];
              if (msgContent is String && msgContent.isNotEmpty) {
                gotAnyContent = true;
                yield msgContent;
              }
            } catch (_) {
              // Baris bukan JSON valid — skip
            }
          }
        }

        if (!gotAnyContent) {
          yield '⚠️ Tidak ada respons dari server. Coba lagi atau ganti model.';
        }

      } else {
        // ── Non-streaming ───────────────────────────────────────────────────
        final response = await client.post(
          uri,
          headers: headers,
          body: jsonEncode(bodyMap),
        ).timeout(const Duration(seconds: 60));

        if (response.statusCode != 200) {
          debugPrint('[PuterAI] HTTP ${response.statusCode}: ${response.body}');
          yield _httpErrorMsg(response.statusCode, response.body);
          return;
        }

        final json = jsonDecode(response.body) as Map<String, dynamic>;
        // OpenAI format: choices[0].message.content
        final content = json['choices']?[0]?['message']?['content'];
        if (content is String && content.isNotEmpty) { yield content; return; }
        // Fallback
        final text = json['message']?['content'] ?? json['content'] ?? json['text'];
        if (text is String && text.isNotEmpty) { yield text; return; }

        yield '⚠️ Respons tidak dikenali dari server:\n```\n${response.body.substring(0, response.body.length.clamp(0, 300))}\n```';
      }

    } on TimeoutException {
      yield '⏱️ Koneksi timeout. Periksa internet atau coba model lain.';
    } catch (e) {
      debugPrint('[PuterAI] Error: $e');
      yield '❌ Gagal menghubungi Puter.js API.\n\nError: ${e.toString()}\n\n'
            'Pastikan koneksi internet aktif dan token valid.';
    } finally {
      client.close();
    }
  }

  // ── Helper: pesan error HTTP yang user-friendly ────────────────────────────
  String _httpErrorMsg(int statusCode, String body) {
    final preview = body.length > 300 ? '${body.substring(0, 300)}...' : body;
    switch (statusCode) {
      case 401:
        return '❌ Error 401: Token tidak valid atau kadaluarsa.\n\n'
            'Pergi ke **puter.com**, login ulang, generate token baru, '
            'lalu update di **Settings → Setup Puter.js**.';
      case 403:
        return '❌ Error 403: Akses ditolak.\n\n'
            '**Cara mendapatkan token yang benar:**\n'
            '1. Buka **puter.com** di browser HP\n'
            '2. Login ke akun kamu\n'
            '3. Buka **Account Settings → API Keys**\n'
            '4. Generate token, copy, dan paste di **Settings → Setup Puter.js**';
      case 429:
        return '❌ Error 429: Rate limit — terlalu banyak permintaan.\n\n'
            'Tunggu beberapa menit lalu coba lagi.';
      case 500:
      case 502:
      case 503:
        return '❌ Error $statusCode: Server Puter.js sedang bermasalah.\n\n'
            'Coba lagi dalam beberapa menit.';
      default:
        return '❌ Error $statusCode:\n```\n$preview\n```';
    }
  }

  // ── Test koneksi ───────────────────────────────────────────────────────────
  Future<bool> testConnection() async {
    if (_apiKey.isEmpty) return false;
    try {
      // Test dengan prompt sederhana
      final stream = chatStream(
        systemPrompt: 'Respond with exactly: "OK"',
        history: [],
        userMessage: 'ping',
      );
      String response = '';
      await for (final chunk in stream) {
        response += chunk;
        if (response.length > 100) break;
      }
      return response.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── Non-streaming generate ─────────────────────────────────────────────────
  Future<String> generate({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required String userMessage,
  }) async {
    final sb = StringBuffer();
    await for (final chunk in chatStream(
      systemPrompt: systemPrompt,
      history: history,
      userMessage: userMessage,
    )) {
      sb.write(chunk);
    }
    return sb.toString();
  }
}
