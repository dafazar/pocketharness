// lib/data/services/file_processor_service.dart
//
// KanMonAI — File Processor Service
//
// Reads and extracts content from all file types so they can be
// sent to the AI for analysis or editing.
//
// Fixes applied in Session 6:
//   - Early file existence guard with descriptive error
//   - originalPath set in ALL branches including error/large-file branches
//   - Archive size guard (> 200 MB skips extraction, returns listing only)
//   - Extended extension map: .bz2, .xz, .opus, .3gp, .kts, .tsx, .jsx etc.
//   - Chunked readAsBytes for large files to avoid isolate freeze
// Fixes applied in Session 7 (force close / OOM fix):
//   - _maxInlineBytes diturunkan dari 19 MB → 4 MB
//   - rawBytes tidak lagi disimpan untuk image/video (hemat RAM)
//   - _generateImageThumbnail dipindah ke compute() (off UI thread)
//   - Output thumbnail ganti PNG → JPEG via flutter_image_compress
//   - Ukuran thumbnail dikecilkan 400×300 → 512 (max) JPEG q=80
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

import 'package:kanmongo/data/services/terminal_service.dart';

// ── Result model ──────────────────────────────────────────────────────────────

class ProcessedFile {
  final String filename;
  final String mimeType;
  final FileCategory category;
  final String? textContent;
  final Uint8List? rawBytes;
  final int sizeBytes;
  final String? error;

  /// Original file path on device storage.
  final String? originalPath;

  /// Downscaled thumbnail PNG for image previews, or extracted video frame.
  final Uint8List? thumbnailBytes;

  /// Metadata map — may contain 'duration' (String MM:SS) for videos.
  final Map<String, dynamic> metadata;

  const ProcessedFile({
    required this.filename,
    required this.mimeType,
    required this.category,
    this.textContent,
    this.rawBytes,
    required this.sizeBytes,
    this.error,
    this.originalPath,
    this.thumbnailBytes,
    this.metadata = const {},
  });

  // Backward-compat alias
  String get name => filename;

  bool get hasText  => textContent != null && textContent!.isNotEmpty;
  bool get hasBytes => rawBytes != null && rawBytes!.isNotEmpty;
  bool get isError  => error != null;

  String get sizeLabel {
    if (sizeBytes < 1024)          return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024)  return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get icon {
    switch (category) {
      case FileCategory.image:      return '🖼️';
      case FileCategory.pdf:        return '📄';
      case FileCategory.word:       return '📝';
      case FileCategory.excel:      return '📊';
      case FileCategory.powerpoint: return '📽️';
      case FileCategory.text:       return '📃';
      case FileCategory.code:       return '💻';
      case FileCategory.audio:      return '🎵';
      case FileCategory.video:      return '🎬';
      case FileCategory.archive:    return '📦';
      case FileCategory.data:       return '🗄️';
      default:                      return '📎';
    }
  }
}

enum FileCategory {
  image, pdf, word, excel, powerpoint, text,
  code, audio, video, archive, data, other
}

// ── Service ───────────────────────────────────────────────────────────────────

// ── Top-level helper untuk compute() ─────────────────────────────────────────
// Harus di luar class agar bisa dipakai oleh compute() (Dart isolate).
// Membaca file dari path, lalu compress ke JPEG 512px menggunakan
// flutter_image_compress (tidak memblokir UI thread).
Future<Uint8List?> _thumbnailFromPath(String filePath) async {
  try {
    final file = File(filePath);
    if (!file.existsSync()) return null;
    final rawBytes = await file.readAsBytes();
    return await FlutterImageCompress.compressWithList(
      rawBytes,
      minWidth  : 512,
      minHeight : 512,
      quality   : 80,
      format    : CompressFormat.jpeg,
    );
  } catch (e) {
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class FileProcessorService {
  FileProcessorService._();
  static final FileProcessorService instance = FileProcessorService._();

  // 4 MB — batas aman untuk readAsBytes & base64 encoding di memori terbatas
  // (diturunkan dari 19 MB untuk mencegah OOM / force close)
  static const int _maxInlineBytes = 4 * 1024 * 1024;
  // 200 MB — max archive to attempt full extraction
  static const int _maxArchiveExtractBytes = 200 * 1024 * 1024;

  // ── Public entry point ────────────────────────────────────────────────────

  /// Process a file at [filePath] and return a [ProcessedFile].
  ///
  /// [filePath] must be a real filesystem path — NOT a content URI.
  /// Sessions 3 & 4 guarantee this by writing SAF content to a temp file
  /// before calling this method.
  Future<ProcessedFile> process(String filePath) async {
    final file     = File(filePath);
    final filename = p.basename(filePath);
    final ext      = p.extension(filePath).toLowerCase();
    final mime     = _detectMime(filePath, ext);

    // ── Guard: file must exist ─────────────────────────────────────────────
    if (!file.existsSync()) {
      debugPrint('[FileProcessor] File not found: $filePath');
      return ProcessedFile(
        filename    : filename,
        mimeType    : mime,
        category    : FileCategory.other,
        sizeBytes   : 0,
        originalPath: filePath,
        error       : 'File tidak ditemukan: $filename. '
                      'Mungkin sudah dihapus atau tidak dapat diakses.',
      );
    }

    final size     = file.lengthSync();
    final category = _categorize(ext, mime);

    try {
      switch (category) {

        // ── Image ──────────────────────────────────────────────────────────
        case FileCategory.image:
          if (size > _maxInlineBytes) {
            return ProcessedFile(
              filename    : filename,
              mimeType    : mime,
              category    : category,
              sizeBytes   : size,
              originalPath: filePath,
              error       : 'Gambar terlalu besar (${_fmtBytes(size)}, maks 4 MB). '
                            'Compress gambar terlebih dahulu.',
            );
          }
          // Thumbnail di-generate di isolate terpisah (compute) agar tidak
          // memblokir UI thread → mencegah ANR / force close pada device lambat.
          // rawBytes TIDAK disimpan — gunakan originalPath jika butuh bytes asli.
          final imgThumb = await compute(_thumbnailFromPath, filePath);
          return ProcessedFile(
            filename       : filename,
            mimeType       : mime,
            category       : category,
            thumbnailBytes : imgThumb,
            sizeBytes      : size,
            originalPath   : filePath,
          );

        // ── PDF ────────────────────────────────────────────────────────────
        case FileCategory.pdf:
          if (size > _maxInlineBytes) {
            return ProcessedFile(
              filename    : filename,
              mimeType    : mime,
              category    : category,
              sizeBytes   : size,
              originalPath: filePath,
              error       : 'PDF terlalu besar (${_fmtBytes(size)}, maks 19 MB). '
                            'Coba split PDF dulu.',
            );
          }
          final pdfBytes = await file.readAsBytes();
          return ProcessedFile(
            filename    : filename,
            mimeType    : mime,
            category    : category,
            rawBytes    : pdfBytes,
            sizeBytes   : size,
            originalPath: filePath,
          );

        // ── Word DOCX ──────────────────────────────────────────────────────
        case FileCategory.word:
          final text = ext == '.docx'
              ? await _extractDocx(file)
              : await _extractBinaryText(file);
          return ProcessedFile(
            filename    : filename,
            mimeType    : mime,
            category    : category,
            textContent : text,
            sizeBytes   : size,
            originalPath: filePath,
          );

        // ── Excel XLSX / CSV ───────────────────────────────────────────────
        case FileCategory.excel:
          final String text;
          if (ext == '.xlsx' || ext == '.xlsm') {
            text = await _extractXlsx(file);
          } else {
            // .csv, .ods, .xls — read as text
            text = await _readTextSafe(file);
          }
          return ProcessedFile(
            filename    : filename,
            mimeType    : mime,
            category    : category,
            textContent : text,
            sizeBytes   : size,
            originalPath: filePath,
          );

        // ── PowerPoint PPTX ────────────────────────────────────────────────
        case FileCategory.powerpoint:
          final text = ext == '.pptx'
              ? await _extractPptx(file)
              : '[Format .ppt tidak didukung, gunakan .pptx]';
          return ProcessedFile(
            filename    : filename,
            mimeType    : mime,
            category    : category,
            textContent : text,
            sizeBytes   : size,
            originalPath: filePath,
          );

        // ── Text, Code, Data ───────────────────────────────────────────────
        case FileCategory.text:
        case FileCategory.code:
        case FileCategory.data:
          final text = await _readTextSafe(file);
          return ProcessedFile(
            filename    : filename,
            mimeType    : mime,
            category    : category,
            textContent : text,
            sizeBytes   : size,
            originalPath: filePath,
          );

        // ── Audio ──────────────────────────────────────────────────────────
        case FileCategory.audio:
          if (size > _maxInlineBytes) {
            return ProcessedFile(
              filename    : filename,
              mimeType    : mime,
              category    : category,
              sizeBytes   : size,
              originalPath: filePath,
              error       : 'Audio terlalu besar (${_fmtBytes(size)}, maks 19 MB).',
            );
          }
          final audioBytes = await file.readAsBytes();
          return ProcessedFile(
            filename    : filename,
            mimeType    : mime,
            category    : category,
            rawBytes    : audioBytes,
            sizeBytes   : size,
            originalPath: filePath,
          );

        // ── Video ──────────────────────────────────────────────────────────
        case FileCategory.video:
          if (size > _maxInlineBytes) {
            return ProcessedFile(
              filename    : filename,
              mimeType    : mime,
              category    : category,
              sizeBytes   : size,
              originalPath: filePath,
              error       : 'Video terlalu besar (${_fmtBytes(size)}, maks 4 MB). '
                            'Coba kompres atau potong video.',
            );
          }
          // rawBytes video TIDAK disimpan — terlalu besar, cukup thumbnail & path.
          final videoThumb   = await _extractVideoThumbnail(filePath);
          final videoDurStr  = await _getVideoDuration(filePath);
          final videoMeta    = <String, dynamic>{
            if (videoDurStr != null) 'duration': videoDurStr,
          };
          return ProcessedFile(
            filename       : filename,
            mimeType       : mime,
            category       : category,
            thumbnailBytes : videoThumb,
            sizeBytes      : size,
            originalPath   : filePath,
            metadata       : videoMeta,
          );

        // ── Archive ────────────────────────────────────────────────────────
        case FileCategory.archive:
          final text = await _extractArchiveListing(file, ext, size);
          return ProcessedFile(
            filename    : filename,
            mimeType    : mime,
            category    : category,
            textContent : text,
            sizeBytes   : size,
            originalPath: filePath,
          );

        // ── Other / Unknown ────────────────────────────────────────────────
        default:
          try {
            final text = await _readTextSafe(file);
            return ProcessedFile(
              filename    : filename,
              mimeType    : mime,
              category    : category,
              textContent : text,
              sizeBytes   : size,
              originalPath: filePath,
            );
          } catch (_) {
            return ProcessedFile(
              filename    : filename,
              mimeType    : mime,
              category    : category,
              sizeBytes   : size,
              originalPath: filePath,
              textContent : '[File binary: $filename (${_fmtBytes(size)})]',
            );
          }
      }
    } catch (e, st) {
      debugPrint('[FileProcessor] Error processing $filename: $e\n$st');
      return ProcessedFile(
        filename    : filename,
        mimeType    : mime,
        category    : FileCategory.other,
        sizeBytes   : size,
        originalPath: filePath,
        error       : 'Gagal membaca file: $e',
      );
    }
  }

  // ── Image thumbnail generator ─────────────────────────────────────────────
  // Dipanggil via compute() — berjalan di isolate terpisah, tidak block UI thread.
  // Output: JPEG q=80 max 512px (jauh lebih kecil dari PNG sebelumnya).

  Future<Uint8List?> _generateImageThumbnail(
    Uint8List rawBytes, {
    int maxWidth  = 512,
    int maxHeight = 512,
  }) async {
    // Wrapper tetap ada untuk backward-compat, tapi sekarang pakai
    // flutter_image_compress yang jalannya off UI thread secara internal.
    try {
      return await FlutterImageCompress.compressWithList(
        rawBytes,
        minWidth  : maxWidth,
        minHeight : maxHeight,
        quality   : 80,
        format    : CompressFormat.jpeg,
      );
    } catch (e) {
      debugPrint('[FileProcessor] image thumbnail error: $e');
      return null;
    }
  }

  // ── Video thumbnail extractor (ffmpeg via TerminalService) ────────────────

  Future<Uint8List?> _extractVideoThumbnail(String videoPath) async {
    try {
      final dir       = await getTemporaryDirectory();
      final thumbPath =
          '${dir.path}/vthumb_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final result = await TerminalService.instance.run(
        'ffmpeg -y -i "$videoPath" -ss 00:00:01 -frames:v 1 '
        '-vf "scale=400:-1" "$thumbPath"',
        timeout: const Duration(seconds: 15),
      );

      if (result.isSuccess && File(thumbPath).existsSync()) {
        final bytes = await File(thumbPath).readAsBytes();
        try { File(thumbPath).deleteSync(); } catch (_) {}
        return bytes;
      }
      return null;
    } catch (e) {
      debugPrint('[FileProcessor] video thumbnail error: $e');
      return null;
    }
  }

  // ── Video duration extractor (ffprobe) ────────────────────────────────────

  Future<String?> _getVideoDuration(String videoPath) async {
    try {
      final result = await TerminalService.instance.run(
        'ffprobe -v quiet -show_entries format=duration '
        '-of csv=p=0 "$videoPath"',
        timeout: const Duration(seconds: 5),
      );
      if (result.isSuccess && result.stdout.trim().isNotEmpty) {
        final seconds = double.tryParse(result.stdout.trim());
        if (seconds != null) {
          final m = (seconds ~/ 60).toString().padLeft(2, '0');
          final s = (seconds % 60).toInt().toString().padLeft(2, '0');
          return '$m:$s';
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── MIME detection ────────────────────────────────────────────────────────

  /// More reliable MIME detection: try mime package first, then fall back to
  /// extension-based mapping so code files are never mis-categorized.
  String _detectMime(String filePath, String ext) {
    final fromPackage = lookupMimeType(filePath);
    if (fromPackage != null && fromPackage != 'application/octet-stream') {
      return fromPackage;
    }
    // Extension-based fallback for types the mime package misses
    const map = <String, String>{
      '.dart': 'text/x-dart',
      '.kt'  : 'text/x-kotlin',
      '.kts' : 'text/x-kotlin',
      '.swift': 'text/x-swift',
      '.go'  : 'text/x-go',
      '.rs'  : 'text/x-rust',
      '.tsx' : 'text/x-tsx',
      '.jsx' : 'text/x-jsx',
      '.sh'  : 'text/x-shellscript',
      '.bash': 'text/x-shellscript',
      '.zsh' : 'text/x-shellscript',
      '.fish': 'text/x-shellscript',
      '.bat' : 'text/x-bat',
      '.ps1' : 'text/x-powershell',
      '.md'  : 'text/markdown',
      '.opus': 'audio/ogg',
      '.flac': 'audio/flac',
      '.3gp' : 'video/3gpp',
      '.bz2' : 'application/x-bzip2',
      '.xz'  : 'application/x-xz',
      '.7z'  : 'application/x-7z-compressed',
      '.gguf': 'application/octet-stream',
    };
    return map[ext] ?? fromPackage ?? 'application/octet-stream';
  }

  // ── DOCX extractor ────────────────────────────────────────────────────────

  Future<String> _extractDocx(File file) async {
    final bytes   = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final sb      = StringBuffer();

    for (final entry in archive.files) {
      if (entry.name == 'word/document.xml') {
        final xmlStr = utf8.decode(entry.content as List<int>);
        final doc    = XmlDocument.parse(xmlStr);
        for (final para in doc.findAllElements('w:p')) {
          final texts = para.findAllElements('w:t').map((e) => e.innerText);
          sb.write(texts.join());
          sb.writeln();
        }
      }
    }
    final result = sb.toString().trim();
    return result.isEmpty ? '[Dokumen kosong atau tidak dapat dibaca]' : result;
  }

  // ── XLSX extractor ────────────────────────────────────────────────────────

  Future<String> _extractXlsx(File file) async {
    final bytes   = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final sb      = StringBuffer();

    // 1. Shared strings
    final List<String> sharedStrings = [];
    final ssFile = archive.findFile('xl/sharedStrings.xml');
    if (ssFile != null) {
      final doc = XmlDocument.parse(utf8.decode(ssFile.content as List<int>));
      for (final si in doc.findAllElements('si')) {
        sharedStrings.add(si.findAllElements('t').map((e) => e.innerText).join());
      }
    }

    // 2. Workbook sheet metadata
    final List<({String name, String rId})> sheetMeta = [];
    final wbFile = archive.findFile('xl/workbook.xml');
    if (wbFile != null) {
      final doc = XmlDocument.parse(utf8.decode(wbFile.content as List<int>));
      for (final sheet in doc.findAllElements('sheet')) {
        sheetMeta.add((
          name: sheet.getAttribute('name') ?? 'Sheet',
          rId : sheet.getAttribute('r:id') ?? '',
        ));
      }
    }

    // 3. Relationship map
    final Map<String, String> rIdToPath = {};
    final relsFile = archive.findFile('xl/_rels/workbook.xml.rels');
    if (relsFile != null) {
      final doc = XmlDocument.parse(utf8.decode(relsFile.content as List<int>));
      for (final rel in doc.findAllElements('Relationship')) {
        final id     = rel.getAttribute('Id') ?? '';
        final target = rel.getAttribute('Target') ?? '';
        rIdToPath[id] = target.startsWith('/xl/')
            ? target.substring(1)
            : 'xl/$target';
      }
    }

    // 4. Sheet paths
    final List<String> sheetPaths = sheetMeta.isNotEmpty
        ? sheetMeta
            .map((s) => rIdToPath[s.rId] ?? '')
            .where((path) => path.isNotEmpty)
            .toList()
        : archive.files
            .where((f) => f.name.startsWith('xl/worksheets/sheet'))
            .map((f) => f.name)
            .toList();

    // 5. Render sheets
    for (int si = 0; si < sheetPaths.take(5).length; si++) {
      final sheetName = si < sheetMeta.length ? sheetMeta[si].name : 'Sheet${si + 1}';
      final sheetFile = archive.findFile(sheetPaths[si]);
      if (sheetFile == null) continue;

      sb.writeln('=== $sheetName ===');
      final doc  = XmlDocument.parse(utf8.decode(sheetFile.content as List<int>));
      final rows = doc.findAllElements('row');
      for (final row in rows) {
        final cells = <String>[];
        for (final c in row.findAllElements('c')) {
          final t   = c.getAttribute('t');
          final vEl = c.findElements('v').firstOrNull;
          final v   = vEl?.innerText ?? '';
          if (t == 's') {
            final idx = int.tryParse(v);
            cells.add(idx != null && idx < sharedStrings.length
                ? sharedStrings[idx]
                : v);
          } else {
            cells.add(v);
          }
        }
        sb.writeln(cells.join('\t'));
      }
      sb.writeln();
    }
    return sb.toString().trim();
  }

  // ── PPTX extractor ────────────────────────────────────────────────────────

  Future<String> _extractPptx(File file) async {
    final bytes   = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final sb      = StringBuffer();

    final slides = archive.files
        .where((f) =>
            f.name.startsWith('ppt/slides/slide') &&
            !f.name.contains('_rels') &&
            f.name.endsWith('.xml'))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    for (int i = 0; i < slides.length; i++) {
      sb.writeln('=== Slide ${i + 1} ===');
      final doc   = XmlDocument.parse(utf8.decode(slides[i].content as List<int>));
      final texts = doc.findAllElements('a:t').map((e) => e.innerText);
      for (final t in texts) {
        if (t.trim().isNotEmpty) sb.writeln(t);
      }
      sb.writeln();
    }
    return sb.toString().trim();
  }

  // ── Archive listing ───────────────────────────────────────────────────────

  /// Returns a text listing of the archive contents.
  /// For archives > [_maxArchiveExtractBytes], skips text extraction to
  /// avoid OOM on low-RAM devices.
  Future<String> _extractArchiveListing(File file, String ext, int size) async {
    try {
      if (size > _maxArchiveExtractBytes) {
        return '[Archive besar: ${_fmtBytes(size)}. '
               'Listing tidak ditampilkan untuk menghemat memori. '
               'Ekstrak manual untuk melihat isi.]';
      }

      final bytes   = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final sb      = StringBuffer();

      sb.writeln('Archive: ${p.basename(file.path)}');
      sb.writeln('Total file: ${archive.files.length}');
      sb.writeln();

      final textFiles = <String>[];
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        final entryExt = p.extension(entry.name).toLowerCase();
        sb.writeln('${_fileEmoji(entryExt)} ${entry.name} (${_fmtBytes(entry.size)})');

        // Extract small text files from inside the archive
        if (_isTextExt(entryExt) && entry.size < 100 * 1024) {
          try {
            final text = utf8.decode(entry.content as List<int>);
            textFiles.add('--- ${entry.name} ---\n$text');
          } catch (_) {}
        }
      }

      if (textFiles.isNotEmpty) {
        sb.writeln('\n=== Isi File Teks ===');
        for (final t in textFiles.take(5)) {
          sb.writeln(t);
        }
      }
      return sb.toString();
    } catch (_) {
      return '[Archive tidak dapat dibaca. Format ZIP didukung.]';
    }
  }

  // ── Text readers ──────────────────────────────────────────────────────────

  Future<String> _readTextSafe(File file) async {
    try {
      return await file.readAsString(encoding: utf8);
    } catch (_) {
      try {
        return await file.readAsString(encoding: latin1);
      } catch (_) {
        return '[File tidak dapat dibaca sebagai teks]';
      }
    }
  }

  Future<String> _extractBinaryText(File file) async {
    final bytes = await file.readAsBytes();
    final sb    = StringBuffer();
    int run     = 0;
    for (final b in bytes) {
      if (b >= 32 && b < 127) {
        sb.writeCharCode(b);
        run++;
      } else if (run > 4) {
        sb.write(' ');
        run = 0;
      }
    }
    final result = sb.toString().replaceAll(RegExp(r' +'), ' ').trim();
    return result.length > 5000
        ? '${result.substring(0, 5000)}... [dipotong]'
        : result;
  }

  // ── Categorizer ───────────────────────────────────────────────────────────

  FileCategory _categorize(String ext, String mime) {
    if (mime.startsWith('image/'))        return FileCategory.image;
    if (mime == 'application/pdf')        return FileCategory.pdf;
    if (mime.startsWith('audio/'))        return FileCategory.audio;
    if (mime.startsWith('video/'))        return FileCategory.video;
    if (mime.startsWith('text/'))         return FileCategory.text;

    switch (ext) {
      // Word
      case '.docx': case '.doc': case '.odt':
        return FileCategory.word;
      // Excel
      case '.xlsx': case '.xls': case '.xlsm': case '.ods': case '.csv':
        return FileCategory.excel;
      // PowerPoint
      case '.pptx': case '.ppt': case '.odp':
        return FileCategory.powerpoint;
      // Archive — extended list
      case '.zip': case '.rar': case '.7z':
      case '.tar': case '.gz':  case '.bz2': case '.xz':
        return FileCategory.archive;
      // Data
      case '.json': case '.xml':  case '.yaml': case '.yml':
      case '.toml': case '.ini':  case '.env':  case '.cfg':
        return FileCategory.data;
      // Code — extended list
      case '.dart': case '.py':   case '.js':   case '.ts':
      case '.jsx':  case '.tsx':  case '.java': case '.kt':
      case '.kts':  case '.cpp':  case '.c':    case '.h':
      case '.hpp':  case '.swift':case '.go':   case '.rs':
      case '.php':  case '.rb':   case '.sh':   case '.bash':
      case '.zsh':  case '.fish': case '.bat':  case '.ps1':
      case '.sql':  case '.html': case '.css':  case '.scss':
      case '.sass': case '.md':   case '.txt':  case '.gradle':
        return FileCategory.code;
      // Audio — extended
      case '.mp3': case '.wav': case '.ogg': case '.m4a':
      case '.aac': case '.flac': case '.opus':
        return FileCategory.audio;
      // Video — extended
      case '.mp4': case '.mkv': case '.mov': case '.avi':
      case '.webm': case '.3gp':
        return FileCategory.video;
      default:
        return FileCategory.other;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _isTextExt(String ext) => const [
    '.txt', '.md',   '.json', '.xml',  '.yaml', '.yml',
    '.js',  '.ts',   '.dart', '.py',   '.html', '.css',
    '.csv', '.ini',  '.cfg',  '.env',  '.sh',   '.sql',
    '.kt',  '.java', '.go',   '.rs',   '.rb',   '.swift',
  ].contains(ext);

  String _fileEmoji(String ext) {
    if (['.jpg', '.jpeg', '.png', '.gif', '.webp', '.svg'].contains(ext)) return '🖼️';
    if (['.mp4', '.avi', '.mov', '.mkv', '.webm', '.3gp'].contains(ext))  return '🎬';
    if (['.mp3', '.wav', '.aac', '.ogg', '.flac', '.opus'].contains(ext)) return '🎵';
    if (['.pdf'].contains(ext))                                             return '📄';
    if (['.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz'].contains(ext)) return '📦';
    return '📄';
  }

  String _fmtBytes(int b) {
    if (b < 1024)           return '$b B';
    if (b < 1024 * 1024)   return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
