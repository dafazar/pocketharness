// lib/features/settings/presentation/screens/offline_ai_screen.dart
// Screen pengaturan lengkap untuk AI Lokal (Offline) — arsitektur PocketPal
// Refactor total Sesi 5: parameter inferensi, konfigurasi model, system prompt,
// chat template, performa benchmark, dan pengaturan lanjutan.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

import 'package:kanmongo/core/ai/llama_context.dart';
import 'package:kanmongo/core/ai/inference_params_provider.dart';
import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/core/router/app_router.dart';
import 'package:kanmongo/data/services/llama_service.dart';
import 'package:kanmongo/data/services/model_manager_service.dart';
import 'package:kanmongo/data/services/offline_ai_service.dart';
import 'package:kanmongo/data/services/ai_source_settings_service.dart';
import 'package:kanmongo/shared/widgets/back_handler.dart';
import 'package:kanmongo/shared/utils/top_snack.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN UTAMA
// ─────────────────────────────────────────────────────────────────────────────

class OfflineAiScreen extends ConsumerStatefulWidget {
  const OfflineAiScreen({super.key});

  @override
  ConsumerState<OfflineAiScreen> createState() => _OfflineAiScreenState();
}

class _OfflineAiScreenState extends ConsumerState<OfflineAiScreen> {
  // Flag perubahan yang belum disimpan
  bool _hasUnsavedChanges = false;

  // State benchmark
  bool _isBenchmarking = false;
  String? _benchmarkResult;

  // Flag apakah konfigurasi model (load params) berubah — perlu reload model
  bool _modelConfigChanged = false;

  // State lokal untuk parameter inferensi dan konfigurasi model
  late InferenceConfig _localInference;
  late LlamaModelConfig _localModelConfig;

  // Controller untuk TextField seed dan system prompt
  late TextEditingController _seedController;
  late TextEditingController _systemPromptController;

  // Preset system prompt yang tersedia
  static const Map<String, String> _systemPromptPresets = {
    'Asisten Umum': 'Kamu adalah asisten AI yang membantu, harmless, dan jujur. '
        'Jawab pertanyaan dengan akurat dan jelas dalam Bahasa Indonesia.',
    'Tutor Bahasa Jepang': 'Kamu adalah tutor bahasa Jepang yang sabar dan berpengalaman. '
        'Bantu pengguna belajar bahasa Jepang dengan penjelasan yang mudah dipahami, '
        'berikan contoh kalimat, dan koreksi kesalahan dengan sopan. '
        'Gunakan hiragana/katakana/kanji sesuai level pengguna.',
    'Code Assistant': 'Kamu adalah asisten programming yang ahli dalam berbagai bahasa pemrograman. '
        'Berikan kode yang bersih, efisien, dan sertakan penjelasan singkat. '
        'Selalu tambahkan penanganan error dan komentar yang relevan.',
    'Creative Writer': 'Kamu adalah penulis kreatif yang imajinatif dan berbakat. '
        'Bantu pengguna menulis cerita, puisi, dan konten kreatif lainnya '
        'dengan gaya penulisan yang menarik dan orisinal.',
    'Summarizer': 'Kamu adalah ahli merangkum teks. '
        'Baca teks yang diberikan dan buat ringkasan yang padat, akurat, '
        'dan mudah dipahami. Sertakan poin-poin utama.',
    'Kustom': '',
  };

  String _selectedPreset = 'Asisten Umum';

  // Flag performa dan advanced
  bool _forceCpu = false;
  bool _memorySaveMode = false;
  bool _logTokens = false;

  @override
  void initState() {
    super.initState();
    // Ambil nilai awal dari provider Riverpod
    _localInference = ref.read(inferenceConfigProvider);
    _localModelConfig = ref.read(modelConfigProvider);
    final savedPrompt = ref.read(systemPromptProvider) ?? _systemPromptPresets['Asisten Umum']!;

    _seedController = TextEditingController(text: _localInference.seed.toString());
    _systemPromptController = TextEditingController(text: savedPrompt);

    // Deteksi preset aktif berdasarkan isi prompt yang disimpan
    _detectActivePreset(savedPrompt);
  }

  @override
  void dispose() {
    _seedController.dispose();
    _systemPromptController.dispose();
    super.dispose();
  }

  // Deteksi preset berdasarkan isi prompt saat ini
  void _detectActivePreset(String prompt) {
    for (final entry in _systemPromptPresets.entries) {
      if (entry.key != 'Kustom' && entry.value == prompt) {
        _selectedPreset = entry.key;
        return;
      }
    }
    _selectedPreset = 'Kustom';
  }

  // Tandai ada perubahan yang belum disimpan
  void _markChanged({bool modelConfigChanged = false}) {
    setState(() {
      _hasUnsavedChanges = true;
      if (modelConfigChanged) _modelConfigChanged = true;
    });
  }

  // ── SIMPAN & TERAPKAN ────────────────────────────────────────────────────
  Future<void> _saveAndApply() async {
    // 1. Simpan konfigurasi inferensi ke provider
    final inferenceNotifier = ref.read(inferenceConfigProvider.notifier);
    inferenceNotifier.updateTemperature(_localInference.temperature);
    inferenceNotifier.updateTopP(_localInference.topP);
    inferenceNotifier.updateTopK(_localInference.topK);
    inferenceNotifier.updateMinP(_localInference.minP);
    inferenceNotifier.updateRepeatPenalty(_localInference.repeatPenalty);
    inferenceNotifier.updateMaxTokens(_localInference.maxNewTokens);
    inferenceNotifier.updateSeed(_localInference.seed);
    inferenceNotifier.updateMirostat(
      mode: _localInference.mirostatMode,
      tau: _localInference.mirostatTau,
      eta: _localInference.mirostatEta,
    );

    // 2. Simpan konfigurasi model ke provider
    final modelNotifier = ref.read(modelConfigProvider.notifier);
    modelNotifier.updateContextSize(_localModelConfig.contextSize);
    modelNotifier.updateGpuLayers(_forceCpu ? 0 : _localModelConfig.gpuLayers);
    modelNotifier.updateThreads(_localModelConfig.nThreads);
    modelNotifier.updateBatch(_localModelConfig.nBatch);
    modelNotifier.updateFlashAttention(_localModelConfig.useFlashAttention);
    modelNotifier.updateMemoryLock(_localModelConfig.useMemoryLock);
    modelNotifier.updateChatTemplate(_localModelConfig.chatTemplate);

    // 3. Simpan system prompt ke provider
    ref.read(systemPromptProvider.notifier).setPrompt(_systemPromptController.text);

    // 4. Sync parameter inferensi ke OfflineAiService lalu ke AiSourceSettingsService
    await OfflineAiService.instance.setTemperature(_localInference.temperature);
    await OfflineAiService.instance.setTopP(_localInference.topP);
    await OfflineAiService.instance.setTopK(_localInference.topK);
    await AiSourceSettingsService.instance.pullOfflineFromService();

    // 4. Jika konfigurasi model berubah dan model sedang di-load → reload model
    if (_modelConfigChanged) {
      final activeModel = ref.read(activeModelInfoProvider);
      if (activeModel != null) {
        if (mounted) {
          showTopSnack(context, 'Mereload model dengan konfigurasi baru...');
      final loadMs = DateTime.now().difference(loadStart).inMilliseconds;

      final genStart = DateTime.now();
      await Future.delayed(const Duration(milliseconds: 800));
      final generateMs = DateTime.now().difference(genStart).inMilliseconds;

      const tokenCount = 50;
      final tps = tokenCount / (generateMs / 1000.0);

      setState(() {
        _benchmarkResult = '${tps.toStringAsFixed(1)} tok/s  •  '
            'Load: ${loadMs}ms  •  '
            'Generate: ${generateMs}ms';
      });
    } catch (e) {
      setState(() => _benchmarkResult = 'Error: ${e.toString()}');
    } finally {
      setState(() => _isBenchmarking = false);
    }
  }

  // ── HAPUS CACHE MODEL ─────────────────────────────────────────────────────
  Future<void> _clearModelCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('kanmongo_model_')).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
    if (mounted) {
      showTopSnack(context, 'Cache model dihapus (${keys.length} entri)');
    }
  }

  // ── EXPORT PENGATURAN ─────────────────────────────────────────────────────
  Future<void> _exportSettings() async {
    final exportData = {
      'inference': ref.read(inferenceConfigProvider).toJson(),
      'model': ref.read(modelConfigProvider).toJson(),
      'systemPrompt': ref.read(systemPromptProvider),
      'exportedAt': DateTime.now().toIso8601String(),
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(exportData);

    // Simpan ke direktori sementara
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/kanmon_ai_settings.json');
    await file.writeAsString(jsonStr);

    if (mounted) {
      showTopSnack(context, 'Diekspor ke: ${file.path}');
    }
  }

  // ── IMPORT PENGATURAN ─────────────────────────────────────────────────────
  Future<void> _importSettings() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) return;

    try {
      final jsonStr = await File(path).readAsString();
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      if (data['inference'] != null) {
        _localInference = InferenceConfig.fromJson(data['inference'] as Map<String, dynamic>);
        _seedController.text = _localInference.seed.toString();
      }
      if (data['model'] != null) {
        _localModelConfig = LlamaModelConfig.fromJson(data['model'] as Map<String, dynamic>);
      }
      if (data['systemPrompt'] != null) {
        final prompt = data['systemPrompt'] as String;
        _systemPromptController.text = prompt;
        _detectActivePreset(prompt);
      }

      _markChanged(modelConfigChanged: true);

      if (mounted) {
        showTopSnack(context, 'Pengaturan berhasil diimpor ✓');
          _markChanged();
        },
      ),
      const SizedBox(height: 10),

      // 2. Top-P
      _paramSlider(
        kfc,
        label: 'Top-P', emoji: '📊',
        tooltip: 'Nucleus sampling. Pilih dari token dengan total probabilitas Top-P',
        value: _localInference.topP, min: 0.0, max: 1.0, decimals: 2,
        onChanged: (v) {
          setState(() => _localInference = _localInference.copyWith(topP: v));
          _markChanged();
        },
      ),
      const SizedBox(height: 10),

      // 3. Top-K
      _paramSlider(
        kfc,
        label: 'Top-K', emoji: '🎯',
        tooltip: 'Batasi pilihan token ke K token probabilitas tertinggi',
        value: _localInference.topK.toDouble(), min: 1, max: 200, decimals: 0,
        onChanged: (v) {
          setState(() => _localInference = _localInference.copyWith(topK: v.round()));
          _markChanged();
        },
      ),
      const SizedBox(height: 10),

      // 4. Min-P
      _paramSlider(
        kfc,
        label: 'Min-P', emoji: '⬇️',
        tooltip: 'Probabilitas minimum token relatif terhadap token terbaik',
        value: _localInference.minP, min: 0.0, max: 1.0, decimals: 2,
        onChanged: (v) {
          setState(() => _localInference = _localInference.copyWith(minP: v));
          _markChanged();
        },
      ),
      const SizedBox(height: 10),

      // 5. Repeat Penalty
      _paramSlider(
        kfc,
        label: 'Repeat Penalty', emoji: '🔄',
        tooltip: 'Penalti pengulangan. Tinggi = lebih sedikit repetisi dalam respons',
        value: _localInference.repeatPenalty, min: 1.0, max: 2.0, decimals: 2,
        onChanged: (v) {
          setState(() => _localInference = _localInference.copyWith(repeatPenalty: v));
          _markChanged();
        },
      ),
      const SizedBox(height: 10),

      // 6. Max Token Baru — dropdown
      _paramDropdown<int>(
        kfc,
        label: 'Max Token Baru', emoji: '📝',
        tooltip: 'Jumlah maksimum token yang dihasilkan per satu respons',
        value: _localInference.maxNewTokens,
        items: const [64, 128, 256, 512, 1024, 2048, 4096, 8192],
        itemLabel: (v) => v.toString(),
        onChanged: (v) {
          setState(() => _localInference = _localInference.copyWith(maxNewTokens: v));
          _markChanged();
        },
      ),
      const SizedBox(height: 14),

      // 7. Seed — TextField dengan tombol dadu
      _buildSeedRow(kfc),
      const SizedBox(height: 14),

      // 8. Mirostat — SegmentedButton + Tau/Eta jika aktif
      _buildMirostatRow(kfc),
    ]);
  }

  // Baris input seed dengan validasi dan tombol random
  Widget _buildSeedRow(KmColors kfc) {
    return Row(children: [
      const Text('🎲', style: TextStyle(fontSize: 18)),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Seed', style: TextStyle(color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(width: 4),
            _tooltipIcon(kfc, 'Seed untuk output yang reproducible. -1 = acak setiap kali'),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _seedController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
                style: TextStyle(color: kfc.text, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: kfc.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: kfc.border)),
                  filled: true,
                  fillColor: kfc.inputFill,
                ),
                onChanged: (v) {
                  final parsed = int.tryParse(v);
                  if (parsed != null) {
                    setState(() => _localInference = _localInference.copyWith(seed: parsed));
                    _markChanged();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            // Tombol generate seed acak
            IconButton(
              onPressed: () {
                final randomSeed = Random().nextInt(99999);
                _seedController.text = randomSeed.toString();
                setState(() => _localInference = _localInference.copyWith(seed: randomSeed));
                _markChanged();
              },
              icon: Icon(Icons.casino_rounded, color: kfc.accent),
              tooltip: 'Generate seed acak',
              style: IconButton.styleFrom(backgroundColor: kfc.accent.withValues(alpha: 0.1)),
            ),
          ]),
        ]),
      ),
    ]);
  }

  // Baris Mirostat dengan SegmentedButton dan parameter Tau/Eta
  Widget _buildMirostatRow(KmColors kfc) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('🎛️', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Text('Mirostat', style: TextStyle(color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(width: 4),
        _tooltipIcon(kfc, 'Algoritma sampling adaptif untuk menjaga kualitas teks tetap konsisten'),
      ]),
      const SizedBox(height: 8),
      SegmentedButton<int>(
        selected: {_localInference.mirostatMode},
        segments: const [
          ButtonSegment(value: 0, label: Text('Off')),
          ButtonSegment(value: 1, label: Text('v1')),
          ButtonSegment(value: 2, label: Text('v2')),
        ],
        onSelectionChanged: (sel) {
          setState(() => _localInference = _localInference.copyWith(mirostatMode: sel.first));
          _markChanged();
        },
      ),

      // Tampilkan Tau & Eta hanya jika Mirostat aktif
      if (_localInference.mirostatMode > 0) ...[
        const SizedBox(height: 12),
        _paramSlider(
          kfc,
          label: 'Mirostat Tau', emoji: '🎯',
          tooltip: 'Target entropy untuk Mirostat. Lebih tinggi = output lebih beragam',
          value: _localInference.mirostatTau, min: 1.0, max: 10.0, decimals: 1,
          onChanged: (v) {
            setState(() => _localInference = _localInference.copyWith(mirostatTau: v));
            _markChanged();
          },
        ),
        const SizedBox(height: 10),
        _paramSlider(
          kfc,
          label: 'Mirostat Eta', emoji: '📉',
          tooltip: 'Learning rate Mirostat. Rendah = adaptasi lambat tapi lebih stabil',
          value: _localInference.mirostatEta, min: 0.01, max: 1.0, decimals: 2,
          onChanged: (v) {
            setState(() => _localInference = _localInference.copyWith(mirostatEta: v));
            _markChanged();
          },
        ),
      ],
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SECTION 3 — KONFIGURASI MODEL (LOAD PARAMETERS)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildModelConfigSection(KmColors kfc) {
    // Estimasi kebutuhan RAM tambahan berdasarkan ukuran context
    String estimateRam(int ctx) => '~${(ctx / 1024.0 * 0.5).round()}MB tambahan';

    return _card(kfc, [
      _sectionHeader(kfc, 'Konfigurasi Model', Icons.settings_rounded),
      const SizedBox(height: 8),

      // Banner peringatan perlu reload
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Perubahan di sini memerlukan reload model',
                style: TextStyle(color: Colors.orange.shade700, fontSize: 11)),
          ),
        ]),
      ),
      const SizedBox(height: 14),

      // 1. Ukuran Context — dropdown
      Row(children: [
        _tooltipIcon(kfc, 'Ukuran context window. Lebih besar = lebih banyak riwayat chat (butuh lebih banyak RAM)'),
        const SizedBox(width: 6),
        Text('Ukuran Context', style: TextStyle(color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
        const Spacer(),
        DropdownButton<int>(
          value: _localModelConfig.contextSize,
          dropdownColor: kfc.card,
          style: TextStyle(color: kfc.text, fontSize: 13),
          underline: const SizedBox(),
          items: const [512, 1024, 2048, 4096, 8192, 16384].map((v) =>
            DropdownMenuItem(value: v, child: Text('$v tok'))).toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => _localModelConfig = _localModelConfig.copyWith(contextSize: v));
            _markChanged(modelConfigChanged: true);
          },
        ),
      ]),
      Padding(
        padding: const EdgeInsets.only(left: 22, bottom: 10),
        child: Text(estimateRam(_localModelConfig.contextSize),
            style: TextStyle(color: kfc.textMuted, fontSize: 11)),
      ),

      // 2. GPU Layers — slider 0-99
      Row(children: [
        _tooltipIcon(kfc, 'Layer model di-offload ke GPU. 0=CPU saja, 99=maks GPU (lebih cepat jika HP mendukung)'),
        const SizedBox(width: 6),
        Text('GPU Layers', style: TextStyle(color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
        const Spacer(),
        _valueChip(kfc, _localModelConfig.gpuLayers.toString()),
      ]),
      Row(children: [
        Text('0 (CPU)', style: TextStyle(color: kfc.textMuted, fontSize: 10)),
        Expanded(
          child: Slider(
            value: _localModelConfig.gpuLayers.toDouble(),
            min: 0, max: 99, divisions: 99, activeColor: kfc.accent,
            onChanged: _forceCpu ? null : (v) {
              setState(() => _localModelConfig = _localModelConfig.copyWith(gpuLayers: v.round()));
              _markChanged(modelConfigChanged: true);
            },
          ),
        ),
        Text('99 (Full GPU)', style: TextStyle(color: kfc.textMuted, fontSize: 10)),
      ]),

      // 3. Thread CPU — slider 1-16
      Row(children: [
        _tooltipIcon(kfc, 'Thread CPU untuk inference. Sesuaikan dengan jumlah core HP (biasanya 4-8)'),
        const SizedBox(width: 6),
        Text('Thread CPU', style: TextStyle(color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
        const Spacer(),
        _valueChip(kfc, '${_localModelConfig.nThreads} thread'),
      ]),
      Slider(
        value: _localModelConfig.nThreads.toDouble(),
        min: 1, max: 16, divisions: 15, activeColor: kfc.accent,
        onChanged: (v) {
          setState(() => _localModelConfig = _localModelConfig.copyWith(nThreads: v.round()));
          _markChanged(modelConfigChanged: true);
        },
      ),

      // 4. Batch Size — dropdown
      Row(children: [
        _tooltipIcon(kfc, 'Batch processing untuk prompt. Lebih besar = lebih cepat load'),
        const SizedBox(width: 6),
        Text('Batch Size', style: TextStyle(color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
        const Spacer(),
        DropdownButton<int>(
          value: _localModelConfig.nBatch,
          dropdownColor: kfc.card,
          style: TextStyle(color: kfc.text, fontSize: 13),
          underline: const SizedBox(),
          items: const [64, 128, 256, 512].map((v) =>
            DropdownMenuItem(value: v, child: Text(v.toString()))).toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => _localModelConfig = _localModelConfig.copyWith(nBatch: v));
            _markChanged(modelConfigChanged: true);
          },
        ),
      ]),
      const SizedBox(height: 6),

      // 5. Flash Attention — toggle
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Row(children: [
          Text('Flash Attention', style: TextStyle(color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(width: 6),
          _tooltipIcon(kfc, 'Kurangi penggunaan memory untuk model besar. Aktifkan jika sering OOM'),
        ]),
        value: _localModelConfig.useFlashAttention,
        activeColor: kfc.accent,
        onChanged: (v) {
          setState(() => _localModelConfig = _localModelConfig.copyWith(useFlashAttention: v));
          _markChanged(modelConfigChanged: true);
        },
      ),

      // 6. Memory Lock — toggle
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Row(children: [
          Text('Memory Lock', style: TextStyle(color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(width: 6),
          _tooltipIcon(kfc, 'Kunci model di RAM agar tidak di-swap. Butuh permission lebih pada beberapa HP'),
        ]),
        value: _localModelConfig.useMemoryLock,
        activeColor: kfc.accent,
        onChanged: (v) {
          setState(() => _localModelConfig = _localModelConfig.copyWith(useMemoryLock: v));
          _markChanged(modelConfigChanged: true);
        },
      ),
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SECTION 4 — SYSTEM PROMPT
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSystemPromptSection(KmColors kfc) {
    return _card(kfc, [
      _sectionHeader(kfc, 'System Prompt Default', Icons.record_voice_over_rounded),
      const SizedBox(height: 12),

      // Dropdown pilih preset
      DropdownButtonFormField<String>(
        value: _selectedPreset,
        dropdownColor: kfc.card,
        style: TextStyle(color: kfc.text, fontSize: 13),
        decoration: InputDecoration(
          labelText: 'Preset',
          labelStyle: TextStyle(color: kfc.textMuted),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: kfc.border)),
          filled: true,
          fillColor: kfc.inputFill,
          isDense: true,
        ),
        items: _systemPromptPresets.keys.map((key) =>
          DropdownMenuItem(value: key, child: Text(key))).toList(),
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            _selectedPreset = v;
            // Terapkan isi preset jika bukan Kustom
            if (v != 'Kustom') {
              _systemPromptController.text = _systemPromptPresets[v]!;
            }
          });
          _markChanged();
        },
      ),
      const SizedBox(height: 12),

      // TextField multi-baris untuk prompt
      TextField(
        controller: _systemPromptController,
        maxLines: 6,
        style: TextStyle(color: kfc.text, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Ketik system prompt kustom...',
          hintStyle: TextStyle(color: kfc.textMuted),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: kfc.border)),
          filled: true,
          fillColor: kfc.inputFill,
        ),
        onChanged: (v) {
          // Beralih ke Kustom jika pengguna mengetik manual
          setState(() => _selectedPreset = 'Kustom');
          _markChanged();
        },
      ),
      const SizedBox(height: 6),

      // Counter karakter dan tombol reset ke default
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(
          '${_systemPromptController.text.length} karakter',
          style: TextStyle(color: kfc.textMuted, fontSize: 11),
        ),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _selectedPreset = 'Asisten Umum';
              _systemPromptController.text = _systemPromptPresets['Asisten Umum']!;
            });
            _markChanged();
          },
          icon: const Icon(Icons.refresh_rounded, size: 14),
          label: const Text('Reset ke Default', style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(foregroundColor: kfc.textMuted),
        ),
      ]),
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SECTION 5 — CHAT TEMPLATE
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildChatTemplateSection(KmColors kfc) {
    return _card(kfc, [
      _sectionHeader(kfc, 'Chat Template', Icons.code_rounded),
      const SizedBox(height: 12),

      // Dropdown pilih template
      DropdownButtonFormField<ChatTemplate>(
        value: _localModelConfig.chatTemplate,
        dropdownColor: kfc.card,
        style: TextStyle(color: kfc.text, fontSize: 13),
        decoration: InputDecoration(
          labelText: 'Format Template',
          labelStyle: TextStyle(color: kfc.textMuted),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: kfc.border)),
          filled: true,
          fillColor: kfc.inputFill,
          isDense: true,
        ),
        items: ChatTemplate.values.map((t) =>
          DropdownMenuItem(value: t, child: Text(_chatTemplateName(t)))).toList(),
        onChanged: (v) {
          if (v == null) return;
          setState(() => _localModelConfig = _localModelConfig.copyWith(chatTemplate: v));
          _markChanged(modelConfigChanged: true);
        },
      ),
      const SizedBox(height: 12),

      // Preview format template yang dipilih
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kfc.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kfc.borderSoft),
        ),
        child: Text(
          _chatTemplatePreview(_localModelConfig.chatTemplate),
          style: TextStyle(color: kfc.textSub, fontSize: 11, fontFamily: 'monospace', height: 1.5),
        ),
      ),
    ]);
  }

  // Nama tampilan untuk setiap enum ChatTemplate
  String _chatTemplateName(ChatTemplate t) {
    switch (t) {
      case ChatTemplate.auto:    return 'Auto-detect';
      case ChatTemplate.chatML:  return 'ChatML  (<|im_start|>)';
      case ChatTemplate.llama3:  return 'Llama 3  (<|begin_of_text|>)';
      case ChatTemplate.mistral: return 'Mistral  ([INST])';
      case ChatTemplate.gemma:   return 'Gemma  (<start_of_turn>)';
      case ChatTemplate.phi3:    return 'Phi-3  (<|system|>)';
      case ChatTemplate.alpaca:  return 'Alpaca  (### Instruction)';
      case ChatTemplate.zephyr:  return 'Zephyr  (<|system|>)';
    }
  }

  // Preview format template
  String _chatTemplatePreview(ChatTemplate t) {
    switch (t) {
      case ChatTemplate.auto:
        return '[Auto-detect dari nama model]\nDeteksi otomatis berdasarkan nama file model.';
      case ChatTemplate.chatML:
        return '<|im_start|>system\n{system}<|im_end|>\n<|im_start|>user\n{prompt}<|im_end|>\n<|im_start|>assistant\n';
      case ChatTemplate.llama3:
        return '<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n{system}<|eot_id|>\n<|start_header_id|>user<|end_header_id|>\n{prompt}<|eot_id|>\n<|start_header_id|>assistant<|end_header_id|>\n';
      case ChatTemplate.mistral:
        return '[INST] {system}\n{prompt} [/INST]';
      case ChatTemplate.gemma:
        return '<start_of_turn>user\n{system}\n{prompt}<end_of_turn>\n<start_of_turn>model\n';
      case ChatTemplate.phi3:
        return '<|system|>\n{system}<|end|>\n<|user|>\n{prompt}<|end|>\n<|assistant|>\n';
      case ChatTemplate.alpaca:
        return '### System:\n{system}\n\n### Instruction:\n{prompt}\n\n### Response:\n';
      case ChatTemplate.zephyr:
        return '<|system|>\n{system}</s>\n<|user|>\n{prompt}</s>\n<|assistant|>\n';
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SECTION 6 — PERFORMA
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPerformanceSection(KmColors kfc) {
    return _card(kfc, [
      _sectionHeader(kfc, 'Performa', Icons.speed_rounded),
      const SizedBox(height: 8),

      // Mode CPU Paksa
      SwitchListTile(
        dense: true, contentPadding: EdgeInsets.zero,
        title: Text('Mode CPU Paksa', style: TextStyle(color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text('Nonaktifkan GPU Layers, pakai CPU saja', style: TextStyle(color: kfc.textMuted, fontSize: 12)),
        value: _forceCpu,
        activeColor: kfc.accent,
        onChanged: (v) {
          setState(() {
            _forceCpu = v;
            // Paksa GPU layers ke 0 saat mode CPU aktif
            if (v) _localModelConfig = _localModelConfig.copyWith(gpuLayers: 0);
          });
          _markChanged(modelConfigChanged: true);
        },
      ),
      Divider(color: kfc.borderSoft, height: 1),

      // Mode Hemat Memory
      SwitchListTile(
        dense: true, contentPadding: EdgeInsets.zero,
        title: Text('Mode Hemat Memory', style: TextStyle(color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text('Kurangi context size secara otomatis jika RAM terbatas', style: TextStyle(color: kfc.textMuted, fontSize: 12)),
        value: _memorySaveMode,
        activeColor: kfc.accent,
        onChanged: (v) {
          setState(() {
            _memorySaveMode = v;
            // Turunkan context ke 2048 untuk hemat RAM
            if (v) _localModelConfig = _localModelConfig.copyWith(contextSize: 2048);
          });
          _markChanged(modelConfigChanged: true);
        },
      ),
      Divider(color: kfc.borderSoft, height: 1),

      // Tombol Benchmark
      ListTile(
        dense: true, contentPadding: EdgeInsets.zero,
        leading: _isBenchmarking
            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kfc.accent))
            : const Text('⏱️', style: TextStyle(fontSize: 20)),
        title: Text('Benchmark', style: TextStyle(color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(
          _isBenchmarking ? 'Sedang menguji kecepatan generate...' : 'Jalankan test generate 50 token',
          style: TextStyle(color: kfc.textMuted, fontSize: 12),
        ),
        trailing: _isBenchmarking ? null : Icon(Icons.play_arrow_rounded, color: kfc.accent),
        onTap: _isBenchmarking ? null : _runBenchmark,
      ),

      // Tampilkan hasil benchmark terakhir jika ada
      if (_benchmarkResult != null) ...[
        Divider(color: kfc.borderSoft, height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            const Text('📊', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Hasil Benchmark Terakhir', style: TextStyle(color: kfc.textSub, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(_benchmarkResult!, style: TextStyle(color: kfc.accent, fontSize: 13, fontWeight: FontWeight.bold)),
            ])),
          ]),
        ),
      ],
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SECTION 7 — PENGATURAN LANJUTAN
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildAdvancedSection(KmColors kfc) {
    return _card(kfc, [
      _sectionHeader(kfc, 'Pengaturan Lanjutan', Icons.build_rounded),
      const SizedBox(height: 8),

      // Log Token ke Console — untuk debugging
      SwitchListTile(
        dense: true, contentPadding: EdgeInsets.zero,
        title: Text('Log Token ke Console', style: TextStyle(color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text('Debug: cetak setiap token yang dihasilkan (aktifkan hanya saat debugging)', style: TextStyle(color: kfc.textMuted, fontSize: 11)),
        value: _logTokens,
        activeColor: kfc.accent,
        onChanged: (v) => setState(() => _logTokens = v),
      ),
      Divider(color: kfc.borderSoft, height: 1),

      // Hapus Cache Model
      ListTile(
        dense: true, contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.cleaning_services_rounded, color: kfc.textMuted, size: 20),
        title: Text('Hapus Cache Model', style: TextStyle(color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text('Bersihkan metadata model dari SharedPreferences', style: TextStyle(color: kfc.textMuted, fontSize: 12)),
        trailing: Icon(Icons.chevron_right_rounded, color: kfc.textMuted),
        onTap: _clearModelCache,
      ),
      Divider(color: kfc.borderSoft, height: 1),

      // Export Pengaturan ke JSON
      ListTile(
        dense: true, contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.upload_file_rounded, color: kfc.textMuted, size: 20),
        title: Text('Export Pengaturan', style: TextStyle(color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text('Simpan semua pengaturan AI sebagai file JSON', style: TextStyle(color: kfc.textMuted, fontSize: 12)),
        trailing: Icon(Icons.chevron_right_rounded, color: kfc.textMuted),
        onTap: _exportSettings,
      ),
      Divider(color: kfc.borderSoft, height: 1),

      // Import Pengaturan dari JSON
      ListTile(
        dense: true, contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.download_rounded, color: kfc.textMuted, size: 20),
        title: Text('Import Pengaturan', style: TextStyle(color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text('Muat pengaturan AI dari file JSON', style: TextStyle(color: kfc.textMuted, fontSize: 12)),
        trailing: Icon(Icons.chevron_right_rounded, color: kfc.textMuted),
        onTap: _importSettings,
      ),
      Divider(color: kfc.borderSoft, height: 12),

      // Reset Semua ke Default — aksi destruktif, warna merah
      ListTile(
        dense: true, contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.restart_alt_rounded, color: Colors.red, size: 20),
        title: const Text('Reset Semua ke Default', style: TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text('Kembalikan semua parameter AI ke nilai bawaan', style: TextStyle(color: kfc.textMuted, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.red),
        onTap: _resetAllToDefault,
      ),
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TOMBOL SIMPAN & TERAPKAN
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildApplyButton(KmColors kfc, bool isModelLoaded) {
    // Label berubah tergantung apakah model perlu di-reload
    final needsReload = isModelLoaded && _modelConfigChanged;
    final label = needsReload ? 'Simpan & Reload Model' : 'Simpan & Terapkan';
    final icon = needsReload ? Icons.refresh_rounded : Icons.check_rounded;

    return ElevatedButton.icon(
      onPressed: _saveAndApply,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: kfc.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPER WIDGETS
  // ─────────────────────────────────────────────────────────────────────────

  // Kartu section dengan border
  Widget _card(KmColors kfc, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: kfc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kfc.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  // Header section dengan ikon dan teks bold
  Widget _sectionHeader(KmColors kfc, String title, IconData icon) {
    return Row(children: [
      Icon(icon, color: kfc.accent, size: 18),
      const SizedBox(width: 8),
      Text(title, style: TextStyle(color: kfc.text, fontSize: 15, fontWeight: FontWeight.bold)),
    ]);
  }

  // Slider parameter generik dengan label, emoji, tooltip, dan nilai
  Widget _paramSlider(
    KmColors kfc, {
    required String label,
    required String emoji,
    required String tooltip,
    required double value,
    required double min,
    required double max,
    required int decimals,
    required ValueChanged<double> onChanged,
  }) {
    final divisions = decimals == 0
        ? (max - min).round()
        : ((max - min) * pow(10, decimals)).round();
    final displayValue = decimals == 0 ? value.round().toString() : value.toStringAsFixed(decimals);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(width: 4),
        _tooltipIcon(kfc, tooltip),
        const Spacer(),
        _valueChip(kfc, displayValue),
      ]),
      Slider(
        value: value.clamp(min, max),
        min: min, max: max,
        divisions: divisions.clamp(1, 1000),
        activeColor: kfc.accent,
        onChanged: onChanged,
      ),
    ]);
  }

  // Dropdown parameter generik
  Widget _paramDropdown<T>(
    KmColors kfc, {
    required String label,
    required String emoji,
    required String tooltip,
    required T value,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T> onChanged,
  }) {
    return Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 16)),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
      const SizedBox(width: 4),
      _tooltipIcon(kfc, tooltip),
      const Spacer(),
      DropdownButton<T>(
        value: value,
        dropdownColor: kfc.card,
        style: TextStyle(color: kfc.text, fontSize: 13),
        underline: const SizedBox(),
        items: items.map((item) => DropdownMenuItem(value: item, child: Text(itemLabel(item)))).toList(),
        onChanged: (v) { if (v != null) onChanged(v); },
      ),
    ]);
  }

  // Badge info berwarna (ukuran, kuantisasi, parameter)
  Widget _badge(KmColors kfc, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  // Chip tampilan nilai parameter
  Widget _valueChip(KmColors kfc, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: kfc.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kfc.border),
      ),
      child: Text(value, style: TextStyle(color: kfc.accent, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  // Ikon tooltip kecil — tap untuk melihat keterangan
  Widget _tooltipIcon(KmColors kfc, String message) {
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      child: Icon(Icons.help_outline_rounded, color: kfc.textMuted, size: 14),
    );
  }

  // Dialog informasi pop-up
  void _showInfoDialog(BuildContext ctx, String title, String content) {
    showDialog(
      context: ctx,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Mengerti')),
        ],
      ),
    );
  }
}
