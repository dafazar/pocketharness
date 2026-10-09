// lib/data/services/smart_file_output_service.dart
// PocketHarness — Smart File Output Service
//
// Detects code blocks in AI responses and offers them as downloadable files.
// Works without requiring file attachments — intent keywords in user message
// are enough to trigger file output detection.
// =============================================================================

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────

/// Represents a single extracted file output from an AI response.
class SmartFileOutput {
  final String filename;
  final String content;
  final String extension;
  final String language;

  const SmartFileOutput({
    required this.filename,
    required this.content,
    required this.extension,
    required this.language,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class SmartFileOutputService {
  SmartFileOutputService._();
  static final SmartFileOutputService instance = SmartFileOutputService._();

  // ── Intent keywords that suggest user wants a file output ─────────────────

  static const _intentKeywords = [
    'buat', 'create', 'generate', 'tulis', 'write', 'edit', 'perbaiki',
    'fix', 'refactor', 'update', 'modify', 'ubah', 'tambah', 'add',
    'implement', 'implementasi', 'kode', 'code', 'script', 'file',
    'buatkan', 'tolong buat', 'please create', 'please write',
    'jadikan', 'konversi', 'convert',
  ];

  // ── Language → extension mapping ──────────────────────────────────────────

  static const _langToExt = {
    'dart': 'dart',
    'python': 'py',
    'py': 'py',
    'javascript': 'js',
    'js': 'js',
    'typescript': 'ts',
    'ts': 'ts',
    'html': 'html',
    'css': 'css',
    'json': 'json',
    'yaml': 'yaml',
    'yml': 'yml',
    'xml': 'xml',
    'kotlin': 'kt',
    'kt': 'kt',
    'java': 'java',
    'cpp': 'cpp',
    'c++': 'cpp',
    'c': 'c',
    'rust': 'rs',
    'go': 'go',
    'swift': 'swift',
    'php': 'php',
    'ruby': 'rb',
    'shell': 'sh',
    'bash': 'sh',
    'sh': 'sh',
    'sql': 'sql',
    'markdown': 'md',
    'md': 'md',
    'txt': 'txt',
    'text': 'txt',
    'csv': 'csv',
    'toml': 'toml',
    'ini': 'ini',
  };

  // ── Detect if user message has file-creation intent ───────────────────────

  bool hasFileIntent(String? userMessage) {
    if (userMessage == null || userMessage.isEmpty) return false;
    final lower = userMessage.toLowerCase();
    return _intentKeywords.any((kw) => lower.contains(kw));
  }

  // ── Extract code blocks from AI response ──────────────────────────────────
  //
  // Matches: ```lang\n...code...\n``` or ``` ... ```
  // Also detects inline full-file content if no code fences found.

  List<SmartFileOutput> extractFromAiResponse({
    required String aiResponse,
    String? userMessage,
    String? originalFilename,
  }) {
    if (aiResponse.isEmpty) return [];

    final outputs = <SmartFileOutput>[];

    // ── Regex: fenced code blocks ```lang\ncontent\n``` ──────────────────────
    final fenceRegex = RegExp(
      r'```([a-zA-Z0-9+#._-]*)\n([\s\S]*?)```',
      multiLine: true,
    );

    final matches = fenceRegex.allMatches(aiResponse);

    for (final match in matches) {
      final lang = (match.group(1) ?? '').trim().toLowerCase();
      final content = (match.group(2) ?? '').trimRight();

      if (content.isEmpty) continue;
      // Skip very short snippets (likely inline examples, not full files)
      if (content.split('\n').length < 3) continue;

      final ext = _langToExt[lang] ?? (lang.isNotEmpty ? lang : 'txt');
      final filename = _buildFilename(
        lang: lang,
        ext: ext,
        originalFilename: originalFilename,
        index: outputs.length,
        userMessage: userMessage,
      );

      outputs.add(SmartFileOutput(
        filename: filename,
        content: content,
        extension: ext,
        language: lang.isNotEmpty ? lang : 'text',
      ));
    }

    // ── Fallback: if no fenced blocks but response looks like a full file ────
    if (outputs.isEmpty && originalFilename != null) {
      final ext = originalFilename.contains('.')
          ? originalFilename.split('.').last.toLowerCase()
          : 'txt';
      const textExts = {
        'txt', 'md', 'dart', 'py', 'js', 'ts', 'html', 'css', 'json',
        'xml', 'csv', 'kt', 'java', 'cpp', 'c', 'h', 'yaml', 'yml',
        'toml', 'ini', 'log', 'sql', 'sh', 'bat',
      };
      if (textExts.contains(ext) && aiResponse.split('\n').length > 5) {
        outputs.add(SmartFileOutput(
          filename: originalFilename,
          content: aiResponse,
          extension: ext,
          language: ext,
        ));
      }
    }

    return outputs;
  }

  // ── Build a descriptive filename ──────────────────────────────────────────

  String _buildFilename({
    required String lang,
    required String ext,
    String? originalFilename,
    int index = 0,
    String? userMessage,
  }) {
    // If original file exists, use base name + _edited suffix
    if (originalFilename != null && originalFilename.isNotEmpty) {
      final base = p.basenameWithoutExtension(originalFilename);
      final ts = DateTime.now().millisecondsSinceEpoch;
      return '${base}_edited_$ts.$ext';
    }

    // Try to extract meaningful name from user message
    if (userMessage != null && userMessage.isNotEmpty) {
      final words = userMessage
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s_]'), '')
          .split(RegExp(r'\s+'))
          .where((w) => w.length > 3 && !_intentKeywords.contains(w))
          .take(2)
          .join('_');
      if (words.isNotEmpty) {
        final ts = DateTime.now().millisecondsSinceEpoch;
        final suffix = index > 0 ? '_${index + 1}' : '';
        return '${words}$suffix.$ext';
      }
    }

    // Generic fallback
    final ts = DateTime.now().millisecondsSinceEpoch;
    final suffix = index > 0 ? '_${index + 1}' : '';
    final langPart = lang.isNotEmpty ? '${lang}_' : '';
    return '${langPart}output$suffix.$ext';
  }

  // ── Resolve output directory (/storage/emulated/0/Download/ompre/) ─────────

  Future<Directory> resolveOutputDirectory() async {
    // Primary: /storage/emulated/0/Download/ompre/
    try {
      final dir = Directory('/storage/emulated/0/Download/ompre');
      if (!dir.existsSync()) await dir.create(recursive: true);
      final test = File('${dir.path}/.wtest_${DateTime.now().millisecondsSinceEpoch}');
      await test.writeAsString('ok');
      await test.delete();
      return dir;
    } catch (_) {}

    // Fallback 1: /sdcard/Download/ompre/
    try {
      final dir = Directory('/sdcard/Download/ompre');
      if (!dir.existsSync()) await dir.create(recursive: true);
      final test = File('${dir.path}/.wtest_${DateTime.now().millisecondsSinceEpoch}');
      await test.writeAsString('ok');
      await test.delete();
      return dir;
    } catch (_) {}

    // Fallback 2: App documents/exports/ompre/
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/exports/ompre');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }
}
