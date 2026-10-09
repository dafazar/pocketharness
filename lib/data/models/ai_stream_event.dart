// lib/data/models/ai_stream_event.dart
// Pocket Harness — Streaming Event Types
// Events emitted during streaming to update UI in real-time
// =============================================================================

import 'ai_request_model.dart';

/// Base class for all streaming events
abstract class AiStreamEvent {
  final String requestId;
  final DateTime timestamp;

  AiStreamEvent({
    required this.requestId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Request started, waiting for first token
class StreamStartedEvent extends AiStreamEvent {
  final String modelId;
  final String sourceType;

  StreamStartedEvent({
    required String requestId,
    required this.modelId,
    required this.sourceType,
    DateTime? timestamp,
  }) : super(requestId: requestId, timestamp: timestamp);
}

/// Chunk of tokens received
class StreamChunkEvent extends AiStreamEvent {
  final String deltaContent;
  final int tokenCount;
  final double? elapsedSeconds;
  final int totalCharacters;
  final List<AiCodeBlock>? detectedCodeBlocks; // Code detected in this chunk

  StreamChunkEvent({
    required String requestId,
    required this.deltaContent,
    required this.tokenCount,
    this.elapsedSeconds,
    this.totalCharacters = 0,
    this.detectedCodeBlocks,
    DateTime? timestamp,
  }) : super(requestId: requestId, timestamp: timestamp);
}

/// Code block or file detected in stream
class StreamArtifactDetectedEvent extends AiStreamEvent {
  final AiCodeBlock artifact;
  final int chunkIndex;

  StreamArtifactDetectedEvent({
    required String requestId,
    required this.artifact,
    required this.chunkIndex,
    DateTime? timestamp,
  }) : super(requestId: requestId, timestamp: timestamp);
}

/// Streaming completed successfully
class StreamCompletedEvent extends AiStreamEvent {
  final String fullContent;
  final int totalTokens;
  final int totalChunks;
  final double totalTimeSeconds;
  final String finishReason;
  final List<AiCodeBlock> finalArtifacts;

  StreamCompletedEvent({
    required String requestId,
    required this.fullContent,
    required this.totalTokens,
    required this.totalChunks,
    required this.totalTimeSeconds,
    required this.finishReason,
    this.finalArtifacts = const [],
    DateTime? timestamp,
  }) : super(requestId: requestId, timestamp: timestamp);
}

/// Streaming error occurred
class StreamErrorEvent extends AiStreamEvent {
  final String errorCode;
  final String errorMessage;
  final dynamic originalError;
  final int? httpStatusCode;
  final int tokensProcessed;

  StreamErrorEvent({
    required String requestId,
    required this.errorCode,
    required this.errorMessage,
    this.originalError,
    this.httpStatusCode,
    this.tokensProcessed = 0,
    DateTime? timestamp,
  }) : super(requestId: requestId, timestamp: timestamp);
}

/// Stream cancelled by user
class StreamCancelledEvent extends AiStreamEvent {
  final int tokensReceived;
  final String partialContent;

  StreamCancelledEvent({
    required String requestId,
    required this.tokensReceived,
    required this.partialContent,
    DateTime? timestamp,
  }) : super(requestId: requestId, timestamp: timestamp);
}

/// Metadata update during streaming
class StreamMetadataUpdateEvent extends AiStreamEvent {
  final int estimatedTotalTokens;
  final double estimatedTokensPerSecond;
  final String currentStatus; // "thinking", "generating", "finishing"

  StreamMetadataUpdateEvent({
    required String requestId,
    required this.estimatedTotalTokens,
    required this.estimatedTokensPerSecond,
    required this.currentStatus,
    DateTime? timestamp,
  }) : super(requestId: requestId, timestamp: timestamp);
}
