// lib/data/services/offline_ai_request_service.dart
// Pocket Harness — Offline HTTP AI Request Service (Session 6 Integration Layer)
//
// HTTP client for local AI servers (Ollama / llama.cpp server mode).
// Distinct from offline_ai_service.dart (which uses llama.cpp JNI directly).
// Use this when user runs Ollama or llama-server on the device/LAN.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/ai_request_model.dart';
import '../models/ai_source_config.dart';

// ── Server type constants ─────────────────────────────────────────────────────

const kServerTypeOllama   = 'ollama';
const kServerTypeLlamaCpp = 'llama_cpp';

// ── Service class ─────────────────────────────────────────────────────────────

/// HTTP client for local AI servers (Ollama / llama.cpp http server mode).
/// Takes [OfflineAiConfig] for inference params; server address is configurable.
class OfflineAiRequestService {
  final OfflineAiConfig config;
  final String serverHost;   // e.g. "localhost" or "192.168.1.x"
  final int    serverPort;   // e.g. 11434 (Ollama) or 8080 (llama.cpp)
  final String serverType;   // "ollama" | "llama_cpp"
  final http.Client httpClient;

  OfflineAiRequestService({
    required this.config,
    this.serverHost = 'localhost',
    this.serverPort = 11434,
    this.serverType = kServerTypeOllama,
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client();

  String get _baseUrl => 'http://$serverHost:$serverPort';

  String get _chatEndpoint => serverType == kServerTypeOllama
      ? '$_baseUrl/api/chat'
      : '$_baseUrl/v1/chat/completions';

  String get _generateEndpoint => serverType == kServerTypeOllama
      ? '$_baseUrl/api/generate'
      : '$_baseUrl/v1/completions';

  // ── Health check ──────────────────────────────────────────────────────────

  Future<bool> isServerReachable() async {
    try {
      final url = serverType == kServerTypeOllama
          ? '$_baseUrl/api/tags'
          : '$_baseUrl/health';
      final resp = await httpClient
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Non-streaming request ─────────────────────────────────────────────────

  Future<AiResponse> sendRequest(AiRequest request) async {
    final startTime = DateTime.now();

    try {
      final body    = _buildBody(request);
      final headers = {HttpHeaders.contentTypeHeader: 'application/json'};

      final response = await httpClient
          .post(Uri.parse(_chatEndpoint), headers: headers, body: jsonEncode(body))
          .timeout(Duration(seconds: _timeout));

      if (response.statusCode != 200) {
        throw AiServiceException(
          code:           'offline_server_error',
          message:        'Server returned ${response.statusCode}',
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
          totalTokensUsed:  0,
          promptTokens:     0,
          completionTokens: 0,
          finishReason:     'stop',
          processingTimeMs: DateTime.now().difference(startTime).inMilliseconds.toDouble(),
          httpStatusCode:   response.statusCode,
        ),
      );
    } on AiServiceException {
      rethrow;
    } catch (e, st) {
      throw AiServiceException(
        code:          'offline_request_failed',
        message:       'Failed to reach offline AI server at $_baseUrl',
        originalError: e,
        stackTrace:    st,
      );
    }
  }

  // ── Streaming request ─────────────────────────────────────────────────────

  Stream<AiStreamChunk> streamRequest(AiRequest request) async* {
    try {
      final body    = _buildBody(request, stream: true);
      final headers = {HttpHeaders.contentTypeHeader: 'application/json'};

      final httpReq = http.Request('POST', Uri.parse(_chatEndpoint))
        ..headers.addAll(headers)
        ..body = jsonEncode(body);

      final streamed = await httpClient
          .send(httpReq)
          .timeout(Duration(seconds: _timeout));

      if (streamed.statusCode != 200) {
        throw AiServiceException(
          code:           'offline_server_error',
          message:        'HTTP ${streamed.statusCode}',
          httpStatusCode: streamed.statusCode,
        );
      }

      int seq = 0;
      if (serverType == kServerTypeOllama) {
        // Ollama streams JSON lines
        await for (final line in streamed.stream
            .transform(const Utf8Decoder())
            .transform(const LineSplitter())) {
          if (line.isEmpty) continue;
          try {
            final data    = jsonDecode(line) as Map<String, dynamic>;
            final message = data['message'] as Map<String, dynamic>?;
            final delta   = message?['content'] as String? ?? '';
            final isDone  = data['done'] as bool? ?? false;

            yield AiStreamChunk(
              id:             const Uuid().v4(),
              requestId:      request.id,
              deltaContent:   delta,
              sequenceNumber: seq++,
              isLast:         isDone,
            );
            if (isDone) break;
          } catch (_) {
            continue;
          }
        }
      } else {
        // llama.cpp server uses SSE
        await for (final line in streamed.stream
            .transform(const Utf8Decoder())
            .transform(const LineSplitter())) {
          if (line.isEmpty || !line.startsWith('data: ')) continue;
          try {
            final jsonStr = line.substring(6).trim();
            if (jsonStr == '[DONE]') break;

            final data  = jsonDecode(jsonStr) as Map<String, dynamic>;
            final delta = data['choices']?[0]['delta'] as Map<String, dynamic>?;
            if (delta == null) continue;

            yield AiStreamChunk(
              id:             const Uuid().v4(),
              requestId:      request.id,
              deltaContent:   delta['content'] as String? ?? '',
              sequenceNumber: seq++,
              isLast:         data['choices']?[0]['finish_reason'] != null,
            );
          } catch (_) {
            continue;
          }
        }
      }
    } catch (e, st) {
      throw AiServiceException(
        code:          'offline_stream_failed',
        message:       'Offline stream failed: $e',
        originalError: e,
        stackTrace:    st,
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  // OfflineAiConfig uses maxNewTokens (not maxTokens)
  int get _maxTokens => config.maxNewTokens;
  int get _timeout   => 120; // Offline models can be slow; generous timeout

  Map<String, dynamic> _buildBody(AiRequest request, {bool stream = false}) {
    if (serverType == kServerTypeOllama) {
      final messages = <Map<String, dynamic>>[];
      if (request.systemPrompt.isNotEmpty) {
        messages.add({'role': 'system', 'content': request.systemPrompt});
      }
      for (final msg in request.conversationHistory) {
        messages.add({'role': msg.role, 'content': msg.content});
      }
      messages.add({'role': 'user', 'content': request.userMessage});

      return {
        'model':    config.activeModelPath.split('/').last.replaceAll('.gguf', ''),
        'messages': messages,
        'stream':   stream,
        'options': {
          'temperature':     config.temperature,
          'top_p':           config.topP,
          'top_k':           config.topK,
          'repeat_penalty':  config.repeatPenalty,
          'num_predict':     _maxTokens,
          'seed':            config.seed,
        },
      };
    } else {
      // llama.cpp server (OpenAI-compatible)
      final messages = <Map<String, dynamic>>[];
      if (request.systemPrompt.isNotEmpty) {
        messages.add({'role': 'system', 'content': request.systemPrompt});
      }
      for (final msg in request.conversationHistory) {
        messages.add({'role': msg.role, 'content': msg.content});
      }
      messages.add({'role': 'user', 'content': request.userMessage});

      return {
        'model':       'local',
        'messages':    messages,
        'stream':      stream,
        'temperature': config.temperature,
        'top_p':       config.topP,
        'max_tokens':  _maxTokens,
      };
    }
  }

  String _extractContent(Map<String, dynamic> data) {
    // Ollama chat format
    final message = data['message'] as Map<String, dynamic>?;
    if (message != null) return message['content'] as String? ?? '';
    // OpenAI-compatible
    if (data['choices'] != null) {
      final choice = (data['choices'] as List).first as Map<String, dynamic>;
      return choice['message']?['content'] as String? ?? '';
    }
    return data['response'] as String? ?? '';
  }
}
