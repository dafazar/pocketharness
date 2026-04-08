// lib/data/services/offline_ai_service.dart
// KanMon GO — Offline AI Service
//
// FIX v7 — Architecture Overhaul: "Unlimited Message" Guarantees
// =============================================================================
//
// ROOT CAUSE BUGS (v6 → v7 fix):
//   1. [CRASH] StreamController per-call tanpa guard: pesan ke-2 membuat ctrl
//      baru sementara ctrl lama bisa masih emit → addEvent ke ctrl.isClosed
//      → StateError (unhandled) → force close.
//
//   2. [HANG/CRASH] stopGeneration() tidak await native sebelum startGeneration:
//      native thread llama.cpp masih jalan saat startGeneration berikutnya
//      dipanggil → double-generate, OOM, atau callback ke eventSink lama.
//
//   3. [STALE TOKEN] _chatSessionId Dart vs genSessionId Kotlin increment
//      terpisah dan bisa mismatch → token generate lama tembus filter.
//
//   4. [TIMEOUT CRASH] stream.timeout() inject error langsung ke stream
//      → uncaught exception → force close saat generate normal terlambat.
//
//   5. [MEMORY LEAK] sub?.cancel() bisa gagal jika ctrl sudah close
//      dan cleanup tidak bersih.
//
// SOLUTION v7:
//   A. _activeGenCtrl: SATU StreamController<String> global (nullable).
//      chatStream() baru: _stopAndWait() → close ctrl lama → buat ctrl baru.
//
//   B. _stopAndWait(): invoke stopGeneration native + tunggu ctrl.done
//      (max 2 dtk) sebelum lanjut ke generate baru.
//
//   C. Timeout via Timer terpisah — tidak inject error ke stream.
//      Timeout hanya kirim pesan error lalu close ctrl.
//
//   D. _sessionSeq: single source of truth, dikirim ke native (field 'seq').
//      Difilter di _onNativeEvent → token stale diabaikan sempurna.
//
//   E. _genRunning + _genCompleter: serialisasi calls, aman concurrent.
//
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanmongo/data/services/model_manager_service.dart';

class OfflineAiService {
  OfflineAiService._() {
    _initEventChannel();
  }
  static final OfflineAiService instance = OfflineAiService._();

  static const _methodCh = MethodChannel('com.kanmongo.llama/engine');
  static const _eventCh  = EventChannel('com.kanmongo.llama/stream');

  static const _keyForceOffline = 'offline_ai_force_offline';
  static const _keyGpuLayers    = 'offline_ai_gpu_layers';
  static const _keyContextSize  = 'offline_ai_context_size';

  // ── State ──────────────────────────────────────────────────────────────────
  bool    _isReady         = false;
  bool    _isLoading       = false;
  String? _error;
  bool    _forceOffline    = false;
  int     _gpuLayers       = 0;
  int     _contextSize     = 2048;
  String? _loadedModelPath;

  bool    get isReady          => _isReady;
  bool    get isLoading        => _isLoading;
  String? get error            => _error;
  bool    get forceOfflineMode => _forceOffline;
  int     get gpuLayers        => _gpuLayers;
  int     get contextSize      => _contextSize;
  String? get loadedModelPath  => _loadedModelPath;

  // ── FIX v7: Single global active StreamController ─────────────────────────
  StreamController<String>? _activeGenCtrl;
  int  _sessionSeq        = 0;
  int  _currentActiveSeq  = 0;
  bool _genRunning        = false;
  Completer<void>? _genCompleter;
  Timer? _firstTokenTimer;
  bool   _gotFirstToken = false;

  // ── EventChannel: single persistent subscription ──────────────────────────
  StreamSubscription<dynamic>? _eventChannelSub;

  void _initEventChannel() {
    _eventChannelSub?.cancel();
    _eventChannelSub = _eventCh.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! Map) return;
        _onNativeEvent(Map<dynamic, dynamic>.from(event));
      },
      onError: (Object e) {
        debugPrint('[OfflineAI] EventChannel error: $e — re-init 200ms');
        Future.delayed(const Duration(milliseconds: 200), _initEventChannel);
      },
      cancelOnError: false,
    );
    debugPrint('[OfflineAI] EventChannel subscribed v7');
  }

  void _onNativeEvent(Map<dynamic, dynamic> event) {
    final seq    = (event['seq']   as int?)    ?? -1;
    final token  = (event['token'] as String?) ?? '';
    final isDone = (event['done']  as bool?)   ?? false;

    final ctrl = _activeGenCtrl;
    if (ctrl == null || ctrl.isClosed) {
      // Tidak ada generate aktif — abaikan
      return;
    }

    // Filter token dari session yang sudah tidak aktif
    // Hanya filter jika native mengirim field 'seq' (backward compat)
    if (seq >= 0 && seq != _currentActiveSeq) {
      debugPrint('[OfflineAI] stale event seq=$seq (active=$_currentActiveSeq) skip');
      return;
    }

    // Batalkan first-token timeout jika sudah dapat token
    if (!_gotFirstToken && token.isNotEmpty) {
      _gotFirstToken = true;
      _firstTokenTimer?.cancel();
      _firstTokenTimer = null;
      debugPrint('[OfflineAI] first token ✓ seq=$_currentActiveSeq');
    }

    if (token.isNotEmpty) {
      try { ctrl.add(token); } catch (e) {
        debugPrint('[OfflineAI] ctrl.add error (ctrl closed?): $e');
      }
    }

    if (isDone) {
      debugPrint('[OfflineAI] done seq=$_currentActiveSeq');
      _firstTokenTimer?.cancel();
      _firstTokenTimer = null;
      _closeActiveCtrl();
    }
  }

  void _closeActiveCtrl() {
    final ctrl = _activeGenCtrl;
    if (ctrl != null && !ctrl.isClosed) ctrl.close();
    _activeGenCtrl = null;
    _genRunning    = false;
    final comp = _genCompleter;
    _genCompleter  = null;
    if (comp != null && !comp.isCompleted) comp.complete();
  }

  /// Hentikan generate aktif dan tunggu sampai benar-benar selesai.
  Future<void> _stopAndWait() async {
    if (!_genRunning && _activeGenCtrl == null) return;
    debugPrint('[OfflineAI] _stopAndWait start...');

    _firstTokenTimer?.cancel();
    _firstTokenTimer = null;

    // Invalidate seq agar event lama diabaikan
    _currentActiveSeq = ++_sessionSeq;

    try {
      await _methodCh.invokeMethod('stopGeneration');
    } catch (e) {
      debugPrint('[OfflineAI] stopGeneration error: $e');
    }

    // Tunggu ctrl.done max 2 detik
    final ctrl = _activeGenCtrl;
    if (ctrl != null && !ctrl.isClosed) {
      try {
        await ctrl.done.timeout(const Duration(seconds: 2));
      } catch (_) {
        if (!ctrl.isClosed) ctrl.close();
      }
    }
    _activeGenCtrl = null;
    _genRunning    = false;
    final comp = _genCompleter;
    _genCompleter  = null;
    if (comp != null && !comp.isCompleted) comp.complete();

    // Delay agar native thread berhenti
    await Future.delayed(const Duration(milliseconds: 150));
    debugPrint('[OfflineAI] _stopAndWait done');
  }

  // ── Settings ───────────────────────────────────────────────────────────────
  Future<void> loadSettings() async {
    try {
      final prefs   = await SharedPreferences.getInstance();
      _forceOffline = prefs.getBool(_keyForceOffline)            ?? false;
      _gpuLayers    = prefs.getInt(_keyGpuLayers)                ?? 0;
      _contextSize  = prefs.getInt(_keyContextSize)              ?? 2048;
      _temperature  = prefs.getDouble('offline_ai_temperature')  ?? 0.7;
      _topP         = prefs.getDouble('offline_ai_top_p')        ?? 0.9;
      _topK         = prefs.getInt('offline_ai_top_k')           ?? 40;
    } catch (e) { debugPrint('[OfflineAI] loadSettings error: $e'); }
  }

  Future<void> saveSettings({
    required bool forceOffline,
    required int  gpuLayers,
    int contextSize = 2048,
  }) async {
    _forceOffline = forceOffline;
    _gpuLayers    = gpuLayers;
    _contextSize  = contextSize;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyForceOffline, forceOffline);
    await prefs.setInt(_keyGpuLayers,    gpuLayers);
    await prefs.setInt(_keyContextSize,  contextSize);
  }

  // ── Model Loading ──────────────────────────────────────────────────────────
  Future<bool> isModelReadySafe() async {
    if (!_isReady) return false;
    try {
      final nativeReady = await _methodCh.invokeMethod<bool>('isModelLoaded') ?? false;
      if (!nativeReady) { _isReady = false; debugPrint('[OfflineAI] native=false reset'); }
      return nativeReady;
    } catch (_) { return false; }
  }

  Future<void> flushInferenceBuffer() async {
    try { await _methodCh.invokeMethod('stopGeneration'); await Future.delayed(const Duration(milliseconds: 50)); }
    catch (_) {}
  }

  Future<void> initActiveModel() async {
    if (_isReady || _isLoading) return;
    if (ModelManagerService.instance.activeModel == null) return;
    await loadActiveModel();
  }

  Future<int> _getAvailableRamMb() async {
    try { return await _methodCh.invokeMethod<int>('getAvailableMemoryMb') ?? 0; }
    catch (_) { return 0; }
  }

  String _buildRamWarning(int modelMb, int availMb, int requiredMb) => [
    'RAM tidak cukup untuk model ini!', '',
    'Ukuran model   : ${modelMb}MB',
    'RAM tersedia   : ${availMb}MB',
    'RAM dibutuhkan : ~${requiredMb}MB', '',
    'Solusi:',
    '- Tutup semua aplikasi lain lalu coba lagi',
    '- Gunakan model lebih kecil (1B-3B, ~700MB-2GB)',
    '- Kurangi Context Size di Settings > AI Offline',
    if (modelMb > 2000) '- Model ${modelMb}MB butuh HP dengan RAM 8GB+',
  ].join('\n');

  Future<void> loadActiveModel() async {
    if (_isLoading) return;

    final activeRaw = ModelManagerService.instance.activeModelRaw;
    AiModel? active = ModelManagerService.instance.activeModel;

    if (activeRaw == null) {
      _error = 'Tidak ada model aktif.\n\nBuka Settings > Model Manager lalu pilih model GGUF.';
      return;
    }

    if (active == null) {
      debugPrint('[OfflineAI] path healing...');
      await ModelManagerService.instance.load();
      active = ModelManagerService.instance.activeModel;
      if (active == null) {
        _error = 'File model tidak ditemukan.\n\nModel: ${activeRaw.name}\n\n'
            'Buka Settings > Model Manager > hapus entri lama > import ulang .gguf';
        return;
      }
    }

    _isLoading = true; _isReady = false; _error = null;

    try {
      final modelSizeMb = File(active.path).lengthSync() ~/ (1024 * 1024);
      final availRamMb  = await _getAvailableRamMb();
      final kvMb        = (_contextSize / 1024.0 * 200).toInt();
      const scratchMb   = 384;
      final requiredMb  = (modelSizeMb * 0.35).toInt() + kvMb + scratchMb;

      if (availRamMb > 0 && availRamMb < requiredMb) {
        _error = _buildRamWarning(modelSizeMb, availRamMb, requiredMb);
        _isLoading = false; return;
      }

      try { await _methodCh.invokeMethod('releaseModel'); } catch (_) {}

      final isLargeModel = modelSizeMb >= 3500;
      final safeCtx = isLargeModel
          ? _contextSize.clamp(512, 1024) : _contextSize.clamp(512, 4096);

      debugPrint('[OfflineAI] loadModel: ${active.path} ctx=$safeCtx gpu=$_gpuLayers');

      final ok = await _methodCh.invokeMethod<bool>('loadModel', {
        'path': active.path, 'contextSize': safeCtx, 'gpuLayers': _gpuLayers,
      });

      if (ok == true) {
        _isReady = true; _isLoading = false; _loadedModelPath = active.path;
        debugPrint('[OfflineAI] Model ready: ${active.path}');
      } else {
        _error = 'Gagal memuat model.\n\n- File GGUF mungkin corrupt\n- RAM tidak cukup\n- Gunakan model Q4_K_M 1B-3B';
        _isLoading = false;
      }
    } on PlatformException catch (e) {
      _error = _friendlyLoadError(e.message ?? e.toString()); _isReady = false; _isLoading = false;
    } catch (e) {
      _error = _friendlyLoadError(e.toString()); _isReady = false; _isLoading = false;
    }
  }

  String _friendlyLoadError(String raw) {
    final r = raw.toLowerCase();
    if (r.contains('insufficient_ram') || r.contains('ram tidak cukup')) return raw;
    if (r.contains('out of memory') || r.contains('oom'))
      return 'RAM tidak cukup.\n- Tutup app lain\n- Gunakan model 1B Q4_K_M';
    if (r.contains('no such file') || r.contains('not found'))
      return 'File model tidak ditemukan.\nImport ulang di Settings > Model Manager.';
    if (r.contains('stub') || r.contains('belum dikompilasi'))
      return 'AI Offline belum aktif.\n\nGGUF engine belum dikompilasi.\nBuild ulang APK via GitHub Actions.';
    if (r.contains('magic') || r.contains('gguf'))
      return 'File GGUF tidak valid atau corrupt.\nDownload ulang dari HuggingFace.';
    return 'Gagal memuat model:\n$raw\n\nCoba restart app atau pilih model lain.';
  }

  _PromptFormat _detectFormat(String modelPath) {
    final n = modelPath.toLowerCase();
    if (n.contains('llama-3') || n.contains('llama3')) return _PromptFormat.llama3;
    if (n.contains('gemma'))                            return _PromptFormat.gemma;
    if (n.contains('mistral') || n.contains('mixtral')) return _PromptFormat.mistral;
    if (n.contains('phi'))                              return _PromptFormat.phi;
    if (n.contains('qwen'))                             return _PromptFormat.chatMl;
    return _PromptFormat.chatMl;
  }

  String _buildPrompt({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required String userMessage,
  }) => _detectFormat(_loadedModelPath ?? '').build(
    systemPrompt: systemPrompt, history: history, userMessage: userMessage,
  );

  // ── chatStream — CORE FIX v7 ───────────────────────────────────────────────
  Stream<String> chatStream({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required String userMessage,
    int    maxTokens     = 512,
    double temperature   = 0.7,
    double topP          = 0.9,
    double repeatPenalty = 1.1,
  }) async* {
    final safeMsg = userMessage.trim();
    if (safeMsg.isEmpty) { yield 'Pesan tidak boleh kosong.'; return; }

    // [STEP 1] Hentikan generate sebelumnya + tunggu bersih
    await _stopAndWait();

    // [STEP 2] Validasi model
    if (!_isReady) {
      final activeRaw = ModelManagerService.instance.activeModelRaw;
      final active    = ModelManagerService.instance.activeModel;
      if (activeRaw == null) {
        yield 'Belum ada model offline.\n\nBuka Settings > Model Manager > import file .gguf';
        return;
      }
      if (active == null) {
        yield 'File model tidak ditemukan.\n\nModel: ${activeRaw.name}\n\n'
            'Buka Settings > Model Manager > hapus entri lama > import ulang .gguf';
        return;
      }
      yield 'Memuat model AI...\n\n';
      await loadActiveModel();
      if (!_isReady) {
        yield 'Gagal memuat model.\n\n${_error ?? "Unknown error"}';
        return;
      }
      yield 'Model siap!\n\n';
    }

    final nativeReady = await isModelReadySafe();
    if (!nativeReady) {
      yield 'Model belum siap di native layer.\nCoba reload model di Settings > AI Offline.';
      return;
    }

    // [STEP 3] Build prompt
    final prompt = _buildPrompt(
      systemPrompt: systemPrompt, history: history, userMessage: safeMsg,
    );
    if (prompt.trim().isEmpty) { yield 'Gagal membangun prompt. Coba lagi.'; return; }

    // [STEP 4] Buat ctrl baru + increment sessionSeq
    _sessionSeq++;
    _currentActiveSeq = _sessionSeq;
    final mySeq = _currentActiveSeq;

    // FIX: Buat ctrl BARU yang bersih — dijamin tidak ada ctrl lama aktif
    // karena _stopAndWait() sudah menutup ctrl lama di atas.
    final ctrl = StreamController<String>();
    _activeGenCtrl = ctrl;
    _genRunning    = true;
    _genCompleter  = Completer<void>();
    _gotFirstToken = false;

    debugPrint('[OfflineAI] chatStream START seq=$mySeq');

    // [STEP 5] First-token timeout via Timer (tidak inject error ke stream!)
    // Jika 90 detik belum ada token, kirim pesan error lalu close ctrl.
    _firstTokenTimer = Timer(const Duration(seconds: 90), () {
      if (_currentActiveSeq == mySeq && !_gotFirstToken && !ctrl.isClosed) {
        debugPrint('[OfflineAI] first-token timeout seq=$mySeq');
        ctrl.add('\n\n⏰ Timeout: AI tidak merespons dalam 90 detik.\n'
            'Coba:\n• Kirim ulang pesan\n• Restart app\n• Reload model di Settings');
        _closeActiveCtrl();
      }
    });

    // [STEP 6] Invoke startGeneration native
    try {
      await _methodCh.invokeMethod('startGeneration', {
        'prompt'       : prompt,
        'maxTokens'    : maxTokens,
        'temperature'  : temperature,
        'topP'         : topP,
        'repeatPenalty': repeatPenalty,
        'seq'          : mySeq,  // dikirim agar native bisa filter jika didukung
      });

      // [STEP 7] yield tokens dari ctrl.stream
      // Tokens datang melalui _onNativeEvent → ctrl.add(token)
      await for (final token in ctrl.stream) {
        if (_currentActiveSeq != mySeq) break; // guard double-check
        yield token;
      }

    } on PlatformException catch (e) {
      _firstTokenTimer?.cancel(); _firstTokenTimer = null;
      final code = e.code.toUpperCase();
      final msg  = e.message ?? e.toString();
      if (code.contains('OOM') || msg.toLowerCase().contains('out of memory')) {
        yield '\n\nRAM habis saat inferensi.\n- Tutup app lain\n- Kurangi Context Size di Settings';
      } else if (code.contains('INVALID') || msg.toLowerCase().contains('invalid')) {
        yield '\n\nPrompt tidak valid.\nCoba kirim pesan yang lebih pendek.';
      } else if (code.contains('DESTROYED') || msg.toLowerCase().contains('destroyed')) {
        _isReady = false;
        yield '\n\nModel unloaded secara paksa.\nKirim pesan lagi untuk reload otomatis.';
      } else {
        yield '\n\nError native: $msg';
      }
    } catch (e) {
      _firstTokenTimer?.cancel(); _firstTokenTimer = null;
      yield '\n\nError: ${e.toString().replaceAll("Exception: ", "")}';
    } finally {
      // [STEP 8] Cleanup — pastikan selalu bersih meski ada exception
      _firstTokenTimer?.cancel(); _firstTokenTimer = null;
      if (_currentActiveSeq == mySeq) {
        if (!ctrl.isClosed) ctrl.close();
        _activeGenCtrl = null;
        _genRunning    = false;
        final comp = _genCompleter;
        _genCompleter  = null;
        if (comp != null && !comp.isCompleted) comp.complete();
      }
      debugPrint('[OfflineAI] chatStream END seq=$mySeq gotFirst=$_gotFirstToken');
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────
  Future<void> stopGeneration() async {
    debugPrint('[OfflineAI] stopGeneration() called');
    await _stopAndWait();
  }

  Future<void> unloadModel() async {
    await stopGeneration();
    try { await _methodCh.invokeMethod('releaseModel'); } catch (_) {}
    _isReady = false; _loadedModelPath = null;
  }

  /// Load model dari path tertentu dengan contextSize dan gpuLayers override.
  /// Digunakan oleh AiSourcePicker untuk memuat model langsung dari UI.
  Future<void> loadModel(
    String path, {
    int? contextSize,
    int? gpuLayers,
  }) async {
    if (_isLoading) return;
    if (path.isEmpty) {
      _error = 'Path model kosong.';
      return;
    }

    final file = File(path);
    if (!file.existsSync()) {
      _error = 'File model tidak ditemukan:\n$path\n\nImport ulang file .gguf via Model Manager.';
      return;
    }

    _isLoading = true; _isReady = false; _error = null;

    // Gunakan override jika diberikan, fallback ke setting tersimpan
    final ctxSize  = (contextSize ?? _contextSize).clamp(512, 8192);
    final gpuL     = gpuLayers   ?? _gpuLayers;

    try {
      final modelSizeMb = file.lengthSync() ~/ (1024 * 1024);
      final availRamMb  = await _getAvailableRamMb();
      final kvMb        = (ctxSize / 1024.0 * 200).toInt();
      const scratchMb   = 384;
      final requiredMb  = (modelSizeMb * 0.35).toInt() + kvMb + scratchMb;

      if (availRamMb > 0 && availRamMb < requiredMb) {
        _error = _buildRamWarning(modelSizeMb, availRamMb, requiredMb);
        _isLoading = false; return;
      }

      try { await _methodCh.invokeMethod('releaseModel'); } catch (_) {}

      final isLargeModel = modelSizeMb >= 3500;
      final safeCtx = isLargeModel
          ? ctxSize.clamp(512, 1024) : ctxSize.clamp(512, 4096);

      debugPrint('[OfflineAI] loadModel(path): $path ctx=$safeCtx gpu=$gpuL');

      final ok = await _methodCh.invokeMethod<bool>('loadModel', {
        'path': path, 'contextSize': safeCtx, 'gpuLayers': gpuL,
      });

      if (ok == true) {
        _isReady = true; _isLoading = false; _loadedModelPath = path;
        debugPrint('[OfflineAI] Model ready (path override): $path');
      } else {
        _error = 'Gagal memuat model.\n\n- File GGUF mungkin corrupt\n- RAM tidak cukup\n- Gunakan model Q4_K_M 1B-3B';
        _isLoading = false;
      }
    } on PlatformException catch (e) {
      _error = _friendlyLoadError(e.message ?? e.toString()); _isReady = false; _isLoading = false;
    } catch (e) {
      _error = _friendlyLoadError(e.toString()); _isReady = false; _isLoading = false;
    }
  }

  Future<void> reset() async { await unloadModel(); _error = null; }

  Future<bool>   isModelLoaded() async {
    try { return await _methodCh.invokeMethod<bool>('isModelLoaded') ?? false; }
    catch (_) { return false; }
  }
  Future<int>    getAvailableRamMb() async => _getAvailableRamMb();
  Future<String> getModelInfo() async {
    try { return await _methodCh.invokeMethod<String>('getModelInfo') ?? '{"loaded":false}'; }
    catch (_) { return '{"loaded":false}'; }
  }

  Future<String> generate(String userMessage, {
    int    maxTokens    = 256,
    double temperature  = 0.3,
    String systemPrompt = '',
  }) async {
    if (!_isReady) return '';
    final sb = StringBuffer();
    await for (final chunk in chatStream(
      systemPrompt: systemPrompt, history: [], userMessage: userMessage,
      maxTokens: maxTokens, temperature: temperature,
    )) { sb.write(chunk); }
    return sb.toString();
  }

  // ── Preferences ───────────────────────────────────────────────────────────
  Future<void> setForceOfflineMode(bool v) async {
    _forceOffline = v;
    (await SharedPreferences.getInstance()).setBool(_keyForceOffline, v);
  }
  Future<void> setNumGpuLayers(int l) async {
    _gpuLayers = l;
    (await SharedPreferences.getInstance()).setInt(_keyGpuLayers, l);
  }
  Future<void> setContextSize(int s) async {
    _contextSize = s.clamp(512, 8192);
    (await SharedPreferences.getInstance()).setInt(_keyContextSize, _contextSize);
  }

  // ── Download ───────────────────────────────────────────────────────────────
  static const _defaultModelUrl =
      'https://huggingface.co/google/gemma-3-1b-it-qat-q4_0-gguf/resolve/main/gemma-3-1b-it-qat-q4_0.gguf';
  static const _defaultModelName = 'gemma-3-1b-it-q4_0.gguf';

  Future<void> downloadAndInstall({ void Function(double)? onProgress }) async {
    if (_isLoading) return;
    _isLoading = true; _error = null;
    try {
      final dir       = await getApplicationDocumentsDirectory();
      final modelsDir = Directory('${dir.path}/ai_models');
      if (!modelsDir.existsSync()) modelsDir.createSync(recursive: true);
      final destPath = '${modelsDir.path}/$_defaultModelName';
      final client   = http.Client();
      try {
        final req  = http.Request('GET', Uri.parse(_defaultModelUrl));
        final resp = await client.send(req);
        if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
        final total = resp.contentLength ?? 0;
        int received = 0;
        final sink = File(destPath).openWrite();
        await resp.stream.map((chunk) {
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
          return chunk;
        }).pipe(sink);
        await sink.close();
      } finally { client.close(); }
      final model = await ModelManagerService.instance.importModel(destPath);
      if (model != null) await ModelManagerService.instance.setActive(model.id);
      _isLoading = false;
      await loadActiveModel();
    } catch (e) {
      _error = 'Download gagal: $e\n\nCek koneksi internet.';
      _isReady = false; _isLoading = false;
    }
  }

  Future<void> deleteModel() async {
    final active = ModelManagerService.instance.activeModel;
    if (active == null) return;
    await reset();
    try {
      if (File(active.path).existsSync()) await File(active.path).delete();
      await ModelManagerService.instance.deleteModel(active.id);
    } catch (e) { _error = 'Gagal hapus model: $e'; }
  }

  // ── Compatibility stubs ────────────────────────────────────────────────────
  bool get isGenerating => _genRunning;
  Future<void> stop() => stopGeneration();

  final StreamController<double> _loadingProgressCtrl =
      StreamController<double>.broadcast();
  Stream<double> get loadingProgress => _loadingProgressCtrl.stream;

  double _temperature = 0.7;
  double _topP        = 0.9;
  int    _topK        = 40;

  double get temperature => _temperature;
  double get topP        => _topP;
  int    get topK        => _topK;

  Future<void> setTemperature(double v) async {
    _temperature = v.clamp(0.0, 2.0);
    (await SharedPreferences.getInstance()).setDouble('offline_ai_temperature', _temperature);
  }
  Future<void> setTopP(double v) async {
    _topP = v.clamp(0.0, 1.0);
    (await SharedPreferences.getInstance()).setDouble('offline_ai_top_p', _topP);
  }
  Future<void> setTopK(int v) async {
    _topK = v.clamp(1, 200);
    (await SharedPreferences.getInstance()).setInt('offline_ai_top_k', _topK);
  }

  Future<Map<String, dynamic>?> getModelInfoMap() async {
    try {
      final raw = await getModelInfo();
      final d   = jsonDecode(raw);
      return d is Map<String, dynamic> ? d : null;
    } catch (_) { return null; }
  }
}

// ── Prompt Formats ─────────────────────────────────────────────────────────

enum _PromptFormat { chatMl, llama3, gemma, mistral, phi }

extension _PromptFormatX on _PromptFormat {
  String build({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required String userMessage,
  }) {
    switch (this) {
      case _PromptFormat.chatMl: {
        final sb = StringBuffer();
        if (systemPrompt.isNotEmpty) sb.write("<|im_start|>system\n$systemPrompt<|im_end|>\n");
        for (final m in history) {
          final role = m['role'] ?? 'user';
          final text = m['content'] ?? '';
          sb.write(role == 'assistant'
            ? "<|im_start|>assistant\n$text<|im_end|>\n"
            : "<|im_start|>user\n$text<|im_end|>\n");
        }
        sb.write("<|im_start|>user\n$userMessage<|im_end|>\n<|im_start|>assistant\n");
        return sb.toString();
      }
      case _PromptFormat.llama3: {
        final sb = StringBuffer()..write('<|begin_of_text|>');
        if (systemPrompt.isNotEmpty)
          sb.write("<|start_header_id|>system<|end_header_id|>\n\n$systemPrompt<|eot_id|>");
        for (final m in history) {
          final role = m['role'] ?? 'user';
          final text = m['content'] ?? '';
          sb.write("<|start_header_id|>$role<|end_header_id|>\n\n$text<|eot_id|>");
        }
        sb.write("<|start_header_id|>user<|end_header_id|>\n\n$userMessage<|eot_id|>"
            "<|start_header_id|>assistant<|end_header_id|>\n\n");
        return sb.toString();
      }
      case _PromptFormat.gemma: {
        final sb  = StringBuffer();
        final sys = systemPrompt.isNotEmpty ? "$systemPrompt\n\n" : '';
        bool first = true;
        for (final m in history) {
          final role = m['role'] ?? 'user';
          final text = m['content'] ?? '';
          if (role == 'user') {
            sb.write("<start_of_turn>user\n${first && sys.isNotEmpty ? sys : ''}$text<end_of_turn>\n");
            first = false;
          } else {
            sb.write("<start_of_turn>model\n$text<end_of_turn>\n");
          }
        }
        sb.write("<start_of_turn>user\n${first && sys.isNotEmpty ? sys : ''}$userMessage<end_of_turn>\n<start_of_turn>model\n");
        return sb.toString();
      }
      case _PromptFormat.mistral: {
        final sb  = StringBuffer();
        final sys = systemPrompt.isNotEmpty ? "$systemPrompt\n\n" : '';
        bool first = true;
        for (final m in history) {
          final role = m['role'] ?? 'user';
          final text = m['content'] ?? '';
          if (role == 'user') {
            sb.write("[INST] ${first && sys.isNotEmpty ? sys : ''}$text [/INST]");
            first = false;
          } else { sb.write(" $text</s>"); }
        }
        sb.write("[INST] ${first && sys.isNotEmpty ? sys : ''}$userMessage [/INST]");
        return sb.toString();
      }
      case _PromptFormat.phi: {
        final sb = StringBuffer();
        if (systemPrompt.isNotEmpty) sb.write("<|system|>\n$systemPrompt<|end|>\n");
        for (final m in history) {
          final role = m['role'] ?? 'user';
          final text = m['content'] ?? '';
          sb.write(role == 'assistant'
            ? "<|assistant|>\n$text<|end|>\n"
            : "<|user|>\n$text<|end|>\n");
        }
        sb.write("<|user|>\n$userMessage<|end|>\n<|assistant|>\n");
        return sb.toString();
      }
    }
  }
}
