// lib/data/services/content/import_progress_service.dart
// =============================================================================
// Global singleton yang menyimpan state import model agar animasi progress
// TIDAK hilang saat user keluar dari ModelManagerScreen ke beranda.
//
// Bug sebelumnya:
//   _downloads & _importing disimpan di _ModelManagerScreenState → di-dispose
//   saat navigasi keluar → animasi hilang, progress reset.
//
// Fix:
//   ImportProgressService adalah singleton (hidup selama app berjalan).
//   ModelManagerScreen & MainShell hanya *observe* state ini via stream.
// =============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'model_manager_service.dart';

class ImportProgressService extends ChangeNotifier {
  ImportProgressService._();
  static final ImportProgressService instance = ImportProgressService._();

  // ── State import & download yang sedang berjalan ──────────────────────────
  final Map<String, DownloadProgress> _downloads = {};
  final Map<String, StreamSubscription<DownloadProgress>> _subs = {};
  final Map<String, Map<String, String>> _resumable = {};
  // ── Cancel tokens untuk import lokal ─────────────────────────────────────
  final Map<String, ImportCancelToken> _cancelTokens = {};

  bool _importing = false;

  // ── Getters ───────────────────────────────────────────────────────────────
  Map<String, DownloadProgress> get downloads =>
      Map.unmodifiable(_downloads);
  Map<String, Map<String, String>> get resumable =>
      Map.unmodifiable(_resumable);
  bool get importing => _importing;

  /// True jika ada proses import aktif (progress belum selesai)
  bool get hasActiveImport =>
      _downloads.values.any((p) => p.isImport && !p.isComplete && !p.hasError);

  /// True jika ada proses download aktif
  bool get hasActiveDownload =>
      _downloads.values.any((p) => !p.isImport && !p.isComplete && !p.hasError);

  // ── Import dari file lokal ────────────────────────────────────────────────

  /// Mulai import file model dari path lokal.
  /// Mengembalikan modelId yang digunakan, atau null jika sudah ada import aktif.
  Future<String?> startImport(String filePath, {String? customName}) async {
    if (_importing) return null;

    _importing = true;
    notifyListeners();

    String? importId;
    final cancelToken = ImportCancelToken();

    final sub = ModelManagerService.instance
        .importFileStream(filePath, customName: customName, cancelToken: cancelToken)
        .listen(
      (progress) async {
        importId ??= progress.modelId;

        // Simpan cancelToken agar cancelDownload() bisa menghentikan loop
        if (importId != null) {
          _cancelTokens[importId!] = cancelToken;
        }

        _downloads[progress.modelId] = progress;
        notifyListeners();

        if (progress.isComplete) {
          await ModelManagerService.instance.load();
          _subs[progress.modelId]?.cancel();
          _subs.remove(progress.modelId);
          _cancelTokens.remove(progress.modelId);
          _downloads.remove(progress.modelId);
          _importing = false;
          notifyListeners();
          debugPrint('[ImportProgressService] ✅ Import selesai: ${progress.modelName}');
        }

        if (progress.hasError) {
          _subs[progress.modelId]?.cancel();
          _subs.remove(progress.modelId);
          _cancelTokens.remove(progress.modelId);
          _downloads.remove(progress.modelId);
          _importing = false;
          notifyListeners();
          debugPrint('[ImportProgressService] ❌ Import error: ${progress.error}');
        }
      },
      onDone: () {
        if (_importing) {
          _importing = false;
          notifyListeners();
        }
      },
      onError: (_) {
        _importing = false;
        notifyListeners();
      },
    );

    // Tunggu sebentar agar importId terisi dari event pertama
    await Future.delayed(const Duration(milliseconds: 50));
    if (importId != null) {
      _subs[importId!] = sub;
      _cancelTokens[importId!] = cancelToken;
    }

    return importId;
  }

  // ── Download dari URL ─────────────────────────────────────────────────────

  void startDownload({
    required String url,
    required String modelId,
    String? customName,
  }) {
    _resumable.remove(modelId);
    _downloads[modelId] = DownloadProgress(
      modelId: modelId,
      modelName: customName,
      received: 0,
      total: 0,
    );
    notifyListeners();

    final sub = ModelManagerService.instance
        .downloadFromUrl(url: url, modelId: modelId, customName: customName)
        .listen(
      (progress) {
        _downloads[modelId] = progress;
        notifyListeners();

        if (progress.isComplete) {
          _subs[modelId]?.cancel();
          _subs.remove(modelId);
          _downloads.remove(modelId);
          ModelManagerService.instance.load();
          notifyListeners();
        }
        if (progress.hasError) {
          _subs[modelId]?.cancel();
          _subs.remove(modelId);
          _resumable[modelId] = {'url': url, 'name': customName ?? ''};
          notifyListeners();
        }
      },
    );
    _subs[modelId] = sub;
  }

  void cancelDownload(String id) {
    // Sinyal ke loop copy agar berhenti di iterasi berikutnya
    _cancelTokens[id]?.isCancelled = true;
    _cancelTokens.remove(id);

    _subs[id]?.cancel();
    _subs.remove(id);
    _resumable.remove(id);
    _downloads.remove(id);
    if (_importing && _downloads.isEmpty) _importing = false;
    notifyListeners();
  }

  void resumeDownload(String id) {
    final info = _resumable[id];
    if (info == null) return;
    startDownload(
      url: info['url']!,
      modelId: id,
      customName: info['name'],
    );
  }

  /// Progress dari import yang sedang berjalan (untuk banner di luar screen)
  DownloadProgress? get activeImportProgress {
    try {
      return _downloads.values.firstWhere((p) => p.isImport);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    for (final token in _cancelTokens.values) {
      token.isCancelled = true;
    }
    _cancelTokens.clear();
    for (final sub in _subs.values) {
      sub.cancel();
    }
    super.dispose();
  }
}
