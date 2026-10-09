// lib/core/ai/llama_isolate_manager.dart
// Manager untuk menjalankan inferensi llama.cpp di Dart Isolate terpisah
// Mencegah UI freeze saat model sedang menghasilkan token

import 'dart:async';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'llama_context.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────────────────────────────────────

/// Jenis pesan yang dikirim ke isolate
enum IsolateMessageType { inference, cancel, clear, dispose, ping }

/// Status saat ini dari isolate manager
enum IsolateStatus { idle, running, error, disposed }

// ─────────────────────────────────────────────────────────────────────────────
// CLASS: IsolateMessage
// ─────────────────────────────────────────────────────────────────────────────

/// Pesan yang dikirim dari thread utama ke isolate
class IsolateMessage {
  final IsolateMessageType type;
  final String? prompt;
  final InferenceConfig? config;
  final String? sessionId;

  const IsolateMessage({
    required this.type,
    this.prompt,
    this.config,
    this.sessionId,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// CLASS: IsolateResponse
// ─────────────────────────────────────────────────────────────────────────────

/// Respons yang dikirim dari isolate ke thread utama
class IsolateResponse {
  final IsolateMessageType type;
  final String? token;
  final bool isDone;
  final String? error;
  final String? sessionId;

  const IsolateResponse({
    required this.type,
    this.token,
    this.isDone = false,
    this.error,
    this.sessionId,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP-LEVEL FUNCTION: Entry point untuk isolate (wajib top-level)
// ─────────────────────────────────────────────────────────────────────────────

/// Entry point isolate — harus berupa fungsi top-level (bukan method class)
/// karena Dart Isolate tidak dapat menerima closure atau instance method
void _isolateEntryPoint(SendPort mainSendPort) {
  final receivePort = ReceivePort();

  // Kirim SendPort isolate ke thread utama agar bisa mengirim pesan
  mainSendPort.send(receivePort.sendPort);

  // Inisialisasi MethodChannel di sisi isolate untuk llama.cpp JNI
  // Catatan: MethodChannel di isolate memerlukan BackgroundIsolateBinaryMessenger
  // yang tersedia sejak Flutter 3.7+
  const MethodChannel methodChannel = MethodChannel('com.pocketharness.llama/engine');
  const EventChannel eventChannel = EventChannel('com.pocketharness.llama/stream');

  receivePort.listen((dynamic message) async {
    if (message is! IsolateMessage) return;

    switch (message.type) {
      // ── PING: Cek apakah isolate masih aktif ──────────────────────────────
      case IsolateMessageType.ping:
        mainSendPort.send(
          const IsolateResponse(type: IsolateMessageType.ping, isDone: true),
        );
        break;

      // ── INFERENCE: Jalankan generasi token ───────────────────────────────
      case IsolateMessageType.inference:
        if (message.prompt == null || message.config == null) {
          mainSendPort.send(
            IsolateResponse(
              type: IsolateMessageType.inference,
              error: 'Prompt atau config tidak boleh null',
              isDone: true,
              sessionId: message.sessionId,
            ),
          );
          break;
        }
        try {
          // Bangun argumen untuk MethodChannel JNI
          final args = <String, dynamic>{
            'prompt': message.prompt,
            'temperature': message.config!.temperature,
            'topP': message.config!.topP,
            'topK': message.config!.topK,
            'minP': message.config!.minP,
            'tfsZ': message.config!.tfsZ,
            'typicalP': message.config!.typicalP,
            'repeatPenalty': message.config!.repeatPenalty,
            'repeatLastN': message.config!.repeatLastN,
            'penalizeNl': message.config!.penalizeNl,
            'maxNewTokens': message.config!.maxNewTokens,
            'mirostatMode': message.config!.mirostatMode,
            'mirostatTau': message.config!.mirostatTau,
            'mirostatEta': message.config!.mirostatEta,
            'seed': message.config!.seed,
            'stopSequences': message.config!.stopSequences,
          };

          // Mulai inferensi via MethodChannel ke native llama.cpp
          await methodChannel.invokeMethod<void>('startInference', args);

          // Dengarkan token streaming dari EventChannel
          final stream = eventChannel.receiveBroadcastStream();
          await for (final event in stream) {
            if (event == null) continue;
            if (event is String) {
              // Kirim token ke thread utama
              mainSendPort.send(
                IsolateResponse(
                  type: IsolateMessageType.inference,
                  token: event,
                  isDone: false,
                  sessionId: message.sessionId,
                ),
              );
            } else if (event is Map && event['done'] == true) {
              // Inferensi selesai
              break;
            }
          }

          // Beritahu thread utama bahwa generasi selesai
          mainSendPort.send(
            IsolateResponse(
              type: IsolateMessageType.inference,
              isDone: true,
              sessionId: message.sessionId,
            ),
          );
        } catch (e) {
          mainSendPort.send(
            IsolateResponse(
              type: IsolateMessageType.inference,
              error: e.toString(),
              isDone: true,
              sessionId: message.sessionId,
            ),
          );
        }
        break;

      // ── CANCEL: Hentikan inferensi yang sedang berjalan ──────────────────
      case IsolateMessageType.cancel:
        try {
          await methodChannel.invokeMethod<void>('cancelInference');
          mainSendPort.send(
            const IsolateResponse(
              type: IsolateMessageType.cancel,
              isDone: true,
            ),
          );
        } catch (e) {
          mainSendPort.send(
            IsolateResponse(
              type: IsolateMessageType.cancel,
              error: e.toString(),
              isDone: true,
            ),
          );
        }
        break;

      // ── CLEAR: Bersihkan KV cache konteks ────────────────────────────────
      case IsolateMessageType.clear:
        try {
          await methodChannel.invokeMethod<void>('clearContext');
          mainSendPort.send(
            const IsolateResponse(
              type: IsolateMessageType.clear,
              isDone: true,
            ),
          );
        } catch (e) {
          mainSendPort.send(
            IsolateResponse(
              type: IsolateMessageType.clear,
              error: e.toString(),
              isDone: true,
            ),
          );
        }
        break;

      // ── DISPOSE: Matikan isolate dengan bersih ────────────────────────────
      case IsolateMessageType.dispose:
        try {
          await methodChannel.invokeMethod<void>('unloadModel');
        } catch (_) {
          // Abaikan error saat dispose
        }
        mainSendPort.send(
          const IsolateResponse(
            type: IsolateMessageType.dispose,
            isDone: true,
          ),
        );
        receivePort.close();
        break;
    }
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// CLASS: LlamaIsolateManager
// ─────────────────────────────────────────────────────────────────────────────

/// Manager singleton untuk menjalankan inferensi llama.cpp di Isolate terpisah.
/// Memastikan UI tetap responsif selama proses generasi token berlangsung.
class LlamaIsolateManager {
  // Singleton instance
  static final LlamaIsolateManager _instance = LlamaIsolateManager._internal();
  static LlamaIsolateManager get instance => _instance;
  LlamaIsolateManager._internal();

  Isolate? _isolate;
  SendPort? _isolateSendPort;
  ReceivePort? _receivePort;
  StreamController<IsolateResponse>? _responseController;

  IsolateStatus _status = IsolateStatus.idle;
  bool _isInitialized = false;

  /// Status saat ini dari isolate
  IsolateStatus get status => _status;

  /// Apakah isolate sedang menjalankan inferensi
  bool get isRunning => _status == IsolateStatus.running;

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC: initialize
  // ─────────────────────────────────────────────────────────────────────────

  /// Inisialisasi isolate. Harus dipanggil sebelum menggunakan manager ini.
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _spawnIsolate();
    _isInitialized = true;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE: _spawnIsolate
  // ─────────────────────────────────────────────────────────────────────────

  /// Buat dan jalankan isolate baru
  Future<void> _spawnIsolate() async {
    _receivePort = ReceivePort();
    _responseController = StreamController<IsolateResponse>.broadcast();

    // Spawn isolate dengan entry point top-level
    _isolate = await Isolate.spawn(
      _isolateEntryPoint,
      _receivePort!.sendPort,
      onError: _receivePort!.sendPort,
      onExit: _receivePort!.sendPort,
      errorsAreFatal: false,
    );

    // Dengarkan semua pesan dari isolate
    _receivePort!.listen((dynamic message) {
      if (message is SendPort) {
        // Terima SendPort dari isolate untuk mengirim pesan ke dalamnya
        _isolateSendPort = message;
      } else if (message is IsolateResponse) {
        _responseController?.add(message);
      } else if (message is List && message.length == 2) {
        // Format error dari onError: [errorMessage, stackTrace]
        _handleIsolateError(message[0]);
      }
    });

    // Tunggu hingga isolate siap (SendPort diterima)
    await Future.doWhile(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return _isolateSendPort == null;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC: dispose
  // ─────────────────────────────────────────────────────────────────────────

  /// Matikan isolate dan bersihkan semua resource
  Future<void> dispose() async {
    if (_status == IsolateStatus.disposed) return;

    if (_isolateSendPort != null) {
      _isolateSendPort!.send(
        const IsolateMessage(type: IsolateMessageType.dispose),
      );
      // Beri waktu isolate untuk membersihkan diri
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    await _responseController?.close();

    _isolate = null;
    _isolateSendPort = null;
    _receivePort = null;
    _responseController = null;
    _status = IsolateStatus.disposed;
    _isInitialized = false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC: runInference
  // ─────────────────────────────────────────────────────────────────────────

  /// Kirim permintaan inferensi ke isolate dan kembalikan stream token.
  /// Stream akan memancarkan token satu per satu hingga generasi selesai.
  Stream<String> runInference({
    required String prompt,
    required InferenceConfig config,
    required String sessionId,
  }) {
    if (!_isInitialized || _isolateSendPort == null) {
      return Stream.error(
        LlamaException('IsolateManager belum diinisialisasi', code: 'NOT_INIT'),
      );
    }
    if (_status == IsolateStatus.running) {
      return Stream.error(
        LlamaException('Inferensi sedang berjalan', code: 'BUSY'),
      );
    }
    if (_status == IsolateStatus.disposed) {
      return Stream.error(
        LlamaException('IsolateManager sudah di-dispose', code: 'DISPOSED'),
      );
    }

    final controller = StreamController<String>();

    _status = IsolateStatus.running;

    // Kirim pesan inferensi ke isolate
    _isolateSendPort!.send(
      IsolateMessage(
        type: IsolateMessageType.inference,
        prompt: prompt,
        config: config,
        sessionId: sessionId,
      ),
    );

    // Dengarkan respons dari isolate
    late StreamSubscription<IsolateResponse> sub;
    sub = _responseController!.stream
        .where((r) => r.sessionId == sessionId || r.sessionId == null)
        .listen(
          (response) {
            if (response.type != IsolateMessageType.inference) return;

            if (response.error != null) {
              // Terjadi error selama inferensi
              _status = IsolateStatus.idle;
              controller.addError(
                LlamaException(response.error!, code: 'INFERENCE_ERROR'),
              );
              controller.close();
              sub.cancel();
              return;
            }

            if (response.token != null) {
              // Kirim token ke stream output
              controller.add(response.token!);
            }

            if (response.isDone) {
              // Inferensi selesai
              _status = IsolateStatus.idle;
              controller.close();
              sub.cancel();
            }
          },
          onError: (Object error) {
            _status = IsolateStatus.error;
            controller.addError(error);
            controller.close();
            sub.cancel();
          },
        );

    return controller.stream;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC: cancel
  // ─────────────────────────────────────────────────────────────────────────

  /// Batalkan inferensi yang sedang berjalan
  Future<void> cancel() async {
    if (_isolateSendPort == null) return;
    _isolateSendPort!.send(
      const IsolateMessage(type: IsolateMessageType.cancel),
    );
    // Tunggu konfirmasi dari isolate
    await _responseController!.stream
        .firstWhere(
          (r) => r.type == IsolateMessageType.cancel && r.isDone,
        )
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => const IsolateResponse(
            type: IsolateMessageType.cancel,
            isDone: true,
          ),
        );
    _status = IsolateStatus.idle;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC: clearContext
  // ─────────────────────────────────────────────────────────────────────────

  /// Bersihkan KV cache konteks di sisi native (llama.cpp)
  Future<void> clearContext() async {
    if (_isolateSendPort == null) return;
    _isolateSendPort!.send(
      const IsolateMessage(type: IsolateMessageType.clear),
    );
    // Tunggu konfirmasi dari isolate
    await _responseController!.stream
        .firstWhere(
          (r) => r.type == IsolateMessageType.clear && r.isDone,
        )
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => const IsolateResponse(
            type: IsolateMessageType.clear,
            isDone: true,
          ),
        );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE: _handleIsolateError
  // ─────────────────────────────────────────────────────────────────────────

  /// Tangani error yang tidak terduga dari isolate
  void _handleIsolateError(dynamic error) {
    _status = IsolateStatus.error;
    _isInitialized = false;

    // Jadwalkan restart otomatis isolate setelah crash
    Future<void>.delayed(const Duration(seconds: 2), () {
      _restartIsolate();
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE: _restartIsolate
  // ─────────────────────────────────────────────────────────────────────────

  /// Restart isolate secara otomatis setelah crash
  Future<void> _restartIsolate() async {
    // Bersihkan state lama
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();

    _isolate = null;
    _isolateSendPort = null;
    _receivePort = null;

    // Buat StreamController baru untuk respons
    await _responseController?.close();
    _responseController = StreamController<IsolateResponse>.broadcast();

    // Spawn ulang isolate
    try {
      await _spawnIsolate();
      _status = IsolateStatus.idle;
      _isInitialized = true;
    } catch (e) {
      _status = IsolateStatus.error;
    }
  }
}
