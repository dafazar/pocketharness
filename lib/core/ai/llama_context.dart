// lib/core/ai/llama_context.dart
// Model data utama untuk arsitektur AI offline KanMon GO
// Berisi semua class, enum, dan model yang dibutuhkan oleh sistem LlamaContext

import 'dart:math';
import 'package:uuid/uuid.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────────────────────────────────────

/// Peran dalam percakapan chat
enum ChatRole { system, user, assistant }

/// Alasan inferensi berhenti
enum StopReason { eosToken, maxTokens, userCancelled, timeout, error }

/// Status model AI saat ini
enum ModelStatus { notLoaded, loading, loaded, error, generating }

/// Jenis kuantisasi model GGUF
enum QuantizationType {
  q2K,
  q3KM,
  q4KM,
  q4KS,
  q5KM,
  q5KS,
  q6K,
  q8_0,
  f16,
  f32,
  unknown,
}

/// Template chat yang didukung oleh model
enum ChatTemplate {
  auto,
  chatML,
  llama3,
  mistral,
  gemma,
  phi3,
  alpaca,
  zephyr,
}

// ─────────────────────────────────────────────────────────────────────────────
// CLASS: ChatMessage
// ─────────────────────────────────────────────────────────────────────────────

/// Merepresentasikan satu pesan dalam sesi chat
class ChatMessage {
  final String id;
  final ChatRole role;
  final String content;
  final DateTime timestamp;
  final int? tokenCount;
  final int? generationMs;
  final StopReason? stopReason;
  final bool isError;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.tokenCount,
    this.generationMs,
    this.stopReason,
    this.isError = false,
  });

  /// Buat pesan dari pengguna
  factory ChatMessage.user(String content) {
    return ChatMessage(
      id: const Uuid().v4(),
      role: ChatRole.user,
      content: content,
      timestamp: DateTime.now(),
    );
  }

  /// Buat pesan dari asisten AI
  factory ChatMessage.assistant(String content) {
    return ChatMessage(
      id: const Uuid().v4(),
      role: ChatRole.assistant,
      content: content,
      timestamp: DateTime.now(),
    );
  }

  /// Buat pesan sistem (instruksi/prompt sistem)
  factory ChatMessage.system(String content) {
    return ChatMessage(
      id: const Uuid().v4(),
      role: ChatRole.system,
      content: content,
      timestamp: DateTime.now(),
    );
  }

  /// Buat salinan dengan nilai yang diperbarui
  ChatMessage copyWith({
    String? id,
    ChatRole? role,
    String? content,
    DateTime? timestamp,
    int? tokenCount,
    int? generationMs,
    StopReason? stopReason,
    bool? isError,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      tokenCount: tokenCount ?? this.tokenCount,
      generationMs: generationMs ?? this.generationMs,
      stopReason: stopReason ?? this.stopReason,
      isError: isError ?? this.isError,
    );
  }

  /// Konversi ke Map JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.name,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'tokenCount': tokenCount,
      'generationMs': generationMs,
      'stopReason': stopReason?.name,
      'isError': isError,
    };
  }

  /// Buat dari Map JSON
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      role: ChatRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => ChatRole.user,
      ),
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      tokenCount: json['tokenCount'] as int?,
      generationMs: json['generationMs'] as int?,
      stopReason:
          json['stopReason'] != null
              ? StopReason.values.firstWhere(
                (e) => e.name == json['stopReason'],
                orElse: () => StopReason.eosToken,
              )
              : null,
      isError: json['isError'] as bool? ?? false,
    );
  }

  @override
  String toString() =>
      'ChatMessage(id: $id, role: $role, content: ${content.substring(0, min(50, content.length))}...)';
}

// ─────────────────────────────────────────────────────────────────────────────
// CLASS: LlamaModelConfig
// ─────────────────────────────────────────────────────────────────────────────

/// Konfigurasi untuk memuat model llama.cpp
class LlamaModelConfig {
  final int contextSize;
  final int nBatch;
  final int nThreads;
  final int gpuLayers;
  final bool useFlashAttention;
  final bool useMemoryLock;
  final double ropeFreqBase;
  final double ropeFreqScale;
  final ChatTemplate chatTemplate;

  const LlamaModelConfig({
    this.contextSize = 4096,
    this.nBatch = 512,
    this.nThreads = 4,
    this.gpuLayers = 0,
    this.useFlashAttention = false,
    this.useMemoryLock = false,
    this.ropeFreqBase = 0.0,
    this.ropeFreqScale = 0.0,
    this.chatTemplate = ChatTemplate.auto,
  });

  /// Konfigurasi default yang direkomendasikan
  static LlamaModelConfig get defaultConfig => const LlamaModelConfig();

  /// Buat salinan dengan nilai yang diperbarui
  LlamaModelConfig copyWith({
    int? contextSize,
    int? nBatch,
    int? nThreads,
    int? gpuLayers,
    bool? useFlashAttention,
    bool? useMemoryLock,
    double? ropeFreqBase,
    double? ropeFreqScale,
    ChatTemplate? chatTemplate,
  }) {
    return LlamaModelConfig(
      contextSize: contextSize ?? this.contextSize,
      nBatch: nBatch ?? this.nBatch,
      nThreads: nThreads ?? this.nThreads,
      gpuLayers: gpuLayers ?? this.gpuLayers,
      useFlashAttention: useFlashAttention ?? this.useFlashAttention,
      useMemoryLock: useMemoryLock ?? this.useMemoryLock,
      ropeFreqBase: ropeFreqBase ?? this.ropeFreqBase,
      ropeFreqScale: ropeFreqScale ?? this.ropeFreqScale,
      chatTemplate: chatTemplate ?? this.chatTemplate,
    );
  }

  /// Konversi ke Map JSON
  Map<String, dynamic> toJson() {
    return {
      'contextSize': contextSize,
      'nBatch': nBatch,
      'nThreads': nThreads,
      'gpuLayers': gpuLayers,
      'useFlashAttention': useFlashAttention,
      'useMemoryLock': useMemoryLock,
      'ropeFreqBase': ropeFreqBase,
      'ropeFreqScale': ropeFreqScale,
      'chatTemplate': chatTemplate.name,
    };
  }

  /// Buat dari Map JSON
  factory LlamaModelConfig.fromJson(Map<String, dynamic> json) {
    return LlamaModelConfig(
      contextSize: json['contextSize'] as int? ?? 4096,
      nBatch: json['nBatch'] as int? ?? 512,
      nThreads: json['nThreads'] as int? ?? 4,
      gpuLayers: json['gpuLayers'] as int? ?? 0,
      useFlashAttention: json['useFlashAttention'] as bool? ?? false,
      useMemoryLock: json['useMemoryLock'] as bool? ?? false,
      ropeFreqBase: (json['ropeFreqBase'] as num?)?.toDouble() ?? 0.0,
      ropeFreqScale: (json['ropeFreqScale'] as num?)?.toDouble() ?? 0.0,
      chatTemplate: ChatTemplate.values.firstWhere(
        (e) => e.name == json['chatTemplate'],
        orElse: () => ChatTemplate.auto,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CLASS: InferenceConfig
// ─────────────────────────────────────────────────────────────────────────────

/// Konfigurasi sampling untuk proses inferensi
class InferenceConfig {
  final double temperature;
  final double topP;
  final int topK;
  final double minP;
  final double tfsZ;
  final double typicalP;
  final double repeatPenalty;
  final int repeatLastN;
  final bool penalizeNl;
  final int maxNewTokens;

  /// Mode mirostat: 0=nonaktif, 1=v1, 2=v2
  final int mirostatMode;
  final double mirostatTau;
  final double mirostatEta;
  final int seed;
  final List<String> stopSequences;

  const InferenceConfig({
    this.temperature = 0.7,
    this.topP = 0.9,
    this.topK = 40,
    this.minP = 0.05,
    this.tfsZ = 1.0,
    this.typicalP = 1.0,
    this.repeatPenalty = 1.1,
    this.repeatLastN = 64,
    this.penalizeNl = false,
    this.maxNewTokens = 1024,
    this.mirostatMode = 0,
    this.mirostatTau = 5.0,
    this.mirostatEta = 0.1,
    this.seed = -1,
    this.stopSequences = const [],
  });

  /// Konfigurasi default yang seimbang
  static InferenceConfig get defaultConfig => const InferenceConfig();

  /// Konfigurasi deterministik — hasil lebih konsisten dan terfokus
  static InferenceConfig get deterministicConfig => const InferenceConfig(
    temperature: 0.1,
    topP: 0.9,
    topK: 20,
  );

  /// Konfigurasi kreatif — lebih variatif dan imajinatif
  static InferenceConfig get creativeConfig => const InferenceConfig(
    temperature: 1.2,
    topP: 0.95,
    topK: 80,
  );

  /// Konfigurasi untuk pembuatan kode — presisi tinggi
  static InferenceConfig get codeConfig => const InferenceConfig(
    temperature: 0.2,
    topP: 0.9,
    topK: 40,
    repeatPenalty: 1.05,
  );

  /// Buat salinan dengan nilai yang diperbarui
  InferenceConfig copyWith({
    double? temperature,
    double? topP,
    int? topK,
    double? minP,
    double? tfsZ,
    double? typicalP,
    double? repeatPenalty,
    int? repeatLastN,
    bool? penalizeNl,
    int? maxNewTokens,
    int? mirostatMode,
    double? mirostatTau,
    double? mirostatEta,
    int? seed,
    List<String>? stopSequences,
  }) {
    return InferenceConfig(
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      minP: minP ?? this.minP,
      tfsZ: tfsZ ?? this.tfsZ,
      typicalP: typicalP ?? this.typicalP,
      repeatPenalty: repeatPenalty ?? this.repeatPenalty,
      repeatLastN: repeatLastN ?? this.repeatLastN,
      penalizeNl: penalizeNl ?? this.penalizeNl,
      maxNewTokens: maxNewTokens ?? this.maxNewTokens,
      mirostatMode: mirostatMode ?? this.mirostatMode,
      mirostatTau: mirostatTau ?? this.mirostatTau,
      mirostatEta: mirostatEta ?? this.mirostatEta,
      seed: seed ?? this.seed,
      stopSequences: stopSequences ?? this.stopSequences,
    );
  }

  /// Konversi ke Map JSON
  Map<String, dynamic> toJson() {
    return {
      'temperature': temperature,
      'topP': topP,
      'topK': topK,
      'minP': minP,
      'tfsZ': tfsZ,
      'typicalP': typicalP,
      'repeatPenalty': repeatPenalty,
      'repeatLastN': repeatLastN,
      'penalizeNl': penalizeNl,
      'maxNewTokens': maxNewTokens,
      'mirostatMode': mirostatMode,
      'mirostatTau': mirostatTau,
      'mirostatEta': mirostatEta,
      'seed': seed,
      'stopSequences': stopSequences,
    };
  }

  /// Buat dari Map JSON
  factory InferenceConfig.fromJson(Map<String, dynamic> json) {
    return InferenceConfig(
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      topP: (json['topP'] as num?)?.toDouble() ?? 0.9,
      topK: json['topK'] as int? ?? 40,
      minP: (json['minP'] as num?)?.toDouble() ?? 0.05,
      tfsZ: (json['tfsZ'] as num?)?.toDouble() ?? 1.0,
      typicalP: (json['typicalP'] as num?)?.toDouble() ?? 1.0,
      repeatPenalty: (json['repeatPenalty'] as num?)?.toDouble() ?? 1.1,
      repeatLastN: json['repeatLastN'] as int? ?? 64,
      penalizeNl: json['penalizeNl'] as bool? ?? false,
      maxNewTokens: json['maxNewTokens'] as int? ?? 1024,
      mirostatMode: json['mirostatMode'] as int? ?? 0,
      mirostatTau: (json['mirostatTau'] as num?)?.toDouble() ?? 5.0,
      mirostatEta: (json['mirostatEta'] as num?)?.toDouble() ?? 0.1,
      seed: json['seed'] as int? ?? -1,
      stopSequences: List<String>.from(json['stopSequences'] as List? ?? []),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CLASS: ModelPerformanceMetrics
// ─────────────────────────────────────────────────────────────────────────────

/// Metrik performa dari satu sesi inferensi
class ModelPerformanceMetrics {
  final int loadTimeMs;
  final int promptEvalMs;
  final int evalMs;
  final int promptTokens;
  final int evalTokens;
  final double tokensPerSecond;
  final int peakMemoryMb;

  const ModelPerformanceMetrics({
    required this.loadTimeMs,
    required this.promptEvalMs,
    required this.evalMs,
    required this.promptTokens,
    required this.evalTokens,
    required this.tokensPerSecond,
    required this.peakMemoryMb,
  });

  /// Ringkasan performa dalam satu baris
  String get summary =>
      'Load: ${loadTimeMs}ms | Prompt: ${promptTokens}tok / ${promptEvalMs}ms | '
      'Eval: ${evalTokens}tok / ${evalMs}ms | '
      '${tokensPerSecond.toStringAsFixed(1)} tok/s | RAM: ${peakMemoryMb}MB';

  /// Konversi ke Map JSON
  Map<String, dynamic> toJson() {
    return {
      'loadTimeMs': loadTimeMs,
      'promptEvalMs': promptEvalMs,
      'evalMs': evalMs,
      'promptTokens': promptTokens,
      'evalTokens': evalTokens,
      'tokensPerSecond': tokensPerSecond,
      'peakMemoryMb': peakMemoryMb,
    };
  }

  /// Buat dari Map JSON
  factory ModelPerformanceMetrics.fromJson(Map<String, dynamic> json) {
    return ModelPerformanceMetrics(
      loadTimeMs: json['loadTimeMs'] as int,
      promptEvalMs: json['promptEvalMs'] as int,
      evalMs: json['evalMs'] as int,
      promptTokens: json['promptTokens'] as int,
      evalTokens: json['evalTokens'] as int,
      tokensPerSecond: (json['tokensPerSecond'] as num).toDouble(),
      peakMemoryMb: json['peakMemoryMb'] as int,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CLASS: LlamaModelInfo
// ─────────────────────────────────────────────────────────────────────────────

/// Informasi lengkap tentang sebuah model AI
class LlamaModelInfo {
  final String id;
  final String name;
  final String path;
  final int sizeBytes;

  /// Format file: gguf / ggml / tflite / onnx
  final String format;
  final QuantizationType quantization;
  final int estimatedRamMb;
  final int contextLength;

  /// Jumlah parameter dalam miliar (nullable)
  final int? parameterCount;
  final String description;
  final String author;
  final List<String> tags;
  final bool isDownloaded;
  final DateTime? lastUsed;

  const LlamaModelInfo({
    required this.id,
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.format,
    required this.quantization,
    required this.estimatedRamMb,
    required this.contextLength,
    this.parameterCount,
    this.description = '',
    this.author = '',
    this.tags = const [],
    this.isDownloaded = false,
    this.lastUsed,
  });

  /// Label ukuran file yang mudah dibaca (contoh: "1.2 GB", "650 MB")
  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      final gb = sizeBytes / (1024 * 1024 * 1024);
      return '${gb.toStringAsFixed(1)} GB';
    }
    final mb = sizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB';
  }

  /// Label kuantisasi yang mudah dibaca
  String get quantizationLabel {
    switch (quantization) {
      case QuantizationType.q2K:
        return 'Q2_K';
      case QuantizationType.q3KM:
        return 'Q3_K_M';
      case QuantizationType.q4KM:
        return 'Q4_K_M';
      case QuantizationType.q4KS:
        return 'Q4_K_S';
      case QuantizationType.q5KM:
        return 'Q5_K_M';
      case QuantizationType.q5KS:
        return 'Q5_K_S';
      case QuantizationType.q6K:
        return 'Q6_K';
      case QuantizationType.q8_0:
        return 'Q8_0';
      case QuantizationType.f16:
        return 'F16';
      case QuantizationType.f32:
        return 'F32';
      case QuantizationType.unknown:
        return 'Unknown';
    }
  }

  /// Mengembalikan true jika ukuran model lebih dari 3GB
  bool get isLargeModel => sizeBytes > 3 * 1024 * 1024 * 1024;

  /// Buat LlamaModelInfo dari path file — parsing info dari nama file
  factory LlamaModelInfo.fromPath(String path) {
    final fileName = path.split('/').last;
    final nameWithoutExt = fileName.replaceAll(RegExp(r'\.(gguf|ggml|tflite|onnx)$'), '');

    // Tentukan format dari ekstensi
    String format = 'gguf';
    if (fileName.endsWith('.ggml')) format = 'ggml';
    else if (fileName.endsWith('.tflite')) format = 'tflite';
    else if (fileName.endsWith('.onnx')) format = 'onnx';

    // Parse kuantisasi dari nama file
    QuantizationType quant = QuantizationType.unknown;
    final nameLower = nameWithoutExt.toLowerCase();
    if (nameLower.contains('q2_k')) quant = QuantizationType.q2K;
    else if (nameLower.contains('q3_k_m')) quant = QuantizationType.q3KM;
    else if (nameLower.contains('q4_k_m')) quant = QuantizationType.q4KM;
    else if (nameLower.contains('q4_k_s')) quant = QuantizationType.q4KS;
    else if (nameLower.contains('q5_k_m')) quant = QuantizationType.q5KM;
    else if (nameLower.contains('q5_k_s')) quant = QuantizationType.q5KS;
    else if (nameLower.contains('q6_k')) quant = QuantizationType.q6K;
    else if (nameLower.contains('q8_0')) quant = QuantizationType.q8_0;
    else if (nameLower.contains('f16')) quant = QuantizationType.f16;
    else if (nameLower.contains('f32')) quant = QuantizationType.f32;

    return LlamaModelInfo(
      id: const Uuid().v4(),
      name: nameWithoutExt,
      path: path,
      sizeBytes: 0,
      format: format,
      quantization: quant,
      estimatedRamMb: 0,
      contextLength: 4096,
      description: 'Model dimuat dari $fileName',
      isDownloaded: true,
    );
  }

  /// Buat salinan dengan nilai yang diperbarui
  LlamaModelInfo copyWith({
    String? id,
    String? name,
    String? path,
    int? sizeBytes,
    String? format,
    QuantizationType? quantization,
    int? estimatedRamMb,
    int? contextLength,
    int? parameterCount,
    String? description,
    String? author,
    List<String>? tags,
    bool? isDownloaded,
    DateTime? lastUsed,
  }) {
    return LlamaModelInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      format: format ?? this.format,
      quantization: quantization ?? this.quantization,
      estimatedRamMb: estimatedRamMb ?? this.estimatedRamMb,
      contextLength: contextLength ?? this.contextLength,
      parameterCount: parameterCount ?? this.parameterCount,
      description: description ?? this.description,
      author: author ?? this.author,
      tags: tags ?? this.tags,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }

  /// Konversi ke Map JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'sizeBytes': sizeBytes,
      'format': format,
      'quantization': quantization.name,
      'estimatedRamMb': estimatedRamMb,
      'contextLength': contextLength,
      'parameterCount': parameterCount,
      'description': description,
      'author': author,
      'tags': tags,
      'isDownloaded': isDownloaded,
      'lastUsed': lastUsed?.toIso8601String(),
    };
  }

  /// Buat dari Map JSON
  factory LlamaModelInfo.fromJson(Map<String, dynamic> json) {
    return LlamaModelInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      sizeBytes: json['sizeBytes'] as int,
      format: json['format'] as String,
      quantization: QuantizationType.values.firstWhere(
        (e) => e.name == json['quantization'],
        orElse: () => QuantizationType.unknown,
      ),
      estimatedRamMb: json['estimatedRamMb'] as int,
      contextLength: json['contextLength'] as int,
      parameterCount: json['parameterCount'] as int?,
      description: json['description'] as String? ?? '',
      author: json['author'] as String? ?? '',
      tags: List<String>.from(json['tags'] as List? ?? []),
      isDownloaded: json['isDownloaded'] as bool? ?? false,
      lastUsed:
          json['lastUsed'] != null
              ? DateTime.parse(json['lastUsed'] as String)
              : null,
    );
  }

  @override
  String toString() =>
      'LlamaModelInfo(name: $name, format: $format, quant: $quantizationLabel, size: $sizeLabel)';
}

// ─────────────────────────────────────────────────────────────────────────────
// CLASS: LlamaException
// ─────────────────────────────────────────────────────────────────────────────

/// Exception khusus untuk error yang terjadi pada sistem Llama
class LlamaException implements Exception {
  final String message;
  final String? code;

  LlamaException(this.message, {this.code});

  @override
  String toString() {
    if (code != null) {
      return 'LlamaException [$code]: $message';
    }
    return 'LlamaException: $message';
  }
}
