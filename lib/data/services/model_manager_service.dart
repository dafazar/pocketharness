// lib/data/services/model_manager_service.dart
// Pocket Harness — Model Manager Service (Arsitektur PocketPal)
//
// Mengelola semua model AI offline berformat GGUF:
//   - Scan model lokal di folder {appDir}/models/
//   - Download dari HuggingFace dengan resume support (HTTP Range)
//   - Import file dari storage lokal
//   - Katalog model kurasi (8 model)
//   - Pencarian HuggingFace API
//
// Singleton: ModelManagerService.instance

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:pocketharness/core/ai/llama_context.dart';
import 'package:pocketharness/data/services/llama_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// KUNCI SharedPreferences
// ─────────────────────────────────────────────────────────────────────────────

const _kCacheKey      = 'km_model_manager_cache_v2';
const _kActiveModelKey = 'km_active_model_id_v1';

/// Alias agar semua file yang import model_manager_service bisa pakai AiModel
/// tanpa harus import llama_context secara terpisah.
typedef AiModel = LlamaModelInfo;

// ─────────────────────────────────────────────────────────────────────────────
// CLASS: LocalModelInfo
// ─────────────────────────────────────────────────────────────────────────────

/// Informasi model GGUF yang tersimpan secara lokal di perangkat.
class LocalModelInfo {
  final String id;           // UUID unik
  final String name;         // Nama file tanpa ekstensi
  final String path;         // Path lengkap ke file
  final int sizeBytes;       // Ukuran file dalam bytes
  final String format;       // 'gguf', 'ggml', 'tflite', 'onnx'
  final String quantization; // 'Q4_K_M', 'Q8_0', dll
  final int estimatedRamMb;  // Estimasi kebutuhan RAM
  final bool isLoaded;       // Apakah sedang loaded di LlamaService
  final DateTime? lastUsed;
  final List<String> tags;

  const LocalModelInfo({
    required this.id,
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.format,
    required this.quantization,
    required this.estimatedRamMb,
    required this.isLoaded,
    this.lastUsed,
    this.tags = const [],
  });

  /// Label ukuran file yang mudah dibaca (contoh: "1.2 GB", "850 MB")
  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  /// Cek apakah RAM tersedia cukup untuk memuat model ini
  bool get isCompatible {
    // Periksa RAM via LlamaService secara synchronous tidak mungkin,
    // gunakan estimasi konservatif: jika estimatedRamMb <= 4096, dianggap kompatibel
    // Logika lebih akurat ada di ModelManagerService.isRamSufficient()
    return estimatedRamMb <= 4096;
  }

  /// Konversi ke LlamaModelInfo untuk digunakan oleh LlamaService
  LlamaModelInfo toLlamaModelInfo() {
    QuantizationType quant = _parseQuantType(quantization);
    return LlamaModelInfo(
      id            : id,
      name          : name,
      path          : path,
      sizeBytes     : sizeBytes,
      format        : format,
      quantization  : quant,
      estimatedRamMb: estimatedRamMb,
      contextLength : 4096,
      isDownloaded  : true,
      lastUsed      : lastUsed,
      tags          : tags,
    );
  }

  /// Parse QuantizationType dari string kuantisasi
  static QuantizationType _parseQuantType(String q) {
    final lower = q.toLowerCase();
    if (lower.contains('q2_k'))   return QuantizationType.q2K;
    if (lower.contains('q3_k_m')) return QuantizationType.q3KM;
    if (lower.contains('q4_k_s')) return QuantizationType.q4KS;
    if (lower.contains('q4_k'))   return QuantizationType.q4KM;
    if (lower.contains('q5_k_s')) return QuantizationType.q5KS;
    if (lower.contains('q5_k'))   return QuantizationType.q5KM;
    if (lower.contains('q6_k'))   return QuantizationType.q6K;
    if (lower.contains('q8_0'))   return QuantizationType.q8_0;
    if (lower.contains('f16'))    return QuantizationType.f16;
    if (lower.contains('f32'))    return QuantizationType.f32;
    return QuantizationType.unknown;
  }

  /// Buat salinan dengan nilai yang diperbarui
  LocalModelInfo copyWith({
    String? id,
    String? name,
    String? path,
    int? sizeBytes,
    String? format,
    String? quantization,
    int? estimatedRamMb,
    bool? isLoaded,
    DateTime? lastUsed,
    List<String>? tags,
  }) {
    return LocalModelInfo(
      id            : id ?? this.id,
      name          : name ?? this.name,
      path          : path ?? this.path,
      sizeBytes     : sizeBytes ?? this.sizeBytes,
      format        : format ?? this.format,
      quantization  : quantization ?? this.quantization,
      estimatedRamMb: estimatedRamMb ?? this.estimatedRamMb,
      isLoaded      : isLoaded ?? this.isLoaded,
      lastUsed      : lastUsed ?? this.lastUsed,
      tags          : tags ?? this.tags,
    );
  }

  /// Serialisasi ke Map JSON
  Map<String, dynamic> toJson() => {
    'id'            : id,
    'name'          : name,
    'path'          : path,
    'sizeBytes'     : sizeBytes,
    'format'        : format,
    'quantization'  : quantization,
    'estimatedRamMb': estimatedRamMb,
    'isLoaded'      : isLoaded,
    'lastUsed'      : lastUsed?.toIso8601String(),
    'tags'          : tags,
  };

  /// Buat dari Map JSON
  factory LocalModelInfo.fromJson(Map<String, dynamic> j) => LocalModelInfo(
    id            : j['id'] as String,
    name          : j['name'] as String,
    path          : j['path'] as String,
    sizeBytes     : j['sizeBytes'] as int? ?? 0,
    format        : j['format'] as String? ?? 'gguf',
    quantization  : j['quantization'] as String? ?? 'unknown',
    estimatedRamMb: j['estimatedRamMb'] as int? ?? 0,
    isLoaded      : false, // Bug #5 fix: jangan baca dari cache, selalu false saat cold start
    lastUsed      : j['lastUsed'] != null
        ? DateTime.tryParse(j['lastUsed'] as String)
        : null,
    tags          : List<String>.from(j['tags'] as List? ?? []),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CLASS: GGUFFile
// ─────────────────────────────────────────────────────────────────────────────

/// Merepresentasikan satu file GGUF yang tersedia di HuggingFace
class GGUFFile {
  final String filename;
  final int sizeBytes;
  final String downloadUrl; // URL langsung ke file
  final String quantization; // Hasil parse dari nama file: Q4_K_M, Q8_0, dll
  final String? sha256;

  const GGUFFile({
    required this.filename,
    required this.sizeBytes,
    required this.downloadUrl,
    required this.quantization,
    this.sha256,
  });

  /// Label ukuran file yang mudah dibaca
  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  /// Label kompatibilitas berdasarkan ukuran file
  String get recommendedLabel {
    final gb = sizeBytes / (1024 * 1024 * 1024);
    if (gb < 1.0) return 'Ringan';
    if (gb < 3.0) return 'Seimbang';
    if (gb < 5.0) return 'Lengkap';
    return 'Terlalu Besar';
  }

  /// Serialisasi ke Map JSON
  Map<String, dynamic> toJson() => {
    'filename'    : filename,
    'sizeBytes'   : sizeBytes,
    'downloadUrl' : downloadUrl,
    'quantization': quantization,
    'sha256'      : sha256,
  };

  /// Buat dari Map JSON
  factory GGUFFile.fromJson(Map<String, dynamic> j) => GGUFFile(
    filename    : j['filename'] as String,
    sizeBytes   : j['sizeBytes'] as int? ?? 0,
    downloadUrl : j['downloadUrl'] as String,
    quantization: j['quantization'] as String? ?? 'unknown',
    sha256      : j['sha256'] as String?,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CLASS: HuggingFaceModel
// ─────────────────────────────────────────────────────────────────────────────

/// Merepresentasikan model AI yang tersedia di HuggingFace
class HuggingFaceModel {
  final String repoId;      // "bartowski/Llama-3.2-1B-Instruct-GGUF"
  final String name;        // Nama tampilan
  final String author;
  final String description;
  final int likes;
  final int downloads;
  final List<String> tags;
  final List<GGUFFile> files; // Daftar file GGUF yang tersedia

  /// Alias untuk repoId — backward compatibility
  String get modelId => repoId;

  const HuggingFaceModel({
    required this.repoId,
    required this.name,
    required this.author,
    required this.description,
    required this.files,
    this.likes = 0,
    this.downloads = 0,
    this.tags = const [],
  });

  /// Total ukuran semua file dalam bytes (gunakan file terkecil sebagai representasi)
  int get smallestFileSizeBytes {
    if (files.isEmpty) return 0;
    return files.map((f) => f.sizeBytes).reduce((a, b) => a < b ? a : b);
  }

  /// Serialisasi ke Map JSON
  Map<String, dynamic> toJson() => {
    'repoId'      : repoId,
    'name'        : name,
    'author'      : author,
    'description' : description,
    'likes'       : likes,
    'downloads'   : downloads,
    'tags'        : tags,
    'files'       : files.map((f) => f.toJson()).toList(),
  };

  /// Buat dari Map JSON
  factory HuggingFaceModel.fromJson(Map<String, dynamic> j) => HuggingFaceModel(
    repoId     : j['repoId'] as String? ?? j['id'] as String? ?? '',
    name       : j['name'] as String? ?? j['modelId'] as String? ?? '',
    author     : j['author'] as String? ?? '',
    description: j['description'] as String? ?? '',
    likes      : j['likes'] as int? ?? 0,
    downloads  : j['downloads'] as int? ?? 0,
    tags       : List<String>.from(j['tags'] as List? ?? []),
    files      : (j['files'] as List?)
        ?.map((f) => GGUFFile.fromJson(f as Map<String, dynamic>))
        .toList() ?? [],
  );

  /// Buat dari response HuggingFace API
  factory HuggingFaceModel.fromApiJson(Map<String, dynamic> j) {
    final repoId = j['id'] as String? ?? '';
    final nameParts = repoId.split('/');
    final displayName = nameParts.length > 1 ? nameParts[1] : repoId;
    final author = nameParts.isNotEmpty ? nameParts[0] : '';

    // Parse daftar siblings (file) dari response API
    final siblings = (j['siblings'] as List?) ?? [];
    final ggufFiles = siblings
        .where((s) {
          final fname = (s as Map)['rfilename'] as String? ?? '';
          return fname.toLowerCase().endsWith('.gguf');
        })
        .map((s) {
          final fname = (s as Map)['rfilename'] as String;
          return GGUFFile(
            filename    : fname,
            sizeBytes   : (s['size'] as int?) ?? 0,
            downloadUrl : 'https://huggingface.co/$repoId/resolve/main/$fname',
            quantization: ModelManagerService.instance.parseQuantization(fname),
          );
        })
        .toList();

    return HuggingFaceModel(
      repoId     : repoId,
      name       : displayName.replaceAll('-', ' ').replaceAll('_', ' '),
      author     : author,
      description: j['description'] as String? ?? '',
      likes      : j['likes'] as int? ?? 0,
      downloads  : j['downloads'] as int? ?? 0,
      tags       : List<String>.from(j['tags'] as List? ?? []),
      files      : ggufFiles,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ENUM & CLASS: Download
// ─────────────────────────────────────────────────────────────────────────────

/// Status download sebuah model
enum DownloadStatus { queued, downloading, paused, completed, failed, cancelled }

/// Merepresentasikan satu tugas download
class DownloadTask {
  final String id;              // UUID
  final HuggingFaceModel model;
  final GGUFFile file;
  DownloadStatus status;
  double progress;              // 0.0 – 1.0
  String? error;
  int bytesDownloaded;
  final DateTime startedAt;
  DateTime? completedAt;
  String? savedPath;            // Path setelah download selesai

  DownloadTask({
    required this.id,
    required this.model,
    required this.file,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.error,
    this.bytesDownloaded = 0,
    required this.startedAt,
    this.completedAt,
    this.savedPath,
  });

  /// Serialisasi ke Map JSON
  Map<String, dynamic> toJson() => {
    'id'             : id,
    'model'          : model.toJson(),
    'file'           : file.toJson(),
    'status'         : status.name,
    'progress'       : progress,
    'error'          : error,
    'bytesDownloaded': bytesDownloaded,
    'startedAt'      : startedAt.toIso8601String(),
    'completedAt'    : completedAt?.toIso8601String(),
    'savedPath'      : savedPath,
  };

  /// Buat dari Map JSON
  factory DownloadTask.fromJson(Map<String, dynamic> j) => DownloadTask(
    id             : j['id'] as String,
    model          : HuggingFaceModel.fromJson(j['model'] as Map<String, dynamic>),
    file           : GGUFFile.fromJson(j['file'] as Map<String, dynamic>),
    status         : DownloadStatus.values.firstWhere(
      (s) => s.name == j['status'],
      orElse: () => DownloadStatus.failed,
    ),
    progress       : (j['progress'] as num?)?.toDouble() ?? 0.0,
    error          : j['error'] as String?,
    bytesDownloaded: j['bytesDownloaded'] as int? ?? 0,
    startedAt      : DateTime.parse(j['startedAt'] as String),
    completedAt    : j['completedAt'] != null
        ? DateTime.tryParse(j['completedAt'] as String)
        : null,
    savedPath      : j['savedPath'] as String?,
  );
}

/// Progress download real-time untuk satu task
class DownloadProgress {
  final String taskId;
  final int bytesDownloaded;
  final int totalBytes;
  final double percent;          // 0.0 – 100.0
  final double speedBytesPerSec;
  final int etaSeconds;
  final bool isComplete;
  final bool hasError;
  final String? error;

  const DownloadProgress({
    required this.taskId,
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.percent,
    required this.speedBytesPerSec,
    required this.etaSeconds,
    this.isComplete = false,
    this.hasError = false,
    this.error,
  });

  /// Nilai 0.0–1.0 untuk LinearProgressIndicator
  double get fraction => totalBytes > 0 ? bytesDownloaded / totalBytes : 0.0;

  /// Label persen yang mudah dibaca (contoh: \"42.3%\")
  String get percentLabel => '${percent.toStringAsFixed(1)}%';

  /// Alias untuk bytesDownloaded (kompatibilitas)
  int get received => bytesDownloaded;

  /// Alias untuk totalBytes (kompatibilitas)
  int get total => totalBytes;

  /// Label kecepatan download yang mudah dibaca (contoh: "1.2 MB/s")
  String get speedLabel {
    if (speedBytesPerSec >= 1024 * 1024) {
      return '${(speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    if (speedBytesPerSec >= 1024) {
      return '${(speedBytesPerSec / 1024).toStringAsFixed(0)} KB/s';
    }
    return '${speedBytesPerSec.toStringAsFixed(0)} B/s';
  }

  /// Label ETA yang mudah dibaca (contoh: "2 menit 30 detik")
  String get etaLabel {
    if (etaSeconds <= 0) return 'Menghitung...';
    if (etaSeconds < 60) return '$etaSeconds detik';
    final m = etaSeconds ~/ 60;
    final s = etaSeconds % 60;
    if (s == 0) return '$m menit';
    return '$m menit $s detik';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CLASS: ModelManagerService
// ─────────────────────────────────────────────────────────────────────────────

/// Service utama untuk manajemen model AI offline.
/// Arsitektur PocketPal: singleton, broadcast stream, download queue.
class ModelManagerService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final ModelManagerService instance = ModelManagerService._();
  ModelManagerService._();

  // ── State Internal ─────────────────────────────────────────────────────────

  /// Daftar model lokal yang terdeteksi di folder models/
  List<LocalModelInfo> _localModels = [];

  /// Daftar task download aktif dan riwayat
  final List<DownloadTask> _downloads = [];

  /// StreamController untuk perubahan daftar model lokal
  final StreamController<List<LocalModelInfo>> _localModelsCtrl =
      StreamController<List<LocalModelInfo>>.broadcast();

  /// StreamController untuk perubahan daftar download
  final StreamController<List<DownloadTask>> _downloadsCtrl =
      StreamController<List<DownloadTask>>.broadcast();

  /// Map taskId → StreamController untuk progress download per task
  final Map<String, StreamController<DownloadProgress>> _progressCtrl = {};

  /// Apakah sedang ada download yang berjalan (max concurrent = 1)
  bool _isDownloading = false;

  /// ID model yang sedang aktif/dipilih (dipersist ke SharedPreferences)
  String? _activeModelId;

  // ── Getters Publik ─────────────────────────────────────────────────────────

  /// Daftar model lokal (read-only)
  List<LocalModelInfo> get localModels => List.unmodifiable(_localModels);

  /// Alias untuk localModels — backward compatibility dengan kode lama
  List<LocalModelInfo> get models => localModels;

  /// Katalog model kurasi (hardcoded)
  List<HuggingFaceModel> get featuredModels => _featuredModels;

  /// Daftar semua download task (read-only)
  List<DownloadTask> get activeDownloads => List.unmodifiable(_downloads);

  /// Stream perubahan daftar model lokal (broadcast)
  Stream<List<LocalModelInfo>> get localModelsStream => _localModelsCtrl.stream;

  /// Stream perubahan daftar download (broadcast)
  Stream<List<DownloadTask>> get downloadsStream => _downloadsCtrl.stream;

  /// Path folder penyimpanan model
  String _modelsDirectory = '';
  String get modelsDirectory => _modelsDirectory;

  /// Model aktif yang terdaftar, termasuk yang file-nya mungkin sudah hilang.
  /// Gunakan [activeModel] jika butuh model yang file-nya pasti ada.
  LlamaModelInfo? get activeModelRaw {
    if (_activeModelId == null) return null;
    final local = _localModels
        .where((m) => m.id == _activeModelId)
        .firstOrNull;
    return local?.toLlamaModelInfo();
  }

  /// Model aktif yang file-nya dipastikan ada di disk.
  /// Mengembalikan null jika belum ada model dipilih atau file sudah dihapus.
  LlamaModelInfo? get activeModel {
    final raw = activeModelRaw;
    if (raw == null) return null;
    return File(raw.path).existsSync() ? raw : null;
  }

  /// Alias untuk [initialize] — backward compatibility.
  Future<void> load() => initialize();

  /// Simpan pilihan model aktif ke SharedPreferences.
  Future<void> setActive(String modelId) async {
    _activeModelId = modelId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kActiveModelKey, modelId);
      debugPrint('[ModelManager] activeModel set: $modelId');
    } catch (e) {
      debugPrint('[ModelManager] setActive error: $e');
    }
  }

  /// Alias untuk [setActive] — backward compatibility.
  Future<void> setActiveModel(String modelId) => setActive(modelId);

  // ── Katalog Model Kurasi ───────────────────────────────────────────────────

  /// 8 model kurasi pilihan untuk layar "Jelajahi"
  static final List<HuggingFaceModel> _featuredModels = [
    // Llama 3.2 1B — Ringan, cocok HP mid-range
    HuggingFaceModel(
      repoId     : 'bartowski/Llama-3.2-1B-Instruct-GGUF',
      name       : 'Llama 3.2 1B Instruct',
      author     : 'Meta',
      description: 'Ringan & cepat, cocok untuk HP mid-range. Bahasa Inggris & Indonesia.',
      tags       : ['general', 'fast', 'low-ram'],
      files      : [
        GGUFFile(
          filename    : 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
          sizeBytes   : 681574400,
          downloadUrl : 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
          quantization: 'Q4_K_M',
        ),
      ],
    ),

    // Llama 3.2 3B — Seimbang kualitas & kecepatan
    HuggingFaceModel(
      repoId     : 'bartowski/Llama-3.2-3B-Instruct-GGUF',
      name       : 'Llama 3.2 3B Instruct',
      author     : 'Meta',
      description: 'Seimbang antara kualitas dan kecepatan. Rekomendasi utama.',
      tags       : ['general', 'recommended', 'balanced'],
      files      : [
        GGUFFile(
          filename    : 'Llama-3.2-3B-Instruct-Q4_K_M.gguf',
          sizeBytes   : 1886003200,
          downloadUrl : 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
          quantization: 'Q4_K_M',
        ),
      ],
    ),

    // Phi-3.5 Mini — Kualitas tinggi, ukuran kecil
    HuggingFaceModel(
      repoId     : 'bartowski/Phi-3.5-mini-instruct-GGUF',
      name       : 'Phi-3.5 Mini Instruct',
      author     : 'Microsoft',
      description: 'Kualitas flagship dalam ukuran kecil. Sangat bagus untuk coding.',
      tags       : ['coding', 'quality', 'microsoft'],
      files      : [
        GGUFFile(
          filename    : 'Phi-3.5-mini-instruct-Q4_K_M.gguf',
          sizeBytes   : 2393800704,
          downloadUrl : 'https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf',
          quantization: 'Q4_K_M',
        ),
      ],
    ),

    // Gemma 2 2B — Google, kualitas tinggi
    HuggingFaceModel(
      repoId     : 'bartowski/gemma-2-2b-it-GGUF',
      name       : 'Gemma 2 2B Instruct',
      author     : 'Google',
      description: 'Model Google dengan kualitas sangat baik untuk ukurannya.',
      tags       : ['general', 'google', 'quality'],
      files      : [
        GGUFFile(
          filename    : 'gemma-2-2b-it-Q4_K_M.gguf',
          sizeBytes   : 1637237760,
          downloadUrl : 'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
          quantization: 'Q4_K_M',
        ),
      ],
    ),

    // Qwen2.5 1.5B — Bagus untuk bahasa Asia
    HuggingFaceModel(
      repoId     : 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
      name       : 'Qwen 2.5 1.5B Instruct',
      author     : 'Alibaba',
      description: 'Sangat baik untuk bahasa Indonesia, Jepang, dan Mandarin.',
      tags       : ['multilingual', 'asian-languages', 'fast'],
      files      : [
        GGUFFile(
          filename    : 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
          sizeBytes   : 986513408,
          downloadUrl : 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
          quantization: 'Q4_K_M',
        ),
      ],
    ),

    // DeepSeek R1 Distill 1.5B — Reasoning
    HuggingFaceModel(
      repoId     : 'bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF',
      name       : 'DeepSeek R1 Distill 1.5B',
      author     : 'DeepSeek',
      description: 'Kemampuan reasoning dan berpikir logis yang kuat.',
      tags       : ['reasoning', 'math', 'logic'],
      files      : [
        GGUFFile(
          filename    : 'DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf',
          sizeBytes   : 986513408,
          downloadUrl : 'https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf',
          quantization: 'Q4_K_M',
        ),
      ],
    ),

    // SmolLM2 1.7B — Ultra-efficient
    HuggingFaceModel(
      repoId     : 'HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF',
      name       : 'SmolLM2 1.7B Instruct',
      author     : 'HuggingFace',
      description: 'Ultra-efficient dari HuggingFace. Cepat dan hemat baterai.',
      tags       : ['efficient', 'fast', 'battery-friendly'],
      files      : [
        GGUFFile(
          filename    : 'smollm2-1.7b-instruct-q4_k_m.gguf',
          sizeBytes   : 1073741824,
          downloadUrl : 'https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF/resolve/main/smollm2-1.7b-instruct-q4_k_m.gguf',
          quantization: 'Q4_K_M',
        ),
      ],
    ),

    // Mistral 7B — Kualitas tertinggi (butuh HP high-end)
    HuggingFaceModel(
      repoId     : 'TheBloke/Mistral-7B-Instruct-v0.3-GGUF',
      name       : 'Mistral 7B Instruct v0.3',
      author     : 'Mistral AI',
      description: 'Kualitas tertinggi — butuh HP flagship dengan RAM 6GB+.',
      tags       : ['quality', 'high-end', 'flagship'],
      files      : [
        GGUFFile(
          filename    : 'mistral-7b-instruct-v0.3.Q4_K_M.gguf',
          sizeBytes   : 4368269312,
          downloadUrl : 'https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.3-GGUF/resolve/main/mistral-7b-instruct-v0.3.Q4_K_M.gguf',
          quantization: 'Q4_K_M',
        ),
      ],
    ),
  ];

  // ── Inisialisasi ───────────────────────────────────────────────────────────

  /// Inisialisasi service: siapkan folder, scan model lokal, muat cache
  Future<void> initialize() async {
    final appDir = await getApplicationDocumentsDirectory();
    _modelsDirectory = '${appDir.path}/models';

    // Buat folder models jika belum ada
    final dir = Directory(_modelsDirectory);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      debugPrint('[ModelManager] Folder models dibuat: $_modelsDirectory');
    }

    // Muat cache dari SharedPreferences
    await _loadCache();

    // Scan ulang untuk memperbarui status file
    await scanLocalModels();

    debugPrint('[ModelManager] initialize() selesai — ${_localModels.length} model ditemukan');
  }

  // ── Manajemen Model Lokal ──────────────────────────────────────────────────

  /// Scan folder models/ dan perbarui daftar model lokal
  Future<void> scanLocalModels() async {
    try {
      final dir = Directory(_modelsDirectory);
      if (!dir.existsSync()) return;

      final loadedModelPath = LlamaService.instance.currentModel?.path;
      final foundModels = <LocalModelInfo>[];

      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final path = entity.path;
        final filename = path.split('/').last.toLowerCase();

        // Hanya proses file GGUF dan GGML
        if (!filename.endsWith('.gguf') && !filename.endsWith('.ggml')) continue;

        final existingModel = _localModels
            .where((m) => m.path == path)
            .firstOrNull;

        if (existingModel != null) {
          // Perbarui status isLoaded dari LlamaService
          foundModels.add(existingModel.copyWith(
            isLoaded: loadedModelPath == path,
          ));
        } else {
          // Model baru — parse info dari file
          final info = await getModelDetails(path);
          if (info != null) foundModels.add(info);
        }
      }

      _localModels = foundModels;
      await _saveCache();
      _emitLocalModels();
    } catch (e) {
      debugPrint('[ModelManager] scanLocalModels error: $e');
    }
  }

  /// Import file model dari path eksternal ke folder models/
  /// Import model dari path eksternal ke folder models/.
  /// Delegates to [importModelWithProgress] with no-op progress callback.
  Future<LocalModelInfo?> importModel(String sourcePath) async {
    return importModelWithProgress(sourcePath, onProgress: (_) {});
  }

  /// Import model dari bytes — fallback untuk Android scoped storage.
  ///
  /// Menulis bytes ke disk dalam chunk 256 KB agar tidak memblokir isolate
  /// untuk waktu yang lama saat file berukuran besar.
  Future<LocalModelInfo?> importModelFromBytes(
    List<int> bytes,
    String filename, {
    void Function(double progress)? onProgress,
  }) async {
    final destPath = '$_modelsDirectory/$filename';
    final destFile = File(destPath);
    IOSink? sink;

    try {
      sink = destFile.openWrite();
      const chunkSize = 256 * 1024; // 256 KB per chunk
      final total = bytes.length;
      int written = 0;

      while (written < total) {
        final end = min(written + chunkSize, total);
        sink.add(bytes.sublist(written, end));
        written = end;
        // Yield to event loop so UI can update
        await Future<void>.delayed(Duration.zero);
        onProgress?.call(written / total);
      }

      await sink.flush();
      await sink.close();
      sink = null;

      debugPrint(
        '[ModelManager] importModelFromBytes: wrote $total bytes → $destPath',
      );

      final info = await getModelDetails(destPath);
      if (info == null) {
        if (destFile.existsSync()) await destFile.delete();
        return null;
      }

      _localModels.removeWhere((m) => m.path == destPath);
      _localModels.add(info);
      await _saveCache();
      _emitLocalModels();

      debugPrint('[ModelManager] ✅ Model diimport dari bytes: ${info.name}');
      return info;
    } catch (e) {
      debugPrint('[ModelManager] importModelFromBytes error: $e');
      await sink?.close().catchError((_) {});
      if (destFile.existsSync()) await destFile.delete().catchError((_) {});
      return null;
    }
  }

  /// Import model dari path sumber ke folder models/ dengan progress callback.
  ///
  /// Menggunakan stream-based copy (chunk 1 MB) agar:
  ///   - Tidak ada memory spike untuk file besar (4–8 GB GGUF)
  ///   - UI tetap responsif selama proses berlangsung
  ///   - Progress (0.0–1.0) dilaporkan setiap chunk
  ///
  /// Jika [sourcePath] berada di folder temp (misalnya karena SAF bytes fallback
  /// di Session 4), file temp akan dihapus otomatis setelah copy berhasil.
  ///
  /// Returns [LocalModelInfo] jika berhasil, null jika gagal.
  Future<LocalModelInfo?> importModelWithProgress(
    String sourcePath, {
    required void Function(double progress) onProgress,
  }) async {
    final srcFile = File(sourcePath);

    if (!srcFile.existsSync()) {
      debugPrint(
        '[ModelManager] importModelWithProgress: file tidak ditemukan: $sourcePath',
      );
      return null;
    }

    final filename = sourcePath.split('/').last;
    final destPath = '$_modelsDirectory/$filename';

    // If the source is already in the models directory, skip copy
    if (sourcePath == destPath) {
      debugPrint('[ModelManager] Source == dest, skipping copy: $sourcePath');
      onProgress(1.0);
      final info = await getModelDetails(destPath);
      if (info == null) return null;
      _localModels.removeWhere((m) => m.path == destPath);
      _localModels.add(info);
      await _saveCache();
      _emitLocalModels();
      return info;
    }

    final destFile = File(destPath);
    // Remove partial/corrupt destination if it exists from a previous failed import
    if (destFile.existsSync()) {
      debugPrint('[ModelManager] Removing existing dest file before import: $destPath');
      await destFile.delete();
    }

    final totalBytes = srcFile.lengthSync();
    debugPrint(
      '[ModelManager] importModelWithProgress: '
      '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB → $destPath',
    );

    IOSink? sink;
    try {
      sink = destFile.openWrite();
      final inputStream = srcFile.openRead();

      const chunkSize = 1024 * 1024; // 1 MB per chunk — good balance for GGUF
      int bytesWritten = 0;

      await for (final chunk in inputStream) {
        // Write chunk
        sink.add(chunk);
        bytesWritten += chunk.length;

        // Report progress — yield every ~1 MB
        if (bytesWritten % chunkSize < chunk.length) {
          await sink.flush(); // ensure OS writes buffer
          final progress = totalBytes > 0
              ? (bytesWritten / totalBytes).clamp(0.0, 1.0)
              : 0.0;
          onProgress(progress);
          // Yield to event loop so Flutter can render the progress bar
          await Future<void>.delayed(Duration.zero);
        }
      }

      // Final flush and close
      await sink.flush();
      await sink.close();
      sink = null;

      onProgress(1.0);

      // Verify written size matches source
      final writtenSize = destFile.lengthSync();
      if (writtenSize != totalBytes) {
        debugPrint(
          '[ModelManager] Size mismatch: expected $totalBytes, got $writtenSize — deleting corrupt dest',
        );
        await destFile.delete();
        return null;
      }

      debugPrint(
        '[ModelManager] ✅ Copy selesai: $filename '
        '(${(writtenSize / (1024 * 1024)).toStringAsFixed(1)} MB)',
      );

      // Register in local models
      final info = await getModelDetails(destPath);
      if (info == null) {
        debugPrint('[ModelManager] getModelDetails returned null — removing dest');
        if (destFile.existsSync()) await destFile.delete();
        return null;
      }

      _localModels.removeWhere((m) => m.path == destPath);
      _localModels.add(info);
      await _saveCache();
      _emitLocalModels();

      // Clean up temp file created by SAF bytes fallback (Session 4 Case B/C)
      // Temp files are in the system temp dir — safe to delete after copy
      try {
        if (srcFile.path.contains('/cache/') || srcFile.path.contains('/tmp/')) {
          await srcFile.delete();
          debugPrint('[ModelManager] Temp source file deleted: ${srcFile.path}');
        }
      } catch (_) {
        // Non-critical — temp cleanup failure is acceptable
      }

      return info;
    } catch (e) {
      debugPrint('[ModelManager] importModelWithProgress error: $e');
      // Close sink before attempting delete
      await sink?.close().catchError((_) {});
      // Remove partial destination file to avoid corrupt model in the list
      if (destFile.existsSync()) {
        await destFile.delete().catchError((_) {});
      }
      return null;
    }
  }

  /// Hapus model dari daftar dan disk
  Future<void> deleteModel(String modelId) async {
    final model = _localModels.where((m) => m.id == modelId).firstOrNull;
    if (model == null) {
      debugPrint('[ModelManager] deleteModel: id $modelId tidak ditemukan');
      return;
    }

    // Hapus file fisik
    final file = File(model.path);
    if (file.existsSync()) {
      await file.delete();
      debugPrint('[ModelManager] ✅ File dihapus: ${model.path}');
    }

    _localModels.removeWhere((m) => m.id == modelId);
    await _saveCache();
    _emitLocalModels();
    debugPrint('[ModelManager] ✅ Model $modelId dihapus dari daftar');
  }

  /// Parse info model dari path file (nama, ukuran, kuantisasi, estimasi RAM)
  Future<LocalModelInfo?> getModelDetails(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;

      final filename = path.split('/').last;
      final nameWithoutExt = filename
          .replaceAll(RegExp(r'\.(gguf|ggml)$', caseSensitive: false), '');

      final sizeBytes = await file.length();
      final quantization = parseQuantization(filename);
      final estimatedRam = estimateRamMb(sizeBytes, quantization);
      final format = filename.toLowerCase().endsWith('.ggml') ? 'ggml' : 'gguf';
      final loadedModelPath = LlamaService.instance.currentModel?.path;

      return LocalModelInfo(
        id            : const Uuid().v4(),
        name          : _cleanName(nameWithoutExt),
        path          : path,
        sizeBytes     : sizeBytes,
        format        : format,
        quantization  : quantization,
        estimatedRamMb: estimatedRam,
        isLoaded      : loadedModelPath == path,
      );
    } catch (e) {
      debugPrint('[ModelManager] getModelDetails error untuk $path: $e');
      return null;
    }
  }

  // ── Pencarian HuggingFace ──────────────────────────────────────────────────

  /// Cari model di HuggingFace API berdasarkan query string.
  /// Endpoint: GET https://huggingface.co/api/models?search={query}&filter=gguf&limit=10
  Future<List<HuggingFaceModel>> searchHuggingFace(String query) async {
    try {
      final uri = Uri.parse(
        'https://huggingface.co/api/models'
        '?search=${Uri.encodeComponent(query)}'
        '&filter=gguf'
        '&limit=10'
        '&full=true',
      );

      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('[ModelManager] HuggingFace API error: ${response.statusCode}');
        return [];
      }

      final List<dynamic> data = jsonDecode(response.body) as List;
      final results = <HuggingFaceModel>[];

      for (final item in data) {
        try {
          final model = HuggingFaceModel.fromApiJson(item as Map<String, dynamic>);
          // Hanya tampilkan model yang memiliki file GGUF
          if (model.files.isNotEmpty) results.add(model);
        } catch (e) {
          debugPrint('[ModelManager] Parse model error: $e');
        }
      }

      debugPrint('[ModelManager] Hasil pencarian "$query": ${results.length} model');
      return results;
    } catch (e) {
      debugPrint('[ModelManager] searchHuggingFace error: $e');
      return [];
    }
  }

  // ── Manajemen Download ─────────────────────────────────────────────────────

  /// Mulai download file GGUF dari HuggingFace.
  /// Jika sedang ada download lain, task baru akan diqueue.
  Future<DownloadTask> startDownload(GGUFFile file, HuggingFaceModel model) async {
    // Buat task baru
    final task = DownloadTask(
      id        : const Uuid().v4(),
      model     : model,
      file      : file,
      status    : DownloadStatus.queued,
      startedAt : DateTime.now(),
    );
    _downloads.add(task);
    _emitDownloads();

    // Mulai proses download (queue otomatis jika ada download lain)
    _processDownloadQueue();

    debugPrint('[ModelManager] Download task dibuat: ${file.filename}');
    return task;
  }

  /// Download langsung dari URL tanpa memerlukan GGUFFile/HuggingFaceModel.
  /// Digunakan oleh AiCatalogScreen untuk download dari katalog.
  Stream<DownloadProgress> downloadFromUrl({
    required String url,
    required String modelId,
    required String customName,
  }) async* {
    int receivedBytes = 0;
    int totalBytes   = 0;
    int lastBytes    = 0;
    DateTime lastSpeedCheck = DateTime.now();
    double speedBps  = 0;
    int etaSec       = 0;

    final filename = customName.isNotEmpty ? customName : Uri.parse(url).pathSegments.last;
    final destPath = '$_modelsDirectory/$filename';
    final destFile = File(destPath);

    try {
      // Resolve redirect (HuggingFace 302 → CDN)
      String finalUrl = url;
      try {
        final headResp = await http.get(Uri.parse(url))
            .timeout(const Duration(seconds: 15));
        if (headResp.request?.url != null) {
          finalUrl = headResp.request!.url.toString();
        }
      } catch (_) {}

      final client  = http.Client();
      final request = http.Request('GET', Uri.parse(finalUrl));
      final resp    = await client.send(request);

      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw Exception('HTTP ${resp.statusCode} — download gagal');
      }

      totalBytes = resp.contentLength ?? 0;
      final sink = destFile.openWrite();

      await for (final chunk in resp.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;

        final now     = DateTime.now();
        final elapsed = now.difference(lastSpeedCheck).inMilliseconds;
        if (elapsed >= 500) {
          speedBps       = (receivedBytes - lastBytes) / (elapsed / 1000);
          lastBytes      = receivedBytes;
          lastSpeedCheck = now;
          if (speedBps > 0 && totalBytes > 0) {
            etaSec = ((totalBytes - receivedBytes) / speedBps).round();
          }
        }

        yield DownloadProgress(
          taskId          : modelId,
          bytesDownloaded : receivedBytes,
          totalBytes      : totalBytes,
          percent         : totalBytes > 0 ? (receivedBytes / totalBytes) * 100 : 0,
          speedBytesPerSec: speedBps,
          etaSeconds      : etaSec,
        );
      }

      await sink.close();
      client.close();

      await scanLocalModels();

      yield DownloadProgress(
        taskId          : modelId,
        bytesDownloaded : receivedBytes,
        totalBytes      : totalBytes,
        percent         : 100,
        speedBytesPerSec: 0,
        etaSeconds      : 0,
        isComplete      : true,
      );
    } catch (e) {
      if (destFile.existsSync()) await destFile.delete();
      yield DownloadProgress(
        taskId          : modelId,
        bytesDownloaded : receivedBytes,
        totalBytes      : totalBytes,
        percent         : 0,
        speedBytesPerSec: 0,
        etaSeconds      : 0,
        hasError        : true,
        error           : e.toString(),
      );
    }
  }

  /// Jeda download yang sedang berjalan
  Future<void> pauseDownload(String taskId) async {
    final task = _findTask(taskId);
    if (task == null || task.status != DownloadStatus.downloading) return;

    task.status = DownloadStatus.paused;
    _emitDownloads();

    // Tutup StreamController progress untuk membatalkan download loop
    _progressCtrl[taskId]?.close();
    _progressCtrl.remove(taskId);

    _isDownloading = false;
    debugPrint('[ModelManager] Download dijeda: $taskId');

    // Proses task berikutnya dalam queue
    _processDownloadQueue();
  }

  /// Lanjutkan download yang dijeda
  Future<void> resumeDownload(String taskId) async {
    final task = _findTask(taskId);
    if (task == null || task.status != DownloadStatus.paused) return;

    task.status = DownloadStatus.queued;
    _emitDownloads();
    _processDownloadQueue();
    debugPrint('[ModelManager] Download dilanjutkan: $taskId');
  }

  /// Batalkan download (hapus file parsial)
  Future<void> cancelDownload(String taskId) async {
    final task = _findTask(taskId);
    if (task == null) return;

    task.status = DownloadStatus.cancelled;

    // Tutup progress stream
    _progressCtrl[taskId]?.close();
    _progressCtrl.remove(taskId);

    // Hapus file parsial jika ada
    final destPath = '$_modelsDirectory/${task.file.filename}';
    final partialFile = File(destPath);
    if (partialFile.existsSync()) {
      try { await partialFile.delete(); } catch (_) {}
    }

    _isDownloading = false;
    _emitDownloads();
    _processDownloadQueue();
    debugPrint('[ModelManager] Download dibatalkan: $taskId');
  }

  /// Pantau progress download untuk task tertentu
  Stream<DownloadProgress> watchDownload(String taskId) {
    _progressCtrl[taskId] ??= StreamController<DownloadProgress>.broadcast();
    return _progressCtrl[taskId]!.stream;
  }

  // ── Utilitas ───────────────────────────────────────────────────────────────

  /// Dapatkan ruang penyimpanan yang tersedia dalam MB
  Future<int> getAvailableStorageMb() async {
    try {
      // Gunakan ukuran folder models untuk estimasi kasar
      final dir = Directory(_modelsDirectory);
      if (!dir.existsSync()) return 4096; // Asumsi default 4GB
      // Dart tidak memiliki API langsung untuk free space — kembalikan estimasi
      return 4096;
    } catch (_) {
      return 0;
    }
  }

  /// Dapatkan RAM yang tersedia dalam MB via LlamaService
  Future<int> getAvailableRamMb() async {
    try {
      return await LlamaService.instance.getAvailableMemoryMb();
    } catch (_) {
      return 0;
    }
  }

  /// Cek apakah RAM tersedia cukup untuk model
  bool isRamSufficient(LocalModelInfo model) {
    // Perbandingan synchronous — gunakan threshold konservatif
    return model.estimatedRamMb <= 3500;
  }

  /// Format bytes ke string yang mudah dibaca
  String formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  /// Parse kuantisasi dari nama file (contoh: "Q4_K_M" dari "model-Q4_K_M.gguf")
  String parseQuantization(String filename) {
    final upper = filename.toUpperCase();
    const patterns = [
      'Q2_K', 'Q3_K_M', 'Q3_K_S', 'Q3_K_L',
      'Q4_K_M', 'Q4_K_S', 'Q4_0', 'Q4_1',
      'Q5_K_M', 'Q5_K_S', 'Q5_0', 'Q5_1',
      'Q6_K', 'Q8_0', 'F16', 'F32',
    ];
    for (final pattern in patterns) {
      if (upper.contains(pattern)) return pattern;
    }
    return 'unknown';
  }

  /// Estimasi kebutuhan RAM dari ukuran file dan tipe kuantisasi
  int estimateRamMb(int fileSizeBytes, String quantization) {
    // Overhead: KV cache + scratch buffer ≈ 25-40% dari ukuran file
    double multiplier;
    switch (quantization.toUpperCase()) {
      case 'F32':
        multiplier = 1.5; // F32 butuh overhead lebih besar
        break;
      case 'F16':
        multiplier = 1.4;
        break;
      case 'Q8_0':
        multiplier = 1.35;
        break;
      case 'Q6_K':
        multiplier = 1.3;
        break;
      case 'Q5_K_M':
      case 'Q5_K_S':
        multiplier = 1.28;
        break;
      case 'Q4_K_M':
      case 'Q4_K_S':
        multiplier = 1.25;
        break;
      default:
        multiplier = 1.3;
    }
    return ((fileSizeBytes / (1024 * 1024)) * multiplier).ceil();
  }

  // ── Persistensi Cache ──────────────────────────────────────────────────────

  /// Simpan daftar model lokal ke SharedPreferences
  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(_localModels.map((m) => m.toJson()).toList());
      await prefs.setString(_kCacheKey, data);
    } catch (e) {
      debugPrint('[ModelManager] _saveCache error: $e');
    }
  }

  /// Muat daftar model lokal dari SharedPreferences
  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Muat active model ID yang tersimpan
      _activeModelId = prefs.getString(_kActiveModelKey);

      final raw = prefs.getString(_kCacheKey);
      if (raw == null) return;

      final List<dynamic> list = jsonDecode(raw) as List;
      _localModels = list
          .map((j) => LocalModelInfo.fromJson(j as Map<String, dynamic>))
          .toList();

      debugPrint('[ModelManager] Cache dimuat: ${_localModels.length} model, activeId=$_activeModelId');
    } catch (e) {
      debugPrint('[ModelManager] _loadCache error: $e');
      _localModels = [];
    }
  }

  // ── Internal: Queue & Download Loop ───────────────────────────────────────

  /// Proses task download berikutnya dalam queue (max concurrent = 1)
  void _processDownloadQueue() {
    if (_isDownloading) return;

    final nextTask = _downloads
        .where((t) => t.status == DownloadStatus.queued)
        .firstOrNull;

    if (nextTask == null) return;

    _isDownloading = true;
    nextTask.status = DownloadStatus.downloading;
    _emitDownloads();

    // Jalankan download di background
    _runDownload(nextTask).then((_) {
      _isDownloading = false;
      _processDownloadQueue(); // Cek apakah ada task berikutnya
    });
  }

  /// Eksekusi satu task download dengan HTTP + Range header untuk resume.
  /// Mendukung redirect otomatis (HuggingFace CDN mengembalikan 302).
  Future<void> _runDownload(DownloadTask task) async {
    // Pastikan direktori sudah diinisialisasi sebelum download
    if (_modelsDirectory.isEmpty) {
      await initialize();
    }

    final destPath = '$_modelsDirectory/${task.file.filename}';
    final destFile = File(destPath);

    // Cek byte yang sudah ada (untuk resume)
    int startByte = destFile.existsSync() ? destFile.lengthSync() : 0;

    final progressCtrl = StreamController<DownloadProgress>.broadcast();
    _progressCtrl[task.id] = progressCtrl;

    final startTime = DateTime.now();
    int lastBytes = startByte;
    DateTime lastSpeedCheck = startTime;

    try {
      // ── Resolve URL final (ikuti redirect 301/302/307/308) ───────────────
      // HuggingFace /resolve/main/ mengembalikan 302 ke CDN.
      // http.Client().send() untuk StreamedResponse tidak otomatis follow
      // redirect, sehingga response body kosong → file 0 bytes → gagal.
      String finalUrl = task.file.downloadUrl;
      {
        final headClient = http.Client();
        try {
          final headResp = await headClient
              .get(Uri.parse(finalUrl))
              .timeout(const Duration(seconds: 15));
          // Jika menggunakan http.get (non-streaming), redirects diikuti otomatis.
          // Ambil URL final dari response setelah redirect.
          if (headResp.request?.url != null) {
            finalUrl = headResp.request!.url.toString();
            debugPrint('[ModelManager] URL final setelah redirect: $finalUrl');
          }
        } catch (_) {
          // Gunakan URL asli jika head request gagal
        } finally {
          headClient.close();
        }
      }

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(finalUrl));

      // Tambahkan Range header jika ada byte yang sudah didownload
      if (startByte > 0) {
        request.headers['Range'] = 'bytes=$startByte-';
        debugPrint('[ModelManager] Resume download dari byte $startByte');
      }

      final streamedResponse = await client.send(request);

      // Jika server tidak support resume (200), mulai dari awal
      if (streamedResponse.statusCode == 200 && startByte > 0) {
        startByte = 0;
        if (destFile.existsSync()) await destFile.delete();
      } else if (streamedResponse.statusCode != 200 &&
                 streamedResponse.statusCode != 206) {
        throw Exception('HTTP ${streamedResponse.statusCode} — download gagal');
      }

      final totalBytes = streamedResponse.contentLength != null
          ? streamedResponse.contentLength! + startByte
          : task.file.sizeBytes;

      int receivedBytes = startByte;
      final sink = destFile.openWrite(
        mode: startByte > 0 ? FileMode.append : FileMode.write,
      );

      await for (final chunk in streamedResponse.stream) {
        // Cek apakah task masih aktif (bisa dijeda atau dibatalkan)
        final currentTask = _findTask(task.id);
        if (currentTask == null ||
            currentTask.status == DownloadStatus.paused ||
            currentTask.status == DownloadStatus.cancelled) {
          await sink.close();
          client.close();
          return;
        }

        sink.add(chunk);
        receivedBytes += chunk.length;

        // Hitung kecepatan dan ETA setiap 500ms
        final now = DateTime.now();
        final speedElapsed = now.difference(lastSpeedCheck).inMilliseconds;
        double speedBps = 0;
        int etaSec = 0;

        if (speedElapsed >= 500) {
          final bytesInInterval = receivedBytes - lastBytes;
          speedBps = bytesInInterval / (speedElapsed / 1000);
          lastBytes = receivedBytes;
          lastSpeedCheck = now;

          if (speedBps > 0 && totalBytes > 0) {
            etaSec = ((totalBytes - receivedBytes) / speedBps).round();
          }
        }

        // Update task progress
        task.bytesDownloaded = receivedBytes;
        task.progress = totalBytes > 0 ? receivedBytes / totalBytes : 0;

        // Emit progress ke stream
        if (!progressCtrl.isClosed) {
          progressCtrl.add(DownloadProgress(
            taskId          : task.id,
            bytesDownloaded : receivedBytes,
            totalBytes      : totalBytes,
            percent         : task.progress * 100,
            speedBytesPerSec: speedBps,
            etaSeconds      : etaSec,
          ));
        }

        _emitDownloads();
      }

      await sink.close();
      client.close();

      // Verifikasi file berhasil disimpan
      // Beri sedikit jeda agar OS flush buffer ke disk
      await Future.delayed(const Duration(milliseconds: 200));

      final savedSize = destFile.existsSync() ? destFile.lengthSync() : 0;
      debugPrint('[ModelManager] Verifikasi file: $destPath ($savedSize bytes)');

      if (savedSize == 0) {
        throw Exception('File gagal disimpan ke penyimpanan (0 bytes)');
      }
      // Verifikasi ukuran wajar: minimal 1MB untuk file GGUF
      if (savedSize < 1024 * 1024) {
        if (destFile.existsSync()) await destFile.delete();
        throw Exception('File tidak valid — ukuran terlalu kecil (${savedSize} bytes)');
      }

      // Update task sebagai selesai
      task.status      = DownloadStatus.completed;
      task.progress    = 1.0;
      task.completedAt = DateTime.now();
      task.savedPath   = destPath;
      _emitDownloads();

      // Tutup progress stream
      if (!progressCtrl.isClosed) progressCtrl.close();
      _progressCtrl.remove(task.id);

      // Scan ulang model lokal agar model baru langsung muncul
      await scanLocalModels();

      debugPrint('[ModelManager] ✅ Download selesai: ${task.file.filename}');
    } catch (e) {
      debugPrint('[ModelManager] ❌ Download error: $e');

      task.status = DownloadStatus.failed;
      task.error  = e.toString();
      _emitDownloads();

      if (!progressCtrl.isClosed) {
        progressCtrl.addError(e);
        progressCtrl.close();
      }
      _progressCtrl.remove(task.id);
    }
  }

  // ── Helper Internal ────────────────────────────────────────────────────────

  /// Cari task berdasarkan ID
  DownloadTask? _findTask(String taskId) {
    return _downloads.where((t) => t.id == taskId).firstOrNull;
  }

  /// Emit perubahan daftar model lokal ke stream
  void _emitLocalModels() {
    if (!_localModelsCtrl.isClosed) {
      _localModelsCtrl.add(List.unmodifiable(_localModels));
    }
  }

  /// Emit perubahan daftar download ke stream
  void _emitDownloads() {
    if (!_downloadsCtrl.isClosed) {
      _downloadsCtrl.add(List.unmodifiable(_downloads));
    }
  }

  /// Bersihkan nama file menjadi judul yang mudah dibaca
  String _cleanName(String raw) {
    return raw
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ')
        .trim();
  }
}
