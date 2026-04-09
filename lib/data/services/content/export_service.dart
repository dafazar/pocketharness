// lib/data/services/content/export_service.dart
// KanMon GO — Export Service
// Ekspor data ke berbagai format file
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

class ExportResult {
  final String path;
  final String filename;
  final String format;
  final bool isSuccess;
  final String? error;
  const ExportResult({required this.path, required this.filename,
      required this.format, required this.isSuccess, this.error});
}

class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();

  Future<ExportResult> export({
    required dynamic data,
    required String format,
    String? filename,
  }) async {
    try {
      final dir  = await getApplicationDocumentsDirectory();
      final ts   = DateTime.now().millisecondsSinceEpoch;
      final fn   = filename ?? 'export_$ts.$format';
      final path = p.join(dir.path, 'exports', fn);
      Directory(p.dirname(path)).createSync(recursive: true);

      String content;
      switch (format.toLowerCase()) {
        case 'json':
          content = const JsonEncoder.withIndent('  ').convert(data);
          break;
        case 'csv':
          content = _toCsv(data);
          break;
        case 'md':
        case 'markdown':
          content = _toMarkdown(data);
          break;
        case 'txt':
        default:
          content = data.toString();
      }

      await File(path).writeAsString(content);
      debugPrint('[Export] Saved: $path');
      return ExportResult(path: path, filename: fn, format: format, isSuccess: true);

    } catch (e) {
      debugPrint('[Export] error: $e');
      return ExportResult(path: '', filename: '', format: format,
          isSuccess: false, error: e.toString());
    }
  }

  Future<void> shareFile(String path) async {
    await Share.shareXFiles([XFile(path)]);
  }

  Future<List<FileSystemEntity>> listExports() async {
    final dir = Directory(
        p.join((await getApplicationDocumentsDirectory()).path, 'exports'));
    if (!dir.existsSync()) return [];
    return dir.listSync()..sort((a, b) => b.path.compareTo(a.path));
  }

  String _toCsv(dynamic data) {
    if (data is List) {
      if (data.isEmpty) return '';
      if (data.first is Map) {
        final headers = (data.first as Map).keys.join(',');
        final rows = data.map((row) =>
            (row as Map).values.map((v) => '"$v"').join(',')).join('\n');
        return '$headers\n$rows';
      }
      return data.map((v) => '"$v"').join('\n');
    }
    return data.toString();
  }

  String _toMarkdown(dynamic data) {
    if (data is Map) {
      return data.entries.map((e) => '**${e.key}**: ${e.value}').join('\n');
    }
    if (data is List && data.isNotEmpty && data.first is Map) {
      final headers = (data.first as Map).keys.join(' | ');
      final sep     = (data.first as Map).keys.map((_) => '---').join(' | ');
      final rows    = data.map((row) =>
          (row as Map).values.join(' | ')).join('\n');
      return '| $headers |\n| $sep |\n${rows.split('\n').map((r) => '| $r |').join('\n')}';
    }
    return data.toString();
  }
}
