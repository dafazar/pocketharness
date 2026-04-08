// lib/features/settings/presentation/screens/ai_inference_params_screen.dart
// Screen dedicated untuk fine-tuning parameter inferensi AI ala PocketPal
// Fitur: 3 Tab (Parameter | Preset | Coba Langsung) + live generate test
// Sesi 8 — Final Polish KanMon GO (PocketPal Architecture)

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kanmongo/core/ai/llama_context.dart';
import 'package:kanmongo/core/ai/inference_params_provider.dart';
import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/data/services/llama_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODEL DATA: Preset Inferensi
// ─────────────────────────────────────────────────────────────────────────────

class _InferencePreset {
  final String id;
  final String nama;
  final String emoji;
  final String deskripsi;
  final InferenceConfig config;

  const _InferencePreset({
    required this.id,
    required this.nama,
    required this.emoji,
    required this.deskripsi,
    required this.config,
  });
}

final _presets = <_InferencePreset>[
  _InferencePreset(
    id: 'deterministik',
    nama: 'Deterministik',
    emoji: '🎯',
    deskripsi: 'Output konsisten & faktual',
    config: InferenceConfig.defaultConfig.copyWith(
      temperature: 0.1,
      topP: 0.9,
      topK: 20,
    ),
  ),
  _InferencePreset(
    id: 'seimbang',
    nama: 'Seimbang',
    emoji: '⚖️',
    deskripsi: 'Seimbang antara kreativitas & akurasi',
    config: InferenceConfig.defaultConfig,
  ),
  _InferencePreset(
    id: 'kreatif',
    nama: 'Kreatif',
    emoji: '🎨',
    deskripsi: 'Output imaginatif & beragam',
    config: InferenceConfig.defaultConfig.copyWith(
      temperature: 1.2,
      topP: 0.95,
      topK: 80,
    ),
  ),
  _InferencePreset(
    id: 'kode',
    nama: 'Kode',
    emoji: '💻',
    deskripsi: 'Optimal untuk generate kode',
    config: InferenceConfig.defaultConfig.copyWith(
      temperature: 0.2,
      repeatPenalty: 1.05,
    ),
  ),
  _InferencePreset(
    id: 'bahasa',
    nama: 'Bahasa',
    emoji: '🌐',
    deskripsi: 'Terjemahan & penulisan natural',
    config: InferenceConfig.defaultConfig.copyWith(
      temperature: 0.8,
      minP: 0.03,
    ),
  ),
  _InferencePreset(
    id: 'hemat',
    nama: 'Hemat Token',
    emoji: '💡',
    deskripsi: 'Respons pendek & padat',
    config: InferenceConfig.defaultConfig.copyWith(
      maxNewTokens: 256,
    ),
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class AiInferenceParamsScreen extends ConsumerStatefulWidget {
  const AiInferenceParamsScreen({super.key});

  @override
  ConsumerState<AiInferenceParamsScreen> createState() =>
      _AiInferenceParamsScreenState();
}

class _AiInferenceParamsScreenState
    extends ConsumerState<AiInferenceParamsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // ── State Tab 3 (Coba Langsung) ──────────────────────────────────────────
  final _testPromptCtrl = TextEditingController();
  final _outputScrollCtrl = ScrollController();
  String _testOutput = '';
  bool _isGenerating = false;
  StreamSubscription<String>? _genSub;
  int _totalToken = 0;
  double _tokenPerDetik = 0.0;
  DateTime? _genStart;
  Duration _genDuration = Duration.zero;
  Timer? _durationTimer;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _testPromptCtrl.dispose();
    _outputScrollCtrl.dispose();
    _genSub?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }

  // ── Simpan & Kembali ─────────────────────────────────────────────────────

  void _simpanDanKembali() {
    Navigator.of(context).pop();
  }

  // ── Generate Test ─────────────────────────────────────────────────────────

  Future<void> _mulaiGenerate() async {
    final prompt = _testPromptCtrl.text.trim();
    if (prompt.isEmpty) return;
    if (!LlamaService.instance.isModelLoaded) {
      _tampilSnackbar('Model belum dimuat. Muat model terlebih dahulu.');
      return;
    }

    final config = ref.read(inferenceConfigProvider);

    setState(() {
      _testOutput = '';
      _isGenerating = true;
      _totalToken = 0;
      _tokenPerDetik = 0.0;
      _genStart = DateTime.now();
      _genDuration = Duration.zero;
    });

    // Timer untuk update durasi tiap detik
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_genStart != null && mounted) {
        setState(() {
          _genDuration = DateTime.now().difference(_genStart!);
        });
      }
    });

    _genSub = LlamaService.instance.generateStream(
      messages: [ChatMessage.user(prompt)],
      config: config,
    ).listen(
      (token) {
        if (!mounted) return;
        setState(() {
          _testOutput += token;
          _totalToken++;
          final elapsed =
              DateTime.now().difference(_genStart!).inMilliseconds / 1000.0;
          _tokenPerDetik =
              elapsed > 0 ? (_totalToken / elapsed) : 0.0;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_outputScrollCtrl.hasClients) {
            _outputScrollCtrl.animateTo(
              _outputScrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          }
        });
      },
      onDone: () {
        if (!mounted) return;
        _durationTimer?.cancel();
        setState(() {
          _isGenerating = false;
          if (_genStart != null) {
            _genDuration = DateTime.now().difference(_genStart!);
          }
        });
      },
      onError: (e) {
        if (!mounted) return;
        _durationTimer?.cancel();
        setState(() {
          _isGenerating = false;
          _testOutput += '\n\n[Error: $e]';
        });
      },
    );
  }

  Future<void> _hentikanGenerate() async {
    await LlamaService.instance.stopGeneration();
    _durationTimer?.cancel();
    await _genSub?.cancel();
    if (mounted) setState(() => _isGenerating = false);
  }

  void _tampilSnackbar(String pesan) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(pesan), duration: const Duration(seconds: 2)),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.card,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: c.text, size: 20),
          onPressed: _simpanDanKembali,
        ),
        title: Text(
          'Parameter Inferensi AI',
          style: TextStyle(
              color: c.text, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: c.accent,
          unselectedLabelColor: c.textMuted,
          indicatorColor: c.accent,
          tabs: const [
            Tab(text: 'Parameter'),
            Tab(text: 'Preset'),
            Tab(text: 'Coba Langsung'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _TabParameter(c: c),
          _TabPreset(c: c, cs: cs),
          _buildTabCobaLangsung(c, cs),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _simpanDanKembali,
        backgroundColor: c.accent,
        icon: const Icon(Icons.check_rounded, color: Colors.white),
        label: const Text('Simpan & Kembali',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 3: Coba Langsung
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTabCobaLangsung(KmColors c, ColorScheme cs) {
    final durStr = _genDuration.inSeconds > 0
        ? '${_genDuration.inSeconds}d ${_genDuration.inMilliseconds % 1000}ms'
        : '-';

    return Column(
      children: [
        // ── Input prompt ────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          color: c.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Test Prompt',
                  style: TextStyle(
                      color: c.textSub,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                ),
                child: TextField(
                  controller: _testPromptCtrl,
                  style: TextStyle(color: c.text, fontSize: 14),
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Tulis prompt untuk diuji dengan settings saat ini...',
                    hintStyle:
                        TextStyle(color: c.textMuted, fontSize: 14),
                    contentPadding: const EdgeInsets.all(12),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        _isGenerating ? null : _mulaiGenerate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('Generate',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                if (_isGenerating) ...[
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _hentikanGenerate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.card,
                      foregroundColor: c.wrong,
                      side: BorderSide(color: c.wrong),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                    ),
                    icon: const Icon(Icons.stop_rounded, size: 20),
                    label: const Text('Hentikan',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ]),
            ],
          ),
        ),

        // ── Statistik ────────────────────────────────────────────────────
        if (_genStart != null)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: c.surface,
            child: Row(children: [
              _statChip(c, '${_tokenPerDetik.toStringAsFixed(1)} tok/s', Icons.speed_rounded),
              const SizedBox(width: 8),
              _statChip(c, '$_totalToken token', Icons.tag_rounded),
              const SizedBox(width: 8),
              _statChip(c, durStr, Icons.timer_outlined),
              if (_isGenerating) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.accent,
                  ),
                ),
              ],
            ]),
          ),

        // ── Output ───────────────────────────────────────────────────────
        Expanded(
          child: _testOutput.isEmpty
              ? Center(
                  child: Text(
                    _isGenerating
                        ? 'Menghasilkan...'
                        : 'Output akan muncul di sini',
                    style: TextStyle(color: c.textMuted, fontSize: 14),
                  ),
                )
              : Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border),
                  ),
                  child: SingleChildScrollView(
                    controller: _outputScrollCtrl,
                    child: SelectableText(
                      _testOutput,
                      style: TextStyle(
                          color: c.text, fontSize: 14, height: 1.55),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _statChip(KmColors c, String label, IconData icon) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: c.accent),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: c.text,
                fontSize: 11,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1: Parameter
// ─────────────────────────────────────────────────────────────────────────────

class _TabParameter extends ConsumerWidget {
  const _TabParameter({required this.c});

  final KmColors c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(inferenceConfigProvider);
    final notifier = ref.read(inferenceConfigProvider.notifier);

    return SingleChildScrollView(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Kreativitas & Sampling ──────────────────────────────────────
          _sectionLabel(c, '🎲 Kreativitas & Sampling'),
          const SizedBox(height: 12),

          _ParamSliderRow(
            c: c,
            label: 'Temperature',
            emoji: '🌡️',
            tooltip:
                'Semakin tinggi = output lebih beragam & kreatif. Semakin rendah = deterministik.',
            value: cfg.temperature,
            min: 0.0,
            max: 2.0,
            decimals: 2,
            onChanged: notifier.updateTemperature,
            onReset: () => notifier.updateTemperature(
                InferenceConfig.defaultConfig.temperature),
          ),
          const SizedBox(height: 16),

          _ParamSliderRow(
            c: c,
            label: 'Top-P',
            emoji: '📊',
            tooltip:
                'Nucleus sampling. Hanya token dengan probabilitas kumulatif ≤ nilai ini yang dipilih.',
            value: cfg.topP,
            min: 0.0,
            max: 1.0,
            decimals: 2,
            onChanged: notifier.updateTopP,
            onReset: () =>
                notifier.updateTopP(InferenceConfig.defaultConfig.topP),
          ),
          const SizedBox(height: 16),

          _ParamSliderRow(
            c: c,
            label: 'Top-K',
            emoji: '🔢',
            tooltip:
                'Hanya K token teratas yang dipertimbangkan saat sampling.',
            value: cfg.topK.toDouble(),
            min: 1,
            max: 200,
            decimals: 0,
            onChanged: (v) => notifier.updateTopK(v.round()),
            onReset: () =>
                notifier.updateTopK(InferenceConfig.defaultConfig.topK),
          ),
          const SizedBox(height: 16),

          _ParamSliderRow(
            c: c,
            label: 'Min-P',
            emoji: '📉',
            tooltip:
                'Ambang batas minimum probabilitas relatif terhadap token paling mungkin.',
            value: cfg.minP,
            min: 0.0,
            max: 0.5,
            decimals: 2,
            onChanged: notifier.updateMinP,
            onReset: () =>
                notifier.updateMinP(InferenceConfig.defaultConfig.minP),
          ),

          const SizedBox(height: 24),

          // ── Kontrol Output ────────────────────────────────────────────
          _sectionLabel(c, '📦 Kontrol Output'),
          const SizedBox(height: 12),

          _ParamSliderRow(
            c: c,
            label: 'Max Tokens',
            emoji: '📏',
            tooltip: 'Jumlah maksimum token yang dihasilkan per respons.',
            value: cfg.maxNewTokens.toDouble(),
            min: 64,
            max: 8192,
            decimals: 0,
            onChanged: (v) => notifier.updateMaxTokens(v.round()),
            onReset: () => notifier.updateMaxTokens(
                InferenceConfig.defaultConfig.maxNewTokens),
          ),
          const SizedBox(height: 16),

          _ParamSliderRow(
            c: c,
            label: 'Repeat Penalty',
            emoji: '🔄',
            tooltip:
                'Penalti untuk token yang sudah muncul. > 1.0 mengurangi pengulangan.',
            value: cfg.repeatPenalty,
            min: 1.0,
            max: 2.0,
            decimals: 2,
            onChanged: notifier.updateRepeatPenalty,
            onReset: () => notifier.updateRepeatPenalty(
                InferenceConfig.defaultConfig.repeatPenalty),
          ),

          const SizedBox(height: 24),

          // ── Reset Semua ───────────────────────────────────────────────
          Center(
            child: TextButton.icon(
              onPressed: notifier.resetToDefaults,
              icon: Icon(Icons.restart_alt_rounded,
                  color: c.textMuted, size: 18),
              label: Text('Reset semua ke default',
                  style: TextStyle(color: c.textMuted, fontSize: 13)),
            ),
          ),

          const SizedBox(height: 80), // padding bawah untuk FAB
        ],
      ),
    );
  }

  Widget _sectionLabel(KmColors c, String label) {
    return Text(
      label,
      style: TextStyle(
          color: c.textSub,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2: Preset
// ─────────────────────────────────────────────────────────────────────────────

class _TabPreset extends ConsumerWidget {
  const _TabPreset({required this.c, required this.cs});

  final KmColors c;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(inferenceConfigProvider);
    final notifier = ref.read(inferenceConfigProvider.notifier);

    // Tentukan preset aktif berdasarkan kesamaan konfigurasi kunci
    String? activePresetId = _cariPresetAktif(cfg);

    return SingleChildScrollView(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pilih preset untuk menerapkan konfigurasi siap pakai.',
            style: TextStyle(color: c.textSub, fontSize: 13),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _presets.length,
            itemBuilder: (context, i) {
              final preset = _presets[i];
              final isActive = preset.id == activePresetId;
              return _PresetCard(
                c: c,
                preset: preset,
                isActive: isActive,
                onTap: () {
                  notifier.updateTemperature(
                      preset.config.temperature);
                  notifier.updateTopP(preset.config.topP);
                  notifier.updateTopK(preset.config.topK);
                  notifier.updateMinP(preset.config.minP);
                  notifier.updateRepeatPenalty(
                      preset.config.repeatPenalty);
                  notifier.updateMaxTokens(
                      preset.config.maxNewTokens);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Preset "${preset.nama}" diterapkan'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  String? _cariPresetAktif(InferenceConfig cfg) {
    for (final p in _presets) {
      if ((p.config.temperature - cfg.temperature).abs() < 0.01 &&
          (p.config.topP - cfg.topP).abs() < 0.01 &&
          p.config.topK == cfg.topK &&
          (p.config.minP - cfg.minP).abs() < 0.01 &&
          (p.config.repeatPenalty - cfg.repeatPenalty).abs() < 0.01 &&
          p.config.maxNewTokens == cfg.maxNewTokens) {
        return p.id;
      }
    }
    return null;
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.c,
    required this.preset,
    required this.isActive,
    required this.onTap,
  });

  final KmColors c;
  final _InferencePreset preset;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isActive
              ? c.accent.withValues(alpha: 0.08)
              : c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? c.accent : c.border,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Text(preset.emoji,
                  style: const TextStyle(fontSize: 22)),
              const Spacer(),
              if (isActive)
                Icon(Icons.check_circle_rounded,
                    size: 16, color: c.accent),
            ]),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preset.nama,
                  style: TextStyle(
                      color: c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  preset.deskripsi,
                  style:
                      TextStyle(color: c.textMuted, fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET PEMBANTU: Slider baris dengan tombol reset
// ─────────────────────────────────────────────────────────────────────────────

class _ParamSliderRow extends StatelessWidget {
  const _ParamSliderRow({
    required this.c,
    required this.label,
    required this.emoji,
    required this.tooltip,
    required this.value,
    required this.min,
    required this.max,
    required this.decimals,
    required this.onChanged,
    required this.onReset,
  });

  final KmColors c;
  final String label;
  final String emoji;
  final String tooltip;
  final double value;
  final double min;
  final double max;
  final int decimals;
  final ValueChanged<double> onChanged;
  final VoidCallback onReset;

  String get _displayValue => decimals == 0
      ? value.round().toString()
      : value.toStringAsFixed(decimals);

  int get _divisions {
    final range = max - min;
    if (decimals == 0) return range.round().clamp(1, 1000);
    return (range * pow(10, decimals)).round().clamp(1, 1000);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: c.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 4),
          // Tooltip info
          GestureDetector(
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: c.card,
                  title: Text('$emoji $label',
                      style: TextStyle(color: c.text, fontSize: 15)),
                  content: Text(tooltip,
                      style:
                          TextStyle(color: c.textSub, fontSize: 13)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('OK',
                            style: TextStyle(color: c.accent))),
                  ],
                ),
              );
            },
            child: Icon(Icons.info_outline_rounded,
                size: 14, color: c.textMuted),
          ),
          const Spacer(),
          // Nilai (bisa di-tap untuk edit langsung)
          _TapToEditChip(
            c: c,
            value: _displayValue,
            label: label,
            min: min,
            max: max,
            decimals: decimals,
            onSubmit: onChanged,
          ),
          const SizedBox(width: 4),
          // Tombol reset
          GestureDetector(
            onTap: onReset,
            child: Icon(Icons.close_rounded,
                size: 14, color: c.textMuted),
          ),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: c.accent,
            thumbColor: c.accent,
            overlayColor: c.accent.withValues(alpha: 0.12),
            inactiveTrackColor: c.border,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: _divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET PEMBANTU: Chip nilai yang bisa di-tap untuk edit langsung
// ─────────────────────────────────────────────────────────────────────────────

class _TapToEditChip extends StatelessWidget {
  const _TapToEditChip({
    required this.c,
    required this.value,
    required this.label,
    required this.min,
    required this.max,
    required this.decimals,
    required this.onSubmit,
  });

  final KmColors c;
  final String value;
  final String label;
  final double min;
  final double max;
  final int decimals;
  final ValueChanged<double> onSubmit;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showEditDialog(context),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.border),
        ),
        child: Text(
          value,
          style: TextStyle(
              color: c.accent,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final ctrl = TextEditingController(text: value);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.card,
        title: Text('Edit $label',
            style: TextStyle(color: c.text, fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(color: c.text),
          decoration: InputDecoration(
            hintText: 'Min: $min — Max: $max',
            hintStyle: TextStyle(color: c.textMuted),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: c.border)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: c.accent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                Text('Batal', style: TextStyle(color: c.textMuted)),
          ),
          TextButton(
            onPressed: () {
              final parsed = double.tryParse(ctrl.text);
              if (parsed != null) {
                onSubmit(parsed.clamp(min, max));
              }
              Navigator.pop(context);
            },
            child: Text('OK', style: TextStyle(color: c.accent)),
          ),
        ],
      ),
    );
  }
}
