// lib/data/services/ai_request_handler.dart
// KanMon GO — Main AI Request Router + Unified Interface (Session 6)
//
// Routes requests to the active AI source (Online / Bulk / Offline HTTP).
// Uses AiSourceSettingsService for config; wraps the three HTTP services.
// NOTE: "Offline" here = Ollama/llama-server HTTP mode, not JNI llama.cpp.
//       For JNI offline inference, use offline_ai_service.dart directly.
// =============================================================================

import 'dart:async';
import 'package:uuid/uuid.dart';

import '../models/ai_request_model.dart';
import '../models/ai_stream_event.dart';
import '../models/ai_source_config.dart';
import 'ai_source_settings_service.dart';
import 'online_ai_service.dart';
import 'bulk_ai_request_service.dart';
import 'offline_ai_request_service.dart';
import 'response_processor.dart';
import 'file_context_manager.dart';

// ── Unified config snapshot ───────────────────────────────────────────────────

class _AiConfigSnapshot {
  final OnlineAiConfig  online;
  final BulkAiConfig    bulk;
  final OfflineAiConfig offline;
  final String          activeSource;

  const _AiConfigSnapshot({
    required this.online,
    required this.bulk,
    required this.offline,
    required this.activeSource,
  });
}

// ── Handler ───────────────────────────────────────────────────────────────────

/// Main AI request handler — routes to the appropriate HTTP service.
class AiRequestHandler {
  final AiSourceSettingsService _settings;
  final ResponseProcessor       _processor;
  final FileContextManager      _fileCtxMgr;

  // Optional pre-built services (injected for testability)
  final OnlineAiService?         _onlineService;
  final BulkAiRequestService?    _bulkService;
  final OfflineAiRequestService? _offlineService;

  // Broadcast stream for UI to listen to
  final _eventCtrl = StreamController<AiStreamEvent>.broadcast();
  Stream<AiStreamEvent> get streamEvents => _eventCtrl.stream;

  // Active request tracking (for cancellation)
  final _activeStreams = <String, bool>{};

  AiRequestHandler({
    required AiSourceSettingsService settings,
    required ResponseProcessor       processor,
    required FileContextManager      fileContextManager,
    OnlineAiService?         onlineService,
    BulkAiRequestService?    bulkService,
    OfflineAiRequestService? offlineService,
  })  : _settings     = settings,
        _processor    = processor,
        _fileCtxMgr   = fileContextManager,
        _onlineService  = onlineService,
        _bulkService    = bulkService,
        _offlineService = offlineService;

  // ── Config accessors ──────────────────────────────────────────────────────

  String getActiveSourceType() => _settings.activeSource;

  _AiConfigSnapshot _snapshot() => _AiConfigSnapshot(
    online:       _settings.online,
    bulk:         _settings.bulk,
    offline:      _settings.offline,
    activeSource: _settings.activeSource,
  );

  // ── Public API ────────────────────────────────────────────────────────────

  /// Send a request (streaming or non-streaming) and return the full response.
  Future<AiResponse> sendRequest(
    String userMessage, {
    List<AiMessage>?  conversationHistory,
    List<String>?     attachedFilePaths,
    bool              useStreaming = false,
  }) async {
    final requestId = const Uuid().v4();
    final snap      = _snapshot();

    final request = AiRequest(
      id:                   requestId,
      sourceType:           snap.activeSource,
      sourceModelId:        _modelId(snap),
      conversationHistory:  conversationHistory ?? [],
      userMessage:          userMessage,
      systemPrompt:         _systemPrompt(snap),
      personaName:          _personaName(snap),
      parameters:           _parameters(snap),
      attachedFilePaths:    attachedFilePaths ?? [],
      enableStreaming:      useStreaming,
      timeoutSeconds:       _timeout(snap),
      customHeaders:        _headers(snap),
      languageHint:         _language(snap),
      webSearchEnabled:     _webSearch(snap),
    );

    try {
      final raw       = useStreaming
          ? await _streamedRequest(request, snap)
          : await _directRequest(request, snap);
      final processed = await _processor.processResponse(raw);
      return processed;
    } on AiServiceException {
      rethrow;
    } catch (e, st) {
      throw AiServiceException(
        code:          'request_failed',
        message:       'Request failed: ${e.toString()}',
        originalError: e,
        stackTrace:    st,
      );
    }
  }

  /// Cancel an active streaming request.
  void cancelRequest(String requestId) {
    _activeStreams.remove(requestId);
    _eventCtrl.add(StreamCancelledEvent(
      requestId:       requestId,
      tokensReceived:  0,
      partialContent:  '',
    ));
  }

  void dispose() {
    _eventCtrl.close();
  }

  // ── Direct (non-streaming) ────────────────────────────────────────────────

  Future<AiResponse> _directRequest(
    AiRequest request,
    _AiConfigSnapshot snap,
  ) {
    switch (snap.activeSource) {
      case 'online':
        return (_onlineService ?? _buildOnlineService(snap.online))
            .sendRequest(request);
      case 'bulk':
        return (_bulkService ?? _buildBulkService(snap.bulk))
            .sendRequest(request);
      case 'offline':
        return (_offlineService ?? _buildOfflineService(snap.offline))
            .sendRequest(request);
      default:
        throw AiServiceException(
          code:    'unknown_source',
          message: 'Unknown source: ${snap.activeSource}',
        );
    }
  }

  // ── Streamed ──────────────────────────────────────────────────────────────

  Future<AiResponse> _streamedRequest(
    AiRequest request,
    _AiConfigSnapshot snap,
  ) async {
    _activeStreams[request.id] = true;

    _eventCtrl.add(StreamStartedEvent(
      requestId:  request.id,
      modelId:    request.sourceModelId,
      sourceType: request.sourceType,
    ));

    late Stream<AiStreamChunk> chunks;
    switch (snap.activeSource) {
      case 'online':
        chunks = (_onlineService ?? _buildOnlineService(snap.online))
            .streamRequest(request);
        break;
      case 'bulk':
        chunks = (_bulkService ?? _buildBulkService(snap.bulk))
            .streamRequest(request);
        break;
      case 'offline':
        chunks = (_offlineService ?? _buildOfflineService(snap.offline))
            .streamRequest(request);
        break;
      default:
        throw AiServiceException(
          code:    'unknown_source',
          message: 'Unknown source: ${snap.activeSource}',
        );
    }

    final content = StringBuffer();
    int   tokens  = 0;
    int   count   = 0;
    final start   = DateTime.now();

    try {
      await for (final chunk in chunks) {
        if (!_activeStreams.containsKey(request.id)) break; // cancelled

        content.write(chunk.deltaContent);
        tokens += chunk.deltaContent.split(' ').length;
        count++;

        final event = StreamChunkEvent(
          requestId:       request.id,
          deltaContent:    chunk.deltaContent,
          tokenCount:      chunk.deltaContent.split(' ').length,
          elapsedSeconds:  DateTime.now().difference(start).inMilliseconds / 1000,
          totalCharacters: content.length,
        );
        _eventCtrl.add(event);

        if (chunk.isLast) break;
      }
    } finally {
      _activeStreams.remove(request.id);
    }

    final totalMs = DateTime.now().difference(start).inMilliseconds.toDouble();

    final response = AiResponse(
      id:        const Uuid().v4(),
      requestId: request.id,
      role:      'assistant',
      content:   content.toString(),
      metadata:  AiResponseMetadata(
        totalTokensUsed:  tokens,
        promptTokens:     0,
        completionTokens: tokens,
        finishReason:     'stop',
        processingTimeMs: totalMs,
      ),
      isStreamed: true,
      chunkCount: count,
    );

    _eventCtrl.add(StreamCompletedEvent(
      requestId:        request.id,
      fullContent:      content.toString(),
      totalTokens:      tokens,
      totalChunks:      count,
      totalTimeSeconds: totalMs / 1000,
      finishReason:     'stop',
    ));

    return response;
  }

  // ── Service builders (lazy defaults) ─────────────────────────────────────

  OnlineAiService _buildOnlineService(OnlineAiConfig cfg) =>
      OnlineAiService(config: cfg);

  BulkAiRequestService _buildBulkService(BulkAiConfig cfg) {
    // Resolve provider key from activeProvider enum name
    final providerKey = cfg.activeProvider?.toString().split('.').last ?? 'openrouter';
    // API key is normally injected by BulkApiService; default to empty for now
    return BulkAiRequestService(
      config:      cfg,
      apiKey:      '',
      providerKey: providerKey,
    );
  }

  OfflineAiRequestService _buildOfflineService(OfflineAiConfig cfg) =>
      OfflineAiRequestService(config: cfg);

  // ── Config extraction helpers ─────────────────────────────────────────────

  String _modelId(_AiConfigSnapshot s) {
    switch (s.activeSource) {
      case 'online':  return s.online.selectedModel;
      case 'bulk':    return s.bulk.selectedModel;
      case 'offline': return s.offline.activeModelPath.split('/').last;
      default:        return 'unknown';
    }
  }

  String _systemPrompt(_AiConfigSnapshot s) {
    switch (s.activeSource) {
      case 'online':  return s.online.systemPrompt;
      case 'bulk':    return s.bulk.systemPrompt;
      case 'offline': return s.offline.systemPrompt;
      default:        return '';
    }
  }

  String _personaName(_AiConfigSnapshot s) {
    switch (s.activeSource) {
      case 'online':  return s.online.personaName;
      case 'bulk':    return s.bulk.personaName;
      case 'offline': return s.offline.personaName;
      default:        return 'Assistant';
    }
  }

  Map<String, dynamic> _parameters(_AiConfigSnapshot s) {
    switch (s.activeSource) {
      case 'online':
        return {
          'temperature':      s.online.temperature,
          'maxTokens':        s.online.maxTokens,
          'topP':             s.online.topP,
          'frequencyPenalty': s.online.frequencyPenalty,
          'presencePenalty':  s.online.presencePenalty,
        };
      case 'bulk':
        return {
          'temperature': s.bulk.temperature,
          'maxTokens':   s.bulk.maxTokens,
          'topP':        s.bulk.topP,
        };
      case 'offline':
        return {
          'temperature':   s.offline.temperature,
          'maxTokens':     s.offline.maxNewTokens,
          'topP':          s.offline.topP,
          'topK':          s.offline.topK,
          'repeatPenalty': s.offline.repeatPenalty,
        };
      default:
        return {};
    }
  }

  int _timeout(_AiConfigSnapshot s) {
    switch (s.activeSource) {
      case 'online':  return s.online.timeoutSeconds;
      case 'bulk':    return s.bulk.timeoutSeconds;
      case 'offline': return 120;
      default:        return 30;
    }
  }

  Map<String, String> _headers(_AiConfigSnapshot s) {
    if (s.activeSource == 'online' && s.online.apiKey.isNotEmpty) {
      return {'Authorization': 'Bearer ${s.online.apiKey}'};
    }
    return {};
  }

  String _language(_AiConfigSnapshot s) {
    if (s.activeSource == 'online') return s.online.language;
    if (s.activeSource == 'bulk')   return s.bulk.language;
    return 'auto';
  }

  bool _webSearch(_AiConfigSnapshot s) {
    if (s.activeSource == 'online') return s.online.webSearchEnabled;
    return false;
  }
}
