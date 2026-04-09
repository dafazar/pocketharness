// lib/features/chat/widgets/attachment_picker_sheet.dart
//
// KanMonAI — Attachment Picker Sheet
// Bottom sheet with 8 file-type pickers for AI Chat.
//
// Permission strategy per Android API level:
//   Camera        → Permission.camera (all versions)
//   Gallery       → No permission on API 33+ (system Photo Picker)
//                   Permission.photos on API 29-32
//                   Permission.storage on API ≤ 28
//   Audio         → READ_MEDIA_AUDIO on API 33+
//                   Permission.storage on API ≤ 32
//   Video         → READ_MEDIA_VIDEO on API 33+
//                   Permission.storage on API ≤ 32
//   Document/Code → SAF (no permission needed on API 30+)
//                   Permission.storage on API ≤ 29
//   Archive/Any   → SAF on API 30+ (no permission needed)
//                   Permission.storage on API ≤ 29
//
// SAF fallback: when FilePicker returns path==null, we copy bytes to a temp
// file in the app cache dir and use that path — so FileProcessorService always
// gets a real file path and never receives null.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/data/models/chat_models.dart';
import 'package:kanmongo/data/services/content/file_processor_service.dart';
import 'package:kanmongo/data/services/system/permission_service.dart';
import 'package:kanmongo/shared/utils/top_snack.dart';
// StoragePermissionHelper is defined in permission_service.dart (Session 2)

// ── Public widget ─────────────────────────────────────────────────────────────

class AttachmentPickerSheet extends StatefulWidget {
  final void Function(List<ChatAttachment>) onAttachmentsPicked;

  const AttachmentPickerSheet({
    super.key,
    required this.onAttachmentsPicked,
  });

  @override
  State<AttachmentPickerSheet> createState() => _AttachmentPickerSheetState();
}

class _AttachmentPickerSheetState extends State<AttachmentPickerSheet> {
  bool _isProcessing = false;
  String _processingStatus = '';

  // ── Core process helper ───────────────────────────────────────────────────

  /// Runs [pickFn] to get file paths, then processes each via
  /// [FileProcessorService] and calls [onAttachmentsPicked] with results.
  Future<void> _pickAndProcess(
    Future<List<String>?> Function() pickFn,
  ) async {
    if (_isProcessing) return;

    List<String>? paths;
    try {
      paths = await pickFn();
    } catch (e) {
      debugPrint('[AttachmentPicker] pick error: $e');
      if (mounted) {
        showTopSnack(context, 'Gagal membuka picker: $e', isError: true);
      }
      return;
    }

    if (paths == null || paths.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _processingStatus = 'Memproses file...';
    });

    final results = <ChatAttachment>[];

    for (int i = 0; i < paths.length; i++) {
      final path = paths[i];
      if (!mounted) break;
      setState(() {
        _processingStatus =
            'Memproses file ${i + 1} dari ${paths!.length}...';
      });
      try {
        final pf = await FileProcessorService.instance.process(path);
        results.add(ChatAttachment.fromProcessedFile(pf));
      } catch (e) {
        debugPrint('[AttachmentPicker] process error for $path: $e');
        // Skip broken file, continue with the rest
      }
    }

    if (mounted) {
      Navigator.of(context).pop();
      widget.onAttachmentsPicked(results);
    }
  }

  // ── SAF bytes → temp file helper ──────────────────────────────────────────

  /// When FilePicker (SAF) returns bytes but no path (Android 11+ scoped
  /// storage), write bytes to app cache and return the temp path.
  /// Returns null if both path and bytes are null (user cancelled or error).
  Future<String?> _bytesToTempFile(PlatformFile f) async {
    if (f.path != null) return f.path;
    if (f.bytes == null) return null;

    final cacheDir = await getTemporaryDirectory();
    final dest = File(p.join(
      cacheDir.path,
      'attach_${DateTime.now().millisecondsSinceEpoch}_${f.name}',
    ));
    await dest.writeAsBytes(f.bytes!, flush: true);
    debugPrint(
      '[AttachmentPicker] SAF fallback: wrote ${f.bytes!.length} bytes to ${dest.path}',
    );
    return dest.path;
  }

  /// Resolves a [FilePickerResult] to a list of real file paths.
  /// Handles the SAF bytes-fallback automatically.
  Future<List<String>?> _resolveFileResult(FilePickerResult? result) async {
    if (result == null || result.files.isEmpty) return null;
    final paths = <String>[];
    for (final f in result.files) {
      final resolved = await _bytesToTempFile(f);
      if (resolved != null) paths.add(resolved);
    }
    return paths.isEmpty ? null : paths;
  }

  // ── Permission helper with dialog ─────────────────────────────────────────

  Future<bool> _showPermDeniedDialog(String permName) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Izin Diperlukan'),
        content: Text(
          'Izin "$permName" diperlukan.\n\n'
          'Buka Pengaturan → Aplikasi → KanMonAI → Izin, '
          'lalu aktifkan izin tersebut.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context, true);
            },
            child: const Text('Buka Pengaturan'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── 8 Picker implementations ───────────────────────────────────────────────

  // 1. Camera
  Future<void> _pickCamera() async {
    // Camera permission is needed on ALL Android versions.
    // This is unrelated to storage.
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        await _showPermDeniedDialog('Kamera');
      } else if (mounted) {
        showTopSnack(context, 'Izin kamera diperlukan.');
      }
      return;
    }

    await _pickAndProcess(() async {
      final img = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      return img != null ? [img.path] : null;
    });
  }

  // 2. Gallery (photos)
  Future<void> _pickGallery() async {
    // Android 13+ (API 33): ImagePicker uses the system Photo Picker —
    // no READ_MEDIA_IMAGES permission is needed.
    // Android 29-32: permission_handler handles READ_EXTERNAL_STORAGE.
    // Android ≤ 28: same, READ_EXTERNAL_STORAGE.
    // We let StoragePermissionHelper decide — it's a no-op on API 33+.
    final ok = await StoragePermissionHelper.requestForMediaRead(
      MediaType.images,
      context: context,
    );
    if (!ok) return;

    await _pickAndProcess(() async {
      final imgs = await ImagePicker().pickMultiImage(imageQuality: 85);
      if (imgs.isEmpty) return null;
      return imgs.take(10).map((x) => x.path).toList();
    });
  }

  // 3. Document (PDF, Office, text)
  Future<void> _pickDocument() async {
    final ok = await StoragePermissionHelper.requestForFileAccess(
      context: context,
    );
    if (!ok) return;

    await _pickAndProcess(() async {
      FilePickerResult? result;
      bool usedFallback = false;

      try {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: [
            'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
            'txt', 'md', 'csv', 'rtf', 'odt', 'ods',
          ],
          allowMultiple: true,
          withData: false,
        );
      } on PlatformException catch (e) {
        debugPrint('[AttachmentPicker] document custom filter failed ($e), fallback');
        usedFallback = true;
        result = null;
      } catch (e) {
        debugPrint('[AttachmentPicker] document picker error: $e');
        result = null;
      }

      if (usedFallback) {
        try {
          result = await FilePicker.platform.pickFiles(
            type: FileType.any,
            allowMultiple: true,
            withData: false,
          );
        } catch (e) {
          debugPrint('[AttachmentPicker] FileType.any doc fallback error: $e');
          return null;
        }
      }

      if (result == null || result.files.isEmpty) return null;

      if (usedFallback) {
        const validDocExts = {
          'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
          'txt', 'md', 'csv', 'rtf', 'odt', 'ods',
        };
        result = FilePickerResult(result.files.where((f) {
          final ext = f.name.split('.').last.toLowerCase();
          return validDocExts.contains(ext);
        }).toList());
        if (result.files.isEmpty) {
          if (mounted) {
            showTopSnack(context, '❌ File harus berformat dokumen (pdf, docx, xlsx, dll)', isError: true);
          }
          return null;
        }
      }

      return _resolveFileResult(result);
    });
  }

  // 4. Code / Text
  Future<void> _pickCode() async {
    final ok = await StoragePermissionHelper.requestForFileAccess(
      context: context,
    );
    if (!ok) return;

    await _pickAndProcess(() async {
      FilePickerResult? result;
      bool usedFallback = false;

      try {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: [
            'dart', 'py', 'js', 'ts', 'jsx', 'tsx',
            'java', 'kt', 'kts', 'cpp', 'c', 'h', 'hpp',
            'go', 'rs', 'rb', 'swift', 'cs', 'php',
            'json', 'xml', 'yaml', 'yml', 'toml', 'ini',
            'sh', 'bash', 'zsh', 'fish', 'bat', 'ps1',
            'html', 'css', 'scss', 'sass', 'sql',
            'gradle', 'cmake', 'makefile',
          ],
          allowMultiple: true,
          withData: false,
        );
      } on PlatformException catch (e) {
        debugPrint('[AttachmentPicker] code custom filter failed ($e), fallback');
        usedFallback = true;
        result = null;
      } catch (e) {
        debugPrint('[AttachmentPicker] code picker error: $e');
        result = null;
      }

      if (usedFallback) {
        try {
          result = await FilePicker.platform.pickFiles(
            type: FileType.any,
            allowMultiple: true,
            withData: false,
          );
        } catch (e) {
          debugPrint('[AttachmentPicker] FileType.any code fallback error: $e');
          return null;
        }
      }

      if (result == null || result.files.isEmpty) return null;

      if (usedFallback) {
        const validCodeExts = {
          'dart', 'py', 'js', 'ts', 'jsx', 'tsx', 'java', 'kt', 'kts',
          'cpp', 'c', 'h', 'hpp', 'go', 'rs', 'rb', 'swift', 'cs', 'php',
          'json', 'xml', 'yaml', 'yml', 'toml', 'ini', 'sh', 'bash',
          'zsh', 'fish', 'bat', 'ps1', 'html', 'css', 'scss', 'sass',
          'sql', 'gradle', 'cmake',
        };
        result = FilePickerResult(result.files.where((f) {
          final ext = f.name.split('.').last.toLowerCase();
          return validCodeExts.contains(ext);
        }).toList());
        if (result.files.isEmpty) {
          if (mounted) {
            showTopSnack(context, '❌ File harus berformat kode/teks (dart, py, js, dll)', isError: true);
          }
          return null;
        }
      }

      return _resolveFileResult(result);
    });
  }

  // 5. Audio
  Future<void> _pickAudio() async {
    // Android 13+ needs READ_MEDIA_AUDIO; API ≤ 32 needs READ_EXTERNAL_STORAGE
    final ok = await StoragePermissionHelper.requestForMediaRead(
      MediaType.audio,
      context: context,
    );
    if (!ok) return;

    await _pickAndProcess(() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'ogg', 'm4a', 'aac', 'flac', 'opus'],
        allowMultiple: true,
        withData: false,
      );
      return _resolveFileResult(result);
    });
  }

  // 6. Video
  Future<void> _pickVideo() async {
    final ok = await StoragePermissionHelper.requestForMediaRead(
      MediaType.video,
      context: context,
    );
    if (!ok) return;

    await _pickAndProcess(() async {
      FilePickerResult? result;
      bool usedFallback = false;

      try {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['mp4', 'mkv', 'mov', 'avi', 'webm', '3gp'],
          allowMultiple: false,
          withData: false,
        );
      } on PlatformException catch (e) {
        debugPrint('[AttachmentPicker] video custom filter failed ($e), fallback');
        usedFallback = true;
        result = null;
      } catch (e) {
        debugPrint('[AttachmentPicker] video picker error: $e');
        result = null;
      }

      if (usedFallback) {
        try {
          result = await FilePicker.platform.pickFiles(
            type: FileType.any,
            allowMultiple: false,
            withData: false,
          );
        } catch (e) {
          debugPrint('[AttachmentPicker] FileType.any video fallback error: $e');
          return null;
        }
      }

      if (result == null || result.files.isEmpty) return null;

      if (usedFallback) {
        final ext = result.files.first.name.split('.').last.toLowerCase();
        const validVideoExts = {
          'mp4', 'mkv', 'mov', 'avi', 'webm', '3gp', 'flv', 'wmv',
        };
        if (!validVideoExts.contains(ext)) {
          if (mounted) {
            showTopSnack(context, '❌ File harus berformat video (mp4, mkv, mov, dll)', isError: true);
          }
          return null;
        }
      }

      return _resolveFileResult(result);
    });
  }

  // 7. Archive / ZIP
  Future<void> _pickArchive() async {
    final ok = await StoragePermissionHelper.requestForFileAccess(
      context: context,
    );
    if (!ok) return;

    await _pickAndProcess(() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip', 'tar', 'gz', 'bz2', '7z', 'rar', 'xz'],
        allowMultiple: true,
        withData: false,
      );
      return _resolveFileResult(result);
    });
  }

  // 8. Any file
  Future<void> _pickAny() async {
    final ok = await StoragePermissionHelper.requestForFileAccess(
      context: context,
    );
    if (!ok) return;

    await _pickAndProcess(() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: false,
      );
      return _resolveFileResult(result);
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final kfc = KmColors.of(context);

    return DraggableScrollableSheet(
      expand: false,
      minChildSize: 0.4,
      initialChildSize: 0.5,
      maxChildSize: 0.85,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: kfc.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: _isProcessing
              ? _buildLoading(kfc)
              : _buildGrid(kfc, scrollCtrl),
        );
      },
    );
  }

  Widget _buildLoading(KmColors kfc) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(color: kfc.accent),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _processingStatus,
            style: TextStyle(color: kfc.textSub, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildGrid(KmColors kfc, ScrollController scrollCtrl) {
    final items = [
      _PickerOption('📷', 'Kamera',      _pickCamera),
      _PickerOption('🖼️', 'Galeri Foto', _pickGallery),
      _PickerOption('📄', 'Dokumen',     _pickDocument),
      _PickerOption('💻', 'Kode/Teks',   _pickCode),
      _PickerOption('🎵', 'Audio',        _pickAudio),
      _PickerOption('🎬', 'Video',        _pickVideo),
      _PickerOption('📦', 'Arsip/ZIP',   _pickArchive),
      _PickerOption('📎', 'Semua File',  _pickAny),
    ];

    return CustomScrollView(
      controller: scrollCtrl,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kfc.borderSoft,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Lampirkan File',
                style: TextStyle(
                  color: kfc.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.0,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _PickerGridItem(
                option: items[i],
                kfc: kfc,
                enabled: !_isProcessing,
              ),
              childCount: items.length,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Data class ─────────────────────────────────────────────────────────────────

class _PickerOption {
  final String emoji;
  final String label;
  final VoidCallback onTap;
  const _PickerOption(this.emoji, this.label, this.onTap);
}

// ── Grid item ──────────────────────────────────────────────────────────────────

class _PickerGridItem extends StatelessWidget {
  final _PickerOption option;
  final KmColors kfc;
  final bool enabled;

  const _PickerGridItem({
    required this.option,
    required this.kfc,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? option.onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 200),
        child: Container(
          decoration: BoxDecoration(
            color: kfc.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kfc.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(option.emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(height: 8),
              Text(
                option.label,
                style: TextStyle(
                  color: kfc.textSub,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
