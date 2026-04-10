// lib/data/models/file_context_model.dart
// KanMon GO — File Context for AI
// Represents files being edited/discussed in chat
// =============================================================================

import 'dart:typed_data';

/// Represents a file in context (user uploaded or AI generated)
class FileContext {
  final String id;                // UUID
  final String filename;
  final String filepath;          // Full path on device
  final String mimeType;          // "text/plain", "application/json", etc.
  final int fileSizeBytes;
  final String contentPreview;    // First 500 chars for display
  final String? language;         // For code files: "dart", "python", etc.
  final DateTime uploadedAt;
  final String uploadedBy;        // "user" or AI model name
  final bool isEditable;
  final Map<String, dynamic> metadata; // Custom metadata
  final List<FileEdit> edits;     // Version history

  FileContext({
    required this.id,
    required this.filename,
    required this.filepath,
    required this.mimeType,
    required this.fileSizeBytes,
    required this.contentPreview,
    this.language,
    DateTime? uploadedAt,
    this.uploadedBy = 'user',
    this.isEditable = true,
    this.metadata = const {},
    this.edits = const [],
  }) : uploadedAt = uploadedAt ?? DateTime.now();

  factory FileContext.fromJson(Map<String, dynamic> json) => FileContext(
    id: json['id'] as String? ?? ''? ?? '',
    filename: json['filename'] as String? ?? ''? ?? '',
    filepath: json['filepath'] as String? ?? ''? ?? '',
    mimeType: json['mimeType'] as String? ?? ''? ?? 'text/plain',
    fileSizeBytes: json['fileSizeBytes'] as int? ?? 0? ?? 0,
    contentPreview: json['contentPreview'] as String? ?? ''? ?? '',
    language: json['language'] as String? ?? ''?,
    uploadedAt: json['uploadedAt'] != null
      ? DateTime.parse(json['uploadedAt'] as String? ?? '')
      : null,
    uploadedBy: json['uploadedBy'] as String? ?? ''? ?? 'user',
    isEditable: json['isEditable'] as bool? ?? false? ?? true,
    metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    edits: (json['edits'] as List?)
      ?.map((e) => FileEdit.fromJson(e as Map<String, dynamic>))
      .toList() ?? [],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'filename': filename,
    'filepath': filepath,
    'mimeType': mimeType,
    'fileSizeBytes': fileSizeBytes,
    'contentPreview': contentPreview,
    'language': language,
    'uploadedAt': uploadedAt.toIso8601String(),
    'uploadedBy': uploadedBy,
    'isEditable': isEditable,
    'metadata': metadata,
    'edits': edits.map((e) => e.toJson()).toList(),
  };
}

/// Single edit to a file
class FileEdit {
  final String id;                // UUID
  final String fileContextId;     // Parent file ID
  final int lineStart;
  final int lineEnd;
  final String oldContent;
  final String newContent;
  final String editedBy;          // "user" or model name
  final DateTime editedAt;
  final String? reason;           // Why this edit was made

  FileEdit({
    required this.id,
    required this.fileContextId,
    required this.lineStart,
    required this.lineEnd,
    required this.oldContent,
    required this.newContent,
    this.editedBy = 'user',
    DateTime? editedAt,
    this.reason,
  }) : editedAt = editedAt ?? DateTime.now();

  factory FileEdit.fromJson(Map<String, dynamic> json) => FileEdit(
    id: json['id'] as String? ?? ''? ?? '',
    fileContextId: json['fileContextId'] as String? ?? ''? ?? '',
    lineStart: json['lineStart'] as int? ?? 0? ?? 0,
    lineEnd: json['lineEnd'] as int? ?? 0? ?? 0,
    oldContent: json['oldContent'] as String? ?? ''? ?? '',
    newContent: json['newContent'] as String? ?? ''? ?? '',
    editedBy: json['editedBy'] as String? ?? ''? ?? 'user',
    editedAt: json['editedAt'] != null
      ? DateTime.parse(json['editedAt'] as String? ?? '')
      : null,
    reason: json['reason'] as String? ?? ''?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileContextId': fileContextId,
    'lineStart': lineStart,
    'lineEnd': lineEnd,
    'oldContent': oldContent,
    'newContent': newContent,
    'editedBy': editedBy,
    'editedAt': editedAt.toIso8601String(),
    'reason': reason,
  };
}

/// Diff between two versions
class FileDiff {
  final String fileId;
  final String filename;
  final String beforeContent;
  final String afterContent;
  final List<DiffLine> lines;
  final int linesAdded;
  final int linesRemoved;

  FileDiff({
    required this.fileId,
    required this.filename,
    required this.beforeContent,
    required this.afterContent,
    required this.lines,
    required this.linesAdded,
    required this.linesRemoved,
  });

  factory FileDiff.fromJson(Map<String, dynamic> json) => FileDiff(
    fileId: json['fileId'] as String? ?? ''? ?? '',
    filename: json['filename'] as String? ?? ''? ?? '',
    beforeContent: json['beforeContent'] as String? ?? ''? ?? '',
    afterContent: json['afterContent'] as String? ?? ''? ?? '',
    lines: (json['lines'] as List?)
      ?.map((l) => DiffLine.fromJson(l as Map<String, dynamic>))
      .toList() ?? [],
    linesAdded: json['linesAdded'] as int? ?? 0? ?? 0,
    linesRemoved: json['linesRemoved'] as int? ?? 0? ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'fileId': fileId,
    'filename': filename,
    'beforeContent': beforeContent,
    'afterContent': afterContent,
    'lines': lines.map((l) => l.toJson()).toList(),
    'linesAdded': linesAdded,
    'linesRemoved': linesRemoved,
  };
}

/// Single line in a diff
class DiffLine {
  final int lineNumber;
  final String type;              // "add", "remove", "context"
  final String content;

  DiffLine({
    required this.lineNumber,
    required this.type,
    required this.content,
  });

  factory DiffLine.fromJson(Map<String, dynamic> json) => DiffLine(
    lineNumber: json['lineNumber'] as int? ?? 0? ?? 0,
    type: json['type'] as String? ?? ''? ?? 'context',
    content: json['content'] as String? ?? ''? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'lineNumber': lineNumber,
    'type': type,
    'content': content,
  };
}
