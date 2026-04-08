import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:open_file/open_file.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:archive/archive_io.dart';
import 'package:xml/xml.dart' as xmlp;
import 'dart:convert' show utf8;
import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/shared/widgets/view_toggle.dart';
import 'package:kanmongo/shared/widgets/screen_theme_banner.dart';
import 'package:kanmongo/core/theme/theme_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kanmongo/shared/widgets/wallpaper_background.dart';
import 'package:kanmongo/shared/widgets/back_handler.dart';

enum _FileType { pdf, pptx, docx, xlsx, audio, video, text, unknown }

_FileType _detectType(String path) {
  final ext = path.split('.').last.toLowerCase();
  switch (ext) {
    case 'pdf':   return _FileType.pdf;
    case 'ppt': case 'pptx': return _FileType.pptx;
    case 'doc': case 'docx': return _FileType.docx;
    case 'xls': case 'xlsx': return _FileType.xlsx;
    case 'mp3': case 'wav': case 'aac': case 'm4a': case 'ogg': case 'flac':
      return _FileType.audio;
    case 'mp4': case 'mkv': case 'mov': case 'avi': case 'webm':
      return _FileType.video;
    case 'txt': case 'md': return _FileType.text;
    default: return _FileType.unknown;
  }
}

String _typeLabel(_FileType t) {
  switch (t) {
    case _FileType.pdf:   return 'PDF';
    case _FileType.pptx:  return 'PPT';
    case _FileType.docx:  return 'DOC';
    case _FileType.xlsx:  return 'XLS';
    case _FileType.audio: return 'Audio';
    case _FileType.video: return 'Video';
    case _FileType.text:  return 'TXT';
    default:              return 'File';
  }
}

String _typeEmoji(_FileType t) {
  switch (t) {
    case _FileType.pdf:   return 'assets/icons/logo/file-pdf-thin.svg';
    case _FileType.pptx:  return 'assets/icons/logo/presentation-chart-thin.svg';
    case _FileType.docx:  return 'assets/icons/logo/file-doc-thin.svg';
    case _FileType.xlsx:  return 'assets/icons/logo/microsoft-excel-logo-thin.svg';
    case _FileType.audio: return 'assets/icons/logo/music-note-thin.svg';
    case _FileType.video: return 'assets/icons/logo/video-thin.svg';
    case _FileType.text:  return 'assets/icons/logo/file-text-thin.svg';
    default:              return 'assets/icons/logo/file-thin.svg';
  }
}

Color _typeColor(_FileType t) {
  // Monochrome B&W: all file types use white/black via theme
  return const Color(0xFFFFFFFF); // Caller uses KmColors.of(context).accent at runtime
}

// ═════════════════════════════════════════════════════════════════════════════
// EBOOK SCREEN
// ═════════════════════════════════════════════════════════════════════════════
class EbookScreen extends ConsumerStatefulWidget {
  const EbookScreen({super.key});
  @override
  ConsumerState<EbookScreen> createState() => _EbookScreenState();
}

class _EbookScreenState extends ConsumerState<EbookScreen> {

  List<Map<String, String>> _files = []; // {title, path}
  bool _loading = true;
  bool _isGrid = false;
  String _filterType = 'Semua';

  // ── Edit mode ─────────────────────────────────────────────────────────────
  bool _editMode = false;
  final Set<String> _selected = {};

  static const _allTypes = ['Semua', 'PDF', 'PPT', 'DOC', 'XLS', 'Audio', 'Video', 'TXT'];

  static const _allowedExtensions = [
    'pdf',
    'ppt', 'pptx',
    'doc', 'docx',
    'xls', 'xlsx',
    'mp3', 'wav', 'aac', 'm4a', 'ogg', 'flac',
    'mp4', 'mkv', 'mov', 'avi',
    'txt', 'md',
  ];

  // ── SharedPreferences keys ────────────────────────────────────────────────
  static const _kLibraryPaths       = 'kp.library.paths';
  static const _kLibraryPathsLegacy = 'library_paths';

  // ── Subfolder per tipe file ───────────────────────────────────────────────
  static const _audioExts = {'mp3', 'wav', 'aac', 'm4a', 'ogg', 'flac'};
  static const _videoExts = {'mp4', 'mkv', 'mov', 'avi'};

  String _subfolderFor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (_audioExts.contains(ext)) return 'audio';
    if (_videoExts.contains(ext)) return 'video';
    return 'documents';
  }

  @override
  void initState() {
    super.initState(); _loadFiles();
    loadViewMode('ebook').then((v) { if (mounted) setState(() => _isGrid = v); });
  }

  Future<void> _loadFiles() async {
    final prefs = await SharedPreferences.getInstance();

    // ── Migrasi: library_paths → kmg.library.paths ─────────────────────────
    if (prefs.containsKey(_kLibraryPathsLegacy)) {
      final legacyPaths = prefs.getStringList(_kLibraryPathsLegacy) ?? [];
      if (legacyPaths.isNotEmpty) {
        final dir = await getApplicationDocumentsDirectory();
        final migratedPaths = <String>[];

        for (final oldPath in legacyPaths) {
          if (!await File(oldPath).exists()) continue;
          final fileName = oldPath.split('/').last;
          final subfolder = _subfolderFor(fileName);
          final newDir = Directory('${dir.path}/library/$subfolder');
          await newDir.create(recursive: true);
          final newPath = '${newDir.path}/$fileName';

          if (!await File(newPath).exists()) {
            await File(oldPath).copy(newPath);
          }
          migratedPaths.add(newPath);
        }

        await prefs.setStringList(_kLibraryPaths, migratedPaths);
        await prefs.remove(_kLibraryPathsLegacy);

        // Hapus file lama dari root library/ setelah migrasi berhasil
        for (final oldPath in legacyPaths) {
          try {
            final oldFile = File(oldPath);
            if (await oldFile.exists() && oldPath.contains('/library/') &&
                !oldPath.contains('/library/documents/') &&
                !oldPath.contains('/library/audio/') &&
                !oldPath.contains('/library/video/')) {
              await oldFile.delete();
            }
          } catch (_) {}
        }
      } else {
        await prefs.remove(_kLibraryPathsLegacy);
      }
    }

    final saved = prefs.getStringList(_kLibraryPaths) ?? [];
    final valid = <Map<String, String>>[];
    for (final p in saved) {
      if (await File(p).exists()) {
        valid.add({'title': p.split('/').last, 'path': p});
      }
    }
    if (mounted) setState(() { _files = valid; _loading = false; });
    await prefs.setStringList(_kLibraryPaths, valid.map((f) => f['path']!).toList());
  }

  Future<void> _addFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      allowMultiple: true,
    );
    if (result == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_kLibraryPaths) ?? [];

    for (final file in result.files) {
      if (file.path == null) continue;
      final subfolder = _subfolderFor(file.name);
      final subDir = Directory('${dir.path}/library/$subfolder');
      await subDir.create(recursive: true);
      final dest = '${subDir.path}/${file.name}';
      await File(file.path!).copy(dest);
      if (!saved.contains(dest)) saved.add(dest);
    }
    await prefs.setStringList(_kLibraryPaths, saved);
    await _loadFiles();
  }

  // ── Edit Mode: enter / exit / select / rename / delete selected ──────────
  void _enterEditMode(String initialPath) {
    HapticFeedback.heavyImpact();
    setState(() {
      _editMode = true;
      _selected.add(initialPath);
    });
  }

  void _exitEditMode() {
    setState(() {
      _editMode = false;
      _selected.clear();
    });
  }

  void _toggleSelect(String path) {
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
        if (_selected.isEmpty) _editMode = false;
      } else {
        _selected.add(path);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selected.addAll(_filteredFiles.map((f) => f['path']!));
    });
  }

  Future<void> _renameFile(Map<String, String> file) async {
    final ctrl = TextEditingController(text: file['title']);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KmColors.of(context).card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.edit_rounded, color: KmColors.of(context).accent, size: 20),
          const SizedBox(width: 8),
          Text('Ganti Nama', style: TextStyle(color: KmColors.of(context).text, fontSize: 16)),
        ]),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: KmColors.of(context).text),
          decoration: InputDecoration(
            hintText: 'Nama baru...',
            hintStyle: TextStyle(color: KmColors.of(context).textMuted),
            filled: true,
            fillColor: KmColors.of(context).elevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: KmColors.of(context).border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: KmColors.of(context).accent, width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal', style: TextStyle(color: KmColors.of(context).textSub)),
          ),
          ElevatedButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) Navigator.pop(ctx, name);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: KmColors.of(context).accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;

    // Rename physical file (keep extension)
    final oldPath = file['path']!;
    final ext = oldPath.contains('.') ? '.${oldPath.split('.').last}' : '';
    final dir = oldPath.substring(0, oldPath.lastIndexOf('/'));
    final newName = result.endsWith(ext) ? result : '$result$ext';
    final newPath = '$dir/$newName';

    try {
      await File(oldPath).rename(newPath);
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_kLibraryPaths) ?? [];
      final idx = saved.indexOf(oldPath);
      if (idx >= 0) {
        saved[idx] = newPath;
        await prefs.setStringList(_kLibraryPaths, saved);
      }
      await _loadFiles();
      _exitEditMode();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Berganti nama ke "$newName"',
              style: TextStyle(color: KmColors.of(context).text)),
          backgroundColor: KmColors.of(context).card,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: KmColors.of(context).border),
          ),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal rename: $e',
              style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KmColors.of(context).card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 22),
          const SizedBox(width: 8),
          Text('Hapus $count File',
              style: TextStyle(color: KmColors.of(context).text, fontSize: 16)),
        ]),
        content: Text(
          'Hapus $count file yang dipilih dari perpustakaan?',
          style: TextStyle(color: KmColors.of(context).textSub, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal', style: TextStyle(color: KmColors.of(context).textSub)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_rounded, size: 16),
            label: const Text('Hapus'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_kLibraryPaths) ?? [];

    for (final path in _selected) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      saved.removeWhere((p) => p == path);
    }

    await prefs.setStringList(_kLibraryPaths, saved);
    await _loadFiles();
    _exitEditMode();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$count file dihapus',
            style: TextStyle(color: KmColors.of(context).text)),
        backgroundColor: KmColors.of(context).card,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: KmColors.of(context).border),
        ),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _deleteFile(Map<String, String> file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KmColors.of(context).card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 22),
          const SizedBox(width: 8),
          Text('Hapus File',
              style: TextStyle(color: KmColors.of(context).text, fontSize: 16)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Hapus file berikut dari perpustakaan?',
              style: TextStyle(color: KmColors.of(context).textSub, fontSize: 13)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: KmColors.of(context).bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: KmColors.of(context).border),
            ),
            child: Row(children: [
              Icon(Icons.insert_drive_file_outlined,
                  color: Colors.red.shade300, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(file['title'] ?? '',
                    style: TextStyle(color: KmColors.of(context).text,
                        fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Text('File akan dihapus permanen dari penyimpanan.',
              style: TextStyle(color: KmColors.of(context).textMuted, fontSize: 11)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal',
                style: TextStyle(color: KmColors.of(context).textSub)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_rounded, size: 16),
            label: const Text('Hapus'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Hapus file fisik dari disk
      try {
        final physicalFile = File(file['path']!);
        if (await physicalFile.exists()) await physicalFile.delete();
      } catch (_) {}

      // Hapus dari SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_kLibraryPaths) ?? [];
      saved.removeWhere((p) => p == file['path']);
      await prefs.setStringList(_kLibraryPaths, saved);

      // Reload UI
      await _loadFiles();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('"${file['title']}" dihapus',
              style: TextStyle(color: KmColors.of(context).text)),
          backgroundColor: KmColors.of(context).card,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: KmColors.of(context).border),
          ),
          duration: const Duration(seconds: 2),
        ));
      }
    }
  }

  void _openFile(Map<String, String> file) {
    final path = file['path']!;
    final type = _detectType(path);
    final title = file['title']!;

    switch (type) {
      case _FileType.pdf:
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _PdfViewerScreen(title: title, path: path),
        ));
        break;
      case _FileType.audio:
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _AudioPlayerScreen(title: title, path: path),
        ));
        break;
      case _FileType.video:
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _VideoPlayerScreen(title: title, path: path),
        ));
        break;
      case _FileType.text:
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _TextViewerScreen(title: title, path: path),
        ));
        break;
      case _FileType.pptx:
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _PptxViewerScreen(title: title, path: path),
        ));
        break;
      case _FileType.docx:
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _DocxViewerScreen(title: title, path: path),
        ));
        break;
      case _FileType.xlsx:
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _XlsxViewerScreen(title: title, path: path),
        ));
        break;
      default:
        OpenFile.open(path);
    }
  }

  List<Map<String, String>> get _filteredFiles {
    if (_filterType == 'Semua') return _files;
    return _files.where((f) {
      final type = _detectType(f['path']!);
      return _typeLabel(type) == _filterType;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themePackProvider);
    final filtered = _filteredFiles;
    final c = KmColors.of(context);
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_editMode) { _exitEditMode(); return; }
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: wallpaperAwareBg(context, ref, c.bg),
        appBar: _editMode ? AppBar(
          backgroundColor: c.accent,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _exitEditMode,
          ),
          title: Text('${_selected.length} dipilih'),
          actions: [
            TextButton(
              onPressed: _selectAll,
              child: const Text('Pilih Semua', style: TextStyle(color: Colors.white, fontSize: 13)),
            ),
            if (_selected.length == 1)
              IconButton(
                icon: const Icon(Icons.edit_rounded),
                tooltip: 'Ganti Nama',
                onPressed: () {
                  final file = _filteredFiles.firstWhere((f) => f['path'] == _selected.first);
                  _renameFile(file);
                },
              ),
            IconButton(
              icon: const Icon(Icons.delete_rounded),
              tooltip: 'Hapus',
              onPressed: _selected.isNotEmpty ? _deleteSelected : null,
            ),
          ],
        ) : AppBar(
          backgroundColor: wallpaperAwareCard(context, ref, c.card),
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded),
              onPressed: () => Navigator.pop(context)),
          title: const Text('Perpustakaan'),
          actions: [
            ViewToggleButton(isGrid: _isGrid, onToggle: () { saveViewMode('ebook', !_isGrid); setState(() => _isGrid = !_isGrid); }),
            IconButton(
              icon: Icon(Icons.add_rounded, color: c.accent),
              onPressed: _addFile,
              tooltip: 'Tambah File',
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                // Edit mode hint banner
                if (_editMode)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: c.accent.withValues(alpha: 0.12),
                    child: Row(children: [
                      Icon(Icons.info_outline_rounded, color: c.accent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        'Ketuk file untuk memilih · Tahan untuk rename · Tekan ✕ untuk keluar',
                        style: TextStyle(color: c.textSub, fontSize: 11),
                      )),
                    ]),
                  ),
                if (_files.isNotEmpty)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      scrollDirection: Axis.horizontal,
                      children: _allTypes.map((type) {
                        final active = _filterType == type;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(type,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: active ? Colors.white : c.textSub,
                                )),
                            selected: active,
                            onSelected: (_) => setState(() => _filterType = type),
                            selectedColor: c.accent,
                            backgroundColor: c.card,
                            side: BorderSide(
                                color: active ? c.accent : c.border),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                Expanded(
                  child: _files.isEmpty
                      ? _buildEmpty()
                      : filtered.isEmpty
                          ? Center(
                              child: Text('Tidak ada file $_filterType',
                                  style: TextStyle(color: c.textSub)),
                            )
                          : _isGrid
                              ? GridView.builder(
                                  padding: const EdgeInsets.all(12),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.80),
                                  itemCount: filtered.length,
                                  itemBuilder: (ctx, i) => _buildFileGridCard(filtered[i]),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: filtered.length,
                                  itemBuilder: (ctx, i) => _buildFileCard(filtered[i]),
                                ),
                ),
              ]),
        floatingActionButton: _files.isNotEmpty && !_editMode
            ? FloatingActionButton(
                onPressed: _addFile,
                backgroundColor: c.accent,
                child: Icon(Icons.add_rounded, color: c.text),
              )
            : null,
      ),
    );
  }


  Widget _buildFileGridCard(Map<String, String> file) {
    final c = KmColors.of(context);
    final path = file['path']!;
    final type = _detectType(path);
    final label = _typeLabel(type);
    final emoji = _typeEmoji(type);
    final isSelected = _selected.contains(path);
    final typeColors = {
      'PDF': const Color(0xFFDC2626), 'PPT': const Color(0xFFD4651D),
      'DOC': const Color(0xFF2563B8), 'XLS': const Color(0xFF1A8C5B),
      'Audio': const Color(0xFF7030A0), 'Video': const Color(0xFF0F8C7A),
      'TXT': const Color(0xFFC07D10), 'File': c.accent,
    };
    final color = typeColors[label] ?? c.accent;

    return GestureDetector(
      onTap: _editMode ? () => _toggleSelect(path) : () => _openFile(file),
      onLongPress: () {
        if (_editMode) {
          _renameFile(file);
        } else {
          _enterEditMode(path);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: isSelected ? c.accent.withValues(alpha: 0.15) : c.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? c.accent : c.border,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0,3))],
        ),
        child: Stack(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Top color band
            Container(
              height: 90,
              decoration: BoxDecoration(
                color: color.withValues(alpha: isSelected ? 0.25 : 0.15),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.25))),
              ),
              child: Stack(children: [
                Center(child: SvgPicture.asset(emoji, width: 42, height: 42,
                    colorFilter: ColorFilter.mode(color, BlendMode.srcIn))),
                Positioned(top: 8, right: 8, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.20), borderRadius: BorderRadius.circular(5)),
                  child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
                )),
              ]),
            ),
            // Title
            Expanded(child: Padding(
              padding: const EdgeInsets.fromLTRB(10,8,10,8),
              child: Text(file['title']!, style: TextStyle(color: c.text, fontSize: 12, fontWeight: FontWeight.w600, height: 1.3),
                  maxLines: 3, overflow: TextOverflow.ellipsis),
            )),
            // Action row
            Padding(
              padding: const EdgeInsets.fromLTRB(8,0,8,8),
              child: Row(children: [
                Expanded(child: Text(
                  _editMode ? 'Tahan → rename' : 'Tahan 3s → edit',
                  style: TextStyle(color: c.textMuted, fontSize: 9),
                )),
                Icon(Icons.open_in_new_rounded, color: c.textMuted, size: 14),
              ]),
            ),
          ]),
          // Selection checkmark overlay
          if (_editMode)
            Positioned(
              top: 8, left: 8,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: isSelected ? c.accent : Colors.white.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                  border: Border.all(color: isSelected ? c.accent : c.border, width: 2),
                ),
                child: isSelected
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                    : null,
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SvgPicture.asset('assets/icons/logo/books-thin.svg', width: 64, height: 64, colorFilter: ColorFilter.mode(KmColors.of(context).textMuted, BlendMode.srcIn)),
        const SizedBox(height: 16),
        Text('Perpustakaan Kosong',
            style: TextStyle(color: KmColors.of(context).text,
                fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
            'Tambahkan PDF, PowerPoint, Word, Excel,\nAudio, Video, atau file teks',
            textAlign: TextAlign.center,
            style: TextStyle(color: KmColors.of(context).textSub, fontSize: 14, height: 1.6)),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: _addFile,
          icon: const Icon(Icons.upload_file_rounded),
          label: Text('Tambah File'),
          style: ElevatedButton.styleFrom(backgroundColor: KmColors.of(context).accent),
        ),
      ]),
    );
  }

  Widget _buildFileCard(Map<String, String> file) {
    final c = KmColors.of(context);
    final path = file['path']!;
    final type = _detectType(path);
    final label = _typeLabel(type);
    final emoji = _typeEmoji(type);
    final isSelected = _selected.contains(path);

    // File type colors
    final typeColors = {
      'PDF': const Color(0xFFDC2626), 'PPT': const Color(0xFFD4651D),
      'DOC': const Color(0xFF2563B8), 'XLS': const Color(0xFF1A8C5B),
      'Audio': const Color(0xFF7030A0), 'Video': const Color(0xFF0F8C7A),
      'TXT': const Color(0xFFC07D10), 'File': c.accent,
    };
    final color = typeColors[label] ?? c.accent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? c.accent.withValues(alpha: 0.12) : c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? c.accent : c.border,
          width: isSelected ? 2.0 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _editMode ? () => _toggleSelect(path) : () => _openFile(file),
        onLongPress: () {
          if (_editMode) {
            _renameFile(file);
          } else {
            _enterEditMode(path);
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
          child: Row(children: [
            // Selection indicator / file icon
            if (_editMode)
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 28, height: 28, margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: isSelected ? c.accent : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: isSelected ? c.accent : c.border, width: 2),
                ),
                child: isSelected
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                    : null,
              ),
            Container(
              width: 52, height: 64,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                SvgPicture.asset(emoji, width: 26, height: 26, colorFilter: ColorFilter.mode(color, BlendMode.srcIn)),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 10)),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(file['title']!,
                    style: TextStyle(
                        color: c.text, fontSize: 14,
                        fontWeight: FontWeight.w600),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(
                  _editMode
                      ? 'Tahan untuk rename'
                      : 'Ketuk untuk membuka · Tahan 3s → edit',
                  style: TextStyle(color: c.textMuted, fontSize: 11),
                ),
              ]),
            ),
            // Action button
            if (_editMode)
              IconButton(
                icon: Icon(Icons.edit_outlined, color: c.accent.withValues(alpha: 0.8), size: 22),
                tooltip: 'Ganti nama',
                onPressed: () => _renameFile(file),
              )
            else
              IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    color: Colors.red.withValues(alpha: 0.7), size: 22),
                tooltip: 'Hapus file',
                onPressed: () => _deleteFile(file),
              ),
          ]),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PDF VIEWER  — UI seragam dengan PPTX viewer (card style + thumbnail strip)
// ═════════════════════════════════════════════════════════════════════════════
class _PdfViewerScreen extends StatefulWidget {
  final String title, path;
  const _PdfViewerScreen({required this.title, required this.path});
  @override
  State<_PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<_PdfViewerScreen> {

  final PdfViewerController _pdfCtrl = PdfViewerController();
  final ScrollController _thumbScroll = ScrollController();
  int _currentPage = 1;
  int _totalPages = 1;
  bool _loading = true;

  static const _accentColor  = Color(0xFFE74C3C);   // merah PDF
  static const _accentDark   = Color(0xFFC0392B);
  // _bgDark removed (use KmColors.of(context).card directly)
  static const _thumbWidth   = 72.0;

  @override
  void dispose() {
    _thumbScroll.dispose();
    super.dispose();
  }

  void _scrollThumbToPage(int page) {
    final idx = page - 1;
    final offset = idx * (_thumbWidth + 8) - 40;
    if (_thumbScroll.hasClients) {
      _thumbScroll.animateTo(
        offset.clamp(0.0, _thumbScroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConfirmExitBack(
      message: 'Yakin ingin menutup file PDF ini?',
      confirmLabel: 'Keluar',
      child: Scaffold(
      backgroundColor: KmColors.of(context).card,
      // ── AppBar bergaya PPTX (gradient merah PDF) ─────────────────────────
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_accentColor, _accentDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
            if (!_loading)
              Text('Halaman $_currentPage dari $_totalPages',
                  style: TextStyle(fontSize: 11, color: KmColors.of(context).textSub)),
          ],
        ),
        actions: [
          // Tombol jump ke halaman
          IconButton(
            icon: const Icon(Icons.find_in_page_rounded),
            tooltip: 'Pergi ke halaman',
            onPressed: _totalPages > 1 ? _showJumpDialog : null,
          ),
        ],
      ),
      body: Column(children: [
        // ── Area PDF (kartu putih bergaya PPTX) ──────────────────────────────
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: KmColors.of(context).bg.withValues(alpha: 0.45),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(children: [
                SfPdfViewer.file(
                  File(widget.path),
                  controller: _pdfCtrl,
                  onDocumentLoaded: (d) {
                    setState(() {
                      _totalPages = d.document.pages.count;
                      _loading = false;
                    });
                  },
                  onPageChanged: (d) {
                    setState(() => _currentPage = d.newPageNumber);
                    _scrollThumbToPage(d.newPageNumber);
                  },
                ),
                if (_loading)
                  Container(
                    color: Colors.white,
                    child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        CircularProgressIndicator(color: _accentColor),
                        SizedBox(height: 12),
                        Text('Memuat PDF...', style: TextStyle(color: KmColors.of(context).textMuted)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ),

        // ── Thumbnail strip (mirip PPTX) ─────────────────────────────────────
        if (!_loading && _totalPages > 1)
          Container(
            height: 76,
            color: KmColors.of(context).card,
            child: ListView.builder(
              controller: _thumbScroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: _totalPages,
              itemBuilder: (_, i) {
                final page = i + 1;
                final active = _currentPage == page;
                return GestureDetector(
                  onTap: () {
                    _pdfCtrl.jumpToPage(page);
                  },
                  child: Container(
                    width: _thumbWidth,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: active
                          ? _accentColor.withValues(alpha: 0.25)
                          : KmColors.of(context).border,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: active ? _accentColor : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Icon(Icons.description_rounded,
                          color: active ? _accentColor : KmColors.of(context).textMuted,
                          size: 18),
                      const SizedBox(height: 3),
                      Text('$page',
                          style: TextStyle(
                            color: active ? _accentColor : KmColors.of(context).textSub,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          )),
                    ]),
                  ),
                );
              },
            ),
          ),
      ]),

      // ── Bottom navigation bar bergaya PPTX ───────────────────────────────
      bottomNavigationBar: _loading
          ? null
          : Container(
              color: KmColors.of(context).card,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Pertama
                  IconButton(
                    icon: Icon(Icons.first_page_rounded, color: KmColors.of(context).textSub),
                    tooltip: 'Halaman pertama',
                    onPressed: _currentPage > 1
                        ? () => _pdfCtrl.jumpToPage(1)
                        : null,
                  ),
                  // Mundur
                  IconButton(
                    icon: Icon(Icons.navigate_before_rounded, color: KmColors.of(context).text),
                    iconSize: 32,
                    onPressed: _currentPage > 1
                        ? () => _pdfCtrl.previousPage()
                        : null,
                  ),
                  // Indikator tengah
                  GestureDetector(
                    onTap: _showJumpDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: _accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _accentColor.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        '$_currentPage / $_totalPages',
                        style: TextStyle(
                          color: KmColors.of(context).text,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  // Maju
                  IconButton(
                    icon: Icon(Icons.navigate_next_rounded, color: KmColors.of(context).text),
                    iconSize: 32,
                    onPressed: _currentPage < _totalPages
                        ? () => _pdfCtrl.nextPage()
                        : null,
                  ),
                  // Terakhir
                  IconButton(
                    icon: Icon(Icons.last_page_rounded, color: KmColors.of(context).textSub),
                    tooltip: 'Halaman terakhir',
                    onPressed: _currentPage < _totalPages
                        ? () => _pdfCtrl.jumpToPage(_totalPages)
                        : null,
                  ),
                ],
              ),
            ),
    ),
    );
  }

  Future<void> _showJumpDialog() async {
    final ctrl = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KmColors.of(context).card,
        title: Text('Pergi ke Halaman',
            style: TextStyle(color: KmColors.of(context).text, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: TextStyle(color: KmColors.of(context).text),
          decoration: InputDecoration(
            hintText: '1 – $_totalPages',
            hintStyle: TextStyle(color: KmColors.of(context).textMuted),
            enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: _accentColor)),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: _accentColor, width: 2)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Batal', style: TextStyle(color: KmColors.of(context).textSub))),
          TextButton(
            onPressed: () {
              final p = int.tryParse(ctrl.text.trim());
              if (p != null && p >= 1 && p <= _totalPages) {
                Navigator.pop(ctx, p);
              }
            },
            child: const Text('Pergi', style: TextStyle(color: _accentColor)),
          ),
        ],
      ),
    );
    if (result != null) _pdfCtrl.jumpToPage(result);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// AUDIO PLAYER
// ═════════════════════════════════════════════════════════════════════════════
class _AudioPlayerScreen extends StatefulWidget {
  final String title, path;
  const _AudioPlayerScreen({required this.title, required this.path});
  @override
  State<_AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<_AudioPlayerScreen>
    with WidgetsBindingObserver {

  final _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    _player.onPlayerStateChanged.listen((s) { if (mounted) setState(() => _state = s); });
    _player.onPositionChanged.listen((p)  { if (mounted) setState(() => _position = p); });
    _player.onDurationChanged.listen((d)  { if (mounted) setState(() => _duration = d); });
    _player.onPlayerComplete.listen((_)   { if (mounted) setState(() => _position = Duration.zero); });
    await _player.setSourceDeviceFile(widget.path);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Pause audio saat app di background
      if (_state == PlayerState.playing) _player.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _togglePlay() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
    } else {
      if (_position == Duration.zero) await _player.setSourceDeviceFile(widget.path);
      await _player.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _state == PlayerState.playing;
    final maxVal = _duration.inSeconds.toDouble();
    final curVal = _position.inSeconds.toDouble().clamp(0.0, maxVal > 0 ? maxVal : 1.0);

    return ConfirmExitBack(
      message: 'Yakin ingin menutup audio ini?',
      confirmLabel: 'Keluar',
      onBeforeConfirm: () { _player.pause(); },
      child: Scaffold(
      backgroundColor: KmColors.of(context).bg,
      appBar: AppBar(
        backgroundColor: KmColors.of(context).card,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded),
            onPressed: () => Navigator.pop(context)),
        title: Text(widget.title,
            style: TextStyle(color: KmColors.of(context).text, fontSize: 15),
            overflow: TextOverflow.ellipsis),
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // Art
          Container(
            width: 200, height: 200,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [KmColors.of(context).accent, Color(0xFF6C3483)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: KmColors.of(context).accent.withValues(alpha: 0.4),
                  blurRadius: 30, spreadRadius: 5)],
            ),
            child: Center(child: SvgPicture.asset('assets/icons/logo/music-note-thin.svg', width: 80, height: 80, colorFilter: ColorFilter.mode(KmColors.of(context).textMuted, BlendMode.srcIn))),
          ),
          const SizedBox(height: 40),
          Text(widget.title,
              style: TextStyle(color: KmColors.of(context).text,
                  fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 32),
          // Seek
          Column(children: [
            Slider(
              value: curVal, min: 0, max: maxVal > 0 ? maxVal : 1.0,
              onChanged: (v) => _player.seek(Duration(seconds: v.toInt())),
              activeColor: KmColors.of(context).accent,
              inactiveColor: KmColors.of(context).border,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(_fmt(_position), style: TextStyle(color: KmColors.of(context).textMuted, fontSize: 12)),
                Text(_fmt(_duration), style: TextStyle(color: KmColors.of(context).textMuted, fontSize: 12)),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          // Controls
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            IconButton(iconSize: 36,
                icon: Icon(Icons.replay_10_rounded, color: KmColors.of(context).textSub),
                onPressed: () => _player.seek(_position - const Duration(seconds: 10))),
            GestureDetector(
              onTap: _togglePlay,
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [KmColors.of(context).accent, Color(0xFF6C3483)]),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: KmColors.of(context).accent.withValues(alpha: 0.5),
                      blurRadius: 20, spreadRadius: 2)],
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white, size: 40,
                ),
              ),
            ),
            IconButton(iconSize: 36,
                icon: Icon(Icons.forward_30_rounded, color: KmColors.of(context).textSub),
                onPressed: () => _player.seek(_position + const Duration(seconds: 30))),
          ]),
          const SizedBox(height: 24),
          // Speed
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('Kecepatan: ',
                    style: TextStyle(color: KmColors.of(context).textSub, fontSize: 13)),
              ),
              ...[0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((s) {
                final active = _speed == s;
                return GestureDetector(
                  onTap: () async {
                    await _player.setPlaybackRate(s);
                    setState(() => _speed = s);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? KmColors.of(context).accent : KmColors.of(context).card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: active ? KmColors.of(context).accent : KmColors.of(context).border),
                    ),
                    child: Text(s == 1.0 ? '1x' : '${s}x',
                        style: TextStyle(
                            color: active ? Colors.white : KmColors.of(context).textSub,
                            fontSize: 12,
                            fontWeight: active ? FontWeight.bold : FontWeight.normal)),
                  ),
                );
              }),
            ],
          ),
        ]),
      ),
    ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// VIDEO PLAYER — MX Player Style
// ═════════════════════════════════════════════════════════════════════════════
class _VideoPlayerScreen extends StatefulWidget {
  final String title, path;
  const _VideoPlayerScreen({required this.title, required this.path});
  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {

  late VideoPlayerController _ctrl;
  bool _initialized = false;
  bool _showControls = true;
  bool _isFullscreen = false;
  bool _isLocked = false;

  // Speed
  double _speed = 1.0;
  static const _speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  // Zoom/Fit
  bool _fillScreen = false; // fit vs fill mode

  // Gesture drag feedback
  bool _showGestureHint = false;
  String _gestureHintText = '';
  IconData _gestureHintIcon = Icons.volume_up_rounded;

  // Volume & brightness (stored locally — no native API needed)
  double _volume = 1.0;
  double _brightness = 1.0; // visual overlay only

  // Auto-hide controls timer
  DateTime _lastInteraction = DateTime.now();

  // Seek preview
  bool _isSeeking = false;
  double _seekPreviewSeconds = 0;

  // Double-tap seek zones
  bool _showLeftSeek = false;
  bool _showRightSeek = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ctrl = VideoPlayerController.file(File(widget.path))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
          _ctrl.play();
          _startAutoHide();
        }
      });
    _ctrl.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Pause video otomatis saat user switch app / layar terkunci
      if (_ctrl.value.isInitialized && _ctrl.value.isPlaying) {
        _ctrl.pause();
        if (mounted) setState(() {});
      }
    }
    // Saat resume: video TIDAK auto-play ulang — user harus tekan play manual
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resetOrientation();
    _ctrl.dispose();
    super.dispose();
  }

  void _resetOrientation() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // Panggil ini sebelum Navigator.pop agar orientasi/systemUI reset duluan,
  // bukan setelah animasi transisi (yang menyebabkan grey flash)
  void _closeViewer() {
    _ctrl.pause();
    _resetOrientation();
    Navigator.of(context).pop();
  }

  void _startAutoHide() {
    _lastInteraction = DateTime.now();
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (DateTime.now().difference(_lastInteraction).inSeconds >= 3 &&
          _ctrl.value.isPlaying) {
        setState(() => _showControls = false);
      }
      if (_showControls && _ctrl.value.isPlaying) _startAutoHide();
    });
  }

  void _touch() {
    _lastInteraction = DateTime.now();
    if (!_showControls) {
      setState(() => _showControls = true);
      _startAutoHide();
    }
  }

  void _togglePlay() {
    _touch();
    if (_ctrl.value.isPlaying) {
      _ctrl.pause();
    } else {
      _ctrl.play();
      _startAutoHide();
    }
    setState(() {});
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '\$h:\$m:\$s' : '\$m:\$s';
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    } else {
      _resetOrientation();
    }
  }

  void _showGesture(String text, IconData icon, {Duration dur = const Duration(milliseconds: 800)}) {
    setState(() {
      _showGestureHint = true;
      _gestureHintText = text;
      _gestureHintIcon = icon;
    });
    Future.delayed(dur, () {
      if (mounted) setState(() => _showGestureHint = false);
    });
  }

  // Seek ±10s buttons
  void _seekRelative(int secs) {
    final pos = _ctrl.value.position;
    final dur = _ctrl.value.duration;
    final newPos = pos + Duration(seconds: secs);
    _ctrl.seekTo(newPos.isNegative ? Duration.zero : newPos > dur ? dur : newPos);
    if (secs < 0) {
      setState(() { _showLeftSeek = true; });
      Future.delayed(const Duration(milliseconds: 600), () { if (mounted) setState(() => _showLeftSeek = false); });
    } else {
      setState(() { _showRightSeek = true; });
      Future.delayed(const Duration(milliseconds: 600), () { if (mounted) setState(() => _showRightSeek = false); });
    }
    _touch();
  }

  void _cycleSpeed() {
    _touch();
    final idx = _speeds.indexOf(_speed);
    final next = _speeds[(idx + 1) % _speeds.length];
    setState(() => _speed = next);
    _ctrl.setPlaybackSpeed(next);
    _showGesture('${next}x', Icons.speed_rounded);
  }

  void _toggleFill() {
    _touch();
    setState(() => _fillScreen = !_fillScreen);
    _showGesture(_fillScreen ? 'Fill' : 'Fit', Icons.fit_screen_rounded);
  }

  Widget _gestureHintOverlay() {
    return AnimatedOpacity(
      opacity: _showGestureHint ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_gestureHintIcon, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(_gestureHintText,
                style: const TextStyle(color: Colors.white,
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
  }

  Widget _seekFlash(bool show, bool isRight) {
    return AnimatedOpacity(
      opacity: show ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 150),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(isRight ? Icons.forward_10_rounded : Icons.replay_10_rounded,
                color: Colors.white, size: 48),
            Text(isRight ? '+10s' : '-10s',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ]),
        ),
      ),
    );
  }

  Widget _lockButton() {
    return Positioned(
      left: 16,
      top: 0,
      bottom: 0,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        GestureDetector(
          onTap: () => setState(() => _isLocked = !_isLocked),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Icon(
              _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
              color: Colors.white, size: 22,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _topBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 250),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xDE000000), Colors.transparent],
            ),
          ),
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 4,
            left: 4, right: 8, bottom: 16,
          ),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
              onPressed: _closeViewer,
            ),
            Expanded(
              child: Text(widget.title,
                  style: const TextStyle(color: Colors.white, fontSize: 14,
                      fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis),
            ),
            // Speed
            GestureDetector(
              onTap: _cycleSpeed,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _speed != 1.0
                      ? const Color(0xFF1ABC9C).withValues(alpha: 0.9)
                      : Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${_speed}x',
                    style: const TextStyle(color: Colors.white, fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 8),
            // Fit/Fill
            IconButton(
              icon: Icon(_fillScreen ? Icons.crop_free_rounded : Icons.fit_screen_rounded,
                  color: Colors.white, size: 22),
              tooltip: _fillScreen ? 'Fit' : 'Fill',
              onPressed: _toggleFill,
            ),
            // More options
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              color: const Color(0xFF1E1E2E),
              onSelected: (v) {
                _touch();
                if (v == 'loop') {
                  _ctrl.setLooping(!_ctrl.value.isLooping);
                  setState(() {});
                  _showGesture(_ctrl.value.isLooping ? 'Loop ON' : 'Loop OFF', Icons.loop_rounded);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'loop',
                  child: Row(children: [
                    Icon(Icons.loop_rounded,
                        color: _ctrl.value.isLooping ? const Color(0xFF1ABC9C) : Colors.white54,
                        size: 20),
                    const SizedBox(width: 10),
                    Text(_ctrl.value.isLooping ? 'Loop: ON' : 'Loop: OFF',
                        style: const TextStyle(color: Colors.white)),
                  ]),
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final pos = _ctrl.value.position;
    final dur = _ctrl.value.duration;
    final isPlaying = _ctrl.value.isPlaying;
    final durMs = dur.inMilliseconds.toDouble();

    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 250),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xDE000000), Colors.transparent],
            ),
          ),
          padding: EdgeInsets.only(
            bottom: _isFullscreen ? 16 : (MediaQuery.of(context).padding.bottom + 8),
            left: 12, right: 12, top: 16,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Seek bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(children: [
                Text(_isSeeking
                    ? _fmt(Duration(seconds: _seekPreviewSeconds.toInt()))
                    : _fmt(pos),
                    style: const TextStyle(color: Colors.white, fontSize: 11)),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                      activeTrackColor: const Color(0xFF1ABC9C),
                      inactiveTrackColor: Colors.white30,
                      thumbColor: const Color(0xFF1ABC9C),
                      overlayColor: const Color(0x441ABC9C),
                    ),
                    child: Slider(
                      value: _isSeeking
                          ? _seekPreviewSeconds.clamp(0.0, durMs > 0 ? durMs / 1000.0 : 1.0)
                          : (durMs > 0 ? pos.inSeconds.toDouble().clamp(0.0, durMs / 1000.0) : 0.0),
                      min: 0.0,
                      max: durMs > 0 ? durMs / 1000.0 : 1.0,
                      onChangeStart: (v) {
                        _touch();
                        setState(() { _isSeeking = true; _seekPreviewSeconds = v; });
                      },
                      onChanged: (v) {
                        setState(() => _seekPreviewSeconds = v);
                      },
                      onChangeEnd: (v) {
                        _ctrl.seekTo(Duration(seconds: v.toInt()));
                        setState(() => _isSeeking = false);
                      },
                    ),
                  ),
                ),
                Text(_fmt(dur), style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ]),
            ),
            // Buttons row
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              // Volume
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: Icon(_volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      color: Colors.white, size: 22),
                  onPressed: () {
                    _touch();
                    final newVol = _volume > 0 ? 0.0 : 1.0;
                    setState(() => _volume = newVol);
                    _ctrl.setVolume(newVol);
                  },
                ),
                SizedBox(
                  width: 80,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white30,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: _volume,
                      min: 0, max: 1,
                      onChanged: (v) {
                        _touch();
                        setState(() => _volume = v);
                        _ctrl.setVolume(v);
                      },
                    ),
                  ),
                ),
              ]),
              // Playback controls center
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  iconSize: 36,
                  icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
                  onPressed: () => _seekRelative(-10),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: _togglePlay,
                  child: Container(
                    width: 54, height: 54,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1ABC9C).withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white, size: 32,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  iconSize: 36,
                  icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                  onPressed: () => _seekRelative(10),
                ),
              ]),
              // Right controls
              Row(mainAxisSize: MainAxisSize.min, children: [
                // Loop indicator
                if (_ctrl.value.isLooping)
                  const Icon(Icons.loop_rounded, color: Color(0xFF1ABC9C), size: 18),
                IconButton(
                  icon: Icon(
                    _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                    color: Colors.white, size: 26,
                  ),
                  onPressed: _toggleFullscreen,
                ),
              ]),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _ctrl.value.isPlaying;
    final isBuffering = _ctrl.value.isBuffering;
    final hasError = _ctrl.value.hasError;

    Widget videoWidget = _initialized
        ? _fillScreen
            ? SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _ctrl.value.size.width,
                    height: _ctrl.value.size.height,
                    child: VideoPlayer(_ctrl),
                  ),
                ),
              )
            : Center(
                child: AspectRatio(
                  aspectRatio: _ctrl.value.aspectRatio,
                  child: VideoPlayer(_ctrl),
                ),
              )
        : const Center(child: CircularProgressIndicator(color: Color(0xFF1ABC9C)));
    return ConfirmExitBack(
      message: 'Yakin ingin menutup video ini?',
      confirmLabel: 'Keluar',
      onBeforeConfirm: () { _ctrl.pause(); _resetOrientation(); },
      child: Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        // In fullscreen remove safe area
        top: !_isFullscreen,
        bottom: !_isFullscreen,
        child: GestureDetector(
          onTap: () {
            if (_isLocked) return;
            setState(() => _showControls = !_showControls);
            if (_showControls) _startAutoHide();
          },
          // Double tap left/right = seek ±10s
          onDoubleTapDown: (d) {
            if (_isLocked) return;
            final w = MediaQuery.of(context).size.width;
            if (d.localPosition.dx < w * 0.4) {
              _seekRelative(-10);
            } else if (d.localPosition.dx > w * 0.6) {
              _seekRelative(10);
            }
          },
          // Vertical drag for volume (right side) or brightness overlay (left side)
          onVerticalDragUpdate: (d) {
            if (_isLocked) return;
            final w = MediaQuery.of(context).size.width;
            final delta = -d.delta.dy / 200;
            if (d.localPosition.dx > w / 2) {
              // Right side = volume
              final newVol = (_volume + delta).clamp(0.0, 1.0);
              setState(() => _volume = newVol);
              _ctrl.setVolume(newVol);
              final pct = (newVol * 100).round();
              _showGesture('Volume \$pct%',
                  newVol == 0 ? Icons.volume_off_rounded
                      : newVol < 0.5 ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded,
                  dur: const Duration(milliseconds: 400));
            } else {
              // Left side = brightness (visual only)
              final newBri = (_brightness + delta).clamp(0.0, 1.0);
              setState(() => _brightness = newBri);
              final pct = (newBri * 100).round();
              _showGesture('Brightness \$pct%',
                  newBri < 0.33 ? Icons.brightness_low_rounded
                      : newBri < 0.66 ? Icons.brightness_medium_rounded
                      : Icons.brightness_high_rounded,
                  dur: const Duration(milliseconds: 400));
            }
          },
          child: Stack(children: [
            // Video
            SizedBox.expand(child: videoWidget),

            // Brightness overlay (dim screen)
            if (_brightness < 1.0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withValues(alpha: (1.0 - _brightness) * 0.7),
                  ),
                ),
              ),

            // Buffering spinner
            if (isBuffering && _initialized)
              const Center(
                child: CircularProgressIndicator(color: Color(0xFF1ABC9C)),
              ),

            // Error
            if (hasError)
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 8),
                  Text(_ctrl.value.errorDescription ?? 'Error memutar video',
                      style: const TextStyle(color: Colors.white)),
                ]),
              ),

            // Seek flash
            if (_showLeftSeek || _showRightSeek)
              Positioned.fill(
                child: Row(children: [
                  Expanded(child: _seekFlash(_showLeftSeek, false)),
                  Expanded(child: _seekFlash(_showRightSeek, true)),
                ]),
              ),

            // Gesture hint
            _gestureHintOverlay(),

            // Controls (top + bottom)
            if (!_isLocked) ...[ _topBar(), _bottomBar() ],

            // Lock button (always visible when controls shown, or tap anywhere if locked)
            if (_showControls || _isLocked) _lockButton(),

            // End of video overlay
            if (_initialized && !isPlaying && _ctrl.value.position >= _ctrl.value.duration - const Duration(milliseconds: 500))
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  GestureDetector(
                    onTap: () {
                      _ctrl.seekTo(Duration.zero);
                      _ctrl.play();
                      _touch();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.replay_rounded, color: Colors.white, size: 48),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Video selesai', style: TextStyle(color: Colors.white70)),
                ]),
              ),
          ]),
        ),
      ),
    ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TEXT VIEWER
// ═════════════════════════════════════════════════════════════════════════════
class _TextViewerScreen extends StatefulWidget {
  final String title, path;
  const _TextViewerScreen({required this.title, required this.path});
  @override
  State<_TextViewerScreen> createState() => _TextViewerScreenState();
}

class _TextViewerScreenState extends State<_TextViewerScreen> {

  String _content = '';
  bool _loading = true;
  double _fontSize = 15;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final text = await File(widget.path).readAsString();
      if (mounted) setState(() { _content = text; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _content = 'Gagal membaca file: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConfirmExitBack(
      message: 'Yakin ingin menutup file teks ini?',
      confirmLabel: 'Keluar',
      child: Scaffold(
      backgroundColor: KmColors.of(context).bg,
      appBar: AppBar(
        backgroundColor: KmColors.of(context).card,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded),
            onPressed: () => Navigator.pop(context)),
        title: Text(widget.title,
            style: TextStyle(color: KmColors.of(context).text, fontSize: 15),
            overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(icon: Icon(Icons.text_decrease_rounded, color: KmColors.of(context).textSub),
              onPressed: () => setState(() => _fontSize = (_fontSize - 1).clamp(10, 28))),
          IconButton(icon: Icon(Icons.text_increase_rounded, color: KmColors.of(context).textSub),
              onPressed: () => setState(() => _fontSize = (_fontSize + 1).clamp(10, 28))),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: SelectableText(
                  _content,
                  style: TextStyle(color: KmColors.of(context).text,
                      fontSize: _fontSize, height: 1.7, fontFamily: 'monospace'),
                ),
              ),
            ),
    ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PROFILE SCREEN
// ═════════════════════════════════════════════════════════════════════════════
class _DocxViewerScreen extends StatefulWidget {
  final String title, path;
  const _DocxViewerScreen({required this.title, required this.path});
  @override
  State<_DocxViewerScreen> createState() => _DocxViewerScreenState();
}

class _DocxViewerScreenState extends State<_DocxViewerScreen> {

  List<_DocParagraph> _paragraphs = [];
  bool _loading = true;
  String? _error;
  double _fontSize = 15.0;
  final TransformationController _docTransformCtrl = TransformationController();
  bool _docZoomed = false;

  @override
  void initState() {
    super.initState();
    _parse();
    _docTransformCtrl.addListener(() {
      final zoomed = _docTransformCtrl.value.getMaxScaleOnAxis() > 1.01;
      if (zoomed != _docZoomed && mounted) setState(() => _docZoomed = zoomed);
    });
  }

  @override
  void dispose() {
    _docTransformCtrl.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final docFile = archive.findFile('word/document.xml');
      if (docFile == null) throw Exception('Bukan file DOCX yang valid');

      final xmlStr = String.fromCharCodes(docFile.content as List<int>);
      final doc = xmlp.XmlDocument.parse(xmlStr);
      final paras = <_DocParagraph>[];

      for (final p in doc.findAllElements('w:p')) {
        // Cek heading
        String? style;
        final pStyle = p.findElements('w:pPr').firstOrNull
            ?.findElements('w:pStyle').firstOrNull
            ?.getAttribute('w:val');
        if (pStyle != null) style = pStyle;

        // Cek list (numbering)
        final hasNum = p.findElements('w:pPr').firstOrNull
            ?.findElements('w:numPr').isNotEmpty ?? false;

        // Kumpulkan runs
        final spans = <_DocSpan>[];
        for (final r in p.findAllElements('w:r')) {
          final rPr = r.findElements('w:rPr').firstOrNull;
          final bold   = rPr?.findElements('w:b').isNotEmpty ?? false;
          final italic = rPr?.findElements('w:i').isNotEmpty ?? false;
          final szEl   = rPr?.findElements('w:sz').firstOrNull;
          double? fontSize;
          if (szEl != null) {
            final sz = double.tryParse(szEl.getAttribute('w:val') ?? '');
            if (sz != null) fontSize = sz / 2;
          }
          final text = r.findAllElements('w:t').map((e) => e.innerText).join();
          if (text.isNotEmpty) {
            spans.add(_DocSpan(text: text, bold: bold, italic: italic, fontSize: fontSize));
          }
        }
        if (spans.isNotEmpty || p.findAllElements('w:r').isEmpty) {
          paras.add(_DocParagraph(spans: spans, style: style, isList: hasNum));
        }
      }

      if (mounted) setState(() { _paragraphs = paras; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConfirmExitBack(
      message: 'Yakin ingin menutup dokumen ini?',
      confirmLabel: 'Keluar',
      child: Scaffold(
      backgroundColor: KmColors.of(context).bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF2980B9),
        foregroundColor: Colors.white,
        title: Text(widget.title, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_docZoomed)
            IconButton(
              icon: const Icon(Icons.zoom_out_map_rounded, color: Colors.white),
              tooltip: 'Reset Zoom',
              onPressed: () {
                _docTransformCtrl.value = Matrix4.identity();
                setState(() => _docZoomed = false);
              },
            ),
          IconButton(
            icon: const Icon(Icons.text_decrease_rounded, color: Colors.white),
            tooltip: 'Kecilkan teks',
            onPressed: () => setState(() => _fontSize = (_fontSize - 1).clamp(10, 28)),
          ),
          IconButton(
            icon: const Icon(Icons.text_increase_rounded, color: Colors.white),
            tooltip: 'Besarkan teks',
            onPressed: () => setState(() => _fontSize = (_fontSize + 1).clamp(10, 28)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24),
                  child: Text('Gagal membaca file:\n$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red))))
              : InteractiveViewer(
                  transformationController: _docTransformCtrl,
                  minScale: 0.5,
                  maxScale: 5.0,
                  panEnabled: _docZoomed,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  onInteractionEnd: (_) {
                    final scale = _docTransformCtrl.value.getMaxScaleOnAxis();
                    if (scale <= 1.01) {
                      _docTransformCtrl.value = Matrix4.identity();
                      if (_docZoomed) setState(() => _docZoomed = false);
                    }
                  },
                  child: SelectionArea(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(20),
                      physics: _docZoomed
                          ? const NeverScrollableScrollPhysics()
                          : const AlwaysScrollableScrollPhysics(),
                      itemCount: _paragraphs.length,
                      itemBuilder: (_, i) => _buildPara(_paragraphs[i]),
                    ),
                  ),
                ),
    ),
    );
  }

  Widget _buildPara(_DocParagraph para) {
    if (para.spans.isEmpty) return const SizedBox(height: 10);

    final isHeading1 = para.style?.toLowerCase().contains('heading1') == true ||
        para.style?.toLowerCase().contains('1') == true && para.style!.toLowerCase().contains('head');
    final isHeading2 = para.style?.toLowerCase().contains('heading2') == true ||
        para.style?.toLowerCase().contains('2') == true && para.style!.toLowerCase().contains('head');

    final spans = para.spans.map((s) {
      double fontSize = s.fontSize ?? (isHeading1 ? _fontSize + 7 : isHeading2 ? _fontSize + 3 : _fontSize);
      return TextSpan(
        text: s.text,
        style: TextStyle(
          fontWeight: s.bold || isHeading1 || isHeading2
              ? FontWeight.bold : FontWeight.normal,
          fontStyle: s.italic ? FontStyle.italic : FontStyle.normal,
          fontSize: fontSize,
          color: const Color(0xFF1A1A1A),
          height: 1.6,
        ),
      );
    }).toList();

    Widget text = RichText(text: TextSpan(children: spans));

    if (para.isList) {
      text = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('• ', style: TextStyle(fontSize: 15, color: Color(0xFF2980B9),
            fontWeight: FontWeight.bold)),
        Expanded(child: text),
      ]);
    }

    return Padding(
      padding: EdgeInsets.only(
          bottom: isHeading1 ? 12 : isHeading2 ? 8 : 4,
          top: isHeading1 ? 16 : isHeading2 ? 10 : 0,
          left: para.isList ? 8 : 0),
      child: text,
    );
  }
}

class _DocParagraph {
  final List<_DocSpan> spans;
  final String? style;
  final bool isList;
  _DocParagraph({required this.spans, this.style, this.isList = false});
}

class _DocSpan {
  final String text;
  final bool bold, italic;
  final double? fontSize;
  _DocSpan({required this.text, this.bold = false, this.italic = false, this.fontSize});
}

// ─── Model internal untuk data XLSX ──────────────────────────────────────────
class _XlsxSheet {
  final String name;
  final List<List<String>> rows; // rows[i][j] = nilai string cell
  final List<Uint8List> images;
  _XlsxSheet({required this.name, required this.rows, this.images = const []});
}

// ═════════════════════════════════════════════════════════════════════════════
// XLSX VIEWER — Parse sheet via archive + xml (tanpa package excel)
// ═════════════════════════════════════════════════════════════════════════════
class _XlsxViewerScreen extends StatefulWidget {
  final String title, path;
  const _XlsxViewerScreen({required this.title, required this.path});
  @override
  State<_XlsxViewerScreen> createState() => _XlsxViewerScreenState();
}

class _XlsxViewerScreenState extends State<_XlsxViewerScreen>
    with SingleTickerProviderStateMixin {

  List<_XlsxSheet> _sheets = [];
  bool _loading = true;
  String? _error;
  late TabController _tabCtrl;

  // Per-sheet TransformationController untuk zoom
  final Map<int, TransformationController> _sheetTransformCtrls = {};
  final Map<int, bool> _sheetZoomed = {};

  TransformationController _getSheetCtrl(int sheetIndex) {
    return _sheetTransformCtrls.putIfAbsent(sheetIndex, () {
      final ctrl = TransformationController();
      ctrl.addListener(() {
        final zoomed = ctrl.value.getMaxScaleOnAxis() > 1.01;
        if (_sheetZoomed[sheetIndex] != zoomed && mounted) {
          setState(() => _sheetZoomed[sheetIndex] = zoomed);
        }
      });
      return ctrl;
    });
  }

  bool _isSheetZoomed(int idx) => _sheetZoomed[idx] ?? false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 1, vsync: this);
    _parse();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    for (final c in _sheetTransformCtrls.values) { c.dispose(); }
    super.dispose();
  }

  // ── Parse XLSX secara manual via archive + xml ────────────────────────────
  static List<_XlsxSheet> _parseXlsx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    // 1. Shared strings
    final List<String> sharedStrings = [];
    final ssFile = archive.findFile('xl/sharedStrings.xml');
    if (ssFile != null) {
      final doc = xmlp.XmlDocument.parse(
          String.fromCharCodes(ssFile.content as List<int>));
      for (final si in doc.findAllElements('si')) {
        sharedStrings.add(
            si.findAllElements('t').map((e) => e.innerText).join());
      }
    }

    // 2. Workbook — urutan & nama sheet
    final List<({String name, String rId})> sheetMeta = [];
    final wbFile = archive.findFile('xl/workbook.xml');
    if (wbFile != null) {
      final doc = xmlp.XmlDocument.parse(
          String.fromCharCodes(wbFile.content as List<int>));
      for (final s in doc.findAllElements('sheet')) {
        sheetMeta.add((
          name: s.getAttribute('name') ?? 'Sheet',
          rId : s.getAttribute('r:id') ?? '',
        ));
      }
    }

    // 3. Relasi workbook → path file sheet
    final Map<String, String> rIdToPath = {};
    final relsFile = archive.findFile('xl/_rels/workbook.xml.rels');
    if (relsFile != null) {
      final doc = xmlp.XmlDocument.parse(
          String.fromCharCodes(relsFile.content as List<int>));
      for (final rel in doc.findAllElements('Relationship')) {
        final id     = rel.getAttribute('Id') ?? '';
        final target = rel.getAttribute('Target') ?? '';
        rIdToPath[id] = target.startsWith('/xl/')
            ? target.substring(1)
            : 'xl/$target';
      }
    }

    // 4. Daftar path sheet (urut sesuai workbook, atau scan ZIP jika tidak ada)
    final List<({String path, String name})> sheetEntries;
    if (sheetMeta.isNotEmpty) {
      sheetEntries = sheetMeta
          .map((m) => (path: rIdToPath[m.rId] ?? '', name: m.name))
          .where((e) => e.path.isNotEmpty)
          .toList();
    } else {
      final fallback = archive.files
          .where((f) =>
              f.name.startsWith('xl/worksheets/sheet') &&
              f.name.endsWith('.xml'))
          .map((f) => (path: f.name, name: f.name.split('/').last.replaceAll('.xml', '')))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      sheetEntries = fallback;
    }

    // 5. Kumpulkan media gambar
    const imgExts = {'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'};
    final Map<String, Uint8List> allMedia = {};
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final n = f.name.toLowerCase();
      if (!n.startsWith('xl/media/')) continue;
      final ext = n.split('.').last;
      if (!imgExts.contains(ext)) continue;
      allMedia[f.name.toLowerCase()] =
          Uint8List.fromList(f.content as List<int>);
    }

    // 6. Parse setiap sheet
    final List<_XlsxSheet> result = [];
    for (final entry in sheetEntries) {
      final sheetFile = archive.findFile(entry.path);
      if (sheetFile == null) continue;

      final doc = xmlp.XmlDocument.parse(
          String.fromCharCodes(sheetFile.content as List<int>));
      final rows = <List<String>>[];

      for (final row in doc.findAllElements('row')) {
        final cells = <String>[];
        for (final c in row.findAllElements('c')) {
          final t = c.getAttribute('t');
          final v = c.findElements('v').firstOrNull?.innerText ??
              c.findElements('is').firstOrNull
                  ?.findAllElements('t')
                  .map((e) => e.innerText)
                  .join() ??
              '';
          String val;
          if (t == 's') {
            final idx = int.tryParse(v) ?? -1;
            val = (idx >= 0 && idx < sharedStrings.length)
                ? sharedStrings[idx]
                : '';
          } else if (t == 'inlineStr') {
            val = c.findAllElements('t').map((e) => e.innerText).join();
          } else if (t == 'b') {
            val = v == '1' ? 'TRUE' : 'FALSE';
          } else {
            val = v;
          }
          cells.add(val);
        }
        if (cells.any((c) => c.isNotEmpty)) rows.add(cells);
      }

      // Gambar via _rels sheet
      final sheetFileName = entry.path.split('/').last;
      final sheetRelsPath = 'xl/worksheets/_rels/$sheetFileName.rels';
      final sheetRelsFile = archive.findFile(sheetRelsPath);
      final List<Uint8List> images = [];
      if (sheetRelsFile != null && allMedia.isNotEmpty) {
        final rDoc = xmlp.XmlDocument.parse(
            String.fromCharCodes(sheetRelsFile.content as List<int>));
        for (final rel in rDoc.findAllElements('Relationship')) {
          final target = rel.getAttribute('Target') ?? '';
          if (!target.contains('../media/')) continue;
          final fname = target.replaceFirst('../media/', '');
          final key   = 'xl/media/$fname'.toLowerCase();
          final found = allMedia[key];
          if (found != null) images.add(found);
        }
      }

      result.add(_XlsxSheet(name: entry.name, rows: rows, images: images));
    }
    return result;
  }

  Future<void> _parse() async {
    try {
      final rawBytes = await File(widget.path).readAsBytes();
      final sheets = await compute(_parseXlsx, rawBytes);
      if (mounted) {
        setState(() {
          _sheets  = sheets;
          _loading = false;
          _tabCtrl = TabController(
            length: sheets.isNotEmpty ? sheets.length : 1,
            vsync: this,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error   = 'Gagal membaca file XLSX: ${e.toString().split(".").first}';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConfirmExitBack(
      message: 'Yakin ingin menutup spreadsheet ini?',
      confirmLabel: 'Keluar',
      child: Scaffold(
      backgroundColor: KmColors.of(context).bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF27AE60),
        foregroundColor: Colors.white,
        title: Text(widget.title, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_sheets.isNotEmpty &&
              _tabCtrl.index < _sheets.length &&
              _isSheetZoomed(_tabCtrl.index))
            IconButton(
              icon: const Icon(Icons.zoom_out_map_rounded, color: Colors.white),
              tooltip: 'Reset Zoom',
              onPressed: () {
                final idx = _tabCtrl.index;
                _sheetTransformCtrls[idx]?.value = Matrix4.identity();
                setState(() => _sheetZoomed[idx] = false);
              },
            ),
        ],
        bottom: _sheets.isEmpty ? null : TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: KmColors.of(context).textSub,
          indicatorColor: Colors.white,
          tabs: _sheets.map((s) => Tab(text: s.name)).toList(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24),
                  child: Text('Gagal membaca file:\n$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red))))
              : _sheets.isEmpty
                  ? Center(child: Text('Tidak ada data',
                        style: TextStyle(color: KmColors.of(context).textSub)))
                  : TabBarView(
                      controller: _tabCtrl,
                      physics: const NeverScrollableScrollPhysics(),
                      children: _sheets.asMap().entries
                          .map((e) => _buildSheet(e.value, e.key))
                          .toList(),
                    ),
    ),
    );
  }

  Widget _buildSheet(_XlsxSheet sheet, int sheetIndex) {
    final dataRows   = sheet.rows;
    final images     = sheet.images;

    if (dataRows.isEmpty && images.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.table_chart_outlined, size: 48, color: KmColors.of(context).textMuted),
            const SizedBox(height: 12),
            Text('Sheet kosong',
                style: TextStyle(color: KmColors.of(context).textMuted)),
          ],
        ),
      );
    }

    final colCount = dataRows.isEmpty
        ? 0
        : dataRows.map((r) => r.length).fold(0, (a, b) => a > b ? a : b);

    final headerRow     = dataRows.isNotEmpty ? dataRows.first : <String>[];
    final transformCtrl = _getSheetCtrl(sheetIndex);
    final zoomed        = _isSheetZoomed(sheetIndex);

    return Stack(
      children: [
        SingleChildScrollView(
          physics: zoomed
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Tabel data ───────────────────────────────────────────────
              if (colCount > 0)
                InteractiveViewer(
                  transformationController: transformCtrl,
                  minScale: 0.5,
                  maxScale: 5.0,
                  panEnabled: zoomed,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  onInteractionEnd: (_) {
                    final scale = transformCtrl.value.getMaxScaleOnAxis();
                    if (scale <= 1.01) {
                      transformCtrl.value = Matrix4.identity();
                      if (zoomed) setState(() => _sheetZoomed[sheetIndex] = false);
                    }
                  },
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: zoomed
                        ? const NeverScrollableScrollPhysics()
                        : const AlwaysScrollableScrollPhysics(),
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.resolveWith((_) =>
                          const Color(0xFF1E8449).withValues(alpha: 0.18)),
                      border: TableBorder.all(
                          color: const Color(0xFFAED6F1), width: 0.5),
                      columnSpacing: 16,
                      headingRowHeight: 42,
                      dataRowMinHeight: 36,
                      dataRowMaxHeight: 56,
                      columns: List.generate(colCount, (i) {
                        final label = i < headerRow.length ? headerRow[i] : '';
                        return DataColumn(
                          label: Text(
                            label.isEmpty ? 'Kolom ${i + 1}' : label,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF1E8449),
                            ),
                          ),
                        );
                      }),
                      rows: dataRows.skip(1).toList().asMap().entries.map((rowEntry) {
                        final rowIdx = rowEntry.key;
                        final row    = rowEntry.value;
                        return DataRow(
                          color: WidgetStateProperty.resolveWith((_) {
                            final isDark =
                                Theme.of(context).brightness == Brightness.dark;
                            if (rowIdx % 2 == 0) return null;
                            return isDark
                                ? Colors.white.withValues(alpha: 0.04)
                                : Colors.black.withValues(alpha: 0.03);
                          }),
                          cells: List.generate(colCount, (i) {
                            final val = i < row.length ? row[i] : '';
                            return DataCell(
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 200),
                                child: Text(
                                  val,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                              ),
                            );
                          }),
                        );
                      }).toList(),
                    ),
                  ),
                ),

              // ── Gambar yang dilampirkan di sheet ini ─────────────────────
              if (images.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(children: [
                    const Icon(Icons.image_outlined,
                        size: 16, color: Color(0xFF27AE60)),
                    const SizedBox(width: 6),
                    Text(
                      'Gambar (${images.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1E8449),
                      ),
                    ),
                  ]),
                ),
                ...images.map((imgBytes) => Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 8.0,
                      boundaryMargin: const EdgeInsets.all(20),
                      child: Image.memory(
                        imgBytes,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Container(
                          height: 80,
                          alignment: Alignment.center,
                          color: const Color(0xFFECF0F1),
                          child: const Text(
                              'Gambar tidak dapat ditampilkan',
                              style: TextStyle(
                                  color: Color(0xFF888888), fontSize: 12)),
                        ),
                      ),
                    ),
                  ),
                )),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),

        // Reset zoom overlay
        if (zoomed)
          Positioned(
            top: 8, right: 8,
            child: GestureDetector(
              onTap: () {
                transformCtrl.value = Matrix4.identity();
                setState(() => _sheetZoomed[sheetIndex] = false);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF27AE60).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.zoom_out_map_rounded,
                      color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text('Reset Zoom',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PPTX VIEWER — Parse setiap slide dari ppt/slides/slideN.xml
// ═════════════════════════════════════════════════════════════════════════════
class _PptxViewerScreen extends StatefulWidget {
  final String title, path;
  const _PptxViewerScreen({required this.title, required this.path});
  @override
  State<_PptxViewerScreen> createState() => _PptxViewerScreenState();
}

class _PptxViewerScreenState extends State<_PptxViewerScreen> {

  List<_PptSlide> _slides = [];
  bool _loading = true;
  String? _error;
  int _current = 0;
  final PageController _pageCtrl = PageController();

  // Zoom: satu TransformationController per slide agar state zoom tidak hilang
  // saat slide berubah. Juga track apakah sedang zoom agar PageView tidak scroll.
  final Map<int, TransformationController> _transformControllers = {};
  bool _isZoomed = false;

  TransformationController _getTransformCtrl(int index) {
    return _transformControllers.putIfAbsent(index, () {
      final ctrl = TransformationController();
      ctrl.addListener(() {
        // Cek apakah scale != 1.0 (sedang zoom)
        final scale = ctrl.value.getMaxScaleOnAxis();
        final zoomed = scale > 1.01;
        if (zoomed != _isZoomed && mounted) setState(() => _isZoomed = zoomed);
      });
      return ctrl;
    });
  }

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    for (final c in _transformControllers.values) { c.dispose(); }
    super.dispose();
  }

  // ── Helper: ekstrak teks dari node apapun secara rekursif ──────────────────
  static List<String> _extractTexts(xmlp.XmlNode node) {
    // Gunakan localName bukan qualified name agar tidak gagal karena prefix berbeda
    return node
        .findAllElements('t', namespace: '*')
        .map((e) => e.innerText.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  static String _shapeText(xmlp.XmlElement sp) {
    // Gabungkan teks per paragraf dengan newline
    final paras = sp.findAllElements('p', namespace: '*')
        .where((e) => e.localName == 'p')
        .map((para) {
          final runs = para.findAllElements('t', namespace: '*')
              .map((e) => e.innerText)
              .join();
          return runs.trim();
        })
        .where((t) => t.isNotEmpty)
        .toList();
    return paras.join('\n');
  }

  Future<void> _parse() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // ── 1. Collect semua media (gambar + audio) dari ppt/media/ ──────────
      final imageExts = {'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'};
      final audioExts = {'mp3', 'wav', 'aac', 'm4a', 'ogg', 'wma'};

      // mediaId → (bytes, ext, name)  key: filename tanpa path
      final mediaMap = <String, ArchiveFile>{};
      for (final f in archive.files) {
        if (f.name.toLowerCase().startsWith('ppt/media/')) {
          final fname = f.name.split('/').last;
          mediaMap[fname.toLowerCase()] = f;
        }
      }

      // ── 2. Parse _rels setiap slide untuk mapping rId → target media ──────
      // Build map: slideN.xml → { rId → filename }
      final slideRels = <String, Map<String, String>>{};
      for (final f in archive.files) {
        final n = f.name.toLowerCase();
        if (n.startsWith('ppt/slides/_rels/slide') && n.endsWith('.xml.rels')) {
          final rawBytes = f.content as List<int>;
          final xmlStr = String.fromCharCodes(rawBytes);
          try {
            final doc = xmlp.XmlDocument.parse(xmlStr);
            final rels = <String, String>{};
            for (final rel in doc.findAllElements('Relationship')) {
              final id = rel.getAttribute('Id') ?? '';
              final target = rel.getAttribute('Target') ?? '';
              // target: ../media/image1.png → basename
              final tname = target.split('/').last.toLowerCase();
              rels[id] = tname;
            }
            // key: slide filename e.g. slide1.xml
            final slideName = f.name
                .replaceAll('ppt/slides/_rels/', '')
                .replaceAll('.rels', '')
                .toLowerCase();
            slideRels[slideName] = rels;
          } catch (_) {}
        }
      }

      // ── 3. Cari semua slide files, urutkan ────────────────────────────────
      final slideFiles = archive.files
          .where((f) => f.name.startsWith('ppt/slides/slide') &&
              f.name.endsWith('.xml') &&
              !f.name.contains('_rels'))
          .toList()
        ..sort((a, b) {
          final na = int.tryParse(
              RegExp(r'slide(\d+)').firstMatch(a.name)?.group(1) ?? '0') ?? 0;
          final nb = int.tryParse(
              RegExp(r'slide(\d+)').firstMatch(b.name)?.group(1) ?? '0') ?? 0;
          return na.compareTo(nb);
        });

      final slides = <_PptSlide>[];
      for (final file in slideFiles) {
        final rawBytes = file.content as List<int>;
        final xmlStr = String.fromCharCodes(rawBytes);
        final doc = xmlp.XmlDocument.parse(xmlStr);

        String titleText = '';
        final bodyParts = <String>[];

        final allShapes = doc.findAllElements('sp', namespace: '*')
            .where((e) => e.localName == 'sp')
            .toList();

        for (final sp in allShapes) {
          final phEls = sp.findAllElements('ph', namespace: '*')
              .where((e) => e.localName == 'ph');
          final phType = phEls.firstOrNull?.getAttribute('type') ?? '';
          final isTitle = phType == 'title' || phType == 'ctrTitle' ||
              phType.isEmpty && titleText.isEmpty && phEls.isNotEmpty;

          final text = _shapeText(sp);
          if (text.isEmpty) continue;

          if (isTitle && titleText.isEmpty) {
            titleText = text;
          } else {
            bodyParts.add(text);
          }
        }

        if (titleText.isEmpty && bodyParts.isEmpty) {
          final allTexts = _extractTexts(doc);
          if (allTexts.isNotEmpty) {
            titleText = allTexts.first;
            if (allTexts.length > 1) {
              bodyParts.addAll(allTexts.skip(1));
            }
          }
        } else if (titleText.isEmpty && bodyParts.isNotEmpty) {
          titleText = bodyParts.removeAt(0);
        }

        // ── 4. Ambil media milik slide ini via _rels ────────────────────────
        final slideFname = file.name.split('/').last.toLowerCase(); // e.g. slide1.xml
        final rels = slideRels[slideFname] ?? {};

        // Kumpulkan rId dari blip (gambar) dan audio di XML slide
        final slideImages = <Uint8List>[];
        final slideAudio = <_PptAudio>[];

        // Gambar: <a:blip r:embed="rId...">
        for (final blip in doc.findAllElements('blip', namespace: '*')) {
          final rId = blip.getAttribute('r:embed') ??
              blip.getAttribute('embed') ?? '';
          if (rId.isEmpty) continue;
          final fname = rels[rId];
          if (fname == null) continue;
          final ext = fname.split('.').last;
          if (!imageExts.contains(ext)) continue;
          final mf = mediaMap[fname];
          if (mf == null) continue;
          slideImages.add(Uint8List.fromList(mf.content as List<int>));
        }

        // Audio: <p:audio>, <p:snd> dll dengan r:link / r:embed
        for (final sndTag in ['snd', 'sndFile', 'extLst']) {
          for (final el in doc.findAllElements(sndTag, namespace: '*')) {
            final rId = el.getAttribute('r:embed') ??
                el.getAttribute('r:link') ?? '';
            if (rId.isEmpty) continue;
            final fname = rels[rId];
            if (fname == null) continue;
            final ext = fname.split('.').last;
            if (!audioExts.contains(ext)) continue;
            final mf = mediaMap[fname];
            if (mf == null) continue;
            slideAudio.add(_PptAudio(
              name: mf.name.split('/').last,
              bytes: Uint8List.fromList(mf.content as List<int>),
              ext: ext,
            ));
          }
        }

        // Juga scan <a:audioFile>, <p:audio> level atas
        for (final el in doc.findAllElements('audioFile', namespace: '*')) {
          final rId = el.getAttribute('r:link') ??
              el.getAttribute('r:embed') ?? '';
          if (rId.isEmpty) continue;
          final fname = rels[rId];
          if (fname == null) continue;
          final ext = fname.split('.').last;
          if (!audioExts.contains(ext)) continue;
          final mf = mediaMap[fname];
          if (mf == null) continue;
          // Cegah duplikat
          if (slideAudio.any((a) => a.name == mf.name.split('/').last)) continue;
          slideAudio.add(_PptAudio(
            name: mf.name.split('/').last,
            bytes: Uint8List.fromList(mf.content as List<int>),
            ext: ext,
          ));
        }

        slides.add(_PptSlide(
          number: slides.length + 1,
          title: titleText,
          body: bodyParts.join('\n\n'),
          rawTexts: _extractTexts(doc),
          images: slideImages,
          audioFiles: slideAudio,
        ));
      }

      if (mounted) setState(() { _slides = slides; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConfirmExitBack(
      message: 'Yakin ingin menutup presentasi ini?',
      confirmLabel: 'Keluar',
      child: Scaffold(
        backgroundColor: KmColors.of(context).bg,
        appBar: AppBar(
          foregroundColor: Colors.white,
          backgroundColor: const Color(0xFFE67E22),
          title: Text(widget.title, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            // Reset zoom button — muncul saat sedang zoom
            if (_isZoomed)
              IconButton(
                icon: const Icon(Icons.zoom_out_map_rounded),
                tooltip: 'Reset Zoom',
                onPressed: () {
                  _transformControllers[_current]?.value = Matrix4.identity();
                  setState(() => _isZoomed = false);
                },
              ),
            if (_slides.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: Text(
                  '${_current + 1} / ${_slides.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                )),
              ),
          ],
        ),
        body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24),
                  child: Text('Gagal membaca file:\n$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red))))
              : _slides.isEmpty
                  ? Center(child: Text('Tidak ada slide',
                      style: TextStyle(color: KmColors.of(context).textSub)))
                  : Column(children: [
                      // Slide viewer
                      // physics: NeverScrollableScrollPhysics saat zoom aktif
                      // agar pinch-to-zoom tidak konflik dengan swipe PageView
                      Expanded(
                        child: PageView.builder(
                          controller: _pageCtrl,
                          physics: _isZoomed
                              ? const NeverScrollableScrollPhysics()
                              : const PageScrollPhysics(),
                          itemCount: _slides.length,
                          onPageChanged: (i) {
                            setState(() => _current = i);
                            // Reset zoom slide sebelumnya saat pindah slide
                            final prev = i > 0 ? i - 1 : (i < _slides.length - 1 ? i + 1 : -1);
                            if (prev >= 0 && _transformControllers.containsKey(prev)) {
                              _transformControllers[prev]!.value = Matrix4.identity();
                            }
                          },
                          itemBuilder: (_, i) => _buildSlide(_slides[i], i),
                        ),
                      ),
                      // Thumbnail bar
                      Container(
                        height: 80,
                        color: KmColors.of(context).card,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          itemCount: _slides.length,
                          itemBuilder: (_, i) => GestureDetector(
                            onTap: () {
                              _pageCtrl.animateToPage(i,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut);
                            },
                            child: Container(
                              width: 100,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: i == _current
                                    ? const Color(0xFFE67E22).withValues(alpha: 0.3)
                                    : KmColors.of(context).border,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: i == _current
                                      ? const Color(0xFFE67E22)
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('${i + 1}',
                                      style: TextStyle(
                                        color: i == _current
                                            ? const Color(0xFFE67E22)
                                            : KmColors.of(context).textSub,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      )),
                                  const SizedBox(height: 2),
                                  Text(
                                    _slides[i].title.isNotEmpty
                                        ? _slides[i].title
                                        : 'Slide ${i + 1}',
                                    style: TextStyle(
                                        color: KmColors.of(context).textMuted, fontSize: 9),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ]),
      bottomNavigationBar: _slides.isEmpty ? null : Container(
        color: KmColors.of(context).card,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(
            icon: Icon(Icons.navigate_before_rounded, color: KmColors.of(context).text),
            onPressed: _current > 0
                ? () => _pageCtrl.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut)
                : null,
          ),
          Text('Slide ${_current + 1} dari ${_slides.length}',
              style: TextStyle(color: KmColors.of(context).textSub, fontSize: 13)),
          IconButton(
            icon: Icon(Icons.navigate_next_rounded, color: KmColors.of(context).text),
            onPressed: _current < _slides.length - 1
                ? () => _pageCtrl.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut)
                : null,
          ),
        ]),
      ),
    ),
    );
  }

  Widget _buildSlide(_PptSlide slide, [int index = 0]) {
    final transformCtrl = _getTransformCtrl(index);
    // InteractiveViewer dengan TransformationController per-slide
    // Ini mencegah konflik dengan PageView swipe horizontal
    return InteractiveViewer(
      transformationController: transformCtrl,
      minScale: 0.8,
      maxScale: 5.0,
      panEnabled: _isZoomed,        // pan hanya aktif saat sudah zoom
      scaleEnabled: true,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      onInteractionStart: (_) {
        if (!_isZoomed) setState(() {});
      },
      onInteractionEnd: (_) {
        // Jika kembali ke scale 1, reset flag
        final scale = transformCtrl.value.getMaxScaleOnAxis();
        if (scale <= 1.01) {
          transformCtrl.value = Matrix4.identity();
          if (_isZoomed) setState(() => _isZoomed = false);
        }
      },
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: KmColors.of(context).bg.withValues(alpha: 0.4),
                blurRadius: 20, spreadRadius: 2),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header slide
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFE67E22), Color(0xFFD35400)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('Slide ${slide.number}',
                          style: TextStyle(
                              color: KmColors.of(context).textSub, fontSize: 11,
                              fontWeight: FontWeight.w500)),
                      const Spacer(),
                      // Petunjuk zoom
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: KmColors.of(context).text.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.pinch_rounded, color: KmColors.of(context).textSub, size: 12),
                          const SizedBox(width: 3),
                          Text('Cubit untuk zoom',
                              style: TextStyle(color: KmColors.of(context).textSub, fontSize: 9)),
                        ]),
                      ),
                    ]),
                    if (slide.title.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(slide.title,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 20,
                              fontWeight: FontWeight.bold, height: 1.3)),
                    ],
                  ],
                ),
              ),
              // Body slide
              Expanded(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Teks body
                      if (slide.body.isNotEmpty)
                        SelectionArea(
                          child: Text(slide.body,
                              style: const TextStyle(
                                  fontSize: 15, height: 1.7,
                                  color: Color(0xFF1A1A1A))))
                      else if (slide.images.isEmpty && slide.audioFiles.isEmpty)
                        Center(
                            child: Text('(Tidak ada teks)',
                                style: TextStyle(color: KmColors.of(context).textMuted, fontSize: 14))),

                      // Gambar-gambar
                      if (slide.images.isNotEmpty) ...[
                        if (slide.body.isNotEmpty) const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        Row(children: const [
                          Icon(Icons.image_outlined, size: 14, color: Color(0xFFE67E22)),
                          SizedBox(width: 4),
                          Text('Gambar', style: TextStyle(color: Color(0xFFE67E22),
                              fontSize: 11, fontWeight: FontWeight.w600)),
                        ]),
                        const SizedBox(height: 8),
                        for (final imgBytes in slide.images) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(imgBytes, fit: BoxFit.contain),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],

                      // Audio player
                      if (slide.audioFiles.isNotEmpty) ...[
                        if (slide.body.isNotEmpty || slide.images.isNotEmpty)
                          const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        Row(children: const [
                          Icon(Icons.audiotrack_rounded, size: 14, color: Color(0xFFE67E22)),
                          SizedBox(width: 4),
                          Text('Audio', style: TextStyle(color: Color(0xFFE67E22),
                              fontSize: 11, fontWeight: FontWeight.w600)),
                        ]),
                        const SizedBox(height: 8),
                        for (final audio in slide.audioFiles)
                          _PptAudioPlayer(audio: audio),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── PPTX Audio Player Widget ────────────────────────────────────────────────
class _PptAudioPlayer extends StatefulWidget {
  final _PptAudio audio;
  const _PptAudioPlayer({required this.audio});
  @override
  State<_PptAudioPlayer> createState() => _PptAudioPlayerState();
}

class _PptAudioPlayerState extends State<_PptAudioPlayer> {

  late final AudioPlayer _player;
  bool _playing = false;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _pos = p);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _dur = d);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() { _playing = false; _pos = Duration.zero; });
    });
  }

  @override
  void dispose() { _player.dispose(); super.dispose(); }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else {
      if (_pos == Duration.zero) {
        await _player.play(BytesSource(widget.audio.bytes));
      } else {
        await _player.resume();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _dur.inMilliseconds > 0
        ? _pos.inMilliseconds / _dur.inMilliseconds : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE67E22).withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: _toggle,
          child: Container(
            width: 36, height: 36,
            decoration: const BoxDecoration(
                color: Color(0xFFE67E22), shape: BoxShape.circle),
            child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white, size: 20),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.audio.name,
                style: const TextStyle(fontSize: 11, color: Color(0xFF6D4C41)),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: const Color(0xFFFFCCBC),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFE67E22)),
                minHeight: 4,
              ),
            ),
          ],
        )),
        const SizedBox(width: 8),
        Text('${_fmt(_pos)} / ${_fmt(_dur)}',
            style: const TextStyle(fontSize: 10, color: Color(0xFF6D4C41))),
      ]),
    );
  }
}

class _PptAudio {
  final String name;
  final Uint8List bytes;
  final String ext;
  const _PptAudio({required this.name, required this.bytes, required this.ext});
}

class _PptSlide {
  final int number;
  final String title, body;
  final List<String> rawTexts;
  final List<Uint8List> images;
  final List<_PptAudio> audioFiles;
  _PptSlide({required this.number, required this.title,
      required this.body, required this.rawTexts,
      this.images = const [], this.audioFiles = const []});
}
