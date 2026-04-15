// lib/data/services/llama_http_server.dart
// KanMon GO — LlamaHttpServer (OpenAI-Compatible HTTP Bridge)
//
// Menyediakan endpoint HTTP yang kompatibel dengan OpenAI API:
//   • POST /v1/chat/completions — streaming SSE dan non-streaming
//   • GET  /v1/models           — daftar model yang tersedia
//
// Server berjalan di dalam proses Flutter (tidak ada proses terpisah).
// Membungkus LlamaService yang sudah ada dan meneruskan token ke klien HTTP.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:kanmongo/core/ai/llama_context.dart';
import 'package:kanmongo/data/services/llama_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CLASS: LlamaHttpServer
// ─────────────────────────────────────────────────────────────────────────────

/// Server HTTP ringan yang kompatibel dengan OpenAI API, membungkus LlamaService.
/// Singleton — panggil [start] untuk mulai, [stop] untuk berhenti.
class LlamaHttpServer {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final LlamaHttpServer instance = LlamaHttpServer._();
  LlamaHttpServer._();

  // ── State ──────────────────────────────────────────────────────────────────
  HttpServer? _server;
  int? _port;

  /// Port aktual yang sedang digunakan server. Null jika tidak berjalan.
  int? get port => _port;

  /// Apakah server sedang berjalan.
  bool get isRunning => _server != null;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Mulai server HTTP. Mengembalikan port aktual yang digunakan.
  /// Jika server sudah berjalan, langsung mengembalikan port yang sudah ada.
  /// Mencoba port 8080–8090 secara berurutan.
  Future<int> start() async {
    if (_server != null) {
      debugPrint('[LlamaHttpServer] Already running on port $_port');
      return _port!;
    }

    HttpServer? server;
    int? actualPort;

    for (int p = 8080; p <= 8090; p++) {
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, p);
        actualPort = p;
        debugPrint('[LlamaHttpServer] Bound to port $p');
        break;
      } on SocketException catch (e) {
        debugPrint('[LlamaHttpServer] Port $p busy: $e');
      }
    }

    if (server == null || actualPort == null) {
      throw StateError('[LlamaHttpServer] Could not bind to any port in range 8080–8090');
    }

    _server = server;
    _port = actualPort;

    // Mulai mendengarkan koneksi masuk (tidak di-await — non-blocking)
    _listenForever(server);

    debugPrint('[LlamaHttpServer] Started. Listening on http://localhost:$_port/');
    return _port!;
  }

  /// Hentikan server HTTP. No-op jika tidak berjalan.
  Future<void> stop() async {
    if (_server == null) return;
    await _server!.close(force: true);
    _server = null;
    _port = null;
    debugPrint('[LlamaHttpServer] Stopped.');
  }

  // ── Internal: Request Loop ─────────────────────────────────────────────────

  void _listenForever(HttpServer server) {
    server.listen(
      (HttpRequest request) async {
        try {
          await _handleRequest(request);
        } catch (e, st) {
          debugPrint('[LlamaHttpServer] Unhandled error in request: $e\n$st');
          try {
            _sendJson(request.response, 500, {
              'error': {
                'message': 'Internal server error: $e',
                'type': 'internal_error',
                'code': 500,
              },
            });
          } catch (_) {}
        }
      },
      onError: (e) => debugPrint('[LlamaHttpServer] Server stream error: $e'),
      cancelOnError: false,
    );
  }

  // ── Internal: Request Dispatcher ──────────────────────────────────────────

  Future<void> _handleRequest(HttpRequest req) async {
    final method = req.method.toUpperCase();
    final path   = req.uri.path;

    debugPrint('[LlamaHttpServer] $method $path');

    // CORS preflight
    if (method == 'OPTIONS') {
      req.response
        ..statusCode = 200
        ..headers.add('Access-Control-Allow-Origin',  '*')
        ..headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        ..headers.add('Access-Control-Allow-Headers', 'Content-Type, Authorization');
      await req.response.close();
      return;
    }

    if (method == 'GET' && path == '/v1/models') {
      return _handleModels(req);
    }

    if (method == 'POST' && path == '/v1/chat/completions') {
      return _handleChatCompletions(req);
    }

    // 404 fallback
    _sendJson(req.response, 404, {
      'error': {'message': 'Not found', 'type': 'not_found', 'code': 404},
    });
  }

  // ── Internal: GET /v1/models ───────────────────────────────────────────────

  void _handleModels(HttpRequest req) {
    _sendJson(req.response, 200, {
      'object': 'list',
      'data': [
        {
          'id':       'local',
          'object':   'model',
          'created':  0,
          'owned_by': 'kanmon',
        }
      ],
    });
  }

  // ── Internal: POST /v1/chat/completions ───────────────────────────────────

  Future<void> _handleChatCompletions(HttpRequest req) async {
    // Parse request body
    final bodyBytes = await req.fold<List<int>>([], (a, b) => a..addAll(b));
    final bodyStr   = utf8.decode(bodyBytes);

    Map<String, dynamic> body;
    try {
      body = jsonDecode(bodyStr) as Map<String, dynamic>;
    } catch (e) {
      _sendJson(req.response, 400, {
        'error': {'message': 'Invalid JSON body: $e', 'type': 'invalid_request', 'code': 400},
      });
      return;
    }

    // Cek apakah model sudah dimuat
    if (!LlamaService.instance.isModelLoaded) {
      _sendJson(req.response, 503, {
        'error': {
          'message': 'No model loaded. Please load a model in KanMonAI settings.',
          'type':    'model_not_loaded',
          'code':    503,
        },
      });
      return;
    }

    // Tunggu jika sedang dalam status generating (max 60 detik)
    if (LlamaService.instance.status == ModelStatus.generating) {
      debugPrint('[LlamaHttpServer] Model busy, waiting up to 60s...');
      final bool ready = await _waitUntilReady(const Duration(seconds: 60));
      if (!ready) {
        _sendJson(req.response, 503, {
          'error': {
            'message': 'Server busy: another generation is in progress and did not finish in 60 seconds.',
            'type':    'server_busy',
            'code':    503,
          },
        });
        return;
      }
    }

    // Konversi messages dan config
    final rawMessages = body['messages'];
    if (rawMessages == null || rawMessages is! List) {
      _sendJson(req.response, 400, {
        'error': {'message': '"messages" field is required and must be an array.', 'type': 'invalid_request', 'code': 400},
      });
      return;
    }

    final messages = _convertMessages(rawMessages.cast<Map<String, dynamic>>());
    final config   = _inferenceConfigFromRequest(body);
    final stream   = body['stream'] == true;
    final reqId    = 'cmpl-${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';

    if (stream) {
      await _respondStreaming(req, messages, config, reqId);
    } else {
      await _respondNonStreaming(req, messages, config, reqId);
    }
  }

  // ── Internal: Streaming Response ──────────────────────────────────────────

  Future<void> _respondStreaming(
    HttpRequest req,
    List<ChatMessage> messages,
    InferenceConfig config,
    String reqId,
  ) async {
    final resp = req.response;
    resp.statusCode = 200;
    _addCorsHeaders(resp);
    resp.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
    resp.headers.add('Cache-Control', 'no-cache');
    resp.headers.add('X-Accel-Buffering', 'no');

    // Chunk awal — role delta
    final firstChunk = _makeChunk(reqId, delta: {'role': 'assistant', 'content': ''});
    resp.write('data: ${jsonEncode(firstChunk)}\n\n');

    bool hadError = false;
    try {
      await for (final token in LlamaService.instance.generateStream(
        messages: messages,
        config:   config,
      )) {
        final chunk = _makeChunk(reqId, delta: {'content': token});
        resp.write('data: ${jsonEncode(chunk)}\n\n');
      }
    } catch (e) {
      debugPrint('[LlamaHttpServer] Streaming error: $e');
      hadError = true;
    }

    // Chunk akhir — finish_reason
    final doneChunk = _makeChunk(reqId, delta: {}, finishReason: 'stop');
    resp.write('data: ${jsonEncode(doneChunk)}\n\n');
    resp.write('data: [DONE]\n\n');

    if (hadError) {
      debugPrint('[LlamaHttpServer] Streaming completed with error for $reqId');
    } else {
      debugPrint('[LlamaHttpServer] Streaming completed for $reqId');
    }

    await resp.close();
  }

  // ── Internal: Non-Streaming Response ──────────────────────────────────────

  Future<void> _respondNonStreaming(
    HttpRequest req,
    List<ChatMessage> messages,
    InferenceConfig config,
    String reqId,
  ) async {
    final buffer = StringBuffer();

    try {
      await for (final token in LlamaService.instance.generateStream(
        messages: messages,
        config:   config,
      )) {
        buffer.write(token);
      }
    } catch (e) {
      debugPrint('[LlamaHttpServer] Non-streaming error: $e');
      _sendJson(req.response, 500, {
        'error': {'message': 'Generation error: $e', 'type': 'generation_error', 'code': 500},
      });
      return;
    }

    _sendJson(req.response, 200, {
      'id':      reqId,
      'object':  'chat.completion',
      'model':   'local',
      'choices': [
        {
          'index':         0,
          'message':       {'role': 'assistant', 'content': buffer.toString()},
          'finish_reason': 'stop',
        }
      ],
      'usage': {
        'prompt_tokens':     0,
        'completion_tokens': 0,
        'total_tokens':      0,
      },
    });
  }

  // ── Internal: Helpers ──────────────────────────────────────────────────────

  /// Tunggu hingga LlamaService tidak lagi dalam status [ModelStatus.generating].
  /// Mengembalikan true jika siap dalam batas waktu, false jika timeout.
  Future<bool> _waitUntilReady(Duration timeout) async {
    final completer = Completer<bool>();
    final deadline  = DateTime.now().add(timeout);

    StreamSubscription<ModelStatus>? sub;
    sub = LlamaService.instance.statusStream.listen((status) {
      if (status == ModelStatus.loaded || status == ModelStatus.error) {
        if (!completer.isCompleted) completer.complete(true);
        sub?.cancel();
      }
    });

    // Timeout guard
    Future.delayed(timeout).then((_) {
      if (!completer.isCompleted) {
        completer.complete(false);
        sub?.cancel();
      }
    });

    // Double-check: jika sudah tidak generating saat listener dipasang
    if (LlamaService.instance.status != ModelStatus.generating) {
      if (!completer.isCompleted) {
        completer.complete(true);
        sub.cancel();
      }
    }

    final bool result = await completer.future;
    // Pastikan deadline tidak terlewat (jika sudah selesai tapi lewat waktu)
    if (DateTime.now().isAfter(deadline)) return false;
    return result;
  }

  /// Konversi list of map (OpenAI format) ke List<ChatMessage>.
  List<ChatMessage> _convertMessages(List<Map<String, dynamic>> raw) {
    return raw.map((m) {
      final role    = m['role'] as String? ?? 'user';
      final content = m['content'] as String? ?? '';
      final chatRole = switch (role) {
        'system'    => ChatRole.system,
        'assistant' => ChatRole.assistant,
        _           => ChatRole.user,
      };
      return ChatMessage(
        id:        DateTime.now().microsecondsSinceEpoch.toString(),
        role:      chatRole,
        content:   content,
        timestamp: DateTime.now(),
      );
    }).toList();
  }

  /// Buat InferenceConfig dari body request OpenAI.
  InferenceConfig _inferenceConfigFromRequest(Map<String, dynamic> body) {
    double _d(String key, double def) {
      final v = body[key];
      if (v is num) return v.toDouble();
      return def;
    }

    int _i(String key, int def) {
      final v = body[key];
      if (v is num) return v.toInt();
      return def;
    }

    final maxTokens = body['max_tokens'] ?? body['max_new_tokens'];
    final maxNew    = (maxTokens is num) ? maxTokens.toInt() : 512;

    return InferenceConfig(
      temperature:  _d('temperature', 0.7),
      topP:         _d('top_p',       0.9),
      topK:         _i('top_k',       40),
      maxNewTokens: maxNew,
      repeatPenalty: _d('repeat_penalty', 1.1),
      seed:         _i('seed',        -1),
    );
  }

  /// Buat satu SSE chunk dalam format OpenAI chat.completion.chunk.
  Map<String, dynamic> _makeChunk(
    String id, {
    required Map<String, dynamic> delta,
    String? finishReason,
  }) {
    return {
      'id':      id,
      'object':  'chat.completion.chunk',
      'model':   'local',
      'choices': [
        {
          'index':         0,
          'delta':         delta,
          'finish_reason': finishReason,
        }
      ],
    };
  }

  /// Kirim response JSON dengan status code dan CORS headers.
  void _sendJson(HttpResponse resp, int statusCode, Map<String, dynamic> body) {
    resp.statusCode = statusCode;
    _addCorsHeaders(resp);
    resp.headers.contentType = ContentType.json;
    resp.write(jsonEncode(body));
    resp.close();
  }

  /// Tambahkan CORS headers ke response.
  void _addCorsHeaders(HttpResponse resp) {
    resp.headers.add('Access-Control-Allow-Origin',  '*');
    resp.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    resp.headers.add('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  }
}
