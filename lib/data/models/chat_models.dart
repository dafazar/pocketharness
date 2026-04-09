// lib/data/models/chat_models.dart
// KanMonAI — Chat Models
// Sesi 1: ChatAttachment, AiSourceChoice, ChatMessage, ChatSession
// =============================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:kanmongo/data/services/ai/ai_service.dart';
import 'package:kanmongo/data/services/content/bulk_api_service.dart';
import 'package:kanmongo/data/services/content/file_processor_service.dart';
import 'package:kanmongo/data/services/ai/web_research_service.dart';

// ─── 1. enum AttachmentType ──────────────────────────────────────────────────

enum AttachmentType {
  image,
  video,
  audio,
  pdf,
  word,
  excel,
  powerpoint,
  code,
  text,
  archive,
  other,
}

// ─── 2. class ChatAttachment ─────────────────────────────────────────────────

class ChatAttachment {
  final String id;
  final String filename;
  final String path;
  final AttachmentType type;
  final int sizeBytes;
  final String? mimeType;
  final Uint8List? thumbnailBytes;
  final String? extractedText;
  final bool isProcessed;

  /// Video duration in "MM:SS" format, extracted via ffprobe.
  final String? videoDuration;

  const ChatAttachment({
    required this.id,
    required this.filename,
    required this.path,
    required this.type,
    required this.sizeBytes,
    this.mimeType,
    this.thumbnailBytes,
    this.extractedText,
    this.isProcessed = false,
    this.videoDuration,
  });

  // ── Getters ──────────────────────────────────────────────────────────────

  String get sizeLabel {
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(2)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get icon {
    switch (type) {
      case AttachmentType.image:
        return '🖼️';
      case AttachmentType.video:
        return '🎬';
      case AttachmentType.audio:
        return '🎵';
      case AttachmentType.pdf:
        return '📄';
      case AttachmentType.word:
        return '📝';
      case AttachmentType.excel:
        return '📊';
      case AttachmentType.powerpoint:
        return '📽️';
      case AttachmentType.code:
        return '💻';
      case AttachmentType.text:
        return '📃';
      case AttachmentType.archive:
        return '📦';
      case AttachmentType.other:
        return '📎';
    }
  }

  bool get isMedia =>
      type == AttachmentType.image ||
      type == AttachmentType.video ||
      type == AttachmentType.audio;

  bool get hasText => extractedText != null && extractedText!.isNotEmpty;

  // ── Factory dari ProcessedFile ───────────────────────────────────────────

  factory ChatAttachment.fromProcessedFile(ProcessedFile pf) {
    AttachmentType attachType;
    switch (pf.category) {
      case FileCategory.image:
        attachType = AttachmentType.image;
        break;
      case FileCategory.video:
        attachType = AttachmentType.video;
        break;
      case FileCategory.audio:
        attachType = AttachmentType.audio;
        break;
      case FileCategory.pdf:
        attachType = AttachmentType.pdf;
        break;
      case FileCategory.word:
        attachType = AttachmentType.word;
        break;
      case FileCategory.excel:
        attachType = AttachmentType.excel;
        break;
      case FileCategory.powerpoint:
        attachType = AttachmentType.powerpoint;
        break;
      case FileCategory.code:
        attachType = AttachmentType.code;
        break;
      case FileCategory.text:
        attachType = AttachmentType.text;
        break;
      case FileCategory.archive:
        attachType = AttachmentType.archive;
        break;
      case FileCategory.data:
        attachType = AttachmentType.other;
        break;
      case FileCategory.other:
        attachType = AttachmentType.other;
        break;
    }

    // Thumbnail: prefer downscaled thumbnail, fall back to rawBytes for images
    Uint8List? thumb;
    if (pf.category == FileCategory.image) {
      thumb = pf.thumbnailBytes ?? pf.rawBytes;
    } else if (pf.category == FileCategory.video) {
      thumb = pf.thumbnailBytes;
    }

    return ChatAttachment(
      id: const Uuid().v4(),
      filename: pf.filename,
      path: pf.originalPath ?? '',
      type: attachType,
      sizeBytes: pf.sizeBytes,
      mimeType: pf.mimeType,
      thumbnailBytes: thumb,
      extractedText: pf.textContent,
      isProcessed: true,
      videoDuration: pf.metadata['duration'] as String?,
    );
  }

  // ── Serialisasi ──────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() {
    String? thumbBase64;
    if (thumbnailBytes != null) {
      thumbBase64 = base64Encode(thumbnailBytes!);
    }

    String? textSnippet;
    if (extractedText != null) {
      textSnippet = extractedText!.length > 10000
          ? extractedText!.substring(0, 10000)
          : extractedText;
    }

    return {
      'id': id,
      'filename': filename,
      'path': path,
      'type': type.name,
      'sizeBytes': sizeBytes,
      'mimeType': mimeType,
      'thumbnailBytes': thumbBase64,
      'extractedText': textSnippet,
      'isProcessed': isProcessed,
      'videoDuration': videoDuration,
    };
  }

  factory ChatAttachment.fromMap(Map<String, dynamic> map) {
    Uint8List? thumb;
    final thumbStr = map['thumbnailBytes'] as String?;
    if (thumbStr != null && thumbStr.isNotEmpty) {
      try {
        thumb = base64Decode(thumbStr);
      } catch (e) {
        debugPrint('[ChatAttachment] base64 decode error: $e');
      }
    }

    AttachmentType parsedType;
    try {
      parsedType = AttachmentType.values.firstWhere(
        (e) => e.name == (map['type'] as String? ?? ''),
        orElse: () => AttachmentType.other,
      );
    } catch (_) {
      parsedType = AttachmentType.other;
    }

    return ChatAttachment(
      id: map['id'] as String? ?? const Uuid().v4(),
      filename: map['filename'] as String? ?? '',
      path: map['path'] as String? ?? '',
      type: parsedType,
      sizeBytes: map['sizeBytes'] as int? ?? 0,
      mimeType: map['mimeType'] as String?,
      thumbnailBytes: thumb,
      extractedText: map['extractedText'] as String?,
      isProcessed: map['isProcessed'] as bool? ?? false,
      videoDuration: map['videoDuration'] as String?,
    );
  }

  ChatAttachment copyWith({
    String? id,
    String? filename,
    String? path,
    AttachmentType? type,
    int? sizeBytes,
    Object? mimeType = _sentinel,
    Object? thumbnailBytes = _sentinel,
    Object? extractedText = _sentinel,
    bool? isProcessed,
    Object? videoDuration = _sentinel,
  }) {
    return ChatAttachment(
      id: id ?? this.id,
      filename: filename ?? this.filename,
      path: path ?? this.path,
      type: type ?? this.type,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      mimeType: mimeType == _sentinel ? this.mimeType : mimeType as String?,
      thumbnailBytes: thumbnailBytes == _sentinel
          ? this.thumbnailBytes
          : thumbnailBytes as Uint8List?,
      extractedText: extractedText == _sentinel
          ? this.extractedText
          : extractedText as String?,
      isProcessed: isProcessed ?? this.isProcessed,
      videoDuration: videoDuration == _sentinel
          ? this.videoDuration
          : videoDuration as String?,
    );
  }
}

// ─── 3. class AiSourceChoice ─────────────────────────────────────────────────

class AiSourceChoice {
  final AiMode mode;
  final String? bulkKeyId;
  final BulkApiProvider? bulkProvider;
  final String? modelOverride;
  final String? label;

  const AiSourceChoice({
    required this.mode,
    this.bulkKeyId,
    this.bulkProvider,
    this.modelOverride,
    this.label,
  });

  @override
  String toString() =>
      'AiSourceChoice(mode: $mode, bulkKeyId: $bulkKeyId, provider: $bulkProvider, model: $modelOverride, label: $label)';
}

// ─── 4. class ChatMessage ────────────────────────────────────────────────────

class ChatMessage {
  final String id;
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  final List<ChatAttachment> attachments;
  final DateTime createdAt;
  final bool isStreaming;
  final String? error;
  final AiMode? aiMode;
  final String? modelName;
  final List<ResearchSource>? webSources;
  final bool isError;
  final int? tokenCount;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.attachments = const [],
    required this.createdAt,
    this.isStreaming = false,
    this.error,
    this.aiMode,
    this.modelName,
    this.webSources,
    this.isError = false,
    this.tokenCount,
  });

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get hasAttachments => attachments.isNotEmpty;
  bool get hasWebSources => webSources != null && webSources!.isNotEmpty;

  // Factory helpers — mirror llama_context.ChatMessage API agar chat_screen
  // tidak perlu import llama_context hanya untuk membuat pesan baru.
  factory ChatMessage.user(String content) => ChatMessage(
        id: const Uuid().v4(),
        role: 'user',
        content: content,
        createdAt: DateTime.now(),
      );

  factory ChatMessage.assistant(String content, {bool isStreaming = false}) =>
      ChatMessage(
        id: const Uuid().v4(),
        role: 'assistant',
        content: content,
        createdAt: DateTime.now(),
        isStreaming: isStreaming,
      );

  factory ChatMessage.system(String content) => ChatMessage(
        id: const Uuid().v4(),
        role: 'system',
        content: content,
        createdAt: DateTime.now(),
      );

  ChatMessage copyWith({
    String? id,
    String? role,
    String? content,
    List<ChatAttachment>? attachments,
    DateTime? createdAt,
    bool? isStreaming,
    bool? isError,
    Object? error = _sentinel,
    Object? aiMode = _sentinel,
    Object? modelName = _sentinel,
    Object? webSources = _sentinel,
    int? tokenCount,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      attachments: attachments ?? this.attachments,
      createdAt: createdAt ?? this.createdAt,
      isStreaming: isStreaming ?? this.isStreaming,
      isError: isError ?? this.isError,
      error: error == _sentinel ? this.error : error as String?,
      aiMode: aiMode == _sentinel ? this.aiMode : aiMode as AiMode?,
      modelName: modelName == _sentinel ? this.modelName : modelName as String?,
      webSources: webSources == _sentinel
          ? this.webSources
          : webSources as List<ResearchSource>?,
      tokenCount: tokenCount ?? this.tokenCount,
    );
  }

  Map<String, dynamic> toMap() {
    // attachments → json list
    final attachList = attachments.map((a) => a.toMap()).toList();

    // webSources → hanya simpan field ringkas (skip fetchedContent)
    List<Map<String, dynamic>>? sourceList;
    if (webSources != null) {
      sourceList = webSources!.map((s) => s.toMap()).toList();
    }

    return {
      'id': id,
      'role': role,
      'content': content,
      'attachments_json': jsonEncode(attachList),
      'created_at': createdAt.millisecondsSinceEpoch,
      // isStreaming tidak dipersist
      'error': error,
      'ai_mode': aiMode?.name,
      'model_name': modelName,
      'web_sources_json':
          sourceList != null ? jsonEncode(sourceList) : null,
      'is_error': isError ? 1 : 0,
      'token_count': tokenCount,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    // Parse attachments
    List<ChatAttachment> attachments = const [];
    final attachJson = map['attachments_json'] as String?;
    if (attachJson != null && attachJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(attachJson) as List<dynamic>;
        attachments = decoded
            .map((e) =>
                ChatAttachment.fromMap(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('[ChatMessage] parse attachments error: $e');
      }
    }

    // Parse web sources
    List<ResearchSource>? webSources;
    final sourcesJson = map['web_sources_json'] as String?;
    if (sourcesJson != null && sourcesJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(sourcesJson) as List<dynamic>;
        webSources = decoded
            .map((e) =>
                ResearchSource.fromMap(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('[ChatMessage] parse webSources error: $e');
      }
    }

    // Parse aiMode
    AiMode? aiMode;
    final modeStr = map['ai_mode'] as String?;
    if (modeStr != null) {
      try {
        aiMode = AiMode.values.firstWhere(
          (e) => e.name == modeStr,
          orElse: () => AiMode.none,
        );
      } catch (_) {}
    }

    return ChatMessage(
      id: map['id'] as String? ?? const Uuid().v4(),
      role: map['role'] as String? ?? 'user',
      content: map['content'] as String? ?? '',
      attachments: attachments,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at'] as int? ?? 0,
      ),
      isStreaming: false, // tidak di-persist
      isError: (map['is_error'] as int? ?? 0) == 1,
      error: map['error'] as String?,
      aiMode: aiMode,
      modelName: map['model_name'] as String?,
      webSources: webSources,
      tokenCount: map['token_count'] as int?,
    );
  }
}

// ─── 5. class ChatSession ────────────────────────────────────────────────────

class ChatSession {
  final String id;
  final String title;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  final DateTime updatedAt;
  final AiMode? lastAiMode;
  final String? lastModelName;

  const ChatSession({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
    this.lastAiMode,
    this.lastModelName,
  });

  String get preview {
    for (int i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.content.isNotEmpty) {
        final raw = m.content.trim().replaceAll('\n', ' ');
        return raw.length > 80 ? '${raw.substring(0, 80)}…' : raw;
      }
    }
    return '';
  }

  int get messageCount => messages.length;
  bool get isEmpty => messages.isEmpty;

  factory ChatSession.empty() {
    final now = DateTime.now();
    return ChatSession(
      id: const Uuid().v4(),
      title: 'Chat Baru',
      messages: const [],
      createdAt: now,
      updatedAt: now,
    );
  }

  ChatSession copyWith({
    String? id,
    String? title,
    List<ChatMessage>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? lastAiMode = _sentinel,
    Object? lastModelName = _sentinel,
  }) {
    return ChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastAiMode:
          lastAiMode == _sentinel ? this.lastAiMode : lastAiMode as AiMode?,
      lastModelName: lastModelName == _sentinel
          ? this.lastModelName
          : lastModelName as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'last_ai_mode': lastAiMode?.name,
        'last_model_name': lastModelName,
      };

  factory ChatSession.fromMap(
      Map<String, dynamic> map, List<ChatMessage> messages) {
    AiMode? lastAiMode;
    final modeStr = map['last_ai_mode'] as String?;
    if (modeStr != null) {
      try {
        lastAiMode = AiMode.values.firstWhere(
          (e) => e.name == modeStr,
          orElse: () => AiMode.none,
        );
      } catch (_) {}
    }

    return ChatSession(
      id: map['id'] as String? ?? const Uuid().v4(),
      title: map['title'] as String? ?? 'Chat Baru',
      messages: messages,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          map['created_at'] as int? ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          map['updated_at'] as int? ?? 0),
      lastAiMode: lastAiMode,
      lastModelName: map['last_model_name'] as String?,
    );
  }
}

// ─── Internal sentinel untuk copyWith nullable ───────────────────────────────
const _sentinel = Object();
