// lib/data/services/llama_service.dart
// KanMon GO — LlamaService (Singleton)
//
// Mengelola lifecycle model AI offline (llama.cpp) melalui platform channel.
// Singleton dengan semua member yang dibutuhkan:
//   • instance singleton
//   • isModelLoaded (bool getter)
//   • isGenerating (bool getter)                ← DITAMBAHKAN
//   • status & statusStream (ModelStatus)
//   • loadProgressStream (Stream<double>)
//   • currentModel (LlamaModelInfo?)
//   • lastLoadedModelPath (String?)
//   • lastLoadedModelId (String?)
//   • lastLoadError (String?)                   ← DITAMBAHKAN
//   • lastMetrics (ModelPerformanceMetrics?)    ← DITAMBAHKAN
//   • initialize()
//   • loadSettings()
//   • loadModel(...) → Future<bool>
//   • releaseModel()
//   • getAvailableMemoryMb() → Future<int>
//   • generateStream({messages, config, systemPromptOverride})
//   • stopGeneration()                          ← DITAMBAHKAN
//   • getContextUsagePercent(messages) → double ← DITAMBAHKAN
//   • saveSettings()
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanmongo/core/ai/llama_context.dart';
import 'package:kanmongo/core/ai/native_event_dispatcher.dart';

class LlamaService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final LlamaService instance = LlamaService._();
  LlamaService._();

  // ── Platform channels ──────────────────────────────────────────────────────
  static const _platform     = MethodChannel('com.kanmongo.llama/engine');

  // ── SharedPreferences keys ─────────────────────────────────────────────────
  static const _keyLastModelPath = 'llama_last_model_path';
  static const _keyLastModelId   = 'llama_last_model_id';

  // ── Internal state ─────────────────────────────────────────────────────────
  ModelStatus               _status             = ModelStatus.notLoaded;
  LlamaModelInfo?           _currentModel;
  String?                   _lastLoadedModelPath;
  String?                   _lastLoadedModelId;
  String?                   _lastLoadError;
  ModelPerformanceMetrics?  _lastMetrics;

  final StreamController<ModelStatus> _statusCtrl =
      StreamController<ModelStatus>.broadcast();

  // Stream progres pemuatan model (0.0 – 1.0)
  final StreamController<double> _loadProgressCtrl =
      StreamController<double>.broadcast();

  // ── Public API ─────────────────────────────────────────────────────────────

  ModelStatus              get status             => _status;
  Stream<ModelStatus>      get statusStream       => _statusCtrl.stream;
  Stream<double>           get loadProgressStream => _loadProgressCtrl.stream;
  bool                     get isModelLoaded =>
      _status == ModelStatus.loaded || _status == ModelStatus.generating;
  /// True selama inferensi sedang berjalan.
  bool                     get isGenerating       => _status == ModelStatus.generating;
  LlamaModelInfo?          get currentModel       => _currentModel;
  String?                  get lastLoadedModelPath => _lastLoadedModelPath;
  String?                  get lastLoadedModelId   => _lastLoadedModelId;
  /// Pesan error terakhir dari loadModel (null jika belum pernah error).
  String?                  get lastLoadError       => _lastLoadError;
  /// Metrik performa dari sesi generateStream terakhir (null jika belum ada).
  ModelPerformanceMetrics? get lastMetrics         => _lastMetrics;

  // ── initialize ─────────────────────────────────────────────────────────────
  // Dipanggil sekali saat app start (setelah ModelManagerService.load()).
  // Memuat persisted last-model info dari SharedPreferences.

  Future<void> initialize() async {
    debugPrint('[LlamaService] initialize()');
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastLoadedModelPath = prefs.getString(_keyLastModelPath);
      _lastLoadedModelId   = prefs.getString(_keyLastModelId);
      debugPrint('[LlamaService] lastPath=$_lastLoadedModelPath');
    } catch (e) {
      debugPrint('[LlamaService] initialize() error (non-fatal): $e');
    }
  }

  // ── loadSettings ───────────────────────────────────────────────────────────
  // Muat ulang settings dari SharedPreferences.
  // Dipanggil dari main.dart sebelum auto-load model.

  Future<void> loadSettings() async {
    debugPrint('[LlamaService] loadSettings()');
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastLoadedModelPath = prefs.getString(_keyLastModelPath);
      _lastLoadedModelId   = prefs.getString(_keyLastModelId);
      debugPrint('[LlamaService] loadSettings — path=$_lastLoadedModelPath');
    } catch (e) {
      debugPrint('[LlamaService] loadSettings() error (non-fatal): $e');
    }
  }

  // ── loadModel ──────────────────────────────────────────────────────────────
  // Return true jika berhasil, false jika gagal (tidak throw).

  Future<bool> loadModel(
    LlamaModelInfo modelInfo, {
    LlamaModelConfig? config,
  }) async {
    final cfg = config ?? LlamaModelConfig.defaultConfig;
    _setStatus(ModelStatus.loading);
    _emitProgress(0.0);
    debugPrint('[LlamaService] loadModel: ${modelInfo.path}');

    try {
      if (modelInfo.path.isEmpty) throw LlamaException('Model path kosong');

      final file = File(modelInfo.path);
      if (!await file.exists()) {
        throw LlamaException('File tidak ditemukan: ${modelInfo.path}');
      }
      if (await file.length() == 0) {
        throw LlamaException('File model kosong (0 bytes)');
      }

      // Validasi magic GGUF
      if (modelInfo.path.toLowerCase().endsWith('.gguf')) {
        final raf = await File(modelInfo.path).open();
        try {
          final magic = await raf.read(4);
          if (magic.length < 4 ||
              magic[0] != 71 || magic[1] != 71 ||
              magic[2] != 85 || magic[3] != 70) {
            throw LlamaException('Format file tidak valid (bukan GGUF)');
          }
        } finally {
          await raf.close();
        }
      }

      _emitProgress(0.2);

      final result = await _platform.invokeMethod<Map>('loadModel', {
        'modelPath':    modelInfo.path,
        'contextSize':  cfg.contextSize,
        'gpuLayers':    cfg.gpuLayers,
        'nBatch':       cfg.nBatch,
        'nThreads':     cfg.nThreads,
        'useFlashAttn': cfg.useFlashAttention,
        'memLock':      cfg.useMemoryLock,
        'ropeBase':     cfg.ropeFreqBase,
        'ropeScale':    cfg.ropeFreqScale,
      });

      if (result == null || (result['handle'] ?? 0) == 0) {
        throw LlamaException('Native loadModel gagal (handle=0)');
      }

      _currentModel        = modelInfo;
      _lastLoadedModelPath = modelInfo.path;
      _lastLoadedModelId   = modelInfo.id;

      // Persist ke SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyLastModelPath, modelInfo.path);
        await prefs.setString(_keyLastModelId,   modelInfo.id);
      } catch (e) {
        debugPrint('[LlamaService] persist lastModel error (non-fatal): $e');
      }

      _emitProgress(1.0);
      _setStatus(ModelStatus.loaded);
      _lastLoadError = null;
      debugPrint('[LlamaService] ✅ Model loaded: ${modelInfo.name}');
      return true;

    } on PlatformException catch (e) {
      debugPrint('[LlamaService] ❌ PlatformException: ${e.code} ${e.message}');
      _lastLoadError = '${e.code}: ${e.message}';
      _setStatus(ModelStatus.error);
      _emitProgress(0.0);
      return false;
    } catch (e) {
      debugPrint('[LlamaService] ❌ Error: $e');
      _lastLoadError = e.toString();
      _setStatus(ModelStatus.error);
      _emitProgress(0.0);
      return false;
    }
  }

  // ── releaseModel ───────────────────────────────────────────────────────────

  Future<void> releaseModel() async {
    try {
      await _platform.invokeMethod('releaseModel');
    } catch (e) {
      debugPrint('[LlamaService] releaseModel error: $e');
    } finally {
      _currentModel = null;
      _setStatus(ModelStatus.notLoaded);
      _emitProgress(0.0);
    }
  }

  // ── getAvailableMemoryMb ───────────────────────────────────────────────────
  // Query memori tersedia dari native layer.
  // Digunakan oleh ModelManagerService untuk estimasi kelayakan model.

  Future<int> getAvailableMemoryMb() async {
    try {
      final result = await _platform.invokeMethod<int>('getAvailableMemoryMb');
      return result ?? 0;
    } catch (e) {
      debugPrint('[LlamaService] getAvailableMemoryMb error (non-fatal): $e');
      // Fallback: baca /proc/meminfo langsung
      try {
        final meminfo = await File('/proc/meminfo').readAsString();
        final match   = RegExp(r'MemAvailable:\s+(\d+)').firstMatch(meminfo);
        if (match != null) {
          return int.parse(match.group(1)!) ~/ 1024; // KB → MB
        }
      } catch (_) {}
      return 0;
    }
  }

  // ── generateStream ─────────────────────────────────────────────────────────
  // systemPromptOverride: jika diisi, disisipkan sebagai pesan system
  // di awal prompt sebelum messages lainnya.

  Stream<String> generateStream({
    required List<ChatMessage> messages,
    InferenceConfig? config,
    String? systemPromptOverride,
  }) async* {
    final cfg = config ?? InferenceConfig.defaultConfig;

    if (!isModelLoaded) throw LlamaException('Tidak ada model yang dimuat');

    _setStatus(ModelStatus.generating);
    debugPrint('[LlamaService] generateStream — ${messages.length} messages');
    final genStartMs = DateTime.now().millisecondsSinceEpoch;
    int tokenCount = 0;

    // Build prompt
    final effectiveMessages = [
      if (systemPromptOverride != null && systemPromptOverride.isNotEmpty)
        ChatMessage.system(systemPromptOverride),
      ...messages,
    ];
    final prompt = _buildChatMLPrompt(effectiveMessages);

    // Use a per-call StreamController. Events arrive via NativeEventDispatcher
    // (the single owner of the EventChannel subscription) instead of subscribing
    // directly. Direct subscription would replace NativeEventDispatcher's native
    // eventSink, breaking OfflineAiService event delivery permanently.
    final controller = StreamController<String>();

    // Register handler with NativeEventDispatcher
    void onEvent(Map<dynamic, dynamic> event) {
      if (controller.isClosed) return;
      final type = event['type'] as String?;
      switch (type) {
        case 'token':
          final t = event['token'] as String? ?? '';
          if (t.isNotEmpty) controller.add(t);
          break;
        case 'done':
        case 'generation_complete':
          if (!controller.isClosed) controller.close();
          break;
        case 'error':
          final msg = event['message'] as String? ?? 'Unknown error';
          if (!controller.isClosed) {
            controller.addError(LlamaException(msg));
            controller.close();
          }
          break;
        // Ignore model_loaded, loading_progress, memory_warning — not relevant here
      }
    }

    NativeEventDispatcher.instance.registerLlamaService(onEvent);

    try {
      await _platform.invokeMethod('generateTokens', {
        'prompt':        prompt,
        'temperature':   cfg.temperature,
        'topP':          cfg.topP,
        'topK':          cfg.topK,
        'maxTokens':     cfg.maxNewTokens,
        'repeatPenalty': cfg.repeatPenalty,
        'seed':          cfg.seed,
        'mirostatMode':  cfg.mirostatMode,
        'mirostatTau':   cfg.mirostatTau,
        'mirostatEta':   cfg.mirostatEta,
        'minP':          cfg.minP,
        'penalizeNl':    cfg.penalizeNl,
        'seq':           0,   // LlamaService always uses seq=0; NativeEventDispatcher
                               // broadcasts to both handlers and OfflineAiService
                               // filters by its own _currentActiveSeq independently.
      });

      await for (final token in controller.stream) {
        tokenCount++;
        yield token;
      }

    } catch (e) {
      debugPrint('[LlamaService] generateStream error: $e');
      rethrow;
    } finally {
      // Unregister immediately so NativeEventDispatcher stops routing events here.
      // OfflineAiService remains registered and unaffected.
      NativeEventDispatcher.instance.unregisterLlamaService();
      if (!controller.isClosed) await controller.close();
      if (_status == ModelStatus.generating) _setStatus(ModelStatus.loaded);
      // Record performance metrics
      final elapsedMs = DateTime.now().millisecondsSinceEpoch - genStartMs;
      if (tokenCount > 0 && elapsedMs > 0) {
        _lastMetrics = ModelPerformanceMetrics(
          loadTimeMs: 0,
          promptEvalMs: 0,
          evalMs: elapsedMs,
          promptTokens: 0,
          evalTokens: tokenCount,
          tokensPerSecond: tokenCount / (elapsedMs / 1000.0),
          peakMemoryMb: 0,
        );
      }
    }
  }

  // ── stopGeneration ─────────────────────────────────────────────────────────
  // Menghentikan inferensi yang sedang berjalan via platform channel.

  Future<void> stopGeneration() async {
    debugPrint('[LlamaService] stopGeneration()');
    try {
      await _platform.invokeMethod('stopGeneration');
    } catch (e) {
      debugPrint('[LlamaService] stopGeneration error (non-fatal): $e');
    } finally {
      if (_status == ModelStatus.generating) _setStatus(ModelStatus.loaded);
    }
  }

  // ── getContextUsagePercent ─────────────────────────────────────────────────
  // Estimasi lokal penggunaan context window (0–100).
  // Menggunakan jumlah karakter sebagai proxy token count.

  double getContextUsagePercent(List<ChatMessage> messages) {
    final contextSize = _currentModel?.contextLength ??
        LlamaModelConfig.defaultConfig.contextSize;
    // Estimasi: ~4 karakter per token
    final estimatedTokens = messages.fold<int>(
      0,
      (sum, m) => sum + (m.content.length / 4).ceil(),
    );
    final percent = (estimatedTokens / contextSize) * 100.0;
    return percent.clamp(0.0, 100.0);
  }

  // ── saveSettings ───────────────────────────────────────────────────────────

  Future<void> saveSettings() async {
    if (_currentModel == null) return;
    try {
      await _platform.invokeMethod('saveSettings', {
        'modelPath': _currentModel!.path,
      });
      debugPrint('[LlamaService] Settings saved');
    } catch (e) {
      debugPrint('[LlamaService] saveSettings error (non-fatal): $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _setStatus(ModelStatus s) {
    _status = s;
    if (!_statusCtrl.isClosed) _statusCtrl.add(s);
  }

  void _emitProgress(double value) {
    if (!_loadProgressCtrl.isClosed) _loadProgressCtrl.add(value);
  }

  String _buildChatMLPrompt(List<ChatMessage> messages) {
    final sb = StringBuffer();
    for (final msg in messages) {
      final role = switch (msg.role) {
        ChatRole.system    => 'system',
        ChatRole.user      => 'user',
        ChatRole.assistant => 'assistant',
      };
      sb.write('<|im_start|>$role\n${msg.content}<|im_end|>\n');
    }
    sb.write('<|im_start|>assistant\n');
    return sb.toString();
  }
}
