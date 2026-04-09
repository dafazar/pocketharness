// lib/data/services/ai/online_ai_service.dart
// KanMon GO — Online AI Service (Puter.js + OpenAI-compatible endpoints)
// Handles HTTP requests to online AI providers
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/ai_request_model.dart';
import '../models/ai_source_config.dart';

/// Online AI service for Puter.js and OpenAI-compatible APIs
class OnlineAiService {
  final OnlineAiConfig config;
  final http.Client httpClient;

  OnlineAiService({
    required this.config,
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client();

  static const String puterEndpoint = 'https://api.puter.js/v1/chat/completions';
  static const String openaiEndpoint = 'https://api.openai.com/v1/chat/completions';

  /// Get appropriate endpoint based on config
  String _getEndpoint() {
    if (config.apiKey.contains('puter')) {
      return puterEndpoint;
    }
    return config.selectedModel.contains('gpt') ? openaiEndpoint : puterEndpoint;
  }

  /// Send non-streamed request
  Future<AiResponse> sendRequest(AiRequest request) async {
    final startTime = DateTime.now();
    
    try {
      // Build request body
      final messages = _buildMessages(request);
      final requestBody = {
        'model': config.selectedModel,
        'messages': messages,
        'temperature': config.temperature,
        'max_tokens': config.maxTokens,
        'top_p': config.topP,
        'frequency_penalty': config.frequencyPenalty,
        'presence_penalty': config.presencePenalty,
      };

      // Add custom parameters
      if (config.webSearchEnabled) {
        requestBody['tools'] = [
          {
            'type': 'web_search',
            'query': request.searchQuery ?? request.userMessage,
            'engine': config.searchEngine,
          }
        ];
      }

      // Send request
      final headers = _buildHeaders();
      final response = await httpClient
          .post(
            Uri.parse(_getEndpoint()),
            headers: headers,
            body: jsonEncode(requestBody),
          )
          .timeout(Duration(seconds: config.timeoutSeconds));

      if (response.statusCode != 200) {
        throw AiServiceException(
          code: 'http_error',
          message: 'HTTP ${response.statusCode}',
          details: response.body,
          httpStatusCode: response.statusCode,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final content = data['choices']?[0]['message']?['content'] as String? ?? '';

      return AiResponse(
        id: const Uuid().v4(),
        requestId: request.id,
        role: 'assistant',
        content: content,
        metadata: AiResponseMetadata(
          totalTokensUsed: data['usage']?['total_tokens'] as int? ?? 0,
          promptTokens: data['usage']?['prompt_tokens'] as int? ?? 0,
          completionTokens: data['usage']?['completion_tokens'] as int? ?? 0,
          finishReason: data['choices']?[0]['finish_reason'] as String?,
          processingTimeMs: DateTime.now().difference(startTime).inMilliseconds.toDouble(),
          httpStatusCode: response.statusCode,
        ),
      );
    } on AiServiceException {
      rethrow;
    } catch (e, st) {
      throw AiServiceException(
        code: 'request_failed',
        message: 'Failed to send request to online AI',
        details: e.toString(),
        originalError: e,
        stackTrace: st,
      );
    }
  }

  /// Stream request
  Stream<AiStreamChunk> streamRequest(AiRequest request) async* {
    try {
      final messages = _buildMessages(request);
      final requestBody = {
        'model': config.selectedModel,
        'messages': messages,
        'stream': true,
        'temperature': config.temperature,
        'max_tokens': config.maxTokens,
        'top_p': config.topP,
        'frequency_penalty': config.frequencyPenalty,
        'presence_penalty': config.presencePenalty,
      };

      final headers = _buildHeaders();
      final httpRequest = http.Request(
        'POST',
        Uri.parse(_getEndpoint()),
      )
        ..headers.addAll(headers)
        ..body = jsonEncode(requestBody);

      final streamedResponse = await httpClient
          .send(httpRequest)
          .timeout(Duration(seconds: config.timeoutSeconds));

      if (streamedResponse.statusCode != 200) {
        throw AiServiceException(
          code: 'http_error',
          message: 'HTTP ${streamedResponse.statusCode}',
          httpStatusCode: streamedResponse.statusCode,
        );
      }

      int sequenceNumber = 0;
      await for (final line in streamedResponse.stream
          .transform(Utf8Codec().decoder)
          .transform(LineSplitter())) {
        
        if (line.isEmpty || line == '[DONE]') continue;
        if (!line.startsWith('data: ')) continue;

        final jsonStr = line.substring(6).trim();
        try {
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;
          final delta = data['choices']?[0]['delta'] as Map<String, dynamic>?;
          
          if (delta == null) continue;

          final content = delta['content'] as String? ?? '';
          final finishReason = data['choices']?[0]['finish_reason'] as String?;

          yield AiStreamChunk(
            id: const Uuid().v4(),
            requestId: request.id,
            deltaContent: content,
            sequenceNumber: sequenceNumber++,
            isLast: finishReason != null && finishReason != 'null',
          );
        } catch (e) {
          // Malformed JSON, skip
          continue;
        }
      }
    } catch (e, st) {
      throw AiServiceException(
        code: 'stream_failed',
        message: 'Streaming failed: $e',
        originalError: e,
        stackTrace: st,
      );
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _buildMessages(AiRequest request) {
    final messages = <Map<String, dynamic>>[];

    // Add system prompt
    if (request.systemPrompt.isNotEmpty) {
      messages.add({
        'role': 'system',
        'content': request.systemPrompt,
      });
    }

    // Add conversation history
    for (final msg in request.conversationHistory) {
      messages.add({
        'role': msg.role,
        'content': msg.content,
      });
    }

    // Add current user message
    messages.add({
      'role': 'user',
      'content': request.userMessage,
    });

    return messages;
  }

  Map<String, String> _buildHeaders() {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'KanMonAI/1.0',
    };

    if (config.apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.apiKey}';
    }

    return headers;
  }
}
