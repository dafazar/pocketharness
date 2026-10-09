// lib/data/services/bulk_ai_request_service.dart
// Pocket Harness — Bulk AI HTTP Request Service (Session 6 Integration Layer)
//
// HTTP client that routes requests to the active Bulk API provider endpoint.
// Adapts BulkAiConfig (existing) for the Session 6 unified request pipeline.
// Distinct from bulk_api_service.dart (key manager / SharedPrefs layer).
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/ai_request_model.dart';
import '../models/ai_source_config.dart';

// ── Provider endpoint map ─────────────────────────────────────────────────────

const _providerEndpoints = <String, String>{
  'groq':       'https://api.groq.com/openai/v1/chat/completions',
  'openai':     'https://api.openai.com/v1/chat/completions',
  'anthropic':  'https://api.anthropic.com/v1/messages',
  'gemini':     'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
  'together':   'https://api.together.xyz/v1/chat/completions',
  'mistral':    'https://api.mistral.ai/v1/chat/completions',
  'openrouter': 'https://openrouter.ai/api/v1/chat/completions',
};

// ── Service class ─────────────────────────────────────────────────────────────

/// HTTP client for the bulk AI pipeline (Session 6 integration layer).
/// Uses [BulkAiConfig] for model/temperature/timeout settings.
/// The API key and active provider are supplied externally from BulkApiService.
class BulkAiRequestService {
  final BulkAiConfig config;
  final String apiKey;           // Resolved from BulkApiService at call time
  final String providerKey;      // e.g. "groq", "openai", "openrouter"
  final String? customEndpoint;  // Override URL for custom providers
  final http.Client httpClient;

  BulkAiRequestService({
    required this.config,
    required this.apiKey,
    required this.providerKey,
    this.customEndpoint,
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client();

  String get _endpoint =>
      customEndpoint ??
      _providerEndpoints[providerKey] ??
      _providerEndpoints['openrouter']!;

  // ── Non-streaming request ─────────────────────────────────────────────────

  Future<AiResponse> sendRequest(AiRequest request) async {
    final startTime = DateTime.now();

    try {
      final body     = _buildBody(request);
      final headers  = _buildHeaders();

      final response = await httpClient
          .post(Uri.parse(_endpoint), headers: headers, body: jsonEncode(body))
          .timeout(Duration(seconds: config.timeoutSeconds));

      if (response.statusCode != 200) {
        throw AiServiceException(
          code:           'http_error',
          message:        'HTTP ${response.statusCode} from $providerKey',
          details:        response.body,
          httpStatusCode: response.statusCode,
        );
      }

      final data    = jsonDecode(response.body) as Map<String, dynamic>;
      final content = _extractContent(data);

      return AiResponse(
        id:        const Uuid().v4(),
        requestId: request.id,
        role:      'assistant',
        content:   content,
        metadata:  AiResponseMetadata(
          totalTokensUsed:  _extractTokens(data),
          promptTokens:     data['usage']?['prompt_tokens']     as int? ?? 0,
          completionTokens: data['usage']?['completion_tokens'] as int? ?? 0,
          finishReason:     data['choices']?[0]['finish_reason'] as String?,
          processingTimeMs: DateTime.now().difference(startTime).inMilliseconds.toDouble(),
          httpStatusCode:   response.statusCode,
        ),
      );
    } on AiServiceException {
      rethrow;
    } catch (e, st) {
      throw AiServiceException(
        code:          'bulk_request_failed',
        message:       'Bulk AI request failed',
        originalError: e,
        stackTrace:    st,
      );
    }
  }

  // ── Streaming request ─────────────────────────────────────────────────────

  Stream<AiStreamChunk> streamRequest(AiRequest request) async* {
    try {
      final body    = _buildBody(request, stream: true);
      final headers = _buildHeaders();

      final httpReq = http.Request('POST', Uri.parse(_endpoint))
        ..headers.addAll(headers)
        ..body = jsonEncode(body);

      final streamed = await httpClient
          .send(httpReq)
          .timeout(Duration(seconds: config.timeoutSeconds));

      if (streamed.statusCode != 200) {
        throw AiServiceException(
          code:           'http_error',
          message:        'HTTP ${streamed.statusCode}',
          httpStatusCode: streamed.statusCode,
        );
      }

      int seq = 0;
      await for (final line in streamed.stream
          .transform(const Utf8Decoder())
          .transform(const LineSplitter())) {
        if (line.isEmpty) continue;

        final chunk = _parseSSELine(line, request.id, seq++);
        if (chunk != null) yield chunk;
      }
    } catch (e, st) {
      throw AiServiceException(
        code:          'bulk_stream_failed',
        message:       'Bulk stream failed: $e',
        originalError: e,
        stackTrace:    st,
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Map<String, dynamic> _buildBody(AiRequest request, {bool stream = false}) {
    final messages = <Map<String, dynamic>>[];
    if (request.systemPrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': request.systemPrompt});
    }
    for (final msg in request.conversationHistory) {
      messages.add({'role': msg.role, 'content': msg.content});
    }
    messages.add({'role': 'user', 'content': request.userMessage});

    return {
      'model':       config.selectedModel,
      'messages':    messages,
      'temperature': config.temperature,
      'max_tokens':  config.maxTokens,
      'top_p':       config.topP,
      if (stream) 'stream': true,
    };
  }

  Map<String, String> _buildHeaders() => {
    HttpHeaders.contentTypeHeader: 'application/json',
    HttpHeaders.authorizationHeader: 'Bearer $apiKey',
    'User-Agent': 'PocketHarness/1.0',
  };

  String _extractContent(Map<String, dynamic> data) {
    if (data['choices'] != null) {
      final choice = (data['choices'] as List).first as Map<String, dynamic>;
      return choice['message']?['content'] as String? ?? '';
    }
    return data['content'] as String? ?? '';
  }

  int _extractTokens(Map<String, dynamic> data) =>
      data['usage']?['total_tokens'] as int? ?? 0;

  AiStreamChunk? _parseSSELine(String line, String requestId, int seq) {
    try {
      if (!line.startsWith('data: ')) return null;
      final jsonStr = line.substring(6).trim();
      if (jsonStr == '[DONE]') return null;

      final data  = jsonDecode(jsonStr) as Map<String, dynamic>;
      final delta = data['choices']?[0]['delta'] as Map<String, dynamic>?;
      if (delta == null) return null;

      return AiStreamChunk(
        id:             const Uuid().v4(),
        requestId:      requestId,
        deltaContent:   delta['content'] as String? ?? '',
        sequenceNumber: seq,
        isLast:         data['choices']?[0]['finish_reason'] != null,
      );
    } catch (_) {
      return null;
    }
  }
}
