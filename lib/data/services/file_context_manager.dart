// lib/data/services/file_context_manager.dart
// KanMon GO — File Context Manager
// Manages user-uploaded files + AI-generated files in chat
// =============================================================================

import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/ai_request_model.dart';
import '../models/file_context_model.dart';

/// Manages files in conversation context
class FileContextManager {
  final Map<String, FileContext> _fileRegistry = {};
  final Uuid _uuid = const Uuid();
  late Directory _chatCacheDir;

  /// Initialize cache directory
  Future<void> initialize() async {
    final appDir = await getApplicationCacheDirectory();
    _chatCacheDir = Directory('${appDir.path}/chat_files');
    if (!await _chatCacheDir.exists()) {
      await _chatCacheDir.create(recursive: true);
    }
  }

  /// Register uploaded file
  Future<FileContext> registerUploadedFile(
    String filepath, {
    String? customName,
  }) async {
    final file = File(filepath);
    if (!await file.exists()) {
      throw Exception('File not found: $filepath');
    }

    final bytes = await file.readAsBytes();
    final filename = customName ?? file.path.split('/').last;
    final mimeType = _detectMimeType(filename);
    final preview = await _generatePreview(filepath, mimeType);

    final context = FileContext(
      id: _uuid.v4(),
      filename: filename,
      filepath: filepath,
      mimeType: mimeType,
      fileSizeBytes: bytes.length,
      contentPreview: preview,
      language: _detectLanguage(filename),
      uploadedBy: 'user',
      isEditable: true,
    );

    _fileRegistry[context.id] = context;
    return context;
  }

  /// Register AI-generated file
  Future<FileContext> registerGeneratedFile(
    String filename,
    String content, {
    String language = 'text',
    Map<String, dynamic>? metadata,
  }) async {
    final cacheFile = File('${_chatCacheDir.path}/${_uuid.v4()}_$filename');
    await cacheFile.writeAsString(content);

    final context = FileContext(
      id: _uuid.v4(),
      filename: filename,
      filepath: cacheFile.path,
      mimeType: _detectMimeType(filename),
      fileSizeBytes: content.length,
      contentPreview: content.length > 500 
        ? content.substring(0, 500) + '...'
        : content,
      language: language,
      uploadedBy: 'ai',
      isEditable: true,
      metadata: metadata ?? {},
    );

    _fileRegistry[context.id] = context;
    return context;
  }

  /// Get file context by ID
  FileContext? getFileContext(String fileId) {
    return _fileRegistry[fileId];
  }

  /// Get all files in registry
  List<FileContext> getAllFiles() {
    return _fileRegistry.values.toList();
  }

  /// Read full file content
  Future<String> readFileContent(String fileId) async {
    final context = getFileContext(fileId);
    if (context == null) {
      throw Exception('File not found in registry: $fileId');
    }

    final file = File(context.filepath);
    if (!await file.exists()) {
      throw Exception('File not found on disk: ${context.filepath}');
    }

    return await file.readAsString();
  }

  /// Edit file (in-place or create new version)
  Future<FileContext> editFile(
    String fileId, {
    required String newContent,
    required String reason,
  }) async {
    final context = getFileContext(fileId);
    if (context == null) {
      throw Exception('File not found: $fileId');
    }

    final oldContent = await readFileContent(fileId);

    // Create edit record
    final edit = FileEdit(
      id: _uuid.v4(),
      fileContextId: fileId,
      lineStart: 0,
      lineEnd: oldContent.split('\n').length,
      oldContent: oldContent,
      newContent: newContent,
      editedBy: 'user',
      reason: reason,
    );

    // Write new content
    final file = File(context.filepath);
    await file.writeAsString(newContent);

    // Update registry
    final updated = context.copyWith(
      edits: [...context.edits, edit],
      contentPreview: newContent.length > 500
        ? newContent.substring(0, 500) + '...'
        : newContent,
    );
    _fileRegistry[fileId] = updated;

    return updated;
  }

  /// Save edited file to user location
  Future<File> saveFileToLocation(
    String fileId,
    String destinationPath,
  ) async {
    final context = getFileContext(fileId);
    if (context == null) {
      throw Exception('File not found: $fileId');
    }

    final sourceFile = File(context.filepath);
    final destFile = File(destinationPath);

    if (!await destFile.parent.exists()) {
      await destFile.parent.create(recursive: true);
    }

    await sourceFile.copy(destinationPath);
    return destFile;
  }

  /// Generate diff between versions
  FileDiff generateDiff(String fileId) {
    final context = getFileContext(fileId);
    if (context == null || context.edits.isEmpty) {
      throw Exception('No edits for file: $fileId');
    }

    final firstEdit = context.edits.first;
    final lines = <DiffLine>[];

    final oldLines = firstEdit.oldContent.split('\n');
    final newLines = firstEdit.newContent.split('\n');

    int maxLines = oldLines.length > newLines.length ? oldLines.length : newLines.length;
    for (int i = 0; i < maxLines; i++) {
      if (i < oldLines.length && (i >= newLines.length || oldLines[i] != newLines[i])) {
        lines.add(DiffLine(
          lineNumber: i,
          type: 'remove',
          content: oldLines[i],
        ));
      }
      if (i < newLines.length && (i >= oldLines.length || oldLines[i] != newLines[i])) {
        lines.add(DiffLine(
          lineNumber: i,
          type: 'add',
          content: newLines[i],
        ));
      }
      if (i < oldLines.length && i < newLines.length && oldLines[i] == newLines[i]) {
        lines.add(DiffLine(
          lineNumber: i,
          type: 'context',
          content: oldLines[i],
        ));
      }
    }

    return FileDiff(
      fileId: fileId,
      filename: context.filename,
      beforeContent: firstEdit.oldContent,
      afterContent: firstEdit.newContent,
      lines: lines,
      linesAdded: lines.where((l) => l.type == 'add').length,
      linesRemoved: lines.where((l) => l.type == 'remove').length,
    );
  }

  /// Clear cache
  Future<void> clearCache() async {
    if (await _chatCacheDir.exists()) {
      await _chatCacheDir.delete(recursive: true);
      await _chatCacheDir.create(recursive: true);
    }
    _fileRegistry.clear();
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  String _detectMimeType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'txt' => 'text/plain',
      'md' => 'text/markdown',
      'json' => 'application/json',
      'dart' => 'text/x-dart',
      'py' => 'text/x-python',
      'js' => 'text/javascript',
      'ts' => 'text/typescript',
      'html' => 'text/html',
      'css' => 'text/css',
      'xml' => 'text/xml',
      'csv' => 'text/csv',
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
  }

  String? _detectLanguage(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'dart' => 'dart',
      'py' => 'python',
      'js' => 'javascript',
      'ts' => 'typescript',
      'java' => 'java',
      'cs' => 'csharp',
      'rb' => 'ruby',
      'go' => 'go',
      'rs' => 'rust',
      'cpp' || 'cc' || 'cxx' => 'cpp',
      'c' => 'c',
      'swift' => 'swift',
      'kt' => 'kotlin',
      'php' => 'php',
      'html' => 'html',
      'css' => 'css',
      'json' => 'json',
      'xml' => 'xml',
      'yaml' || 'yml' => 'yaml',
      'sql' => 'sql',
      'sh' || 'bash' => 'bash',
      _ => null,
    };
  }

  Future<String> _generatePreview(String filepath, String mimeType) async {
    try {
      final file = File(filepath);
      if (!await file.exists()) return '(File not found)';

      if (mimeType.startsWith('text/')) {
        final content = await file.readAsString();
        return content.length > 500 
          ? content.substring(0, 500) + '...'
          : content;
      } else if (mimeType.startsWith('image/')) {
        return '(Image file)';
      } else {
        return '(Binary file)';
      }
    } catch (e) {
      return '(Error reading file: $e)';
    }
  }
}

extension on FileContext {
  FileContext copyWith({
    String? id,
    String? filename,
    String? filepath,
    String? mimeType,
    int? fileSizeBytes,
    String? contentPreview,
    String? language,
    DateTime? uploadedAt,
    String? uploadedBy,
    bool? isEditable,
    Map<String, dynamic>? metadata,
    List<FileEdit>? edits,
  }) => FileContext(
    id: id ?? this.id,
    filename: filename ?? this.filename,
    filepath: filepath ?? this.filepath,
    mimeType: mimeType ?? this.mimeType,
    fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
    contentPreview: contentPreview ?? this.contentPreview,
    language: language ?? this.language,
    uploadedAt: uploadedAt ?? this.uploadedAt,
    uploadedBy: uploadedBy ?? this.uploadedBy,
    isEditable: isEditable ?? this.isEditable,
    metadata: metadata ?? this.metadata,
    edits: edits ?? this.edits,
  );
}
