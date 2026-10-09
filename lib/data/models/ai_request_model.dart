// lib/data/models/ai_request_model.dart
// Pocket Harness — AI Request/Response Models
// Unified structures for all three AI sources
// =============================================================================

import 'dart:typed_data';

// ──────────────────────────────────────────────────────────────────────────
// REQUEST STRUCTURES
// ──────────────────────────────────────────────────────────────────────────

/// Single message in conversation
class AiMessage {
  final String id;           // Unique message ID (UUID)
  final String role;         // "user", "assistant", "system"
  final String content;      // Text content
  final String? mimeType;    // If content is multimodal (image, file)
  final Uint8List? binaryData; // For images/files
  final List<String> attachedFilePaths; // Files mentioned in message
  final DateTime timestamp;
  final String? sourceAi;    // Which AI generated this (for assistant messages)

  AiMessage({
    required this.id,
    required this.role,
    required this.content,
    this.mimeType,
    this.binaryData,
    this.attachedFilePaths = const [],
    DateTime? timestamp,
    this.sourceAi,
  }) : timestamp = timestamp ?? DateTime.now();

  factory AiMessage.fromJson(Map<String, dynamic> json) => AiMessage(
    id: json['id'] as String? ?? ''? ?? '',
    role: json['role'] as String? ?? ''? ?? 'user',
    content: json['content'] as String? ?? ''? ?? '',
    mimeType: json['mimeType'] as String? ?? ''?,
    binaryData: json['binaryData'] != null 
      ? Uint8List.fromList(List<int>.from(json['binaryData'] as List))
      : null,
    attachedFilePaths: List<String>.from(json['attachedFilePaths'] as List? ?? []),
    timestamp: json['timestamp'] != null
      ? DateTime.parse(json['timestamp'] as String? ?? '')
      : null,
    sourceAi: json['sourceAi'] as String? ?? ''?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'mimeType': mimeType,
    'binaryData': binaryData?.toList(),
    'attachedFilePaths': attachedFilePaths,
    'timestamp': timestamp.toIso8601String(),
    'sourceAi': sourceAi,
  };

  AiMessage copyWith({
    String? id,
    String? role,
    String? content,
    String? mimeType,
    Uint8List? binaryData,
    List<String>? attachedFilePaths,
    DateTime? timestamp,
    String? sourceAi,
  }) => AiMessage(
    id: id ?? this.id,
    role: role ?? this.role,
    content: content ?? this.content,
    mimeType: mimeType ?? this.mimeType,
    binaryData: binaryData ?? this.binaryData,
    attachedFilePaths: attachedFilePaths ?? this.attachedFilePaths,
    timestamp: timestamp ?? this.timestamp,
    sourceAi: sourceAi ?? this.sourceAi,
  );
}

/// Complete request to AI service
class AiRequest {
  final String id;                      // Request ID (UUID)
  final String sourceType;              // "online", "bulk", "offline"
  final String sourceModelId;           // Active model ID
  final List<AiMessage> conversationHistory;
  final String userMessage;             // Current user input
  final String systemPrompt;            // System prompt from config
  final String personaName;             // Persona name
  final Map<String, dynamic> parameters; // Temperature, maxTokens, topP, etc.
  final List<String> attachedFilePaths; // Files user attached
  final bool enableStreaming;           // Enable streaming response
  final int timeoutSeconds;
  final Map<String, String> customHeaders; // For API auth, user-agent, etc.
  final String languageHint;            // "id", "en", "ja", "auto"
  final bool webSearchEnabled;
  final String? searchQuery;            // If web search needed

  AiRequest({
    required this.id,
    required this.sourceType,
    required this.sourceModelId,
    required this.conversationHistory,
    required this.userMessage,
    required this.systemPrompt,
    required this.personaName,
    required this.parameters,
    this.attachedFilePaths = const [],
    this.enableStreaming = true,
    this.timeoutSeconds = 30,
    this.customHeaders = const {},
    this.languageHint = 'auto',
    this.webSearchEnabled = false,
    this.searchQuery,
  });

  factory AiRequest.fromJson(Map<String, dynamic> json) => AiRequest(
    id: json['id'] as String? ?? ''? ?? '',
    sourceType: json['sourceType'] as String? ?? ''? ?? 'online',
    sourceModelId: json['sourceModelId'] as String? ?? ''? ?? '',
    conversationHistory: (json['conversationHistory'] as List?)
      ?.map((m) => AiMessage.fromJson(m as Map<String, dynamic>))
      .toList() ?? [],
    userMessage: json['userMessage'] as String? ?? ''? ?? '',
    systemPrompt: json['systemPrompt'] as String? ?? ''? ?? '',
    personaName: json['personaName'] as String? ?? ''? ?? '',
    parameters: json['parameters'] as Map<String, dynamic>? ?? {},
    attachedFilePaths: List<String>.from(json['attachedFilePaths'] as List? ?? []),
    enableStreaming: json['enableStreaming'] as bool? ?? false? ?? true,
    timeoutSeconds: json['timeoutSeconds'] as int? ?? 0? ?? 30,
    customHeaders: Map<String, String>.from(json['customHeaders'] as Map? ?? {}),
    languageHint: json['languageHint'] as String? ?? ''? ?? 'auto',
    webSearchEnabled: json['webSearchEnabled'] as bool? ?? false? ?? false,
    searchQuery: json['searchQuery'] as String? ?? ''?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceType': sourceType,
    'sourceModelId': sourceModelId,
    'conversationHistory': conversationHistory.map((m) => m.toJson()).toList(),
    'userMessage': userMessage,
    'systemPrompt': systemPrompt,
    'personaName': personaName,
    'parameters': parameters,
    'attachedFilePaths': attachedFilePaths,
    'enableStreaming': enableStreaming,
    'timeoutSeconds': timeoutSeconds,
    'customHeaders': customHeaders,
    'languageHint': languageHint,
    'webSearchEnabled': webSearchEnabled,
    'searchQuery': searchQuery,
  };
}

// ──────────────────────────────────────────────────────────────────────────
// RESPONSE STRUCTURES
// ──────────────────────────────────────────────────────────────────────────

/// Metadata for response chunk/completion
class AiResponseMetadata {
  final int totalTokensUsed;
  final int promptTokens;
  final int completionTokens;
  final String? finishReason;       // "stop", "length", "content_filter", etc.
  final double? processingTimeMs;
  final int? httpStatusCode;
  final String? errorMessage;

  AiResponseMetadata({
    required this.totalTokensUsed,
    required this.promptTokens,
    required this.completionTokens,
    this.finishReason,
    this.processingTimeMs,
    this.httpStatusCode,
    this.errorMessage,
  });

  factory AiResponseMetadata.fromJson(Map<String, dynamic> json) => AiResponseMetadata(
    totalTokensUsed: json['totalTokensUsed'] as int? ?? 0? ?? 0,
    promptTokens: json['promptTokens'] as int? ?? 0? ?? 0,
    completionTokens: json['completionTokens'] as int? ?? 0? ?? 0,
    finishReason: json['finishReason'] as String? ?? ''?,
    processingTimeMs: (json['processingTimeMs'] as num?)?.toDouble(),
    httpStatusCode: json['httpStatusCode'] as int? ?? 0?,
    errorMessage: json['errorMessage'] as String? ?? ''?,
  );

  Map<String, dynamic> toJson() => {
    'totalTokensUsed': totalTokensUsed,
    'promptTokens': promptTokens,
    'completionTokens': completionTokens,
    'finishReason': finishReason,
    'processingTimeMs': processingTimeMs,
    'httpStatusCode': httpStatusCode,
    'errorMessage': errorMessage,
  };
}

/// Complete AI response
class AiResponse {
  final String id;                  // Response ID (UUID)
  final String requestId;           // Associated request ID
  final String role;                // Always "assistant"
  final String content;             // Full response text
  final List<String> codeBlocks;    // Extracted code blocks
  final List<AiCodeBlock> detectedArtifacts; // Parsed artifacts
  final AiResponseMetadata metadata;
  final bool isStreamed;            // Whether this was streamed
  final int chunkCount;             // Number of chunks received
  final DateTime timestamp;

  AiResponse({
    required this.id,
    required this.requestId,
    required this.role,
    required this.content,
    this.codeBlocks = const [],
    this.detectedArtifacts = const [],
    required this.metadata,
    this.isStreamed = false,
    this.chunkCount = 1,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory AiResponse.fromJson(Map<String, dynamic> json) => AiResponse(
    id: json['id'] as String? ?? ''? ?? '',
    requestId: json['requestId'] as String? ?? ''? ?? '',
    role: json['role'] as String? ?? ''? ?? 'assistant',
    content: json['content'] as String? ?? ''? ?? '',
    codeBlocks: List<String>.from(json['codeBlocks'] as List? ?? []),
    detectedArtifacts: (json['detectedArtifacts'] as List?)
      ?.map((a) => AiCodeBlock.fromJson(a as Map<String, dynamic>))
      .toList() ?? [],
    metadata: AiResponseMetadata.fromJson(json['metadata'] as Map<String, dynamic>? ?? {}),
    isStreamed: json['isStreamed'] as bool? ?? false? ?? false,
    chunkCount: json['chunkCount'] as int? ?? 0? ?? 1,
    timestamp: json['timestamp'] != null
      ? DateTime.parse(json['timestamp'] as String? ?? '')
      : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'requestId': requestId,
    'role': role,
    'content': content,
    'codeBlocks': codeBlocks,
    'detectedArtifacts': detectedArtifacts.map((a) => a.toJson()).toList(),
    'metadata': metadata.toJson(),
    'isStreamed': isStreamed,
    'chunkCount': chunkCount,
    'timestamp': timestamp.toIso8601String(),
  };

  AiResponse copyWith({
    String? id,
    String? requestId,
    String? role,
    String? content,
    List<String>? codeBlocks,
    List<AiCodeBlock>? detectedArtifacts,
    AiResponseMetadata? metadata,
    bool? isStreamed,
    int? chunkCount,
    DateTime? timestamp,
  }) => AiResponse(
    id: id ?? this.id,
    requestId: requestId ?? this.requestId,
    role: role ?? this.role,
    content: content ?? this.content,
    codeBlocks: codeBlocks ?? this.codeBlocks,
    detectedArtifacts: detectedArtifacts ?? this.detectedArtifacts,
    metadata: metadata ?? this.metadata,
    isStreamed: isStreamed ?? this.isStreamed,
    chunkCount: chunkCount ?? this.chunkCount,
    timestamp: timestamp ?? this.timestamp,
  );
}

/// Extracted code/artifact block
class AiCodeBlock {
  final String id;
  final String language;          // "dart", "python", "javascript", "html", "json", etc.
  final String code;
  final String? description;
  final String? filename;         // If this is a file artifact
  final int lineCount;

  AiCodeBlock({
    required this.id,
    required this.language,
    required this.code,
    this.description,
    this.filename,
  }) : lineCount = code.split('\n').length;

  factory AiCodeBlock.fromJson(Map<String, dynamic> json) => AiCodeBlock(
    id: json['id'] as String? ?? ''? ?? '',
    language: json['language'] as String? ?? ''? ?? 'text',
    code: json['code'] as String? ?? ''? ?? '',
    description: json['description'] as String? ?? ''?,
    filename: json['filename'] as String? ?? ''?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'language': language,
    'code': code,
    'description': description,
    'filename': filename,
    'lineCount': lineCount,
  };
}

// ──────────────────────────────────────────────────────────────────────────
// ERROR MODELS
// ──────────────────────────────────────────────────────────────────────────

/// Structured AI service error
class AiServiceException implements Exception {
  final String code;              // "auth_error", "rate_limit", "timeout", "model_not_found", etc.
  final String message;
  final String? details;
  final dynamic originalError;
  final StackTrace? stackTrace;
  final int? httpStatusCode;

  AiServiceException({
    required this.code,
    required this.message,
    this.details,
    this.originalError,
    this.stackTrace,
    this.httpStatusCode,
  });

  @override
  String toString() => 'AiServiceException($code): $message${details != null ? ' — $details' : ''}';
}

// ──────────────────────────────────────────────────────────────────────────
// STREAMING MODELS
// ──────────────────────────────────────────────────────────────────────────

/// Single streaming chunk
class AiStreamChunk {
  final String id;
  final String requestId;
  final String deltaContent;       // Incremental content (delta)
  final int sequenceNumber;
  final AiResponseMetadata? metadata; // May be null until completion
  final bool isLast;
  final DateTime timestamp;

  AiStreamChunk({
    required this.id,
    required this.requestId,
    required this.deltaContent,
    required this.sequenceNumber,
    this.metadata,
    this.isLast = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory AiStreamChunk.fromJson(Map<String, dynamic> json) => AiStreamChunk(
    id: json['id'] as String? ?? ''? ?? '',
    requestId: json['requestId'] as String? ?? ''? ?? '',
    deltaContent: json['deltaContent'] as String? ?? ''? ?? '',
    sequenceNumber: json['sequenceNumber'] as int? ?? 0? ?? 0,
    metadata: json['metadata'] != null
      ? AiResponseMetadata.fromJson(json['metadata'] as Map<String, dynamic>)
      : null,
    isLast: json['isLast'] as bool? ?? false? ?? false,
    timestamp: json['timestamp'] != null
      ? DateTime.parse(json['timestamp'] as String? ?? '')
      : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'requestId': requestId,
    'deltaContent': deltaContent,
    'sequenceNumber': sequenceNumber,
    'metadata': metadata?.toJson(),
    'isLast': isLast,
    'timestamp': timestamp.toIso8601String(),
  };
}
