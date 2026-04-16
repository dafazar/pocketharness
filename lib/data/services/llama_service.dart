// lib/data/services/llama_service.dart
// KanMon GO — LlamaService (Core AI Engine, PocketPal Architecture)
//
// Menggantikan offline_ai_service.dart dengan arsitektur yang lebih bersih:
//   • Singleton pattern dengan private constructor
//   • State management via ModelStatus enum (bukan boolean terpisah)
//   • Stream broadcast untuk status dan progress
//   • Event channel single subscription yang persisten
//   • Support penuh untuk semua chat template (ChatML, Llama3, Mistral, Gemma, Phi3, Alpaca, Zephyr)
//   • Seq-based filtering untuk mencegah stale token dari generate sebelumnya
//   • Backward compatible dengan OfflineAiService via alias class

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kanmongo/core/ai/llama_context.dart';
import 'package:kanmongo/core/ai/inference_params_provider.dart';
import 'package:kanmongo/core/ai/native_event_dispatcher.dart';
import 'package:kanmongo/data/services/llama_http_server.dart';

// ─────────────────────────────────────────────────────────────────────────────
// KUNCI SharedPreferences
// ─────────────────────────────────────────────────────────────────────────────

const _kContextSize       = 'llama_svc_context_size';
const _kGpuLayers         = 'llama_svc_gpu_layers';
const _kNThreads          = 'llama_svc_n_threads';
const _kNBatch            = 'llama_svc_n_batch';
const _kFlashAttention    = 'llama_svc_flash_attn';
const _kMemoryLock        = 'llama_svc_memory_lock';
const _kRopeFreqBase      = 'llama_svc_rope_freq_base';
const _kRopeFreqScale     = 'llama_svc_rope_freq_scale';
const _kChatTemplate      = 'llama_svc_chat_template';
const _kSystemPrompt      = 'llama_svc_system_prompt';

// ─────────────────────────────────────────────────────────────────────────────
// CLASS: LlamaService
// ─────────────────────────────────────────────────────────────────────────────

/// Layanan utama untuk inferensi model AI offline menggunakan llama.cpp via JNI.
/// Arsitektur PocketPal: singleton, broadcast stream, seq-based event filter.
class LlamaService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final LlamaService instance = LlamaService._();
  LlamaService._() {
    _initEventChannel();
  }

  // ── Native Channels ────────────────────────────────────────────────────────
  /// MethodChannel untuk memanggil fungsi llama.cpp di native layer (Kotlin/JNI)
  static const _methodCh = MethodChannel('com.kanmongo.llama/engine');
  // EventChannel dikelola oleh NativeEventDispatcher singleton

  // ── State Variables ────────────────────────────────────────────────────────
  ModelStatus _status              = ModelStatus.notLoaded;
  LlamaModelInfo? _currentModel;
  LlamaModelConfig _modelConfig    = LlamaModelConfig.defaultConfig;
  double _loadingProgress          = 0.0;
  String? _lastLoadError;
  ModelPerformanceMetrics? _lastMetrics;

  /// StreamController aktif untuk generate yang sedang berjalan (nullable)
  StreamController<String>? _activeGenCtrl;

  /// Nomor urut sesi — bertambah setiap kali generate dimulai
  int _sessionSeq         = 0;

  /// Nomor urut sesi yang sedang aktif saat ini
  int _currentActiveSeq   = 0;

  /// Flag: apakah generate sedang berjalan
  bool _genRunning        = false;

  /// Completer untuk sinkronisasi antara caller dan stream generator
  Completer<void>? _genCompleter;

  /// Timer batas waktu token pertama
  Timer? _firstTokenTimer;

  /// Flag: apakah token pertama sudah diterima
  bool _gotFirstToken = false;

  /// Broadcast stream untuk perubahan ModelStatus
  StreamController<ModelStatus> _statusCtrl =
      StreamController<ModelStatus>.broadcast();

  /// Broadcast stream untuk progres pemuatan model (0.0 – 1.0)
  StreamController<double> _loadProgressCtrl =
      StreamController<double>.broadcast();

  /// Prompt sistem yang sedang aktif
  String? _systemPrompt;

  /// Waktu mulai pemuatan model (untuk kalkulasi loadTimeMs)
  DateTime? _modelLoadStartTime;

  // ── Getters ────────────────────────────────────────────────────────────────

  /// Status model saat ini
  ModelStatus get status => _status;

  /// Pesan error terakhir saat loadModel gagal (null jika sukses)
  String? get lastLoadError => _lastLoadError;

  /// Apakah model sudah dimuat dan siap digunakan
  bool get isModelLoaded => _status == ModelStatus.loaded;

  /// Apakah sedang melakukan inferensi
  bool get isGenerating => _genRunning;

  /// Informasi model yang sedang aktif
  LlamaModelInfo? get currentModel => _currentModel;

  /// Progres pemuatan model (0.0 – 1.0)
  double get loadingProgress => _loadingProgress;

  /// Metrik performa dari inferensi terakhir
  ModelPerformanceMetrics? get lastMetrics => _lastMetrics;

  /// Prompt sistem yang sedang digunakan
  String? get systemPrompt => _systemPrompt;

  /// Stream perubahan status model (broadcast)
  Stream<ModelStatus> get statusStream => _statusCtrl.stream;

  /// Stream progres pemuatan model (broadcast)
  Stream<double> get loadProgressStream => _loadProgressCtrl.stream;

  // ── Last Loaded Model Persistence ─────────────────────────────────────────
  static const _kLastModelPath = 'llama_last_model_path';
  static const _kLastModelId   = 'llama_last_model_id';

  String? _lastLoadedModelPath;
  String? _lastLoadedModelId;

  /// Path model terakhir yang berhasil dimuat (persisted)
  String? get lastLoadedModelPath => _lastLoadedModelPath;

  /// ID model terakhir yang berhasil dimuat (persisted)
  String? get lastLoadedModelId => _lastLoadedModelId;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Inisialisasi service: muat settings, pastikan stream aktif
  Future<void> initialize() async {
    await loadSettings();
    // Pastikan event channel terdaftar ke dispatcher
    NativeEventDispatcher.instance.registerLlamaService(_onNativeEvent);
    debugPrint('[LlamaService] initialize() selesai');
  }

  /// Bersihkan semua resource saat app ditutup
  Future<void> dispose() async {
    await stopGeneration();
    NativeEventDispatcher.instance.unregisterLlamaService();
    if (!_statusCtrl.isClosed) await _statusCtrl.close();
    if (!_loadProgressCtrl.isClosed) await _loadProgressCtrl.close();
    _closeActiveCtrl();
    debugPrint('[LlamaService] dispose() selesai');
  }

  // ── Model Management ───────────────────────────────────────────────────────

  /// Muat model ke dalam memori native llama.cpp.
  /// Mengembalikan true jika berhasil, false jika gagal.
  
  void _ensureStatusCtrlOpen() {
    if (_statusCtrl.isClosed) {
      _statusCtrl = StreamController<ModelStatus>.broadcast();
    }
  }

  void _ensureProgressCtrlOpen() {
    if (_loadProgressCtrl.isClosed) {
      _loadProgressCtrl = StreamController<double>.broadcast();
    }
  }
  Future<bool> loadModel(LlamaModelInfo model, {LlamaModelConfig? config}) async {
    _ensureStatusCtrlOpen();
    _ensureProgressCtrlOpen();
    if (_status == ModelStatus.loading) {
      debugPrint('[LlamaService] loadModel() diabaikan — sedang loading');
      return false;
    }

    // Hentikan generate aktif jika ada
    if (_genRunning) {
      await _stopAndWait();
    }

    // Gunakan config yang diberikan atau config saat ini
    if (config != null) {
      _modelConfig = config;
    }

    _updateStatus(ModelStatus.loading);
    _loadingProgress = 0.0;
    _modelLoadStartTime = DateTime.now();

    // Bebaskan model lama jika ada
    try {
      await _methodCh.invokeMethod<void>('releaseModel');
    } catch (_) {
      // Abaikan jika model lama tidak ada
    }

    try {
      debugPrint('[LlamaService] Memuat model: ${model.path}');
      debugPrint('[LlamaService] Config: ctx=${_modelConfig.contextSize} '
          'gpu=${_modelConfig.gpuLayers} threads=${_modelConfig.nThreads}');

      final ok = await _methodCh.invokeMethod<bool>('loadModel', {
        'modelPath'        : model.path,
        'contextSize'      : _modelConfig.contextSize,
        'gpuLayers'        : _modelConfig.gpuLayers,
        'nBatch'           : _modelConfig.nBatch,
        'nThreads'         : _modelConfig.nThreads,
        'useFlashAttention': _modelConfig.useFlashAttention,
        'useMemoryLock'    : _modelConfig.useMemoryLock,
        'ropeFreqBase'     : _modelConfig.ropeFreqBase,
        'ropeFreqScale'    : _modelConfig.ropeFreqScale,
      });

      if (ok == true) {
        _lastLoadError = null;
        _currentModel = model.copyWith(lastUsed: DateTime.now());
        _updateStatus(ModelStatus.loaded);
        debugPrint('[LlamaService] Model berhasil dimuat: ${model.name}');
        return true;
      } else {
        _lastLoadError = 'Native loadModel mengembalikan false';
        _updateStatus(ModelStatus.error);
        debugPrint('[LlamaService] Native loadModel mengembalikan false');
        return false;
      }
    } on PlatformException catch (e) {
      _lastLoadError = e.message ?? e.toString();
      _updateStatus(ModelStatus.error);
      debugPrint('[LlamaService] PlatformException saat loadModel: ${e.message}');
      return false;
    } catch (e) {
      _lastLoadError = e.toString();
      _updateStatus(ModelStatus.error);
      debugPrint('[LlamaService] Error saat loadModel: $e');
      return false;
    }
  }

  /// Bebaskan model dari memori native
  Future<void> releaseModel() async {
    if (_genRunning) {
      await _stopAndWait();
    }
    try {
      await _methodCh.invokeMethod<void>('releaseModel');
      debugPrint('[LlamaService] Model dilepas dari memori native');
    } catch (e) {
      debugPrint('[LlamaService] Error saat releaseModel: $e');
    }
    _currentModel = null;
    _loadingProgress = 0.0;
    _lastMetrics = null;
    _updateStatus(ModelStatus.notLoaded);
  }

  /// Ambil informasi model dari path file tanpa memuatnya
  Future<LlamaModelInfo?> getModelInfoFromPath(String path) async {
    try {
      // FIX: pass path as a Map key, not a bare String.
      // LlamaPlugin.kt reads call.argument<String>("path") which requires a Map argument.
      final result = await _methodCh.invokeMethod<Map>('getModelInfo', <String, dynamic>{'path': path});
      if (result == null) return null;

      final map = Map<String, dynamic>.from(result);
      final quantStr = (map['quantization'] as String? ?? '').toLowerCase();

      // Parse kuantisasi dari string yang dikembalikan native
      QuantizationType quant = QuantizationType.unknown;
      if (quantStr.contains('q2_k'))      quant = QuantizationType.q2K;
      else if (quantStr.contains('q3_k')) quant = QuantizationType.q3KM;
      else if (quantStr.contains('q4_k_s')) quant = QuantizationType.q4KS;
      else if (quantStr.contains('q4_k')) quant = QuantizationType.q4KM;
      else if (quantStr.contains('q5_k_s')) quant = QuantizationType.q5KS;
      else if (quantStr.contains('q5_k')) quant = QuantizationType.q5KM;
      else if (quantStr.contains('q6_k')) quant = QuantizationType.q6K;
      else if (quantStr.contains('q8_0')) quant = QuantizationType.q8_0;
      else if (quantStr.contains('f16'))  quant = QuantizationType.f16;
      else if (quantStr.contains('f32'))  quant = QuantizationType.f32;

      // Estimasi RAM = ukuran file * 1.2 (overhead KV cache + scratch)
      final sizeBytes = map['fileSize'] as int? ?? 0;
      final estimatedRam = ((sizeBytes / (1024 * 1024)) * 1.2).toInt();

      return LlamaModelInfo(
        id             : DateTime.now().millisecondsSinceEpoch.toString(),
        name           : map['name'] as String? ?? path.split('/').last,
        path           : path,
        sizeBytes      : sizeBytes,
        format         : 'gguf',
        quantization   : quant,
        estimatedRamMb : estimatedRam,
        contextLength  : map['contextLength'] as int? ?? 4096,
        parameterCount : map['paramCount'] as int?,
        description    : 'Arch: ${map['arch'] ?? 'unknown'}',
        isDownloaded   : true,
      );
    } on PlatformException catch (e) {
      debugPrint('[LlamaService] getModelInfoFromPath error: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[LlamaService] getModelInfoFromPath error: $e');
      return null;
    }
  }

  /// Ambil jumlah RAM yang tersedia dalam MB dari native layer
  Future<int> getAvailableMemoryMb() async {
    try {
      return await _methodCh.invokeMethod<int>('getAvailableMemoryMb') ?? 0;
    } catch (e) {
      debugPrint('[LlamaService] getAvailableMemoryMb error: $e');
      return 0;
    }
  }

  // ── Inference ──────────────────────────────────────────────────────────────

  /// Mulai inferensi streaming. Mengembalikan Stream<String> token satu per satu.
  ///
  /// Langkah internal:
  ///   1. Hentikan generate sebelumnya + tunggu bersih (_stopAndWait)
  ///   2. Bangun prompt dari messages sesuai template
  ///   3. Increment seq, buat StreamController baru
  ///   4. Panggil native generateTokens
  ///   5. Yield token dari ctrl.stream hingga done
  Stream<String> generateStream({
    required List<ChatMessage> messages,
    required InferenceConfig config,
    String? systemPromptOverride,
  }) async* {
    // Validasi: model harus sudah dimuat
    if (!isModelLoaded) {
      yield '[ERROR] Model belum dimuat. Muat model terlebih dahulu.';
      return;
    }

    // Hentikan generate sebelumnya + tunggu benar-benar bersih
    await _stopAndWait();

    // Tentukan system prompt yang digunakan
    final sysPrompt = systemPromptOverride ?? _systemPrompt ?? '';

    // Tentukan template yang digunakan
    final template = _modelConfig.chatTemplate == ChatTemplate.auto
        ? detectTemplateFromModelName(_currentModel?.name ?? '')
        : _modelConfig.chatTemplate;

    // Bangun prompt string dari daftar pesan
    final prompt = buildPromptFromMessages(
      messages,
      template: template,
      systemPromptOverride: sysPrompt,
    );

    if (prompt.trim().isEmpty) {
      yield '[ERROR] Gagal membangun prompt. Daftar pesan kosong.';
      return;
    }

    // Increment seq dan buat StreamController baru
    _sessionSeq++;
    _currentActiveSeq = _sessionSeq;
    final mySeq = _currentActiveSeq;

    // Use a regular (non-broadcast) StreamController.
    // broadcast() does NOT buffer events — if any token arrives between
    // invokeMethod returning and "await for" starting, it is silently dropped.
    // A regular StreamController buffers until the single listener subscribes.
    final ctrl = StreamController<String>();
    _activeGenCtrl = ctrl;
    _genRunning    = true;
    _genCompleter  = Completer<void>();
    _gotFirstToken = false;

    _updateStatus(ModelStatus.generating);
    debugPrint('[LlamaService] generateStream START seq=$mySeq template=${template.name}');

    // Timer batas waktu token pertama (90 detik)
    _firstTokenTimer = Timer(const Duration(seconds: 90), () {
      if (_currentActiveSeq == mySeq && !_gotFirstToken && !ctrl.isClosed) {
        debugPrint('[LlamaService] First-token timeout seq=$mySeq');
        try {
          ctrl.add('\n\n⏰ Timeout: AI tidak merespons dalam 90 detik.\n'
              'Coba kirim ulang pesan atau muat ulang model.');
        } catch (_) {}
        _closeActiveCtrl();
      }
    });

    try {
      // Panggil native generateTokens
      await _methodCh.invokeMethod<void>('generateTokens', {
        'prompt'       : prompt,
        'temperature'  : config.temperature,
        'topP'         : config.topP,
        'topK'         : config.topK,
        'maxTokens'    : config.maxNewTokens,
        'seq'          : mySeq,
        'repeatPenalty': config.repeatPenalty,
        'seed'         : config.seed,
        'mirostatMode' : config.mirostatMode,
        'mirostatTau'  : config.mirostatTau,
        'mirostatEta'  : config.mirostatEta,
        'minP'         : config.minP,
      });

      // Yield token dari broadcast stream hingga stream ditutup
      await for (final token in ctrl.stream) {
        // Guard: pastikan masih sesi yang sama
        if (_currentActiveSeq != mySeq) break;
        yield token;
      }
    } on PlatformException catch (e) {
      _firstTokenTimer?.cancel();
      _firstTokenTimer = null;
      final msg = e.message ?? e.toString();
      debugPrint('[LlamaService] PlatformException generate seq=$mySeq: $msg');

      // Berikan pesan error yang ramah pengguna
      final lowerMsg = msg.toLowerCase();
      if (lowerMsg.contains('out of memory') || lowerMsg.contains('oom')) {
        yield '\n\n⚠️ RAM tidak cukup saat inferensi.\n'
            '- Tutup aplikasi lain\n'
            '- Kurangi Context Size di Settings\n'
            '- Gunakan model lebih kecil';
      } else if (lowerMsg.contains('destroyed') || lowerMsg.contains('unloaded')) {
        _currentModel = null;
        _updateStatus(ModelStatus.notLoaded);
        yield '\n\n⚠️ Model di-unload secara paksa.\nKirim pesan lagi untuk memuat ulang.';
      } else if (lowerMsg.contains('invalid') || lowerMsg.contains('prompt')) {
        yield '\n\n⚠️ Prompt tidak valid. Coba pesan yang lebih pendek.';
      } else {
        yield '\n\n⚠️ Error native: $msg';
      }
    } catch (e) {
      _firstTokenTimer?.cancel();
      _firstTokenTimer = null;
      debugPrint('[LlamaService] Error generate seq=$mySeq: $e');
      yield '\n\n⚠️ Error: ${e.toString().replaceAll("Exception: ", "")}';
    } finally {
      // Cleanup — wajib bersih meski ada exception
      _firstTokenTimer?.cancel();
      _firstTokenTimer = null;
      if (_currentActiveSeq == mySeq) {
        _closeActiveCtrl();
        if (_status == ModelStatus.generating) {
          _updateStatus(ModelStatus.loaded);
        }
      }
      debugPrint('[LlamaService] generateStream END seq=$mySeq gotFirst=$_gotFirstToken');
    }
  }

  /// Jalankan inferensi dan kumpulkan semua token menjadi satu string.
  Future<String> generate({
    required List<ChatMessage> messages,
    required InferenceConfig config,
    String? systemPromptOverride,
  }) async {
    final sb = StringBuffer();
    await for (final token in generateStream(
      messages: messages,
      config: config,
      systemPromptOverride: systemPromptOverride,
    )) {
      sb.write(token);
    }
    return sb.toString();
  }

  /// Hentikan inferensi yang sedang berjalan dan tunggu hingga bersih.
  Future<void> stopGeneration() async {
    debugPrint('[LlamaService] stopGeneration() dipanggil');
    await _stopAndWait();
  }

  // ── System Prompt ──────────────────────────────────────────────────────────

  /// Atur atau hapus system prompt (null = tidak ada system prompt)
  void setSystemPrompt(String? prompt) {
    _systemPrompt = prompt?.trim().isEmpty == true ? null : prompt?.trim();
    debugPrint('[LlamaService] System prompt diperbarui: '
        '${_systemPrompt == null ? "null" : "${_systemPrompt!.length} chars"}');
  }

  // ── Utils ──────────────────────────────────────────────────────────────────

  /// Bangun prompt string dari daftar ChatMessage sesuai template.
  ///
  /// Urutan pesan:
  ///   1. Pesan system (jika ada di messages atau dari systemPromptOverride)
  ///   2. Pesan percakapan user/assistant secara bergantian
  ///   3. Prompt pembuka respons asisten
  String buildPromptFromMessages(
    List<ChatMessage> messages, {
    ChatTemplate? template,
    String? systemPromptOverride,
  }) {
    // Tentukan template yang akan digunakan
    final tpl = template ?? (_modelConfig.chatTemplate == ChatTemplate.auto
        ? detectTemplateFromModelName(_currentModel?.name ?? '')
        : _modelConfig.chatTemplate);

    // Pisahkan pesan system dan percakapan
    String sysPrompt = systemPromptOverride ?? _systemPrompt ?? '';

    // Jika ada pesan role system dalam list, gabungkan dengan systemPromptOverride
    final systemMsgs = messages.where((m) => m.role == ChatRole.system).toList();
    if (systemMsgs.isNotEmpty && sysPrompt.isEmpty) {
      sysPrompt = systemMsgs.map((m) => m.content).join('\n');
    }

    // Ambil hanya pesan user dan assistant (bukan system)
    final convMsgs = messages.where((m) => m.role != ChatRole.system).toList();

    final sb = StringBuffer();

    switch (tpl) {
      // ── ChatML (default untuk Qwen, Yi, OpenHermes, dsb.) ─────────────────
      case ChatTemplate.chatML:
      case ChatTemplate.auto:
        if (sysPrompt.isNotEmpty) {
          sb.write('<|im_start|>system\n$sysPrompt<|im_end|>\n');
        }
        for (final m in convMsgs) {
          if (m.role == ChatRole.assistant) {
            sb.write('<|im_start|>assistant\n${m.content}<|im_end|>\n');
          } else {
            sb.write('<|im_start|>user\n${m.content}<|im_end|>\n');
          }
        }
        sb.write('<|im_start|>assistant\n');
        break;

      // ── Llama 3 ───────────────────────────────────────────────────────────
      case ChatTemplate.llama3:
        sb.write('<|begin_of_text|>');
        if (sysPrompt.isNotEmpty) {
          sb.write('<|start_header_id|>system<|end_header_id|>\n\n'
              '$sysPrompt<|eot_id|>');
        }
        for (final m in convMsgs) {
          final role = m.role == ChatRole.assistant ? 'assistant' : 'user';
          sb.write('<|start_header_id|>$role<|end_header_id|>\n\n'
              '${m.content}<|eot_id|>');
        }
        sb.write('<|start_header_id|>assistant<|end_header_id|>\n\n');
        break;

      // ── Mistral / Mixtral ─────────────────────────────────────────────────
      case ChatTemplate.mistral:
        bool first = true;
        final sysPrefix = sysPrompt.isNotEmpty ? '$sysPrompt\n\n' : '';
        for (final m in convMsgs) {
          if (m.role == ChatRole.user) {
            sb.write('[INST] ${first ? sysPrefix : ""}${m.content} [/INST]');
            first = false;
          } else {
            sb.write(' ${m.content}</s>');
          }
        }
        // Jika tidak ada pesan user sama sekali, buat prompt minimal
        if (convMsgs.isEmpty || convMsgs.last.role != ChatRole.user) {
          sb.write('[INST] ${sysPrefix}Mulai percakapan. [/INST]');
        }
        break;

      // ── Gemma ─────────────────────────────────────────────────────────────
      case ChatTemplate.gemma:
        bool firstGemma = true;
        final sysPrefixGemma = sysPrompt.isNotEmpty ? '$sysPrompt\n\n' : '';
        for (final m in convMsgs) {
          if (m.role == ChatRole.user) {
            sb.write('<start_of_turn>user\n'
                '${firstGemma ? sysPrefixGemma : ""}'
                '${m.content}<end_of_turn>\n');
            firstGemma = false;
          } else {
            sb.write('<start_of_turn>model\n${m.content}<end_of_turn>\n');
          }
        }
        sb.write('<start_of_turn>model\n');
        break;

      // ── Phi-3 ─────────────────────────────────────────────────────────────
      case ChatTemplate.phi3:
        if (sysPrompt.isNotEmpty) {
          sb.write('<|system|>\n$sysPrompt<|end|>\n');
        }
        for (final m in convMsgs) {
          if (m.role == ChatRole.assistant) {
            sb.write('<|assistant|>\n${m.content}<|end|>\n');
          } else {
            sb.write('<|user|>\n${m.content}<|end|>\n');
          }
        }
        sb.write('<|assistant|>\n');
        break;

      // ── Alpaca ────────────────────────────────────────────────────────────
      case ChatTemplate.alpaca:
        if (sysPrompt.isNotEmpty) {
          sb.write('### System:\n$sysPrompt\n\n');
        }
        for (final m in convMsgs) {
          if (m.role == ChatRole.user) {
            sb.write('### Instruction:\n${m.content}\n\n');
          } else {
            sb.write('### Response:\n${m.content}\n\n');
          }
        }
        sb.write('### Response:\n');
        break;

      // ── Zephyr ────────────────────────────────────────────────────────────
      case ChatTemplate.zephyr:
        if (sysPrompt.isNotEmpty) {
          sb.write('<|system|>\n$sysPrompt</s>\n');
        }
        for (final m in convMsgs) {
          if (m.role == ChatRole.assistant) {
            sb.write('<|assistant|>\n${m.content}</s>\n');
          } else {
            sb.write('<|user|>\n${m.content}</s>\n');
          }
        }
        sb.write('<|assistant|>\n');
        break;
    }

    return sb.toString();
  }

  /// Deteksi template chat dari nama model berdasarkan kata kunci.
  ChatTemplate detectTemplateFromModelName(String modelName) {
    final lower = modelName.toLowerCase();

    if (lower.contains('llama-3') || lower.contains('llama3') ||
        lower.contains('meta-llama-3')) {
      return ChatTemplate.llama3;
    }
    if (lower.contains('mistral') || lower.contains('mixtral')) {
      return ChatTemplate.mistral;
    }
    if (lower.contains('gemma')) {
      return ChatTemplate.gemma;
    }
    if (lower.contains('phi-3') || lower.contains('phi3')) {
      return ChatTemplate.phi3;
    }
    if (lower.contains('zephyr')) {
      return ChatTemplate.zephyr;
    }
    if (lower.contains('alpaca') || lower.contains('wizard')) {
      return ChatTemplate.alpaca;
    }
    // Default: ChatML cocok untuk Qwen, Yi, OpenHermes, Mistral-7B-instruct v0.2+
    return ChatTemplate.chatML;
  }

  /// Estimasi kasar jumlah token: 1 token ≈ 4 karakter
  int estimateTokenCount(String text) {
    if (text.isEmpty) return 0;
    return (text.length / 4).ceil();
  }

  /// Hitung persentase penggunaan konteks dari daftar pesan (0–100)
  int getContextUsagePercent(List<ChatMessage> messages) {
    if (!isModelLoaded) return 0;
    final contextSize = _modelConfig.contextSize;
    if (contextSize <= 0) return 0;

    final totalTokens = messages.fold<int>(
      0,
      (sum, m) => sum + estimateTokenCount(m.content),
    );
    return ((totalTokens / contextSize) * 100).clamp(0, 100).toInt();
  }

  /// Pangkas daftar pesan agar tidak melebihi batas token konteks.
  /// Pesan system selalu dipertahankan. Pesan lama dibuang lebih dahulu.
  List<ChatMessage> trimMessagesForContext(
    List<ChatMessage> messages,
    int maxContextTokens,
  ) {
    // Pisahkan system dan percakapan
    final sysMessages  = messages.where((m) => m.role == ChatRole.system).toList();
    final convMessages = messages.where((m) => m.role != ChatRole.system).toList();

    // Hitung token system
    final sysTokens = sysMessages.fold<int>(0, (s, m) => s + estimateTokenCount(m.content));
    int remaining = maxContextTokens - sysTokens;

    // Pertahankan pesan terbaru selama masih dalam batas
    final kept = <ChatMessage>[];
    for (final msg in convMessages.reversed) {
      final t = estimateTokenCount(msg.content);
      if (remaining - t >= 0) {
        kept.insert(0, msg);
        remaining -= t;
      } else {
        break;
      }
    }

    return [...sysMessages, ...kept];
  }

  // ── Config Update ──────────────────────────────────────────────────────────

  /// Replace the entire model configuration before calling loadModel().
  /// Used by AiSourcePicker / Settings screens to apply UI settings.
  void updateConfig(LlamaModelConfig config) {
    _modelConfig = config;
    debugPrint('[LlamaService] updateConfig: ctx=${config.contextSize} gpu=${config.gpuLayers}');
  }

  /// Partially update model configuration — only override provided fields.
  void updateConfigPartial({int? contextSize, int? gpuLayers, int? nThreads, int? nBatch}) {
    _modelConfig = _modelConfig.copyWith(
      contextSize: contextSize,
      gpuLayers:   gpuLayers,
      nThreads:    nThreads,
      nBatch:      nBatch,
    );
    debugPrint('[LlamaService] updateConfigPartial applied');
  }

  // ── Settings ───────────────────────────────────────────────────────────────

  /// Simpan konfigurasi service ke SharedPreferences
  Future<void> saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kContextSize,    _modelConfig.contextSize);
      await prefs.setInt(_kGpuLayers,      _modelConfig.gpuLayers);
      await prefs.setInt(_kNThreads,       _modelConfig.nThreads);
      await prefs.setInt(_kNBatch,         _modelConfig.nBatch);
      await prefs.setBool(_kFlashAttention, _modelConfig.useFlashAttention);
      await prefs.setBool(_kMemoryLock,     _modelConfig.useMemoryLock);
      await prefs.setDouble(_kRopeFreqBase, _modelConfig.ropeFreqBase);
      await prefs.setDouble(_kRopeFreqScale, _modelConfig.ropeFreqScale);
      await prefs.setString(_kChatTemplate, _modelConfig.chatTemplate.name);
      if (_systemPrompt != null) {
        await prefs.setString(_kSystemPrompt, _systemPrompt!);
      } else {
        await prefs.remove(_kSystemPrompt);
      }
      // ── FIX: Persist path dan id model yang sedang aktif ─────────────────
      if (_currentModel != null) {
        await prefs.setString(_kLastModelPath, _currentModel!.path);
        await prefs.setString(_kLastModelId,   _currentModel!.id);
        _lastLoadedModelPath = _currentModel!.path;
        _lastLoadedModelId   = _currentModel!.id;
        debugPrint('[LlamaService] Settings disimpan (lastModel: ${_currentModel!.name})');
      } else {
        await prefs.remove(_kLastModelPath);
        await prefs.remove(_kLastModelId);
        debugPrint('[LlamaService] Settings disimpan (no active model)');
      }
    } catch (e) {
      debugPrint('[LlamaService] saveSettings error: $e');
    }
  }

  /// Muat konfigurasi service dari SharedPreferences
  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _modelConfig = LlamaModelConfig(
        contextSize      : prefs.getInt(_kContextSize)     ?? 4096,
        gpuLayers        : prefs.getInt(_kGpuLayers)       ?? 0,
        nThreads         : prefs.getInt(_kNThreads)        ?? 4,
        nBatch           : prefs.getInt(_kNBatch)          ?? 512,
        useFlashAttention: prefs.getBool(_kFlashAttention) ?? false,
        useMemoryLock    : prefs.getBool(_kMemoryLock)     ?? false,
        ropeFreqBase     : prefs.getDouble(_kRopeFreqBase) ?? 0.0,
        ropeFreqScale    : prefs.getDouble(_kRopeFreqScale) ?? 0.0,
        chatTemplate     : ChatTemplate.values.firstWhere(
          (e) => e.name == prefs.getString(_kChatTemplate),
          orElse: () => ChatTemplate.auto,
        ),
      );
      _systemPrompt        = prefs.getString(_kSystemPrompt);
      // ── FIX: Baca path model terakhir sebagai referensi fallback ──────────
      _lastLoadedModelPath = prefs.getString(_kLastModelPath);
      _lastLoadedModelId   = prefs.getString(_kLastModelId);
      debugPrint('[LlamaService] Settings dimuat: ctx=${_modelConfig.contextSize} '
          'gpu=${_modelConfig.gpuLayers} threads=${_modelConfig.nThreads} '
          'lastModel=$_lastLoadedModelPath');
    } catch (e) {
      debugPrint('[LlamaService] loadSettings error: $e');
    }
  }

  // ── Internal Methods ───────────────────────────────────────────────────────

  /// Inisialisasi subscription ke EventChannel native via NativeEventDispatcher (shared singleton)
  void _initEventChannel() {
    NativeEventDispatcher.instance.registerLlamaService(_onNativeEvent);
    debugPrint('[LlamaService] registered to NativeEventDispatcher');
  }

  /// Handler untuk setiap event yang diterima dari native layer
  void _onNativeEvent(Map<dynamic, dynamic> event) {
    final type = event['type']?.toString() ?? '';

    switch (type) {
      // ── Token streaming ───────────────────────────────────────────────────
      case 'token':
        final seq   = (event['seq']   as int?)    ?? -1;
        final token = (event['token'] as String?) ?? '';
        final ctrl  = _activeGenCtrl;

        if (ctrl == null || ctrl.isClosed) return;

        // Filter token dari sesi yang tidak aktif
        if (seq >= 0 && seq != _currentActiveSeq) {
          debugPrint('[LlamaService] Stale token seq=$seq (active=$_currentActiveSeq) — diabaikan');
          return;
        }

        // Batalkan first-token timer saat token pertama tiba
        if (!_gotFirstToken && token.isNotEmpty) {
          _gotFirstToken = true;
          _firstTokenTimer?.cancel();
          _firstTokenTimer = null;
          debugPrint('[LlamaService] Token pertama diterima ✓ seq=$_currentActiveSeq');
        }

        if (token.isNotEmpty) {
          try {
            ctrl.add(token);
          } catch (e) {
            debugPrint('[LlamaService] ctrl.add error: $e');
          }
        }
        break;

      // ── Generate selesai ──────────────────────────────────────────────────
      case 'done':
        final seq         = (event['seq']          as int?)    ?? -1;
        final promptTok   = (event['promptTokens'] as int?)    ?? 0;
        final evalTok     = (event['evalTokens']   as int?)    ?? 0;
        final promptMs    = (event['promptMs']     as int?)    ?? 0;
        final evalMs      = (event['evalMs']       as int?)    ?? 0;
        final tokPerSec   = (event['tokensPerSec'] as double?) ?? 0.0;

        if (seq >= 0 && seq != _currentActiveSeq) return;

        debugPrint('[LlamaService] done seq=$_currentActiveSeq '
            'prompt=${promptTok}tok/${promptMs}ms '
            'eval=${evalTok}tok/${evalMs}ms '
            '${tokPerSec.toStringAsFixed(1)}tok/s');

        // Simpan metrik performa
        final loadMs = _modelLoadStartTime != null
            ? DateTime.now().difference(_modelLoadStartTime!).inMilliseconds
            : 0;
        _lastMetrics = ModelPerformanceMetrics(
          loadTimeMs     : loadMs,
          promptEvalMs   : promptMs,
          evalMs         : evalMs,
          promptTokens   : promptTok,
          evalTokens     : evalTok,
          tokensPerSecond: tokPerSec,
          peakMemoryMb   : 0, // tidak tersedia dari event ini
        );

        _firstTokenTimer?.cancel();
        _firstTokenTimer = null;
        _closeActiveCtrl();
        break;

      // ── Error dari native ─────────────────────────────────────────────────
      case 'error':
        final seq     = (event['seq']     as int?)    ?? -1;
        final message = (event['message'] as String?) ?? 'Unknown native error';

        if (seq >= 0 && seq != _currentActiveSeq) return;

        debugPrint('[LlamaService] Native error seq=$seq: $message');

        final ctrl = _activeGenCtrl;
        if (ctrl != null && !ctrl.isClosed) {
          try {
            ctrl.add('\n\n⚠️ Error native: $message');
          } catch (_) {}
        }
        _firstTokenTimer?.cancel();
        _firstTokenTimer = null;
        _closeActiveCtrl();
        break;

      // ── Progres pemuatan model ────────────────────────────────────────────
      case 'loading_progress':
        final progress = (event['progress'] as double?) ?? 0.0;
        _loadingProgress = progress.clamp(0.0, 1.0);
        try {
          _loadProgressCtrl.add(_loadingProgress);
        } catch (_) {}
        break;

      // ── Model berhasil dimuat (event dari native) ─────────────────────────
      case 'model_loaded':
        final name    = event['name']          as String? ?? '';
        final ctx     = event['contextLength'] as int?    ?? _modelConfig.contextSize;
        final params  = event['paramCount']    as int?;

        debugPrint('[LlamaService] model_loaded: name=$name ctx=$ctx params=$params');

        // Perbarui informasi model jika berbeda
        if (_currentModel != null) {
          _currentModel = _currentModel!.copyWith(
            contextLength  : ctx,
            parameterCount : params,
          );
        }

        _loadingProgress = 1.0;
        try {
          _loadProgressCtrl.add(1.0);
        } catch (_) {}
        break;

      // ── Peringatan memori rendah ──────────────────────────────────────────
      case 'memory_warning':
        final availMb = event['availableMb'] as int? ?? 0;
        debugPrint('[LlamaService] ⚠️ Memory warning: tersisa ${availMb}MB');
        // Kirim ke status stream sebagai sinyal warning (tidak mengubah status utama)
        break;

      default:
        debugPrint('[LlamaService] Event tidak dikenal: type=$type');
    }
  }

  /// Tutup StreamController aktif dan reset semua state generate
  void _closeActiveCtrl() {
    final ctrl = _activeGenCtrl;
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.close();
    }
    _activeGenCtrl = null;
    _genRunning    = false;
    final comp = _genCompleter;
    _genCompleter  = null;
    if (comp != null && !comp.isCompleted) comp.complete();
  }

  /// Hentikan generate aktif dan tunggu sampai benar-benar selesai (max 3 detik)
  Future<void> _stopAndWait() async {
    if (!_genRunning && _activeGenCtrl == null) return;
    debugPrint('[LlamaService] _stopAndWait START...');

    _firstTokenTimer?.cancel();
    _firstTokenTimer = null;

    // Invalidate seq agar event lama dari sesi sebelumnya diabaikan
    _currentActiveSeq = ++_sessionSeq;

    // Panggil stopGeneration di native layer
    try {
      await _methodCh.invokeMethod<void>('stopGeneration');
    } catch (e) {
      debugPrint('[LlamaService] stopGeneration native error: $e');
    }

    // Tunggu ctrl.done maksimal 3 detik
    final ctrl = _activeGenCtrl;
    if (ctrl != null && !ctrl.isClosed) {
      try {
        await ctrl.done.timeout(const Duration(seconds: 3));
      } catch (_) {
        // Timeout — paksa tutup
        if (!ctrl.isClosed) ctrl.close();
      }
    }

    _activeGenCtrl = null;
    _genRunning    = false;
    final comp = _genCompleter;
    _genCompleter  = null;
    if (comp != null && !comp.isCompleted) comp.complete();

    // Beri jeda kecil agar native thread benar-benar berhenti
    await Future<void>.delayed(const Duration(milliseconds: 150));

    if (_status == ModelStatus.generating) {
      _updateStatus(ModelStatus.loaded);
    }

    debugPrint('[LlamaService] _stopAndWait DONE');
  }

  /// Perbarui status model dan emit ke statusStream
  void _updateStatus(ModelStatus newStatus) {
    if (_status == newStatus) return;
    _status = newStatus;
    try {
      _statusCtrl.add(newStatus);
    } catch (_) {}
    debugPrint('[LlamaService] Status → ${newStatus.name}');
  }

  // ── HTTP Server companion ──────────────────────────────────────────────────

  /// Apakah HTTP server companion sedang berjalan. Digunakan UI untuk menampilkan status.
  bool get isHttpServerRunning => LlamaHttpServer.instance.isRunning;

  /// Port yang digunakan HTTP server. Null jika server tidak berjalan.
  int? get httpServerPort => LlamaHttpServer.instance.port;
}

// ─────────────────────────────────────────────────────────────────────────────
// BACKWARD COMPATIBILITY: OfflineAiService
// (Dipindah ke offline_ai_service.dart — lihat file tersebut)
// ─────────────────────────────────────────────────────────────────────────────

// ignore: unused_element
class _RemovedOfflineAiServiceAlias {
  _RemovedOfflineAiServiceAlias._();

  /// Arahkan ke LlamaService singleton
  static LlamaService get instance => LlamaService.instance;

  // ── Forward property yang dipakai kode lama ──────────────────────────────

  /// Apakah model sudah siap digunakan
  bool get isReady => LlamaService.instance.isModelLoaded;

  /// Apakah model sedang dimuat
  bool get isLoading =>
      LlamaService.instance.status == ModelStatus.loading;

  /// Error string — ditangani via statusStream di arsitektur baru
  String? get error => null;

  /// Jumlah GPU layers yang dikonfigurasi
  int get gpuLayers => LlamaService.instance._modelConfig.gpuLayers;

  /// Ukuran konteks yang dikonfigurasi
  int get contextSize => LlamaService.instance._modelConfig.contextSize;

  /// Apakah sedang melakukan generasi
  bool get isGenerating => LlamaService.instance.isGenerating;

  // ── Forward method yang dipakai kode lama ─────────────────────────────────

  /// Muat settings dari SharedPreferences
  Future<void> loadSettings() => LlamaService.instance.loadSettings();

  /// Simpan settings ke SharedPreferences
  Future<void> saveSettings({
    bool forceOffline = false,
    int gpuLayers     = 0,
    int contextSize   = 4096,
  }) async {
    // Perbarui config dulu jika ada perubahan dari caller lama
    if (gpuLayers != LlamaService.instance._modelConfig.gpuLayers ||
        contextSize != LlamaService.instance._modelConfig.contextSize) {
      LlamaService.instance._modelConfig =
          LlamaService.instance._modelConfig.copyWith(
            gpuLayers: gpuLayers,
            contextSize: contextSize,
          );
    }
    return LlamaService.instance.saveSettings();
  }

  /// Stream token dengan signature API lama (prompt string langsung)
  Stream<String> chatStream(
    String prompt, {
    Map<String, dynamic>? params,
  }) {
    final config = InferenceConfig(
      temperature  : (params?['temperature']   as double?) ?? 0.7,
      topP         : (params?['topP']          as double?) ?? 0.9,
      topK         : (params?['topK']          as int?)    ?? 40,
      maxNewTokens : (params?['maxTokens']     as int?)    ?? 512,
      repeatPenalty: (params?['repeatPenalty'] as double?) ?? 1.1,
    );
    final messages = [ChatMessage.user(prompt)];
    return LlamaService.instance.generateStream(
      messages: messages,
      config  : config,
    );
  }

  /// Hentikan generasi yang sedang berjalan
  Future<void> stopGeneration() => LlamaService.instance.stopGeneration();

  /// Stream progres loading model
  Stream<double> get loadingProgress =>
      LlamaService.instance.loadProgressStream;
}
