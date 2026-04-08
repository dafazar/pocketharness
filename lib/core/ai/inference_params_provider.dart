// lib/core/ai/inference_params_provider.dart
// Provider Riverpod untuk semua state AI menggunakan StateNotifier
// Kompatibel dengan flutter_riverpod ^2.5.1

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'llama_context.dart';

// ─────────────────────────────────────────────────────────────────────────────
// KUNCI PENYIMPANAN SharedPreferences
// ─────────────────────────────────────────────────────────────────────────────

const _kInferenceConfigKey = 'kanmongo_inference_config';
const _kModelConfigKey = 'kanmongo_model_config';
const _kSystemPromptKey = 'kanmongo_system_prompt';

// ─────────────────────────────────────────────────────────────────────────────
// 1. INFERENCE CONFIG PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

/// Provider untuk konfigurasi sampling inferensi
final inferenceConfigProvider =
    StateNotifierProvider<InferenceConfigNotifier, InferenceConfig>(
      (ref) => InferenceConfigNotifier(),
    );

/// Notifier untuk mengelola konfigurasi inferensi
class InferenceConfigNotifier extends StateNotifier<InferenceConfig> {
  InferenceConfigNotifier() : super(InferenceConfig.defaultConfig) {
    // Muat konfigurasi dari penyimpanan lokal saat inisialisasi
    load();
  }

  /// Perbarui nilai temperature
  void updateTemperature(double value) {
    state = state.copyWith(temperature: value.clamp(0.0, 2.0));
    save();
  }

  /// Perbarui nilai top-p
  void updateTopP(double value) {
    state = state.copyWith(topP: value.clamp(0.0, 1.0));
    save();
  }

  /// Perbarui nilai top-k
  void updateTopK(int value) {
    state = state.copyWith(topK: value.clamp(1, 200));
    save();
  }

  /// Perbarui nilai min-p
  void updateMinP(double value) {
    state = state.copyWith(minP: value.clamp(0.0, 1.0));
    save();
  }

  /// Perbarui jumlah token maksimum yang dihasilkan
  void updateMaxTokens(int value) {
    state = state.copyWith(maxNewTokens: value.clamp(64, 8192));
    save();
  }

  /// Perbarui seed (gunakan -1 untuk acak)
  void updateSeed(int value) {
    state = state.copyWith(seed: value);
    save();
  }

  /// Perbarui penalti pengulangan
  void updateRepeatPenalty(double value) {
    state = state.copyWith(repeatPenalty: value.clamp(1.0, 2.0));
    save();
  }

  /// Perbarui mode dan parameter mirostat
  void updateMirostat({
    int? mode,
    double? tau,
    double? eta,
  }) {
    state = state.copyWith(
      mirostatMode: mode,
      mirostatTau: tau,
      mirostatEta: eta,
    );
    save();
  }

  /// Perbarui daftar urutan stop kustom
  void updateStopSequences(List<String> sequences) {
    state = state.copyWith(stopSequences: sequences);
    save();
  }

  /// Terapkan preset berdasarkan nama
  void applyPreset(String presetName) {
    switch (presetName.toLowerCase()) {
      case 'default':
        state = InferenceConfig.defaultConfig;
        break;
      case 'deterministic':
        state = InferenceConfig.deterministicConfig;
        break;
      case 'creative':
        state = InferenceConfig.creativeConfig;
        break;
      case 'code':
        state = InferenceConfig.codeConfig;
        break;
      default:
        state = InferenceConfig.defaultConfig;
    }
    save();
  }

  /// Reset ke konfigurasi default
  void resetToDefaults() {
    state = InferenceConfig.defaultConfig;
    save();
  }

  /// Simpan konfigurasi ke SharedPreferences
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kInferenceConfigKey, jsonEncode(state.toJson()));
  }

  /// Muat konfigurasi dari SharedPreferences
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kInferenceConfigKey);
    if (raw != null) {
      state = InferenceConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. MODEL CONFIG PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

/// Provider untuk konfigurasi pemuatan model
final modelConfigProvider =
    StateNotifierProvider<ModelConfigNotifier, LlamaModelConfig>(
      (ref) => ModelConfigNotifier(),
    );

/// Notifier untuk mengelola konfigurasi model llama.cpp
class ModelConfigNotifier extends StateNotifier<LlamaModelConfig> {
  ModelConfigNotifier() : super(LlamaModelConfig.defaultConfig) {
    // Muat konfigurasi dari penyimpanan lokal saat inisialisasi
    load();
  }

  /// Perbarui ukuran konteks
  void updateContextSize(int value) {
    state = state.copyWith(contextSize: value.clamp(512, 65536));
    save();
  }

  /// Perbarui jumlah layer GPU (0 = CPU only)
  void updateGpuLayers(int value) {
    state = state.copyWith(gpuLayers: value.clamp(0, 999));
    save();
  }

  /// Perbarui jumlah thread CPU
  void updateThreads(int value) {
    state = state.copyWith(nThreads: value.clamp(1, 32));
    save();
  }

  /// Perbarui ukuran batch
  void updateBatch(int value) {
    state = state.copyWith(nBatch: value.clamp(32, 2048));
    save();
  }

  /// Aktifkan atau nonaktifkan Flash Attention
  void updateFlashAttention(bool value) {
    state = state.copyWith(useFlashAttention: value);
    save();
  }

  /// Aktifkan atau nonaktifkan memory lock
  void updateMemoryLock(bool value) {
    state = state.copyWith(useMemoryLock: value);
    save();
  }

  /// Perbarui template chat
  void updateChatTemplate(ChatTemplate template) {
    state = state.copyWith(chatTemplate: template);
    save();
  }

  /// Reset ke konfigurasi default
  void resetToDefaults() {
    state = LlamaModelConfig.defaultConfig;
    save();
  }

  /// Simpan konfigurasi ke SharedPreferences
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kModelConfigKey, jsonEncode(state.toJson()));
  }

  /// Muat konfigurasi dari SharedPreferences
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kModelConfigKey);
    if (raw != null) {
      state = LlamaModelConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. ACTIVE MODEL INFO PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

/// Provider untuk model yang sedang aktif (nullable — belum ada model jika null)
final activeModelInfoProvider = StateProvider<LlamaModelInfo?>((ref) => null);

// ─────────────────────────────────────────────────────────────────────────────
// 4. PERFORMANCE METRICS PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

/// Provider untuk metrik performa sesi inferensi terakhir
final modelPerformanceProvider =
    StateProvider<ModelPerformanceMetrics?>((ref) => null);

// ─────────────────────────────────────────────────────────────────────────────
// 5. SYSTEM PROMPT PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

/// Provider untuk prompt sistem yang aktif
final systemPromptProvider =
    StateNotifierProvider<SystemPromptNotifier, String?>(
      (ref) => SystemPromptNotifier(),
    );

/// Notifier untuk mengelola prompt sistem
class SystemPromptNotifier extends StateNotifier<String?> {
  SystemPromptNotifier() : super(null) {
    // Muat prompt dari penyimpanan lokal saat inisialisasi
    load();
  }

  /// Preset prompt sistem yang tersedia
  Map<String, String> get availablePresets => {
    'defaultAssistant':
        'Kamu adalah asisten AI yang membantu, cerdas, dan ramah. '
        'Jawab pertanyaan dengan akurat dan jelas dalam Bahasa Indonesia.',
    'japaneseTutor':
        'Kamu adalah tutor Bahasa Jepang yang berpengalaman. '
        'Bantu pengguna belajar Bahasa Jepang dengan sabar, '
        'berikan contoh kalimat, dan koreksi kesalahan dengan sopan.',
    'codeAssistant':
        'Kamu adalah asisten programmer yang ahli dalam berbagai bahasa pemrograman. '
        'Berikan kode yang bersih, efisien, dan berikan penjelasan singkat. '
        'Selalu sertakan penanganan error dan komentar yang relevan.',
    'creativeWriter':
        'Kamu adalah penulis kreatif yang berbakat. '
        'Bantu pengguna menulis cerita, puisi, dan konten kreatif lainnya '
        'dengan imajinasi dan gaya penulisan yang menarik.',
    'summarizer':
        'Kamu adalah ahli merangkum teks. '
        'Baca teks yang diberikan dan buat ringkasan yang padat, akurat, '
        'dan mudah dipahami. Sertakan poin-poin utama.',
  };

  /// Atur prompt sistem secara langsung
  void setPrompt(String prompt) {
    state = prompt.trim().isEmpty ? null : prompt.trim();
    save();
  }

  /// Terapkan preset berdasarkan nama kunci
  void applyPreset(String name) {
    final prompt = availablePresets[name];
    if (prompt != null) {
      state = prompt;
      save();
    }
  }

  /// Hapus prompt sistem
  void clear() {
    state = null;
    save();
  }

  /// Simpan prompt ke SharedPreferences
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    if (state == null) {
      await prefs.remove(_kSystemPromptKey);
    } else {
      await prefs.setString(_kSystemPromptKey, state!);
    }
  }

  /// Muat prompt dari SharedPreferences
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_kSystemPromptKey);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. CHAT SESSION PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

/// Provider untuk sesi chat yang sedang aktif
final chatSessionProvider =
    StateNotifierProvider<ChatSessionNotifier, List<ChatMessage>>(
      (ref) => ChatSessionNotifier(),
    );

/// Notifier untuk mengelola pesan dalam sesi chat
class ChatSessionNotifier extends StateNotifier<List<ChatMessage>> {
  ChatSessionNotifier() : super([]);

  /// Tambahkan pesan baru ke sesi
  void addMessage(ChatMessage message) {
    state = [...state, message];
  }

  /// Tambahkan token ke pesan asisten terakhir (streaming)
  void updateLastAssistantMessage(String append) {
    if (state.isEmpty) return;
    final last = state.last;
    if (last.role != ChatRole.assistant) return;
    state = [
      ...state.sublist(0, state.length - 1),
      last.copyWith(content: last.content + append),
    ];
  }

  /// Ganti konten pesan asisten terakhir dengan hasil final
  void replaceLastAssistantMessage(
    String content, {
    StopReason? stopReason,
  }) {
    if (state.isEmpty) return;
    final last = state.last;
    if (last.role != ChatRole.assistant) return;
    state = [
      ...state.sublist(0, state.length - 1),
      last.copyWith(content: content, stopReason: stopReason),
    ];
  }

  /// Hapus pesan berdasarkan ID
  void deleteMessage(String id) {
    state = state.where((m) => m.id != id).toList();
  }

  /// Hapus seluruh sesi chat
  void clearSession() {
    state = [];
  }

  /// Hitung persentase penggunaan konteks (estimasi kasar: 1 token ≈ 4 karakter)
  double getContextUsagePercent(int maxContextSize) {
    if (maxContextSize <= 0) return 0;
    final totalChars = state.fold<int>(0, (sum, m) => sum + m.content.length);
    final estimatedTokens = (totalChars / 4).ceil();
    return (estimatedTokens / maxContextSize).clamp(0.0, 1.0);
  }

  /// Pangkas riwayat chat agar tidak melebihi batas token konteks
  /// Pesan sistem selalu dipertahankan, lalu pesan terbaru dipertahankan
  void trimForContext(int maxTokens) {
    if (state.isEmpty) return;

    // Pisahkan pesan sistem dan pesan percakapan
    final systemMessages = state.where((m) => m.role == ChatRole.system).toList();
    final convMessages = state.where((m) => m.role != ChatRole.system).toList();

    // Hitung estimasi token untuk setiap pesan
    int estimateTokens(ChatMessage m) => (m.content.length / 4).ceil();

    final systemTokens = systemMessages.fold<int>(0, (s, m) => s + estimateTokens(m));
    int remainingTokens = maxTokens - systemTokens;

    // Pertahankan pesan terbaru selama masih dalam batas
    final kept = <ChatMessage>[];
    for (final msg in convMessages.reversed) {
      final t = estimateTokens(msg);
      if (remainingTokens - t >= 0) {
        kept.insert(0, msg);
        remainingTokens -= t;
      } else {
        break;
      }
    }

    state = [...systemMessages, ...kept];
  }

  /// Load session dari ChatSession (untuk membuka session yang tersimpan)
  void loadSession(dynamic session) {
    // Gunakan reflection atau tipe casting untuk mendapatkan messages
    if (session == null) return;
    
    // Coba akses field 'messages' dari session object
    try {
      final messages = session.messages;
      if (messages is List<ChatMessage>) {
        state = List<ChatMessage>.from(messages);
      }
    } catch (e) {
      // Fallback jika akses field gagal
      // Pesan error diabaikan untuk production
    }
  }

  /// Set title untuk session saat ini (digunakan untuk rename)
  void setTitle(String title) {
    // Notifier ini hanya mengelola messages, bukan title
    // Title dikelola di UI level (chat_screen.dart)
    // Method ini ada untuk kompatibilitas dengan kode yang memanggil setTitle
  }
}
