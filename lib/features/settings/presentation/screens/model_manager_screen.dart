// lib/features/settings/presentation/screens/model_manager_screen.dart
// KanMon GO — Model Manager Screen (Arsitektur PocketPal)
//
// Layar pengelolaan model AI offline dengan 3 tab:
//   1. Model Lokal  — daftar model yang sudah ada di perangkat
//   2. Jelajahi     — browse & search HuggingFace, download model
//   3. Unduhan      — progress download aktif dan riwayat
//
// Menggunakan: KmColors, ConfirmExitBack, ConsumerStatefulWidget (Riverpod)

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:kanmongo/core/ai/llama_context.dart';
import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/data/services/llama_service.dart';
import 'package:kanmongo/data/services/model_manager_service.dart';
import 'package:kanmongo/data/services/permission_service.dart';
import 'package:kanmongo/shared/widgets/back_handler.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN UTAMA
// ─────────────────────────────────────────────────────────────────────────────

class ModelManagerScreen extends ConsumerStatefulWidget {
  const ModelManagerScreen({super.key});

  @override
  ConsumerState<ModelManagerScreen> createState() => _ModelManagerScreenState();
}

class _ModelManagerScreenState extends ConsumerState<ModelManagerScreen>
    with SingleTickerProviderStateMixin {

  // ── Controller ─────────────────────────────────────────────────────────────
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  // ── State Lokal ────────────────────────────────────────────────────────────

  /// Daftar model lokal dari service
  List<LocalModelInfo> _localModels = [];

  /// Hasil pencarian HuggingFace (null = belum search, gunakan featured)
  List<HuggingFaceModel>? _searchResults;

  /// Daftar task download aktif
  List<DownloadTask> _downloads = [];

  /// Apakah sedang loading hasil pencarian
  bool _isSearching = false;

  /// Filter ukuran model: 'all', 'light', 'balanced', 'full'
  String _sizeFilter = 'all';

  /// RAM tersedia dalam MB (diperbarui saat init)
  int _availableRamMb = 0;

  /// Apakah sedang proses import file
  bool _isImporting = false;

  /// Progress import file (0.0 – 1.0). -1.0 berarti belum diketahui / indeterminate.
  double _importProgress = -1.0;

  // ── Timer RAM realtime ─────────────────────────────────────────────────────
  Timer? _ramTimer;

  // ── Subscriptions ──────────────────────────────────────────────────────────
  StreamSubscription<List<LocalModelInfo>>? _localModelsSub;
  StreamSubscription<List<DownloadTask>>? _downloadsSub;

  // ── Service Reference ──────────────────────────────────────────────────────
  final ModelManagerService _service = ModelManagerService.instance;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 3, vsync: this);

    // Subscribe ke perubahan data dari service
    _localModelsSub = _service.localModelsStream.listen((models) {
      if (mounted) setState(() => _localModels = models);
    });

    _downloadsSub = _service.downloadsStream.listen((downloads) {
      if (mounted) setState(() => _downloads = downloads);
    });

    // Muat data awal
    _initData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    _ramTimer?.cancel();
    _localModelsSub?.cancel();
    _downloadsSub?.cancel();
    super.dispose();
  }

  /// Inisialisasi data: muat model lokal dan cek RAM tersedia secara periodik
  Future<void> _initData() async {
    await _service.initialize();
    final ram = await _service.getAvailableRamMb();
    if (mounted) {
      setState(() {
        _localModels    = _service.localModels;
        _downloads      = _service.activeDownloads;
        _availableRamMb = ram;
      });
    }

    // Refresh RAM setiap 3 detik secara realtime
    _ramTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      final updatedRam = await _service.getAvailableRamMb();
      if (mounted && updatedRam != _availableRamMb) {
        setState(() => _availableRamMb = updatedRam);
      }
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);

    return ConfirmExitBack(
      title  : 'Keluar Model Manager?',
      message: 'Download yang sedang berjalan akan terhenti.',
      child  : Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          backgroundColor: c.bg,
          elevation      : 0,
          leading        : IconButton(
            icon : Icon(Icons.arrow_back_rounded, color: c.text),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Model Manager',
            style: TextStyle(
              color     : c.text,
              fontWeight: FontWeight.bold,
              fontSize  : 18,
            ),
          ),
          bottom: TabBar(
            controller      : _tabController,
            indicatorColor  : c.accent,
            indicatorWeight : 2.5,
            labelColor      : c.accent,
            unselectedLabelColor: c.textSub,
            labelStyle      : const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize  : 13,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize  : 13,
            ),
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.storage_rounded, size: 16),
                    const SizedBox(width: 6),
                    const Text('Model Lokal'),
                    if (_localModels.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _CountBadge(count: _localModels.length, color: c.accent),
                    ],
                  ],
                ),
              ),
              const Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.explore_rounded, size: 16),
                    SizedBox(width: 6),
                    Text('Jelajahi'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.download_rounded, size: 16),
                    const SizedBox(width: 6),
                    const Text('Unduhan'),
                    if (_downloads.where((d) =>
                        d.status == DownloadStatus.downloading ||
                        d.status == DownloadStatus.queued).isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _CountBadge(
                        count: _downloads.where((d) =>
                          d.status == DownloadStatus.downloading ||
                          d.status == DownloadStatus.queued).length,
                        color: c.info,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children  : [
            _LocalModelsTab(
              models          : _localModels,
              availableRamMb  : _availableRamMb,
              isImporting     : _isImporting,
              importProgress  : _importProgress,
              onRefresh       : () => _service.scanLocalModels(),
              onLoadModel     : _loadModel,
              onDeleteModel   : _confirmDeleteModel,
              onImportModel   : _importModel,
            ),
            _BrowseTab(
              featuredModels  : _service.featuredModels,
              searchResults   : _searchResults,
              searchController: _searchController,
              isSearching     : _isSearching,
              sizeFilter      : _sizeFilter,
              localModels     : _localModels,
              onSizeFilter    : (filter) => setState(() => _sizeFilter = filter),
              onSearch        : _onSearchChanged,
              onDownload      : _startDownload,
            ),
            _DownloadsTab(
              downloads: _downloads,
              onPause  : (id) => _service.pauseDownload(id),
              onResume : (id) => _service.resumeDownload(id),
              onCancel : (id) => _confirmCancelDownload(id),
            ),
          ],
        ),
      ),
    );
  }

  // ── Aksi: Model Lokal ──────────────────────────────────────────────────────

  /// Muat model ke LlamaService
  Future<void> _loadModel(LocalModelInfo model) async {
    final c = KmColors.of(context);

    // Cek apakah RAM cukup
    if (_availableRamMb > 0 && model.estimatedRamMb > _availableRamMb) {
      _showSnackbar(
        '⚠️ RAM mungkin tidak cukup (butuh ~${model.estimatedRamMb}MB, tersedia ${_availableRamMb}MB)',
        color: c.warning,
      );
    }

    _showSnackbar('Memuat ${model.name}...', color: c.info);

    final ok = await LlamaService.instance.loadModel(
      model.toLlamaModelInfo(),
    );

    if (!mounted) return;

    if (ok) {
      _showSnackbar('✅ ${model.name} berhasil dimuat!', color: c.correct);
      // Perbarui state isLoaded di semua model
      await _service.scanLocalModels();
    } else {
      _showSnackbar('❌ Gagal memuat ${model.name}', color: c.wrong);
    }
  }

  /// Konfirmasi penghapusan model dengan dialog
  Future<void> _confirmDeleteModel(LocalModelInfo model) async {
    final c = KmColors.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.delete_rounded, color: c.wrong, size: 22),
          const SizedBox(width: 10),
          Text('Hapus Model?',
              style: TextStyle(color: c.text, fontWeight: FontWeight.bold)),
        ]),
        content: Text(
          'Model "${model.name}" (${model.sizeLabel}) akan dihapus permanen dari perangkat.',
          style: TextStyle(color: c.textSub, height: 1.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.text,
                  side          : BorderSide(color: c.border),
                  shape         : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Batal'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.wrong,
                  foregroundColor: Colors.white,
                  elevation      : 0,
                  shape          : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Hapus',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ],
      ),
    );

    if (confirmed == true) {
      await _service.deleteModel(model.id);
      if (mounted) {
        _showSnackbar('✅ ${model.name} dihapus', color: c.correct);
      }
    }
  }

  /// Import file model dari storage eksternal via FilePicker
  /// Import file model .gguf dari storage eksternal via FilePicker / SAF.
  ///
  /// Permission strategy:
  ///   Android ≤ 29  → READ_EXTERNAL_STORAGE (via StoragePermissionHelper)
  ///   Android 30+   → SAF (no permission needed — FilePicker uses DocumentsUI)
  ///   Android 30+   → MANAGE_EXTERNAL_STORAGE requested for faster direct path access
  ///
  /// Large file strategy:
  ///   1. pickFiles(withData: false)        → prefer direct path (O(1) memory)
  ///   2. path != null                       → stream-copy via importModelWithProgress()
  ///   3. path == null, bytes available      → write bytes (SAF cloud fallback)
  ///   4. path == null, bytes == null        → write temp via _safCopyToTemp()
  /// Import model file .gguf/.ggml from external storage.
  ///
  /// Strategy:
  ///   1. Request permission (API ≤ 29 only; SAF needs none on API 30+).
  ///   2. Try FilePicker with custom extension filter ['gguf', 'ggml'].
  ///      If PlatformException thrown → retry with FileType.any + manual validation.
  ///   3. Resolve path or bytes (SAF fallback).
  ///   4. Stream-copy to internal app dir with progress.
  Future<void> _importModel() async {
    if (_isImporting) return;

    // ── 1. Permission (Android ≤29 only) ────────────────────────────────────
    if (Platform.isAndroid) {
      final ok = await StoragePermissionHelper.requestForGgufImport(
        context: context,
      );
      if (!ok) {
        _showSnackbar(
          'Izin penyimpanan diperlukan untuk mengimport model.',
          color: c.warning,
        );
        return;
      }
    }

    // ── 2. Open file picker ──────────────────────────────────────────────────
    FilePickerResult? result;
    bool usedFallbackAny = false;

    try {
      result = await FilePicker.platform.pickFiles(
        type             : FileType.custom,
        allowedExtensions: ['gguf', 'ggml'],
        withData         : false,
      );
    } on PlatformException catch (e) {
      debugPrint('[Import] custom filter failed ($e), falling back to FileType.any');
      usedFallbackAny = true;
      result = null;
    } catch (e) {
      debugPrint('[Import] pickFiles error: $e');
      _showSnackbar('Gagal membuka file picker: $e', color: c.wrong);
      return;
    }

    // Fallback: FileType.any when custom filter is unsupported by OEM
    if (usedFallbackAny) {
      try {
        result = await FilePicker.platform.pickFiles(
          type    : FileType.any,
          withData: false,
        );
      } catch (e) {
        debugPrint('[Import] FileType.any fallback error: $e');
        _showSnackbar('Gagal membuka file picker: $e', color: c.wrong);
        return;
      }
    }

    if (result == null || result.files.isEmpty) return; // user cancelled

    final picked = result.files.first;
    if (!mounted) return;

    // ── 2b. Validate extension when fallback was used ────────────────────────
    if (usedFallbackAny) {
      final ext = picked.name.split('.').last.toLowerCase();
      if (ext != 'gguf' && ext != 'ggml') {
        _showSnackbar('❌ File harus berformat .gguf atau .ggml', color: c.wrong);
        return;
      }
    }

    // ── 3. Resolve file to a real path ───────────────────────────────────────
    String? sourcePath = picked.path;

    if (sourcePath == null && picked.bytes != null) {
      // SAF inline bytes (small file)
      setState(() { _isImporting = true; _importProgress = -1.0; });
      _showSnackbar('Memproses file...', color: c.info);
      final tempDir  = await getTemporaryDirectory();
      final tempFile = File(p.join(tempDir.path, picked.name));
      await tempFile.writeAsBytes(picked.bytes!, flush: true);
      sourcePath = tempFile.path;

    } else if (sourcePath == null && picked.bytes == null) {
      // SAF URI, no path, no bytes → retry with withData: true
      debugPrint('[Import] SAF URI no path/bytes — retrying withData:true');
      setState(() { _isImporting = true; _importProgress = -1.0; });
      _showSnackbar('Membaca file dari storage...', color: c.info);

      FilePickerResult? retry;
      try {
        retry = await FilePicker.platform.pickFiles(
          type    : FileType.any,
          withData: true,
        );
      } catch (e) {
        retry = null;
      }

      if (retry == null || retry.files.isEmpty) {
        if (mounted) setState(() { _isImporting = false; _importProgress = -1.0; });
        return;
      }

      final rf = retry.files.first;
      if (rf.path != null) {
        sourcePath = rf.path;
      } else if (rf.bytes != null) {
        final tempDir  = await getTemporaryDirectory();
        final tempFile = File(p.join(tempDir.path, rf.name));
        await tempFile.writeAsBytes(rf.bytes!, flush: true);
        sourcePath = tempFile.path;
      } else {
        if (mounted) {
          setState(() { _isImporting = false; _importProgress = -1.0; });
          _showSnackbar(
            '❌ Tidak dapat mengakses file. Coba salin ke folder Downloads terlebih dahulu.',
            color: c.wrong,
          );
        }
        return;
      }
    }

    // ── 4. Start import with progress ────────────────────────────────────────
    if (!mounted) return;
    setState(() { _isImporting = true; _importProgress = 0.0; });
    _showSnackbar('Mengimport model...', color: c.info);

    LocalModelInfo? model;
    try {
      model = await _service.importModelWithProgress(
        sourcePath!,
        onProgress: (progress) {
          if (mounted) setState(() => _importProgress = progress);
        },
      );
    } catch (e) {
      debugPrint('[Import] importModelWithProgress error: $e');
      model = null;
    }

    if (!mounted) return;
    setState(() { _isImporting = false; _importProgress = -1.0; });

    if (model != null) {
      _showSnackbar('✅ ${model.name} berhasil diimport!', color: c.correct);
    } else {
      _showSnackbar(
        '❌ Gagal mengimport model. Pastikan file .gguf valid.',
        color: c.wrong,
      );
    }
  }

  // ── Aksi: Browse ───────────────────────────────────────────────────────────

  /// Handler perubahan teks search dengan debounce 500ms
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = null;
        _isSearching   = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    _searchDebounce = Timer(const Duration(milliseconds: 500), () async {
      final results = await _service.searchHuggingFace(query.trim());
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching   = false;
      });
    });
  }

  /// Mulai download model — tampilkan bottom sheet pilih file jika ada banyak
  Future<void> _startDownload(HuggingFaceModel model) async {
    if (model.files.isEmpty) {
      _showSnackbar('Tidak ada file GGUF yang tersedia',
          color: KmColors.of(context).warning);
      return;
    }

    // Jika hanya ada 1 file, langsung download
    if (model.files.length == 1) {
      await _downloadFile(model.files.first, model);
      return;
    }

    // Jika ada beberapa file, tampilkan bottom sheet pilihan
    if (!mounted) return;
    await _showFilePickerSheet(model);
  }

  /// Tampilkan bottom sheet untuk memilih file GGUF
  Future<void> _showFilePickerSheet(HuggingFaceModel model) async {
    final c = KmColors.of(context);

    await showModalBottomSheet<void>(
      context      : context,
      backgroundColor: c.card,
      shape        : const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _FilePickerSheet(
        model       : model,
        localModels : _localModels,
        onDownload  : (file) {
          Navigator.pop(ctx);
          _downloadFile(file, model);
        },
      ),
    );
  }

  /// Eksekusi download satu file
  Future<void> _downloadFile(GGUFFile file, HuggingFaceModel model) async {
    final c = KmColors.of(context);

    // Cek apakah sudah ada di lokal
    final alreadyExists = _localModels.any(
      (m) => m.path.endsWith(file.filename),
    );
    if (alreadyExists) {
      _showSnackbar('Model ini sudah ada di perangkat', color: c.warning);
      return;
    }

    // Cek apakah sudah ada task download aktif untuk file yang sama
    final alreadyQueued = _downloads.any(
      (d) => d.file.filename == file.filename &&
             (d.status == DownloadStatus.downloading ||
              d.status == DownloadStatus.queued),
    );
    if (alreadyQueued) {
      _showSnackbar('Download sudah ada dalam antrian', color: c.warning);
      _tabController.animateTo(2); // Pindah ke tab Unduhan
      return;
    }

    await _service.startDownload(file, model);
    if (!mounted) return;

    _showSnackbar(
      '⬇️ Download dimulai: ${file.filename}',
      color: c.info,
    );

    // Pindah ke tab Unduhan untuk monitor progress
    _tabController.animateTo(2);
  }

  // ── Aksi: Download ─────────────────────────────────────────────────────────

  /// Konfirmasi pembatalan download
  Future<void> _confirmCancelDownload(String taskId) async {
    final c = KmColors.of(context);
    final task = _downloads.where((d) => d.id == taskId).firstOrNull;
    if (task == null) return;

    final confirmed = await showDialog<bool>(
      context     : context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder     : (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title : Text('Batalkan Download?',
            style: TextStyle(color: c.text, fontWeight: FontWeight.bold)),
        content: Text(
          'Download "${task.file.filename}" akan dibatalkan dan file parsial akan dihapus.',
          style: TextStyle(color: c.textSub, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child    : Text('Lanjutkan', style: TextStyle(color: c.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child    : Text('Batalkan', style: TextStyle(color: c.wrong)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _service.cancelDownload(taskId);
    }
  }

  // ── Helper ─────────────────────────────────────────────────────────────────

  /// Tampilkan snackbar di bagian bawah layar
  void _showSnackbar(String message, {required Color color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content  : Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        behavior : SnackBarBehavior.floating,
        duration : const Duration(seconds: 3),
        shape    : RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin   : const EdgeInsets.all(12),
      ),
    );
  }

  KmColors get c => KmColors.of(context);
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1: MODEL LOKAL
// ─────────────────────────────────────────────────────────────────────────────

class _LocalModelsTab extends StatelessWidget {
  final List<LocalModelInfo> models;
  final int availableRamMb;
  final bool isImporting;
  /// -1.0 = indeterminate, 0.0–1.0 = determinate progress
  final double importProgress;
  final VoidCallback onRefresh;
  final Future<void> Function(LocalModelInfo) onLoadModel;
  final Future<void> Function(LocalModelInfo) onDeleteModel;
  final VoidCallback onImportModel;

  const _LocalModelsTab({
    required this.models,
    required this.availableRamMb,
    required this.isImporting,
    required this.importProgress,
    required this.onRefresh,
    required this.onLoadModel,
    required this.onDeleteModel,
    required this.onImportModel,
  });

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);

    return RefreshIndicator(
      onRefresh  : () async => onRefresh(),
      color      : c.accent,
      child      : Column(
        children: [
          // ── Header RAM tersedia ────────────────────────────────────────────
          if (availableRamMb > 0)
            _RamHeader(availableRamMb: availableRamMb),

          // ── Tombol Import + Progress Bar ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child  : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isImporting ? null : onImportModel,
                    icon : isImporting
                        ? SizedBox(
                            width : 16,
                            height: 16,
                            child : CircularProgressIndicator(
                              strokeWidth: 2,
                              color      : c.accent,
                              value      : importProgress >= 0 ? importProgress : null,
                            ),
                          )
                        : Icon(Icons.add_circle_outline_rounded, color: c.accent),
                    label: Text(
                      isImporting
                          ? (importProgress >= 0
                              ? 'Mengimport... ${(importProgress * 100).toStringAsFixed(0)}%'
                              : 'Mempersiapkan...')
                          : '+ Import dari Storage',
                      style: TextStyle(
                        color     : c.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side   : BorderSide(color: c.accent.withValues(alpha: 0.4)),
                      shape  : RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                // Progress bar — only visible during import
                if (isImporting) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value           : importProgress >= 0 ? importProgress : null,
                      backgroundColor : c.border,
                      valueColor      : AlwaysStoppedAnimation<Color>(c.accent),
                      minHeight       : 4,
                    ),
                  ),
                  if (importProgress >= 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Menyalin file model ke penyimpanan internal...',
                      style: TextStyle(
                        color   : c.textSub,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ],
            ),
          ),

          // ── Daftar Model ───────────────────────────────────────────────────
          Expanded(
            child: models.isEmpty
                ? _EmptyState(
                    icon   : Icons.storage_rounded,
                    title  : 'Belum ada model',
                    message: 'Download model dari tab "Jelajahi" atau\nimport file .gguf dari storage.',
                  )
                : ListView.builder(
                    padding      : const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount    : models.length,
                    itemBuilder  : (ctx, i) {
                      final model = models[i];
                      return _LocalModelCard(
                        model      : model,
                        onLoad     : () => onLoadModel(model),
                        onDelete   : () => onDeleteModel(model),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Header RAM tersedia ──────────────────────────────────────────────────────

class _RamHeader extends StatelessWidget {
  final int availableRamMb;
  const _RamHeader({required this.availableRamMb});

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);

    // Tentukan warna berdasarkan persentase RAM yang tersedia
    // (asumsi total RAM device ~6GB = 6144MB untuk estimasi persentase)
    final totalRamEstimate = 6144;
    final fraction = (availableRamMb / totalRamEstimate).clamp(0.0, 1.0);
    final barColor = fraction < 0.2
        ? c.wrong
        : fraction < 0.5
            ? c.warning
            : c.correct;

    return Container(
      margin : const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color       : c.surface,
        borderRadius: BorderRadius.circular(12),
        border      : Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'RAM Tersedia',
                style: TextStyle(
                    color: c.textSub, fontSize: 12, fontWeight: FontWeight.w500),
              ),
              Text(
                availableRamMb >= 1024
                    ? '${(availableRamMb / 1024).toStringAsFixed(1)} GB tersedia'
                    : '$availableRamMb MB tersedia',
                style: TextStyle(
                    color: barColor, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value           : fraction,
              backgroundColor : c.border,
              valueColor      : AlwaysStoppedAnimation<Color>(barColor),
              minHeight       : 6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            fraction < 0.2
                ? '⚠️ RAM sangat terbatas — gunakan model ukuran kecil'
                : fraction < 0.5
                    ? '⚡ RAM cukup — cocok untuk model hingga 3B'
                    : '✅ RAM lega — bisa memuat model besar',
            style: TextStyle(color: c.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Card Model Lokal ─────────────────────────────────────────────────────────

class _LocalModelCard extends StatefulWidget {
  final LocalModelInfo model;
  final VoidCallback onLoad;
  final VoidCallback onDelete;

  const _LocalModelCard({
    required this.model,
    required this.onLoad,
    required this.onDelete,
  });

  @override
  State<_LocalModelCard> createState() => _LocalModelCardState();
}

class _LocalModelCardState extends State<_LocalModelCard> {
  /// Guard agar tombol Muat tidak bisa diklik ganda saat loading
  bool _isLoading = false;

  Future<void> _handleLoad() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await Future.microtask(widget.onLoad);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    final model = widget.model;

    return Dismissible(
      key             : Key(model.id),
      direction       : DismissDirection.endToStart,
      confirmDismiss  : (_) async {
        widget.onDelete();
        return false; // Kita handle penghapusan manual via dialog
      },
      background      : Container(
        alignment   : Alignment.centerRight,
        padding     : const EdgeInsets.only(right: 20),
        margin      : const EdgeInsets.only(bottom: 10),
        decoration  : BoxDecoration(
          color       : c.wrong.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_rounded, color: c.wrong, size: 22),
            const SizedBox(height: 4),
            Text('Hapus',
                style: TextStyle(color: c.wrong, fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      child: Container(
        margin     : const EdgeInsets.only(bottom: 10),
        padding    : const EdgeInsets.all(14),
        decoration : BoxDecoration(
          color       : c.card,
          borderRadius: BorderRadius.circular(14),
          border      : Border.all(
            color: model.isLoaded
                ? c.accent.withValues(alpha: 0.4)
                : c.border,
            width: model.isLoaded ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Baris atas: nama + badge loaded ─────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    model.name,
                    style: TextStyle(
                      color     : c.text,
                      fontWeight: FontWeight.bold,
                      fontSize  : 14,
                    ),
                    maxLines : 2,
                    overflow : TextOverflow.ellipsis,
                  ),
                ),
                if (model.isLoaded)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color       : c.correct.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border      : Border.all(
                          color: c.correct.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: c.correct, size: 12),
                        const SizedBox(width: 4),
                        Text('Aktif',
                            style: TextStyle(
                              color     : c.correct,
                              fontSize  : 11,
                              fontWeight: FontWeight.bold,
                            )),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // ── Baris tengah: badges info ────────────────────────────────────
            Wrap(
              spacing  : 6,
              runSpacing: 4,
              children : [
                _InfoBadge(
                  icon : Icons.sd_card_rounded,
                  label: model.sizeLabel,
                  color: c.info,
                ),
                _InfoBadge(
                  icon : Icons.memory_rounded,
                  label: model.quantization,
                  color: c.gold,
                ),
                _InfoBadge(
                  icon : Icons.developer_board_rounded,
                  label: '~${model.estimatedRamMb}MB RAM',
                  color: model.estimatedRamMb > 3000 ? c.warning : c.correct,
                ),
                _InfoBadge(
                  icon : Icons.data_object_rounded,
                  label: model.format.toUpperCase(),
                  color: c.textSub,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Baris bawah: tombol aksi ─────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: model.isLoaded
                      ? OutlinedButton.icon(
                          onPressed: null,
                          icon : Icon(Icons.check_rounded,
                              color: c.correct, size: 16),
                          label: Text('Sedang Dimuat',
                              style: TextStyle(color: c.correct, fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            side   : BorderSide(color: c.correct.withValues(alpha: 0.3)),
                            shape  : RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        )
                      : ElevatedButton.icon(
                          onPressed: _isLoading ? null : _handleLoad,
                          icon : _isLoading
                              ? SizedBox(
                                  width : 16,
                                  height: 16,
                                  child : CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color      : Colors.white,
                                  ),
                                )
                              : const Icon(Icons.play_arrow_rounded, size: 16),
                          label: Text(
                            _isLoading ? 'Memuat...' : 'Muat',
                            style: const TextStyle(fontSize: 12,
                                fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: c.accent,
                            foregroundColor: Colors.white,
                            elevation      : 0,
                            shape          : RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: widget.onDelete,
                  icon     : Icon(Icons.delete_outline_rounded,
                      color: c.textMuted, size: 20),
                  padding  : EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2: JELAJAHI
// ─────────────────────────────────────────────────────────────────────────────

class _BrowseTab extends StatelessWidget {
  final List<HuggingFaceModel> featuredModels;
  final List<HuggingFaceModel>? searchResults;
  final TextEditingController searchController;
  final bool isSearching;
  final String sizeFilter;
  final List<LocalModelInfo> localModels;
  final ValueChanged<String> onSizeFilter;
  final ValueChanged<String> onSearch;
  final Future<void> Function(HuggingFaceModel) onDownload;

  const _BrowseTab({
    required this.featuredModels,
    required this.searchResults,
    required this.searchController,
    required this.isSearching,
    required this.sizeFilter,
    required this.localModels,
    required this.onSizeFilter,
    required this.onSearch,
    required this.onDownload,
  });

  /// Terapkan filter ukuran ke daftar model
  List<HuggingFaceModel> _applyFilter(List<HuggingFaceModel> models) {
    if (sizeFilter == 'all') return models;
    return models.where((m) {
      final bytes = m.smallestFileSizeBytes;
      final gb    = bytes / (1024 * 1024 * 1024);
      switch (sizeFilter) {
        case 'light':    return gb < 1.0;
        case 'balanced': return gb >= 1.0 && gb <= 3.0;
        case 'full':     return gb > 3.0;
        default:         return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c      = KmColors.of(context);
    final source = searchResults ?? featuredModels;
    final models = _applyFilter(source);

    return Column(
      children: [
        // ── Search bar ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child  : TextField(
            controller : searchController,
            onChanged  : onSearch,
            style      : TextStyle(color: c.text),
            decoration : InputDecoration(
              hintText       : 'Cari model di HuggingFace...',
              hintStyle      : TextStyle(color: c.textMuted),
              prefixIcon     : Icon(Icons.search_rounded, color: c.textSub),
              suffixIcon     : searchController.text.isNotEmpty
                  ? IconButton(
                      icon     : Icon(Icons.close_rounded, color: c.textSub),
                      onPressed: () {
                        searchController.clear();
                        onSearch('');
                      },
                    )
                  : null,
              filled      : true,
              fillColor   : c.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border      : OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide  : BorderSide.none,
              ),
            ),
          ),
        ),

        // ── Filter chips ──────────────────────────────────────────────────
        SizedBox(
          height : 44,
          child  : ListView(
            scrollDirection: Axis.horizontal,
            padding        : const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            children: [
              _FilterChip(
                label    : 'Semua',
                selected : sizeFilter == 'all',
                onTap    : () => onSizeFilter('all'),
              ),
              _FilterChip(
                label    : 'Ringan (<1GB)',
                selected : sizeFilter == 'light',
                onTap    : () => onSizeFilter('light'),
              ),
              _FilterChip(
                label    : 'Seimbang (1-3GB)',
                selected : sizeFilter == 'balanced',
                onTap    : () => onSizeFilter('balanced'),
              ),
              _FilterChip(
                label    : 'Lengkap (>3GB)',
                selected : sizeFilter == 'full',
                onTap    : () => onSizeFilter('full'),
              ),
            ],
          ),
        ),

        // ── Label sumber ──────────────────────────────────────────────────
        if (searchResults == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child    : Text(
                '⭐ Model Pilihan',
                style: TextStyle(
                    color: c.textSub, fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),

        // ── Konten utama ──────────────────────────────────────────────────
        Expanded(
          child: isSearching
              ? _ShimmerList()
              : models.isEmpty
                  ? _EmptyState(
                      icon   : Icons.search_off_rounded,
                      title  : 'Tidak ada hasil',
                      message: 'Coba kata kunci lain atau\nubah filter ukuran model.',
                    )
                  : ListView.builder(
                      padding    : const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      itemCount  : models.length,
                      itemBuilder: (ctx, i) {
                        final model = models[i];
                        final alreadyDownloaded = localModels.any(
                          (m) => model.files.any(
                              (f) => m.path.endsWith(f.filename)),
                        );
                        return _HfModelCard(
                          model            : model,
                          alreadyDownloaded: alreadyDownloaded,
                          onDownload       : () => onDownload(model),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// ── Card Model HuggingFace ───────────────────────────────────────────────────

class _HfModelCard extends StatelessWidget {
  final HuggingFaceModel model;
  final bool alreadyDownloaded;
  final VoidCallback onDownload;

  const _HfModelCard({
    required this.model,
    required this.alreadyDownloaded,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);

    // Tentukan badge kompatibilitas berdasarkan estimasi ukuran
    final smallestBytes = model.smallestFileSizeBytes;
    final estimatedRam  = ModelManagerService.instance.estimateRamMb(
        smallestBytes, 'Q4_K_M');

    final String compatLabel;
    final Color  compatColor;
    if (estimatedRam <= 2500) {
      compatLabel = '✓ Kompatibel';
      compatColor = c.correct;
    } else if (estimatedRam <= 4000) {
      compatLabel = '⚠ RAM Terbatas';
      compatColor = c.warning;
    } else {
      compatLabel = '✗ Butuh RAM Besar';
      compatColor = c.wrong;
    }

    return Container(
      margin    : const EdgeInsets.only(bottom: 10),
      padding   : const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color       : c.card,
        borderRadius: BorderRadius.circular(14),
        border      : Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Nama + penulis ────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.name,
                      style: TextStyle(
                        color     : c.text,
                        fontWeight: FontWeight.bold,
                        fontSize  : 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      model.author,
                      style: TextStyle(color: c.textSub, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Badge kompatibilitas
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color       : compatColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border      : Border.all(
                      color: compatColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  compatLabel,
                  style: TextStyle(
                    color    : compatColor,
                    fontSize : 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Deskripsi ─────────────────────────────────────────────────────
          if (model.description.isNotEmpty)
            Text(
              model.description,
              style  : TextStyle(color: c.textSub, fontSize: 12, height: 1.4),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 8),

          // ── Info ukuran + tags ────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.sd_card_rounded, color: c.textMuted, size: 13),
              const SizedBox(width: 4),
              Text(
                ModelManagerService.instance.formatBytes(smallestBytes),
                style: TextStyle(color: c.textSub, fontSize: 11),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  children: model.tags.take(3).map((tag) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color       : c.surface,
                      borderRadius: BorderRadius.circular(4),
                      border      : Border.all(color: c.border),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(color: c.textMuted, fontSize: 10),
                    ),
                  )).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Tombol download ───────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: alreadyDownloaded
                ? OutlinedButton.icon(
                    onPressed: null,
                    icon : Icon(Icons.check_rounded,
                        color: c.correct, size: 16),
                    label: Text('Sudah Diunduh',
                        style: TextStyle(color: c.correct,
                            fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side : BorderSide(color: c.correct.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: onDownload,
                    icon : const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Unduh',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: Colors.white,
                      elevation      : 0,
                      shape          : RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 3: UNDUHAN
// ─────────────────────────────────────────────────────────────────────────────

class _DownloadsTab extends StatelessWidget {
  final List<DownloadTask> downloads;
  final Future<void> Function(String) onPause;
  final Future<void> Function(String) onResume;
  final Future<void> Function(String) onCancel;

  const _DownloadsTab({
    required this.downloads,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    if (downloads.isEmpty) {
      return const _EmptyState(
        icon   : Icons.download_done_rounded,
        title  : 'Tidak ada unduhan',
        message: 'Download model dari tab "Jelajahi"\nuntuk mulai mengunduh.',
      );
    }

    // Urutkan: yang aktif di atas, selesai di bawah
    final sorted = [...downloads]..sort((a, b) {
      final order = {
        DownloadStatus.downloading: 0,
        DownloadStatus.queued     : 1,
        DownloadStatus.paused     : 2,
        DownloadStatus.failed     : 3,
        DownloadStatus.completed  : 4,
        DownloadStatus.cancelled  : 5,
      };
      return (order[a.status] ?? 5).compareTo(order[b.status] ?? 5);
    });

    return ListView.builder(
      padding    : const EdgeInsets.all(16),
      itemCount  : sorted.length,
      itemBuilder: (ctx, i) {
        final task = sorted[i];
        return _DownloadTaskCard(
          task    : task,
          onPause : () => onPause(task.id),
          onResume: () => onResume(task.id),
          onCancel: () => onCancel(task.id),
        );
      },
    );
  }
}

// ── Card Download Task ───────────────────────────────────────────────────────

class _DownloadTaskCard extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;

  const _DownloadTaskCard({
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);

    // Tentukan warna dan label status
    final Color statusColor;
    final String statusLabel;
    final IconData statusIcon;

    switch (task.status) {
      case DownloadStatus.downloading:
        statusColor = c.info;
        statusLabel = 'Mengunduh...';
        statusIcon  = Icons.downloading_rounded;
        break;
      case DownloadStatus.queued:
        statusColor = c.textSub;
        statusLabel = 'Antri';
        statusIcon  = Icons.schedule_rounded;
        break;
      case DownloadStatus.paused:
        statusColor = c.warning;
        statusLabel = 'Dijeda';
        statusIcon  = Icons.pause_circle_rounded;
        break;
      case DownloadStatus.completed:
        statusColor = c.correct;
        statusLabel = 'Selesai';
        statusIcon  = Icons.check_circle_rounded;
        break;
      case DownloadStatus.failed:
        statusColor = c.wrong;
        statusLabel = 'Gagal';
        statusIcon  = Icons.error_rounded;
        break;
      case DownloadStatus.cancelled:
        statusColor = c.textMuted;
        statusLabel = 'Dibatalkan';
        statusIcon  = Icons.cancel_rounded;
        break;
    }

    final isActive = task.status == DownloadStatus.downloading ||
                     task.status == DownloadStatus.queued ||
                     task.status == DownloadStatus.paused;

    return Container(
      margin    : const EdgeInsets.only(bottom: 12),
      padding   : const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color       : c.card,
        borderRadius: BorderRadius.circular(14),
        border      : Border.all(
          color: isActive
              ? statusColor.withValues(alpha: 0.3)
              : c.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Nama file + status ────────────────────────────────────────────
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.file.filename,
                  style: TextStyle(
                    color     : c.text,
                    fontWeight: FontWeight.bold,
                    fontSize  : 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // ── Nama model ────────────────────────────────────────────────────
          Text(
            task.model.name,
            style: TextStyle(color: c.textSub, fontSize: 12),
          ),
          const SizedBox(height: 10),

          // ── Progress bar (hanya untuk task aktif/paused) ──────────────────
          if (task.status == DownloadStatus.downloading ||
              task.status == DownloadStatus.paused) ...[
            _LiveProgressBar(taskId: task.id, task: task),
            const SizedBox(height: 8),
          ],

          // ── Info progress statis untuk selesai/gagal ──────────────────────
          if (task.status == DownloadStatus.completed)
            Row(
              children: [
                Icon(Icons.check_circle_outline_rounded,
                    color: c.correct, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Berhasil disimpan di perangkat',
                  style: TextStyle(color: c.correct, fontSize: 12),
                ),
              ],
            ),

          if (task.status == DownloadStatus.failed && task.error != null)
            Row(
              children: [
                Icon(Icons.error_outline_rounded, color: c.wrong, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    task.error!,
                    style: TextStyle(color: c.wrong, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

          // ── Tombol aksi ───────────────────────────────────────────────────
          if (isActive) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (task.status == DownloadStatus.downloading)
                  OutlinedButton.icon(
                    onPressed: onPause,
                    icon : Icon(Icons.pause_rounded, size: 14, color: c.warning),
                    label: Text('Jeda',
                        style: TextStyle(color: c.warning, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side   : BorderSide(color: c.warning.withValues(alpha: 0.3)),
                      shape  : RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                    ),
                  ),
                if (task.status == DownloadStatus.paused)
                  OutlinedButton.icon(
                    onPressed: onResume,
                    icon : Icon(Icons.play_arrow_rounded,
                        size: 14, color: c.info),
                    label: Text('Lanjut',
                        style: TextStyle(color: c.info, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side   : BorderSide(color: c.info.withValues(alpha: 0.3)),
                      shape  : RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                    ),
                  ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onCancel,
                  icon : Icon(Icons.close_rounded, size: 14, color: c.wrong),
                  label: Text('Batalkan',
                      style: TextStyle(color: c.wrong, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side   : BorderSide(color: c.wrong.withValues(alpha: 0.3)),
                    shape  : RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Live Progress Bar (subscribe ke stream per task) ─────────────────────────

class _LiveProgressBar extends StatefulWidget {
  final String taskId;
  final DownloadTask task;

  const _LiveProgressBar({required this.taskId, required this.task});

  @override
  State<_LiveProgressBar> createState() => _LiveProgressBarState();
}

class _LiveProgressBarState extends State<_LiveProgressBar> {
  StreamSubscription<DownloadProgress>? _sub;
  DownloadProgress? _lastProgress;

  @override
  void initState() {
    super.initState();
    _sub = ModelManagerService.instance
        .watchDownload(widget.taskId)
        .listen((progress) {
      if (mounted) setState(() => _lastProgress = progress);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c        = KmColors.of(context);
    final progress = _lastProgress;
    final percent  = progress?.percent ?? (widget.task.progress * 100);
    final speed    = progress?.speedLabel ?? '';
    final eta      = progress?.etaLabel ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Baris progress % dan kecepatan
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${percent.toStringAsFixed(1)}%',
              style: TextStyle(
                color     : c.info,
                fontWeight: FontWeight.bold,
                fontSize  : 13,
              ),
            ),
            if (speed.isNotEmpty)
              Text(speed,
                  style: TextStyle(color: c.textSub, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 6),

        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value           : percent / 100,
            backgroundColor : c.border,
            valueColor      : AlwaysStoppedAnimation<Color>(c.info),
            minHeight       : 6,
          ),
        ),
        const SizedBox(height: 4),

        // Bytes + ETA
        if (progress != null)
          Text(
            '${ModelManagerService.instance.formatBytes(progress.bytesDownloaded)}'
            ' / ${ModelManagerService.instance.formatBytes(progress.totalBytes)}'
            '${eta.isNotEmpty ? "  ·  $eta" : ""}',
            style: TextStyle(color: c.textMuted, fontSize: 11),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM SHEET: Pilih File GGUF
// ─────────────────────────────────────────────────────────────────────────────

class _FilePickerSheet extends StatelessWidget {
  final HuggingFaceModel model;
  final List<LocalModelInfo> localModels;
  final void Function(GGUFFile) onDownload;

  const _FilePickerSheet({
    required this.model,
    required this.localModels,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);

    return Container(
      padding     : const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child       : Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width : 36,
              height: 4,
              decoration: BoxDecoration(
                color       : c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Judul
          Text(
            'Pilih File GGUF',
            style: TextStyle(
              color     : c.text,
              fontWeight: FontWeight.bold,
              fontSize  : 16,
            ),
          ),
          Text(
            model.name,
            style: TextStyle(color: c.textSub, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // Daftar file
          ...model.files.map((file) {
            final alreadyExists = localModels.any(
              (m) => m.path.endsWith(file.filename),
            );
            return _GgufFileRow(
              file          : file,
              alreadyExists : alreadyExists,
              onDownload    : () => onDownload(file),
            );
          }),
        ],
      ),
    );
  }
}

// ── Baris file GGUF dalam bottom sheet ───────────────────────────────────────

class _GgufFileRow extends StatelessWidget {
  final GGUFFile file;
  final bool alreadyExists;
  final VoidCallback onDownload;

  const _GgufFileRow({
    required this.file,
    required this.alreadyExists,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);

    return Container(
      margin    : const EdgeInsets.only(bottom: 8),
      padding   : const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color       : c.surface,
        borderRadius: BorderRadius.circular(10),
        border      : Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.quantization,
                  style: TextStyle(
                    color     : c.text,
                    fontWeight: FontWeight.bold,
                    fontSize  : 13,
                  ),
                ),
                Text(
                  '${file.sizeLabel}  ·  ${file.recommendedLabel}',
                  style: TextStyle(color: c.textSub, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          alreadyExists
              ? Icon(Icons.check_circle_rounded,
                  color: c.correct, size: 22)
              : ElevatedButton(
                  onPressed: onDownload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: Colors.white,
                    elevation      : 0,
                    shape          : RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Unduh',
                      style: TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET REUSABLE
// ─────────────────────────────────────────────────────────────────────────────

/// Badge info kecil untuk model card
class _InfoBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return Container(
      padding   : const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color       : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border      : Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color    : color,
              fontSize : 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip filter ukuran model
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration : const Duration(milliseconds: 150),
        margin   : const EdgeInsets.only(right: 8),
        padding  : const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color       : selected ? c.accent : c.surface,
          borderRadius: BorderRadius.circular(20),
          border      : Border.all(
            color: selected ? c.accent : c.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color    : selected ? Colors.white : c.textSub,
            fontSize : 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// Badge hitungan kecil untuk tab
class _CountBadge extends StatelessWidget {
  final int count;
  final Color color;

  const _CountBadge({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding   : const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color       : color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color    : color,
          fontSize : 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Empty state untuk daftar kosong
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child  : Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: c.textMuted, size: 52),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color     : c.text,
                fontWeight: FontWeight.bold,
                fontSize  : 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style    : TextStyle(
                color : c.textSub,
                fontSize: 13,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shimmer loading untuk daftar search results
class _ShimmerList extends StatefulWidget {
  @override
  State<_ShimmerList> createState() => _ShimmerListState();
}

class _ShimmerListState extends State<_ShimmerList>
    with SingleTickerProviderStateMixin {

  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync   : this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return AnimatedBuilder(
      animation: _anim,
      builder  : (_, __) => ListView.builder(
        padding    : const EdgeInsets.all(16),
        itemCount  : 4,
        itemBuilder: (ctx, i) => Container(
          margin    : const EdgeInsets.only(bottom: 12),
          padding   : const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color       : c.card,
            borderRadius: BorderRadius.circular(14),
            border      : Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _shimmerBox(c, width: 180, height: 14),
              const SizedBox(height: 8),
              _shimmerBox(c, width: 80,  height: 11),
              const SizedBox(height: 10),
              _shimmerBox(c, width: double.infinity, height: 11),
              const SizedBox(height: 4),
              _shimmerBox(c, width: 240, height: 11),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shimmerBox(KmColors c, {required double width, required double height}) {
    return Container(
      width : width,
      height: height,
      decoration: BoxDecoration(
        color       : c.border.withValues(alpha: _anim.value),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
