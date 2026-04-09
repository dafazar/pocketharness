// lib/data/services/media_edit_service.dart
// KanMon GO — Media Edit Service
//
// Edit gambar, video, dan audio menggunakan ffmpeg via TerminalService.
// Semua operasi dieksekusi sebagai shell command di dalam workspace.
// =============================================================================

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:kanmongo/data/services/terminal_service.dart';

class MediaEditResult {
  final bool    success;
  final String  outputPath;
  final String  details;
  final String? error;

  const MediaEditResult({
    required this.success,
    required this.outputPath,
    this.details = '',
    this.error,
  });
}

class MediaEditService {
  MediaEditService._();
  static final MediaEditService instance = MediaEditService._();

  // ── Entry point utama ─────────────────────────────────────────────────────
  Future<MediaEditResult> edit({
    required String inputPath,
    required String operation,
    Map<String, dynamic> params = const {},
  }) async {
    try {
      if (!File(inputPath).existsSync()) {
        return MediaEditResult(
          success: false, outputPath: '',
          error: 'File tidak ditemukan: $inputPath',
        );
      }

      final outputPath = await _resolveOutputPath(inputPath, operation, params);
      final cmd = _buildFfmpegCommand(inputPath, outputPath, operation, params);

      if (cmd == null) {
        return MediaEditResult(
          success: false, outputPath: '',
          error: 'Operasi tidak didukung: $operation',
        );
      }

      debugPrint('[MediaEdit] Command: $cmd');
      final result = await TerminalService.instance.run(
        cmd,
        timeout: const Duration(minutes: 10),
      );

      if (result.isSuccess && File(outputPath).existsSync()) {
        final sizeMb = (File(outputPath).lengthSync() / (1024 * 1024))
            .toStringAsFixed(1);
        return MediaEditResult(
          success:    true,
          outputPath: outputPath,
          details:    'Output: ${p.basename(outputPath)} (${sizeMb}MB)',
        );
      }

      return MediaEditResult(
        success: false, outputPath: '',
        error: result.stderr.isNotEmpty ? result.stderr : result.stdout,
      );
    } catch (e) {
      return MediaEditResult(success: false, outputPath: '', error: e.toString());
    }
  }

  // ── Build ffmpeg command ─────────────────────────────────────────────────
  String? _buildFfmpegCommand(
    String input, String output, String op, Map<String, dynamic> p,
  ) {
    final base = 'ffmpeg -y -i "$input"';

    switch (op.toLowerCase()) {

      // ── Resize ─────────────────────────────────────────────────────────
      case 'resize':
        final w = p['width']  as int? ?? 1280;
        final h = p['height'] as int? ?? -1;  // -1 = preserve ratio
        return '$base -vf "scale=$w:$h" "$output"';

      // ── Crop ───────────────────────────────────────────────────────────
      case 'crop':
        final w  = p['width']  as int? ?? 720;
        final h  = p['height'] as int? ?? 720;
        final x  = p['x']      as int? ?? 0;
        final y  = p['y']      as int? ?? 0;
        return '$base -vf "crop=$w:$h:$x:$y" "$output"';

      // ── Rotate ─────────────────────────────────────────────────────────
      case 'rotate':
        final deg = p['degrees'] as int? ?? 90;
        final transpose = switch (deg) {
          90  => '1',
          180 => '2,transpose=2',
          270 => '2',
          _   => '1',
        };
        return '$base -vf "transpose=$transpose" "$output"';

      // ── Flip ───────────────────────────────────────────────────────────
      case 'flip':
        final dir = (p['direction'] as String? ?? 'horizontal').toLowerCase();
        final filter = dir == 'vertical' ? 'vflip' : 'hflip';
        return '$base -vf "$filter" "$output"';

      // ── Compress video ─────────────────────────────────────────────────
      case 'compress':
        final crf = p['crf'] as int? ?? 28;     // 18=hi quality, 28=smaller
        final preset = p['preset'] as String? ?? 'fast';
        return '$base -c:v libx264 -crf $crf -preset $preset -c:a aac "$output"';

      // ── Trim ───────────────────────────────────────────────────────────
      case 'trim':
        final start    = p['start']    as String? ?? '0';
        final duration = p['duration'] as String?;
        final end      = p['end']      as String?;
        if (duration != null) {
          return '$base -ss $start -t $duration -c copy "$output"';
        } else if (end != null) {
          return '$base -ss $start -to $end -c copy "$output"';
        }
        return '$base -ss $start -c copy "$output"';

      // ── Convert format ─────────────────────────────────────────────────
      case 'convert':
        // Output extension sudah diset di _resolveOutputPath
        return '$base "$output"';

      // ── Watermark teks ─────────────────────────────────────────────────
      case 'watermark':
        final text     = p['text']     as String? ?? 'KanMon GO';
        final position = p['position'] as String? ?? 'bottomright';
        final (x, y) = switch (position.toLowerCase()) {
          'topleft'     => ('10',             '10'),
          'topright'    => ('W-tw-10',        '10'),
          'bottomleft'  => ('10',             'H-th-10'),
          'center'      => ('(W-tw)/2',       '(H-th)/2'),
          _             => ('W-tw-10',        'H-th-10'), // bottomright default
        };
        return '$base -vf "drawtext=text=\'$text\':x=$x:y=$y:'
            'fontsize=24:fontcolor=white:shadowx=2:shadowy=2" "$output"';

      // ── Thumbnail ──────────────────────────────────────────────────────
      case 'thumbnail':
        final time = p['time'] as String? ?? '00:00:01';
        return '$base -ss $time -frames:v 1 "$output"';

      // ── Grayscale ──────────────────────────────────────────────────────
      case 'grayscale':
        return '$base -vf "hue=s=0" "$output"';

      // ── Brightness / Contrast ──────────────────────────────────────────
      case 'brightness':
        final b = (p['value'] as num? ?? 0.1).toDouble();
        return '$base -vf "eq=brightness=$b" "$output"';

      case 'contrast':
        final c = (p['value'] as num? ?? 1.5).toDouble();
        return '$base -vf "eq=contrast=$c" "$output"';

      // ── Blur ───────────────────────────────────────────────────────────
      case 'blur':
        final radius = p['radius'] as int? ?? 5;
        return '$base -vf "boxblur=$radius" "$output"';

      // ── Speed ──────────────────────────────────────────────────────────
      case 'speed':
        final factor = (p['factor'] as num? ?? 2.0).toDouble();
        return '$base -filter_complex '
            '"[0:v]setpts=${1 / factor}*PTS[v];[0:a]atempo=$factor[a]" '
            '-map "[v]" -map "[a]" "$output"';

      // ── Volume ─────────────────────────────────────────────────────────
      case 'volume':
        final db = p['db'] as String? ?? '5dB';
        return '$base -filter:a "volume=$db" "$output"';

      // ── Extract audio ──────────────────────────────────────────────────
      case 'extract_audio':
        return '$base -vn -acodec libmp3lame -q:a 2 "$output"';

      // ── Merge video + audio ────────────────────────────────────────────
      case 'merge':
        final audioPath = p['audio_path'] as String? ?? '';
        if (audioPath.isEmpty) return null;
        return 'ffmpeg -y -i "$input" -i "$audioPath" -c:v copy -c:a aac '
            '-shortest "$output"';

      default:
        return null;
    }
  }

  // ── Tentukan output path ──────────────────────────────────────────────────
  Future<String> _resolveOutputPath(
    String inputPath, String operation, Map<String, dynamic> params,
  ) async {
    // Jika ada output_path eksplisit, pakai itu
    if (params['output_path'] is String) {
      return params['output_path'] as String;
    }

    final dir  = await getExternalStorageDirectory() ??
                 await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}/kanmon_media_output');
    await outDir.create(recursive: true);

    final ext    = _resolveOutputExt(inputPath, operation, params);
    final base   = p.basenameWithoutExtension(inputPath);
    final ts     = DateTime.now().millisecondsSinceEpoch;
    return '${outDir.path}/${base}_${operation}_$ts.$ext';
  }

  String _resolveOutputExt(
    String input, String op, Map<String, dynamic> params,
  ) {
    // Output format eksplisit
    if (params['format'] is String) return params['format'] as String;

    switch (op.toLowerCase()) {
      case 'extract_audio': return 'mp3';
      case 'thumbnail':     return 'jpg';
      case 'convert':
        return params['to'] as String? ?? p.extension(input).replaceFirst('.', '');
      default:
        return p.extension(input).replaceFirst('.', '').ifEmpty('mp4');
    }
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
