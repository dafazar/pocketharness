// lib/data/services/llama_service.dart
// KanMon GO — LlamaService (Singleton)
//
// Mengelola lifecycle model AI offline (llama.cpp) melalui platform channel.
// Singleton dengan semua member yang dibutuhkan:
//   • instance singleton
//   • isModelLoaded (bool getter)
//   • status & statusStream (ModelStatus)
//   • currentModel (LlamaModelInfo?)
//   • loadModel(LlamaModelInfo, {LlamaModelConfig?})
//   • releaseModel()
//   • generateStream({messages, config}) → Stream<String>
//   • saveSettings()
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kanmongo/core/ai/llama_context.dart';

class LlamaService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final LlamaService instance = LlamaService._();
  LlamaService._();

  // ── Platform channels ──────────────────────────────────────────────────────
  static const _platform     = MethodChannel('com.kanmongo.llama/engine');
  static const _eventChannel = EventChannel('com.kanmongo.llama/stream');

  // ── Internal state ─────────────────────────────────────────────────────────
  ModelStatus      _status       = ModelStatus.notLoaded;
  LlamaModelInfo?  _currentModel;

  final StreamController<ModelStatus> _statusCtrl =
      StreamController<ModelStatus>.broadcast();

  // ── Public API ─────────────────────────────────────────────────────────────

  ModelStatus     get status       => _status;
  Stream<ModelStatus> get statusStream => _statusCtrl.stream;
  bool            get isModelLoaded =>
      _status == ModelStatus.loaded || _status == ModelStatus.generating;
  LlamaModelInfo? get currentModel => _currentModel;

  // ── loadModel ──────────────────────────────────────────────────────────────

  Future<void> loadModel(
    LlamaModelInfo modelInfo, {
    LlamaModelConfig? config,
  }) async {
    final cfg = config ?? LlamaModelConfig.defaultConfig;
    _setStatus(ModelStatus.loading);
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

      _currentModel = modelInfo;
      _setStatus(ModelStatus.loaded);
      debugPrint('[LlamaService] ✅ Model loaded: ${modelInfo.name}');

    } on PlatformException catch (e) {
      debugPrint('[LlamaService] ❌ PlatformException: ${e.code} ${e.message}');
      _setStatus(ModelStatus.error);
      rethrow;
    } catch (e) {
      debugPrint('[LlamaService] ❌ Error: $e');
      _setStatus(ModelStatus.error);
      rethrow;
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
    }
  }

  // ── generateStream ─────────────────────────────────────────────────────────

  Stream<String> generateStream({
    required List<ChatMessage> messages,
    InferenceConfig? config,
  }) async* {
    final cfg = config ?? InferenceConfig.defaultConfig;

    if (!isModelLoaded) throw LlamaException('Tidak ada model yang dimuat');

    _setStatus(ModelStatus.generating);
    debugPrint('[LlamaService] generateStream — ${messages.length} messages');

    final prompt = _buildChatMLPrompt(messages);
    final controller = StreamController<String>();
    StreamSubscription? sub;

    try {
      sub = _eventChannel.receiveBroadcastStream().listen(
        (event) {
          if (event is! Map) return;
          final type = event['type'] as String?;
          switch (type) {
            case 'token':
              final t = event['token'] as String? ?? '';
              if (t.isNotEmpty) controller.add(t);
              break;
            case 'done':
              controller.close();
              break;
            case 'error':
              controller.addError(
                LlamaException(event['message'] as String? ?? 'Unknown error'),
              );
              controller.close();
              break;
          }
        },
        onError: (e) {
          controller.addError(e);
          controller.close();
        },
      );

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
      });

      await for (final token in controller.stream) {
        yield token;
      }

    } catch (e) {
      debugPrint('[LlamaService] generateStream error: $e');
      rethrow;
    } finally {
      await sub?.cancel();
      if (!controller.isClosed) await controller.close();
      if (_status == ModelStatus.generating) _setStatus(ModelStatus.loaded);
    }
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
