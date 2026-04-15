// lib/data/services/claude_code_file_context.dart
// KanMonAI — File Context Builder for Claude Code
//
// Prepares attached files as context for Claude Code:
//   • Text files: copied to workDir + inline content in preamble
//   • Binary/media files: descriptive summary only
//   • File watcher: emits events when workDir files change
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

// ── Enums & Models ────────────────────────────────────────────────────────────

enum ContextFileType {
  dartCode,
  kotlinCode,
  javaCode,
  pythonCode,
  jsCode,
  tsCode,
  jsonData,
  yamlData,
  xmlData,
  markdown,
  plainText,
  shellScript,
  image,
  video,
  audio,
  pdf,
  archive,
  ggufModel,
  binary,
}

class ContextFile {
  final String originalPath;
  final String workDirPath;     // path in Claude Code workDir after copy
  final String filename;
  final ContextFileType type;
  final String? inlineContent;  // text content (null for binary)
  final int sizeBytes;
  final bool isCopiedToWorkDir; // whether we actually copied it

  const ContextFile({
    required this.originalPath,
    required this.workDirPath,
    required this.filename,
    required this.type,
    this.inlineContent,
    required this.sizeBytes,
    required this.isCopiedToWorkDir,
  });
}

class FileWatchEvent {
  final String path;
  final FileSystemEvent event;
  final DateTime timestamp;

  const FileWatchEvent({
    required this.path,
    required this.event,
    required this.timestamp,
  });
}

// ── ClaudeCodeFileContext ─────────────────────────────────────────────────────

class ClaudeCodeFileContext {
  static final ClaudeCodeFileContext instance = ClaudeCodeFileContext._();
  ClaudeCodeFileContext._();

  final List<StreamSubscription<FileSystemEvent>> _watchSubscriptions = [];
  StreamController<FileWatchEvent>? _watchController;

  // ── processFiles ─────────────────────────────────────────────────────────────

  Future<List<ContextFile>> processFiles(
    List<String> filePaths, {
    required String workDir,
  }) async {
    final results = <ContextFile>[];

    for (final path in filePaths) {
      try {
        final file = File(path);
        if (!await file.exists()) {
          debugPrint('[ClaudeCodeFileContext] File not found, skipping: $path');
          continue;
        }

        final stat = await file.stat();
        final sizeBytes = stat.size;
        final filename = path.split('/').last;
        final ext = _extension(filename);
        final type = _typeFromExtension(ext);

        if (_isTextType(type)) {
          // Read content, truncate if needed
          String content;
          const maxBytes = 100 * 1024; // 100KB
          if (sizeBytes > maxBytes) {
            final bytes = await file.openRead(0, maxBytes).toList();
            final flat = bytes.expand((b) => b).toList();
            content = String.fromCharCodes(flat);
            content += '\n[...truncated, $sizeBytes bytes total]';
            debugPrint('[ClaudeCodeFileContext] Truncated $filename ($sizeBytes bytes)');
          } else {
            content = await file.readAsString();
          }

          // Copy to workDir
          final destPath = '$workDir/$filename';
          try {
            await file.copy(destPath);
            debugPrint('[ClaudeCodeFileContext] Copied $filename → $destPath');
          } catch (e) {
            debugPrint('[ClaudeCodeFileContext] Failed to copy $filename: $e');
          }

          results.add(ContextFile(
            originalPath: path,
            workDirPath: destPath,
            filename: filename,
            type: type,
            inlineContent: content,
            sizeBytes: sizeBytes,
            isCopiedToWorkDir: true,
          ));
        } else {
          // Binary / media: descriptive summary only
          final desc = _binaryDescription(type, filename, sizeBytes);
          results.add(ContextFile(
            originalPath: path,
            workDirPath: '$workDir/$filename',
            filename: filename,
            type: type,
            inlineContent: desc,
            sizeBytes: sizeBytes,
            isCopiedToWorkDir: false,
          ));
          debugPrint('[ClaudeCodeFileContext] Binary file described: $filename ($type)');
        }
      } catch (e) {
        debugPrint('[ClaudeCodeFileContext] Error processing $path: $e');
      }
    }

    debugPrint('[ClaudeCodeFileContext] Processed ${results.length}/${filePaths.length} files');
    return results;
  }

  // ── buildPreamble ─────────────────────────────────────────────────────────────

  String buildPreamble(List<ContextFile> files) {
    if (files.isEmpty) return '';

    final copiedFiles   = files.where((f) => f.isCopiedToWorkDir).toList();
    final binaryFiles   = files.where((f) => !f.isCopiedToWorkDir).toList();

    final buf = StringBuffer();
    buf.writeln('<files>');
    buf.writeln('I\'m working with the following files (they have been copied to your working directory):');
    buf.writeln();

    for (final f in copiedFiles) {
      buf.writeln('### ${f.filename}');
      final lang = _langTag(f.type);
      if (lang.isNotEmpty) {
        buf.writeln('```$lang');
      } else {
        buf.writeln('```');
      }
      buf.writeln(f.inlineContent ?? '');
      buf.writeln('```');
      buf.writeln();
    }

    if (binaryFiles.isNotEmpty) {
      for (final f in binaryFiles) {
        buf.writeln('- ${f.filename} ${f.inlineContent ?? ''}');
      }
      buf.writeln();
    }

    buf.writeln('</files>');
    buf.writeln();
    buf.write(
      'Please review these files before starting. When I ask you to edit them, '
      'use the Edit or Write tool to modify the files in your working directory.',
    );

    return buf.toString();
  }

  // ── watchDirectory ────────────────────────────────────────────────────────────

  Stream<FileWatchEvent> watchDirectory(String workDir) {
    _watchController?.close();
    _watchController = StreamController<FileWatchEvent>.broadcast();

    try {
      final dir = Directory(workDir);
      final sub = dir.watch(recursive: false).listen(
        (event) {
          final watchEvent = FileWatchEvent(
            path: event.path,
            event: event,
            timestamp: DateTime.now(),
          );
          _watchController?.add(watchEvent);
          debugPrint('[ClaudeCodeFileContext] File event: ${event.type} → ${event.path}');
        },
        onError: (e) {
          debugPrint('[ClaudeCodeFileContext] Watch error: $e');
        },
      );
      _watchSubscriptions.add(sub);
      debugPrint('[ClaudeCodeFileContext] Watching directory: $workDir');
    } on UnsupportedError catch (e) {
      debugPrint('[ClaudeCodeFileContext] File watching not supported on this platform: $e');
      // Return empty broadcast stream
      return const Stream.empty();
    } catch (e) {
      debugPrint('[ClaudeCodeFileContext] Failed to start watcher: $e');
      return const Stream.empty();
    }

    return _watchController!.stream;
  }

  // ── stopWatching ──────────────────────────────────────────────────────────────

  Future<void> stopWatching() async {
    for (final sub in _watchSubscriptions) {
      await sub.cancel();
    }
    _watchSubscriptions.clear();
    await _watchController?.close();
    _watchController = null;
    debugPrint('[ClaudeCodeFileContext] Stopped all file watchers');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  String _extension(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot < 0) return '';
    return filename.substring(dot + 1).toLowerCase();
  }

  ContextFileType _typeFromExtension(String ext) {
    return switch (ext) {
      'dart'             => ContextFileType.dartCode,
      'kt' || 'kts'      => ContextFileType.kotlinCode,
      'java'             => ContextFileType.javaCode,
      'py'               => ContextFileType.pythonCode,
      'js' || 'mjs'      => ContextFileType.jsCode,
      'ts' || 'tsx'      => ContextFileType.tsCode,
      'json'             => ContextFileType.jsonData,
      'yaml' || 'yml'    => ContextFileType.yamlData,
      'xml'              => ContextFileType.xmlData,
      'md' || 'markdown' => ContextFileType.markdown,
      'txt'              => ContextFileType.plainText,
      'sh' || 'bash'     => ContextFileType.shellScript,
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' => ContextFileType.image,
      'mp4' || 'mov' || 'avi' || 'mkv'            => ContextFileType.video,
      'mp3' || 'wav' || 'aac' || 'flac' || 'ogg'  => ContextFileType.audio,
      'pdf'                                        => ContextFileType.pdf,
      'zip' || 'tar' || 'gz' || 'rar'             => ContextFileType.archive,
      'gguf' || 'ggml'                             => ContextFileType.ggufModel,
      _                                            => ContextFileType.binary,
    };
  }

  bool _isTextType(ContextFileType type) {
    return switch (type) {
      ContextFileType.dartCode   ||
      ContextFileType.kotlinCode ||
      ContextFileType.javaCode   ||
      ContextFileType.pythonCode ||
      ContextFileType.jsCode     ||
      ContextFileType.tsCode     ||
      ContextFileType.jsonData   ||
      ContextFileType.yamlData   ||
      ContextFileType.xmlData    ||
      ContextFileType.markdown   ||
      ContextFileType.plainText  ||
      ContextFileType.shellScript => true,
      _ => false,
    };
  }

  String _langTag(ContextFileType type) {
    return switch (type) {
      ContextFileType.dartCode   => 'dart',
      ContextFileType.kotlinCode => 'kotlin',
      ContextFileType.javaCode   => 'java',
      ContextFileType.pythonCode => 'python',
      ContextFileType.jsCode     => 'javascript',
      ContextFileType.tsCode     => 'typescript',
      ContextFileType.jsonData   => 'json',
      ContextFileType.yamlData   => 'yaml',
      ContextFileType.xmlData    => 'xml',
      ContextFileType.markdown   => 'markdown',
      ContextFileType.shellScript => 'bash',
      _ => '',
    };
  }

  String _binaryDescription(ContextFileType type, String filename, int sizeBytes) {
    return switch (type) {
      ContextFileType.image    => '[Image: $filename, ${_fmtSize(sizeBytes)}]',
      ContextFileType.video    => '[Media: $filename, ${_fmtSize(sizeBytes)}]',
      ContextFileType.audio    => '[Media: $filename, ${_fmtSize(sizeBytes)}]',
      ContextFileType.ggufModel => '[AI Model: $filename, ${_fmtSize(sizeBytes)} — do not edit]',
      _ => '[Binary file: $filename, ${_fmtSize(sizeBytes)}]',
    };
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }
}
