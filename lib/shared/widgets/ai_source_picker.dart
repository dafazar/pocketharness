// lib/shared/widgets/ai_source_picker.dart
// KanMon GO — AI Source Picker with enable/disable toggles and settings dialogs
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/ai/ai_source_settings_service.dart';
import '../../data/models/ai_source_config.dart';
import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/data/services/ai/puter_ai_service.dart'
    show kPuterModels, PuterAiModel, kPuterProviders;
import 'package:kanmongo/data/services/content/bulk_api_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kanmongo/data/services/ai/offline_ai_service.dart';
import 'package:kanmongo/data/services/content/model_manager_service.dart';
import 'package:kanmongo/core/ai/llama_context.dart';
import 'package:kanmongo/data/services/ai/llama_service.dart';
import 'package:kanmongo/data/models/chat_models.dart' show AiSourceChoice;
import 'package:kanmongo/data/services/ai/ai_service.dart' show AiMode;
import 'package:kanmongo/features/chat/providers/chat_session_provider.dart'
    show aiSourceProvider;

// ── Re-export untuk convenience ───────────────────────────────────────────────
export 'package:kanmongo/features/chat/providers/chat_session_provider.dart'
    show aiSourceProvider;
export 'package:kanmongo/data/models/chat_models.dart' show AiSourceChoice;
export 'package:kanmongo/data/services/ai/ai_service.dart' show AiMode;


class AiSourcePicker extends StatefulWidget {
  const AiSourcePicker({Key? key}) : super(key: key);

  @override
  State<AiSourcePicker> createState() => _AiSourcePickerState();
}

class _AiSourcePickerState extends State<AiSourcePicker>
    with SingleTickerProviderStateMixin {
  late AiSourceSettingsService _svc;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _svc = AiSourceSettingsService.instance;
    final activeKey = _svc.activeSource;
    final initialIndex = activeKey == 'online'
        ? 0
        : activeKey == 'bulk'
            ? 1
            : 2;
    _tabController = TabController(length: 3, vsync: this, initialIndex: initialIndex);
    // Pull state terbaru dari masing-masing service agar picker selalu sinkron
    _refreshFromServices();
  }

  Future<void> _refreshFromServices() async {
    await _svc.pullOnlineFromService();
    await _svc.pullBulkFromService();
    await _svc.pullOfflineFromService();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _updateOnlineToggle(bool value) async {
    await _svc.setOnlineConfig(_svc.online.copyWith(enabled: value));
    if (value) await _svc.setActiveSource('online');
    setState(() {});
  }

  Future<void> _updateBulkToggle(bool value) async {
    await _svc.setBulkConfig(_svc.bulk.copyWith(enabled: value));
    if (value) await _svc.setActiveSource('bulk');
    setState(() {});
  }

  Future<void> _updateOfflineToggle(bool value) async {
    await _svc.setOfflineConfig(_svc.offline.copyWith(enabled: value));
    if (value) await _svc.setActiveSource('offline');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Pilih Sumber AI',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Online'),
              Tab(text: 'Bulk'),
              Tab(text: 'Offline'),
            ],
          ),
          const Divider(height: 1),
          SizedBox(
            height: 320,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOnlineSection(),
                _buildBulkSection(),
                _buildOfflineSection(),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOnlineSection() {
    final cfg = _svc.online;
    final isDisabled = !cfg.enabled;
    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(children: [
                    Icon(Icons.cloud_rounded, color: Colors.blue, size: 24),
                    SizedBox(width: 12),
                    Text('Online AI', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ]),
                  Row(children: [
                    Switch(value: cfg.enabled, onChanged: _updateOnlineToggle, activeColor: Colors.blue),
                    IconButton(
                      icon: const Icon(Icons.settings_rounded),
                      onPressed: isDisabled ? null : () => _showOnlineSettings(context),
                    ),
                  ]),
                ],
              ),
              const SizedBox(height: 12),
              _infoRow('Model', cfg.selectedModel),
              _infoRow('Temperature', cfg.temperature.toStringAsFixed(2)),
              _infoRow('Max Tokens', '${cfg.maxTokens}'),
              _infoRow('Persona', cfg.personaName),
              _infoRow('Stream', cfg.streamEnabled ? 'Ya' : 'Tidak'),
              _infoRow('TTS', cfg.ttsEnabled ? 'Ya' : 'Tidak'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBulkSection() {
    final cfg = _svc.bulk;
    final isDisabled = !cfg.enabled;
    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(children: [
                    Icon(Icons.vpn_key_rounded, color: Colors.orange, size: 24),
                    SizedBox(width: 12),
                    Text('Bulk API', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ]),
                  Row(children: [
                    Switch(value: cfg.enabled, onChanged: _updateBulkToggle, activeColor: Colors.orange),
                    IconButton(
                      icon: const Icon(Icons.settings_rounded),
                      onPressed: isDisabled ? null : () => _showBulkSettings(context),
                    ),
                  ]),
                ],
              ),
              const SizedBox(height: 12),
              _infoRow('Temperature', cfg.temperature.toStringAsFixed(2)),
              _infoRow('Max Tokens', '${cfg.maxTokens}'),
              _infoRow('Persona', cfg.personaName),
              _infoRow('Max Retries', '${cfg.maxRetries}'),
              _infoRow('Stream', cfg.streamEnabled ? 'Ya' : 'Tidak'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfflineSection() {
    final cfg = _svc.offline;
    final isDisabled = !cfg.enabled;
    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(children: [
                    Icon(Icons.phone_android_rounded, color: Colors.green, size: 24),
                    SizedBox(width: 12),
                    Text('Offline AI', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ]),
                  Row(children: [
                    Switch(value: cfg.enabled, onChanged: _updateOfflineToggle, activeColor: Colors.green),
                    IconButton(
                      icon: const Icon(Icons.settings_rounded),
                      onPressed: isDisabled ? null : () => _showOfflineSettings(context),
                    ),
                  ]),
                ],
              ),
              const SizedBox(height: 12),
              _infoRow('Temperature', cfg.temperature.toStringAsFixed(2)),
              _infoRow('Max Tokens', '${cfg.maxNewTokens}'),
              _infoRow('Context Size', '${cfg.contextSize}'),
              _infoRow('GPU Layers', '${cfg.gpuLayers}'),
              _infoRow('Persona', cfg.personaName),
              _infoRow('Stream', cfg.streamEnabled ? 'Ya' : 'Tidak'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(
            width: 120,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
        ]),
      );

  Future<void> _showOnlineSettings(BuildContext context) async {
    await showDialog(context: context, builder: (ctx) => _OnlineSettingsDialog(svc: _svc));
    await _svc.pullOnlineFromService();
    if (mounted) setState(() {});
  }

  Future<void> _showBulkSettings(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BulkSettingsDialog(svc: _svc),
    );
    await _svc.pullBulkFromService();
    if (mounted) setState(() {});
  }

  Future<void> _showOfflineSettings(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OfflineSettingsDialog(svc: _svc),
    );
    await _svc.pullOfflineFromService();
    if (mounted) setState(() {});
  }
}

// ── Stub Dialogs (Bulk & Offline remain stubs until Sessions 3 & 4) ───────────

// =============================================================================
// ONLINE AI SETTINGS POPUP — Session 2
// Full 6-tab settings for Puter.js / Online AI
// =============================================================================

class _OnlineSettingsDialog extends StatefulWidget {
  final AiSourceSettingsService svc;
  const _OnlineSettingsDialog({required this.svc});

  @override
  State<_OnlineSettingsDialog> createState() => _OnlineSettingsDialogState();
}

class _OnlineSettingsDialogState extends State<_OnlineSettingsDialog>
    with SingleTickerProviderStateMixin {

  late TabController _tab;
  late OnlineAiConfig _cfg;

  late TextEditingController _apiKeyCtrl;
  late TextEditingController _personaNameCtrl;
  late TextEditingController _systemPromptCtrl;

  bool _apiKeyVisible = false;
  String _modelSearch = '';
  String _modelProviderFilter = 'Semua';

  static const _ttsVoices = [
    ('id-ID-GadisNeural',  '🇮🇩 Gadis (ID Female)'),
    ('id-ID-ArdiNeural',   '🇮🇩 Ardi (ID Male)'),
    ('ja-JP-NanamiNeural', '🇯🇵 Nanami (JP Female)'),
    ('ja-JP-KeitaNeural',  '🇯🇵 Keita (JP Male)'),
    ('en-US-JennyNeural',  '🇺🇸 Jenny (EN Female)'),
    ('en-US-GuyNeural',    '🇺🇸 Guy (EN Male)'),
    ('en-GB-SoniaNeural',  '🇬🇧 Sonia (EN-GB Female)'),
  ];

  static const _languages = [
    ('auto', '🌐 Auto Detect'),
    ('id',   '🇮🇩 Bahasa Indonesia'),
    ('en',   '🇺🇸 English'),
    ('ja',   '🇯🇵 Japanese (日本語)'),
  ];

  static const _searchEngines = [
    ('ddg',    '🦆 DuckDuckGo'),
    ('google', '🔍 Google'),
    ('bing',   '🔵 Bing'),
  ];

  static const _personaPresets = [
    ('Sensei Bahasa Jepang', '🇯🇵',
      'Kamu adalah Sensei bahasa Jepang yang sabar dan berpengalaman. '
      'Jelaskan konsep dengan contoh kalimat sederhana. Koreksi kesalahan '
      'dengan ramah. Jawab dalam bahasa Indonesia kecuali diminta lain.'),
    ('KanMon Assistant', '🤖',
      'Kamu adalah asisten AI KanMon yang cerdas dan ramah. '
      'Bantu user dengan apapun yang mereka butuhkan.'),
    ('Translator', '🌐',
      'Kamu adalah penerjemah profesional. Terjemahkan teks yang diberikan '
      'ke bahasa yang diminta. Pertahankan nuansa dan gaya bahasa asli.'),
    ('Coder Helper', '💻',
      'Kamu adalah programmer berpengalaman. Bantu debug, review kode, '
      'dan jelaskan konsep pemrograman dengan contoh nyata.'),
    ('Tutor JLPT', '📚',
      'Kamu adalah tutor JLPT yang fokus mempersiapkan siswa untuk ujian. '
      'Berikan soal latihan, penjelasan tata bahasa, dan tips belajar kanji.'),
  ];

  @override
  void initState() {
    super.initState();
    _cfg = widget.svc.online;
    _tab = TabController(length: 6, vsync: this);
    _apiKeyCtrl       = TextEditingController(text: _cfg.apiKey);
    _personaNameCtrl  = TextEditingController(text: _cfg.personaName);
    _systemPromptCtrl = TextEditingController(text: _cfg.systemPrompt);
  }

  @override
  void dispose() {
    _tab.dispose();
    _apiKeyCtrl.dispose();
    _personaNameCtrl.dispose();
    _systemPromptCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(OnlineAiConfig updated) async {
    _cfg = updated;
    await widget.svc.saveOnline(updated);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final kfc = KmColors.of(context);

    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: kfc.bg,
        appBar: AppBar(
          backgroundColor: kfc.surface,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.close_rounded, color: kfc.text),
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.cloud_rounded, color: Colors.blue, size: 18),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Online AI Settings',
                  style: TextStyle(color: kfc.text, fontSize: 15, fontWeight: FontWeight.w700)),
              Text('Puter.js Configuration',
                  style: TextStyle(color: kfc.textMuted, fontSize: 11)),
            ]),
          ]),
          actions: [
            TextButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Reset ke Default?'),
                    content: const Text(
                        'Semua pengaturan Online AI akan dikembalikan ke nilai default.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Batal')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Reset',
                              style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true) {
                  final def = OnlineAiConfig();
                  await _save(def);
                  _apiKeyCtrl.text       = def.apiKey;
                  _personaNameCtrl.text  = def.personaName;
                  _systemPromptCtrl.text = def.systemPrompt;
                }
              },
              icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.red),
              label: const Text('Reset', style: TextStyle(color: Colors.red, fontSize: 12)),
            ),
          ],
          bottom: TabBar(
            controller: _tab,
            labelColor: Colors.blue,
            unselectedLabelColor: kfc.textMuted,
            indicatorColor: Colors.blue,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(icon: Icon(Icons.cloud_rounded,     size: 16), text: 'Koneksi'),
              Tab(icon: Icon(Icons.tune_rounded,      size: 16), text: 'Parameter'),
              Tab(icon: Icon(Icons.face_rounded,      size: 16), text: 'Persona'),
              Tab(icon: Icon(Icons.translate_rounded, size: 16), text: 'Bahasa'),
              Tab(icon: Icon(Icons.palette_rounded,   size: 16), text: 'Tampilan'),
              Tab(icon: Icon(Icons.settings_rounded,  size: 16), text: 'Lanjutan'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tab,
          children: [
            _tabKoneksi(kfc),
            _tabParameter(kfc),
            _tabPersona(kfc),
            _tabBahasa(kfc),
            _tabTampilan(kfc),
            _tabLanjutan(kfc),
          ],
        ),
      ),
    );
  }

  // ── TAB 1: KONEKSI ─────────────────────────────────────────────────────────
  Widget _tabKoneksi(KmColors kfc) {
    final filteredModels = kPuterModels.where((m) {
      final q = _modelSearch.toLowerCase();
      final matchSearch = q.isEmpty ||
          m.name.toLowerCase().contains(q) ||
          m.provider.toLowerCase().contains(q);
      final matchProvider = _modelProviderFilter == 'Semua' ||
          m.provider == _modelProviderFilter;
      return matchSearch && matchProvider;
    }).toList();

    return ListView(padding: const EdgeInsets.all(16), children: [
      _sectionHeader(kfc, '🔑 API Key Puter.js'),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'API Key diperlukan untuk menggunakan Puter.js. '
            'Daftar gratis di puter.com untuk mendapatkan key.',
            style: TextStyle(color: kfc.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _apiKeyCtrl,
            obscureText: !_apiKeyVisible,
            style: TextStyle(color: kfc.text, fontSize: 13, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: 'Masukkan Puter.js API Key...',
              hintStyle: TextStyle(color: kfc.textMuted, fontSize: 12),
              filled: true,
              fillColor: kfc.card,
              prefixIcon: const Icon(Icons.key_rounded, color: Colors.blue, size: 18),
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: Icon(
                    _apiKeyVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: kfc.textMuted, size: 18,
                  ),
                  onPressed: () => setState(() => _apiKeyVisible = !_apiKeyVisible),
                ),
                IconButton(
                  icon: const Icon(Icons.save_rounded, color: Colors.blue, size: 18),
                  onPressed: () => _save(_cfg.copyWith(apiKey: _apiKeyCtrl.text.trim())),
                  tooltip: 'Simpan API Key',
                ),
              ]),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: kfc.borderSoft)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: kfc.borderSoft)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.blue, width: 1.5)),
            ),
            onSubmitted: (v) => _save(_cfg.copyWith(apiKey: v.trim())),
          ),
          if (_cfg.apiKey.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.check_circle_rounded, color: Colors.green, size: 14),
              const SizedBox(width: 6),
              Text('API Key tersimpan',
                  style: TextStyle(color: Colors.green.shade400, fontSize: 12)),
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 20),
      _sectionHeader(kfc, '⚙️ Koneksi'),
      const SizedBox(height: 8),
      _settingsCard(kfc, children: [
        _sliderRow(kfc,
          label: 'Timeout', value: _cfg.timeoutSeconds.toDouble(),
          min: 5, max: 120, divisions: 23, unit: 's', decimals: 0,
          onChanged: (v) => _save(_cfg.copyWith(timeoutSeconds: v.toInt())),
        ),
        _divider(kfc),
        _switchRow(kfc,
          label: 'Mode Streaming',
          subtitle: 'Tampilkan respons token per token (real-time)',
          value: _cfg.streamEnabled,
          onChanged: (v) => _save(_cfg.copyWith(streamEnabled: v)),
        ),
      ]),
      const SizedBox(height: 20),
      _sectionHeader(kfc, '🤖 Pilih Model'),
      const SizedBox(height: 8),
      TextField(
        onChanged: (v) => setState(() => _modelSearch = v),
        style: TextStyle(color: kfc.text, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Cari model...',
          hintStyle: TextStyle(color: kfc.textMuted, fontSize: 12),
          prefixIcon: Icon(Icons.search_rounded, color: kfc.textMuted, size: 18),
          filled: true, fillColor: kfc.card,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: kfc.borderSoft)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: kfc.borderSoft)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.blue, width: 1.5)),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final p in ['Semua', ...kPuterProviders])
              GestureDetector(
                onTap: () => setState(() => _modelProviderFilter = p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _modelProviderFilter == p ? Colors.blue : kfc.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _modelProviderFilter == p ? Colors.blue : kfc.borderSoft),
                  ),
                  child: Text(p, style: TextStyle(
                    color: _modelProviderFilter == p ? Colors.white : kfc.textMuted,
                    fontSize: 11,
                    fontWeight: _modelProviderFilter == p ? FontWeight.w700 : FontWeight.normal,
                  )),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      for (final model in filteredModels)
        _ModelPickerTile(
          kfc: kfc, model: model,
          isSelected: _cfg.selectedModel == model.id,
          onTap: () => _save(_cfg.copyWith(selectedModel: model.id)),
        ),
      if (filteredModels.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text('Tidak ada model ditemukan',
                style: TextStyle(color: kfc.textMuted)),
          ),
        ),
      const SizedBox(height: 24),
    ]);
  }

  // ── TAB 2: PARAMETER ───────────────────────────────────────────────────────
  Widget _tabParameter(KmColors kfc) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _infoBox(kfc,
          '💡 Parameter ini memengaruhi cara AI menghasilkan respons. '
          'Nilai default sudah optimal untuk kebanyakan kasus.',
          Colors.blue),
      const SizedBox(height: 16),
      _sectionHeader(kfc, '🌡️ Sampling'),
      const SizedBox(height: 8),
      _settingsCard(kfc, children: [
        _sliderRow(kfc,
          label: 'Temperature',
          subtitle: 'Kreativitas respons (0 = deterministik, 2 = sangat kreatif)',
          value: _cfg.temperature, min: 0.0, max: 2.0, divisions: 40,
          unit: '', decimals: 2,
          onChanged: (v) => _save(_cfg.copyWith(temperature: v)),
        ),
        _divider(kfc),
        _sliderRow(kfc,
          label: 'Top-P',
          subtitle: 'Nucleus sampling — 0.95 biasanya ideal',
          value: _cfg.topP, min: 0.0, max: 1.0, divisions: 20,
          unit: '', decimals: 2,
          onChanged: (v) => _save(_cfg.copyWith(topP: v)),
        ),
      ]),
      const SizedBox(height: 16),
      _sectionHeader(kfc, '📏 Token Limit'),
      const SizedBox(height: 8),
      _settingsCard(kfc, children: [
        _sliderRow(kfc,
          label: 'Max Tokens',
          subtitle: 'Panjang maksimum respons AI',
          value: _cfg.maxTokens.toDouble(), min: 128, max: 8192, divisions: 62,
          unit: ' tok', decimals: 0,
          onChanged: (v) => _save(_cfg.copyWith(maxTokens: v.toInt())),
        ),
      ]),
      const SizedBox(height: 16),
      _sectionHeader(kfc, '🔄 Repetition Control'),
      const SizedBox(height: 8),
      _settingsCard(kfc, children: [
        _sliderRow(kfc,
          label: 'Frequency Penalty',
          subtitle: 'Kurangi pengulangan kata yang sering muncul',
          value: _cfg.frequencyPenalty, min: -2.0, max: 2.0, divisions: 40,
          unit: '', decimals: 2,
          onChanged: (v) => _save(_cfg.copyWith(frequencyPenalty: v)),
        ),
        _divider(kfc),
        _sliderRow(kfc,
          label: 'Presence Penalty',
          subtitle: 'Dorong AI menggunakan topik baru',
          value: _cfg.presencePenalty, min: -2.0, max: 2.0, divisions: 40,
          unit: '', decimals: 2,
          onChanged: (v) => _save(_cfg.copyWith(presencePenalty: v)),
        ),
      ]),
      const SizedBox(height: 24),
    ]);
  }

  // ── TAB 3: PERSONA ─────────────────────────────────────────────────────────
  Widget _tabPersona(KmColors kfc) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _infoBox(kfc,
          '🎭 Persona menentukan "kepribadian" AI. System prompt dikirim '
          'sebelum setiap percakapan dan tidak terlihat oleh user.',
          Colors.purple),
      const SizedBox(height: 16),
      _sectionHeader(kfc, '👤 Nama Persona'),
      const SizedBox(height: 8),
      _settingsCard(kfc, children: [
        TextField(
          controller: _personaNameCtrl,
          style: TextStyle(color: kfc.text, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Nama AI, misal: KanMon Assistant',
            hintStyle: TextStyle(color: kfc.textMuted, fontSize: 12),
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.badge_rounded, color: Colors.purple, size: 18),
            suffixIcon: IconButton(
              icon: const Icon(Icons.save_rounded, color: Colors.purple, size: 18),
              onPressed: () =>
                  _save(_cfg.copyWith(personaName: _personaNameCtrl.text.trim())),
            ),
          ),
          onSubmitted: (v) => _save(_cfg.copyWith(personaName: v.trim())),
        ),
      ]),
      const SizedBox(height: 16),
      _sectionHeader(kfc, '⚡ Preset Persona'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final preset in _personaPresets)
          ActionChip(
            label: Text(preset.$1, style: const TextStyle(fontSize: 12)),
            avatar: Text(preset.$2, style: const TextStyle(fontSize: 14)),
            onPressed: () {
              _personaNameCtrl.text  = preset.$1;
              _systemPromptCtrl.text = preset.$3;
              _save(_cfg.copyWith(personaName: preset.$1, systemPrompt: preset.$3));
            },
          ),
      ]),
      const SizedBox(height: 16),
      _sectionHeader(kfc, '📝 System Prompt'),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: kfc.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kfc.borderSoft),
        ),
        child: TextField(
          controller: _systemPromptCtrl,
          maxLines: 10, minLines: 5,
          style: TextStyle(color: kfc.text, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Tulis system prompt di sini...\n\n'
                'Contoh:\nKamu adalah asisten belajar bahasa Jepang yang '
                'sabar dan ramah. Jawab dalam bahasa Indonesia. '
                'Gunakan contoh kalimat sederhana.',
            hintStyle: TextStyle(color: kfc.textMuted, fontSize: 12, height: 1.5),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.all(14),
          ),
          onChanged: (v) => _save(_cfg.copyWith(systemPrompt: v)),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: Text('${_systemPromptCtrl.text.length} karakter',
            style: TextStyle(color: kfc.textMuted, fontSize: 11)),
      ),
      const SizedBox(height: 24),
    ]);
  }

  // ── TAB 4: BAHASA ──────────────────────────────────────────────────────────
  Widget _tabBahasa(KmColors kfc) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _sectionHeader(kfc, '🌐 Bahasa Respons'),
      const SizedBox(height: 8),
      _settingsCard(kfc, children: [
        _switchRow(kfc,
          label: 'Auto Detect Bahasa',
          subtitle: 'AI menyesuaikan bahasa dengan input user',
          value: _cfg.autoDetectLanguage,
          onChanged: (v) => _save(_cfg.copyWith(autoDetectLanguage: v)),
        ),
        if (!_cfg.autoDetectLanguage) ...[
          _divider(kfc),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Bahasa Output',
                  style: TextStyle(color: kfc.text, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final lang in _languages)
                RadioListTile<String>(
                  value: lang.$1, groupValue: _cfg.language,
                  title: Text(lang.$2, style: TextStyle(color: kfc.text, fontSize: 13)),
                  activeColor: Colors.blue, dense: true, contentPadding: EdgeInsets.zero,
                  onChanged: (v) { if (v != null) _save(_cfg.copyWith(language: v)); },
                ),
            ]),
          ),
        ],
      ]),
      const SizedBox(height: 16),
      _sectionHeader(kfc, '🔊 Text-to-Speech (TTS)'),
      const SizedBox(height: 8),
      _settingsCard(kfc, children: [
        _switchRow(kfc,
          label: 'Auto-baca Respons',
          subtitle: 'Baca keras respons AI menggunakan Edge TTS',
          value: _cfg.ttsEnabled,
          onChanged: (v) => _save(_cfg.copyWith(ttsEnabled: v)),
        ),
        if (_cfg.ttsEnabled) ...[
          _divider(kfc),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Suara TTS',
                  style: TextStyle(color: kfc.text, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final voice in _ttsVoices)
                RadioListTile<String>(
                  value: voice.$1, groupValue: _cfg.ttsVoice,
                  title: Text(voice.$2, style: TextStyle(color: kfc.text, fontSize: 13)),
                  activeColor: Colors.blue, dense: true, contentPadding: EdgeInsets.zero,
                  onChanged: (v) { if (v != null) _save(_cfg.copyWith(ttsVoice: v)); },
                ),
            ]),
          ),
        ],
      ]),
      const SizedBox(height: 24),
    ]);
  }

  // ── TAB 5: TAMPILAN ────────────────────────────────────────────────────────
  Widget _tabTampilan(KmColors kfc) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _sectionHeader(kfc, '🎨 Rendering Teks'),
      const SizedBox(height: 8),
      _settingsCard(kfc, children: [
        _switchRow(kfc,
          label: 'Render Markdown',
          subtitle: 'Tampilkan **bold**, *italic*, header, dll',
          value: _cfg.markdownEnabled,
          onChanged: (v) => _save(_cfg.copyWith(markdownEnabled: v)),
        ),
        _divider(kfc),
        _switchRow(kfc,
          label: 'Syntax Highlight Kode',
          subtitle: 'Warnai kode program otomatis',
          value: _cfg.codeHighlightEnabled,
          onChanged: (v) => _save(_cfg.copyWith(codeHighlightEnabled: v)),
        ),
      ]),
      const SizedBox(height: 16),
      _sectionHeader(kfc, '👁️ Preview'),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kfc.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kfc.borderSoft),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_cfg.markdownEnabled) ...[
            Text('Markdown aktif:', style: TextStyle(color: kfc.textMuted, fontSize: 11)),
            const SizedBox(height: 6),
            RichText(text: TextSpan(children: [
              TextSpan(text: 'Teks biasa, ', style: TextStyle(color: kfc.text, fontSize: 13)),
              TextSpan(text: 'tebal',
                  style: TextStyle(color: kfc.text, fontSize: 13, fontWeight: FontWeight.bold)),
              TextSpan(text: ', dan ', style: TextStyle(color: kfc.text, fontSize: 13)),
              TextSpan(text: 'miring',
                  style: TextStyle(color: kfc.text, fontSize: 13, fontStyle: FontStyle.italic)),
            ])),
          ] else
            Text('Markdown nonaktif — teks tampil apa adanya.',
                style: TextStyle(color: kfc.textMuted, fontSize: 13)),
          const SizedBox(height: 10),
          if (_cfg.codeHighlightEnabled)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('print("Hello, 世界")',
                  style: TextStyle(
                      color: Color(0xFF89B4FA), fontSize: 12, fontFamily: 'monospace')),
            )
          else
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kfc.inputFill, borderRadius: BorderRadius.circular(8)),
              child: Text('print("Hello, 世界")',
                  style: TextStyle(color: kfc.text, fontSize: 12, fontFamily: 'monospace')),
            ),
        ]),
      ),
      const SizedBox(height: 24),
    ]);
  }

  // ── TAB 6: LANJUTAN ────────────────────────────────────────────────────────
  Widget _tabLanjutan(KmColors kfc) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _sectionHeader(kfc, '🔍 Web Research'),
      const SizedBox(height: 8),
      _settingsCard(kfc, children: [
        _switchRow(kfc,
          label: 'Aktifkan Web Search',
          subtitle: 'AI dapat mencari informasi terkini dari internet',
          value: _cfg.webSearchEnabled,
          onChanged: (v) => _save(_cfg.copyWith(webSearchEnabled: v)),
        ),
        if (_cfg.webSearchEnabled) ...[
          _divider(kfc),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Search Engine',
                  style: TextStyle(color: kfc.text, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final se in _searchEngines)
                RadioListTile<String>(
                  value: se.$1, groupValue: _cfg.searchEngine,
                  title: Text(se.$2, style: TextStyle(color: kfc.text, fontSize: 13)),
                  activeColor: Colors.blue, dense: true, contentPadding: EdgeInsets.zero,
                  onChanged: (v) { if (v != null) _save(_cfg.copyWith(searchEngine: v)); },
                ),
            ]),
          ),
        ],
      ]),
      const SizedBox(height: 16),
      _infoBox(kfc,
          '💡 Tips: Gunakan Web Search hanya saat dibutuhkan karena '
          'menambah latensi sekitar 2–5 detik per request.',
          Colors.orange),
      const SizedBox(height: 16),
      _sectionHeader(kfc, '📊 Ringkasan Konfigurasi'),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kfc.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kfc.borderSoft),
        ),
        child: Column(children: [
          _summaryRow('Model',      _cfg.selectedModel, kfc),
          _summaryRow('Temperature', _cfg.temperature.toStringAsFixed(2), kfc),
          _summaryRow('Max Tokens', '${_cfg.maxTokens}', kfc),
          _summaryRow('Top-P',      _cfg.topP.toStringAsFixed(2), kfc),
          _summaryRow('Persona',    _cfg.personaName, kfc),
          _summaryRow('Streaming',  _cfg.streamEnabled ? '✅ Ya' : '❌ Tidak', kfc),
          _summaryRow('TTS',        _cfg.ttsEnabled    ? '✅ Ya' : '❌ Tidak', kfc),
          _summaryRow('Markdown',   _cfg.markdownEnabled ? '✅ Ya' : '❌ Tidak', kfc),
          _summaryRow('Web Search', _cfg.webSearchEnabled ? '✅ Ya' : '❌ Tidak', kfc),
        ]),
      ),
      const SizedBox(height: 24),
    ]);
  }

  // ── SHARED WIDGETS ─────────────────────────────────────────────────────────
  Widget _sectionHeader(KmColors kfc, String title) => Text(title,
      style: TextStyle(color: kfc.text, fontSize: 13, fontWeight: FontWeight.w700));

  Widget _settingsCard(KmColors kfc, {required List<Widget> children}) => Container(
      decoration: BoxDecoration(
        color: kfc.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kfc.borderSoft),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children));

  Widget _divider(KmColors kfc) =>
      Divider(height: 1, thickness: 1, color: kfc.borderSoft, indent: 14, endIndent: 14);

  Widget _switchRow(KmColors kfc, {
    required String label,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(color: kfc.text, fontSize: 13, fontWeight: FontWeight.w600)),
            if (subtitle != null)
              Text(subtitle, style: TextStyle(color: kfc.textMuted, fontSize: 11)),
          ]),
        ),
        Switch(value: value, onChanged: onChanged, activeColor: Colors.blue),
      ]),
    );
  }

  Widget _sliderRow(KmColors kfc, {
    required String label,
    String? subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String unit,
    required int decimals,
    required ValueChanged<double> onChanged,
  }) {
    final display = decimals == 0
        ? value.toInt().toString()
        : value.toStringAsFixed(decimals);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(color: kfc.text, fontSize: 13, fontWeight: FontWeight.w600)),
              if (subtitle != null)
                Text(subtitle, style: TextStyle(color: kfc.textMuted, fontSize: 11)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Text('$display$unit',
                style: const TextStyle(
                    color: Colors.blue, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]),
        Slider(
          value: value.clamp(min, max),
          min: min, max: max, divisions: divisions,
          activeColor: Colors.blue,
          inactiveColor: Colors.blue.withValues(alpha: 0.2),
          onChanged: onChanged,
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${decimals == 0 ? min.toInt() : min}',
              style: TextStyle(color: kfc.textMuted, fontSize: 10)),
          Text('${decimals == 0 ? max.toInt() : max}',
              style: TextStyle(color: kfc.textMuted, fontSize: 10)),
        ]),
      ]),
    );
  }

  Widget _infoBox(KmColors kfc, String text, Color color) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(text,
            style: TextStyle(color: kfc.textMuted, fontSize: 12, height: 1.4))),
      ]));

  Widget _summaryRow(String k, String v, KmColors kfc) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text('$k:',
            style: TextStyle(color: kfc.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Expanded(child: Text(v,
            style: TextStyle(color: kfc.text, fontSize: 12),
            overflow: TextOverflow.ellipsis, textAlign: TextAlign.right)),
      ]));
}

// ── Model Picker Tile ─────────────────────────────────────────────────────────
class _ModelPickerTile extends StatelessWidget {
  final KmColors     kfc;
  final PuterAiModel model;
  final bool         isSelected;
  final VoidCallback onTap;

  const _ModelPickerTile({
    required this.kfc,
    required this.model,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withValues(alpha: 0.10) : kfc.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.blue.withValues(alpha: 0.5) : kfc.borderSoft,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue.withValues(alpha: 0.15) : kfc.inputFill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: Text(model.emoji, style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(model.name,
                      style: TextStyle(
                          color: isSelected ? Colors.blue : kfc.text,
                          fontSize: 13, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis),
                ),
                if (model.isNew)  _badge('NEW',  Colors.green),
                if (model.isBest) _badge('BEST', Colors.blue),
                if (model.isFast) _badge('FAST', Colors.orange),
              ]),
              Text(model.provider, style: TextStyle(color: kfc.textMuted, fontSize: 11)),
              if (model.description.isNotEmpty)
                Text(model.description,
                    style: TextStyle(color: kfc.textMuted, fontSize: 11),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 6),
          if (isSelected)
            const Icon(Icons.check_circle_rounded, color: Colors.blue, size: 18)
          else
            Icon(Icons.radio_button_unchecked, color: kfc.borderSoft, size: 18),
        ]),
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w800)));
}

// =============================================================================
// BULK API SETTINGS POPUP — Session 3
// Full 5-tab settings for Bulk API (multi-provider, multi-key)
// =============================================================================

class _BulkSettingsDialog extends StatefulWidget {
  final AiSourceSettingsService svc;
  const _BulkSettingsDialog({required this.svc});

  @override
  State<_BulkSettingsDialog> createState() => _BulkSettingsDialogState();
}

class _BulkSettingsDialogState extends State<_BulkSettingsDialog>
    with SingleTickerProviderStateMixin {

  late TabController _tab;
  late BulkAiConfig  _cfg;

  // Key management state
  BulkApiProvider _selectedProvider = BulkApiProvider.groq;
  final _newKeyCtrl      = TextEditingController();
  final _newLabelCtrl    = TextEditingController();
  final _customUrlCtrl   = TextEditingController();
  final _customModelCtrl = TextEditingController();
  bool _showKeyText      = false;
  bool _testingKey       = false;
  String? _testResult;

  // Persona
  late TextEditingController _personaNameCtrl;
  late TextEditingController _systemPromptCtrl;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    _cfg = widget.svc.bulk;
    // Sync keys from BulkApiService into _cfg
    _cfg = _cfg.copyWith(keys: BulkApiService.instance.keys);
    // Sync activeProvider / loadMode from BulkApiService defaults if not set
    _cfg = _cfg.copyWith(
      activeProvider: _cfg.activeProvider ?? BulkApiProvider.groq,
      loadMode: _cfg.loadMode ?? BulkLoadMode.fallback,
    );
    _personaNameCtrl   = TextEditingController(text: _cfg.personaName);
    _systemPromptCtrl  = TextEditingController(text: _cfg.systemPrompt);
  }

  @override
  void dispose() {
    _tab.dispose();
    _newKeyCtrl.dispose();
    _newLabelCtrl.dispose();
    _customUrlCtrl.dispose();
    _customModelCtrl.dispose();
    _personaNameCtrl.dispose();
    _systemPromptCtrl.dispose();
    super.dispose();
  }

  void _save() {
    _cfg = _cfg.copyWith(
      personaName:  _personaNameCtrl.text.trim(),
      systemPrompt: _systemPromptCtrl.text.trim(),
    );
    widget.svc.saveBulk(_cfg);
    setState(() {});
  }

  void _saveField(BulkAiConfig updated) {
    _cfg = updated;
    widget.svc.saveBulk(_cfg);
    setState(() {});
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<String> _modelsForProvider(BulkApiProvider p) {
    switch (p) {
      case BulkApiProvider.anthropic:
        return [
          'claude-opus-4-5',
          'claude-sonnet-4-5',
          'claude-3-5-sonnet-20241022',
          'claude-3-5-haiku-20241022',
          'claude-3-haiku-20240307',
          'claude-3-opus-20240229',
        ];
      case BulkApiProvider.groq:
        return [
          'llama-3.3-70b-versatile',
          'llama-3.1-8b-instant',
          'llama3-70b-8192',
          'llama3-8b-8192',
          'mixtral-8x7b-32768',
          'gemma2-9b-it',
          'gemma-7b-it',
          'deepseek-r1-distill-llama-70b',
        ];
      case BulkApiProvider.gemini:
        return [
          'gemini-1.5-flash',
          'gemini-1.5-flash-8b',
          'gemini-1.5-pro',
          'gemini-2.0-flash-exp',
          'gemini-2.0-flash-thinking-exp',
        ];
      case BulkApiProvider.openai:
        return [
          'gpt-4o-mini',
          'gpt-4o',
          'gpt-4-turbo',
          'gpt-3.5-turbo',
          'o1-mini',
          'o1-preview',
        ];
      case BulkApiProvider.together:
        return [
          'meta-llama/Llama-3.3-70B-Instruct-Turbo-Free',
          'meta-llama/Llama-3.2-11B-Vision-Instruct-Turbo',
          'mistralai/Mixtral-8x7B-Instruct-v0.1',
          'deepseek-ai/DeepSeek-R1-Distill-Llama-70B-free',
        ];
      case BulkApiProvider.mistral:
        return [
          'mistral-small-latest',
          'mistral-medium-latest',
          'mistral-large-latest',
          'open-mixtral-8x7b',
          'open-codestral-mamba',
        ];
      case BulkApiProvider.openrouter:
        return [
          'meta-llama/llama-3.3-70b-instruct:free',
          'google/gemma-3-27b-it:free',
          'deepseek/deepseek-r1:free',
          'mistralai/mistral-7b-instruct:free',
          'nousresearch/nous-hermes-2-mixtral-8x7b-dpo',
          'anthropic/claude-3-haiku',
        ];
      case BulkApiProvider.custom:
        return ['custom'];
    }
  }

  Future<void> _testApiKey(BulkApiKey key) async {
    setState(() { _testingKey = true; _testResult = null; });
    final result = await BulkApiService.instance.testKey(key);
    setState(() {
      _testingKey = false;
      _testResult = result.success
          ? '✅ Key valid dan aktif!'
          : '❌ Key gagal / tidak valid.';
    });
  }

  void _addKey() {
    final raw = _newKeyCtrl.text.trim();
    if (raw.isEmpty) return;
    final label = _newLabelCtrl.text.trim().isEmpty
        ? '${_selectedProvider.label} Key ${(_cfg.keys.length + 1)}'
        : _newLabelCtrl.text.trim();
    BulkApiService.instance.addKey(
      provider:    _selectedProvider,
      apiKey:      raw,
      label:       label,
      customUrl:   _customUrlCtrl.text.trim(),
      customModel: _customModelCtrl.text.trim(),
    ).then((newKey) {
      final updatedKeys = [..._cfg.keys, newKey];
      _saveField(_cfg.copyWith(keys: updatedKeys));
    });
    _newKeyCtrl.clear();
    _newLabelCtrl.clear();
    _customUrlCtrl.clear();
    _customModelCtrl.clear();
    setState(() { _testResult = null; });
  }

  void _deleteKey(BulkApiKey key) {
    BulkApiService.instance.removeKey(key.id);
    final updated = _cfg.keys.cast<BulkApiKey>()
        .where((k) => k.id != key.id).toList();
    _saveField(_cfg.copyWith(keys: updated));
  }

  void _toggleKeyActive(BulkApiKey key) {
    final toggled = BulkApiKey(
      provider:    key.provider,
      apiKey:      key.apiKey,
      label:       key.label,
      customUrl:   key.customUrl,
      customModel: key.customModel,
      isActive:    !key.isActive,
    );
    BulkApiService.instance.updateKey(toggled);
    final updated = _cfg.keys.cast<BulkApiKey>().map((k) {
      return k.id == key.id ? toggled : k;
    }).toList();
    _saveField(_cfg.copyWith(keys: updated));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final tt  = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Scaffold(
            backgroundColor: cs.surface,
            appBar: AppBar(
              backgroundColor: cs.surface,
              automaticallyImplyLeading: false,
              centerTitle: false,
              title: Row(
                children: [
                  Icon(Icons.vpn_key_rounded, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('Pengaturan Bulk API',
                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
              bottom: TabBar(
                controller: _tab,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(icon: Icon(Icons.vpn_key_rounded),      text: 'Keys'),
                  Tab(icon: Icon(Icons.smart_toy_rounded),    text: 'Model'),
                  Tab(icon: Icon(Icons.tune_rounded),         text: 'Parameter'),
                  Tab(icon: Icon(Icons.face_rounded),         text: 'Persona'),
                  Tab(icon: Icon(Icons.settings_rounded),     text: 'Lanjutan'),
                ],
              ),
            ),
            body: TabBarView(
              controller: _tab,
              children: [
                _buildKeysTab(cs, tt, scrollCtrl),
                _buildModelTab(cs, tt, scrollCtrl),
                _buildParameterTab(cs, tt, scrollCtrl),
                _buildPersonaTab(cs, tt, scrollCtrl),
                _buildAdvancedTab(cs, tt, scrollCtrl),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── TAB 1: Keys ────────────────────────────────────────────────────────────

  Widget _buildKeysTab(ColorScheme cs, TextTheme tt, ScrollController sc) {
    final typedKeys = _cfg.keys.cast<BulkApiKey>();
    return ListView(
      controller: sc,
      padding: const EdgeInsets.all(16),
      children: [
        // Provider selector
        Text('Provider AI', style: tt.labelLarge?.copyWith(color: cs.primary)),
        const SizedBox(height: 8),
        DropdownButtonFormField<BulkApiProvider>(
          value: _selectedProvider,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
          ),
          items: BulkApiProvider.values.map((p) => DropdownMenuItem(
            value: p,
            child: Row(
              children: [
                Text(p.emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(child: Text(p.label)),
                if (p.isFree)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(30),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('FREE',
                      style: tt.labelSmall?.copyWith(color: Colors.green, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          )).toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _selectedProvider = v;
              _testResult = null;
            });
          },
        ),

        const SizedBox(height: 12),

        // Link "Dapatkan API Key"
        if (_selectedProvider.getKeyUrl.isNotEmpty)
          TextButton.icon(
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: Text('Dapatkan API Key untuk ${_selectedProvider.label}'),
            onPressed: () async {
              final uri = Uri.tryParse(_selectedProvider.getKeyUrl);
              if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),

        const SizedBox(height: 12),

        // Input API Key
        Text('API Key Baru', style: tt.labelLarge?.copyWith(color: cs.primary)),
        const SizedBox(height: 6),
        TextField(
          controller: _newKeyCtrl,
          obscureText: !_showKeyText,
          decoration: InputDecoration(
            hintText: 'Tempel API key di sini...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            suffixIcon: IconButton(
              icon: Icon(_showKeyText ? Icons.visibility_off_rounded : Icons.visibility_rounded),
              onPressed: () => setState(() => _showKeyText = !_showKeyText),
            ),
          ),
        ),

        const SizedBox(height: 8),
        TextField(
          controller: _newLabelCtrl,
          decoration: InputDecoration(
            hintText: 'Label (opsional, mis: "Key Pribadi")',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
          ),
        ),

        // Custom endpoint fields
        if (_selectedProvider == BulkApiProvider.custom) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _customUrlCtrl,
            decoration: InputDecoration(
              hintText: 'Base URL (mis: https://myserver.ai/v1/chat/completions)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: cs.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _customModelCtrl,
            decoration: InputDecoration(
              hintText: 'Model ID (mis: llama3-custom)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: cs.surfaceContainerHighest,
            ),
          ),
        ],

        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: const Text('Tambah Key'),
                onPressed: _addKey,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: _testingKey
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.network_check_rounded),
              label: const Text('Test'),
              onPressed: _testingKey ? null : () {
                if (_newKeyCtrl.text.trim().isEmpty) return;
                _testApiKey(BulkApiKey(
                  provider:    _selectedProvider,
                  apiKey:      _newKeyCtrl.text.trim(),
                  label:       'Test Key',
                  customUrl:   _customUrlCtrl.text.trim(),
                  customModel: _customModelCtrl.text.trim(),
                ));
              },
            ),
          ],
        ),

        if (_testResult != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _testResult!.startsWith('✅')
                  ? Colors.green.withAlpha(30)
                  : Colors.red.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _testResult!.startsWith('✅') ? Colors.green : Colors.red,
              ),
            ),
            child: Text(_testResult!, style: tt.bodyMedium),
          ),
        ],

        const Divider(height: 32),

        // Existing keys list
        Text('Key Tersimpan (${typedKeys.length})',
          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),

        if (typedKeys.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.key_off_rounded, size: 48, color: cs.outline),
                  const SizedBox(height: 8),
                  Text('Belum ada key tersimpan.',
                    style: tt.bodyMedium?.copyWith(color: cs.outline)),
                ],
              ),
            ),
          )
        else
          ...typedKeys.map((key) => _buildKeyCard(key, cs, tt)),
      ],
    );
  }

  Widget _buildKeyCard(BulkApiKey key, ColorScheme cs, TextTheme tt) {
    final masked = key.apiKey.length > 8
        ? '${key.apiKey.substring(0, 4)}••••${key.apiKey.substring(key.apiKey.length - 4)}'
        : '••••••••';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: key.isActive ? cs.primaryContainer : cs.surfaceContainerHighest,
      child: ListTile(
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(key.provider.emoji, style: const TextStyle(fontSize: 22)),
          ],
        ),
        title: Text(key.label,
          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(masked, style: tt.bodySmall?.copyWith(fontFamily: 'monospace')),
            Text(key.provider.label, style: tt.labelSmall?.copyWith(color: cs.outline)),
            if (key.successCount > 0 || key.failCount > 0)
              Text('✅ ${key.successCount} sukses  ❌ ${key.failCount} gagal',
                style: tt.labelSmall?.copyWith(color: cs.outline)),
          ],
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: key.isActive,
              onChanged: (_) => _toggleKeyActive(key),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              color: cs.error,
              onPressed: () => _deleteKey(key),
            ),
          ],
        ),
      ),
    );
  }

  // ── TAB 2: Model ───────────────────────────────────────────────────────────

  Widget _buildModelTab(ColorScheme cs, TextTheme tt, ScrollController sc) {
    final typedKeys = _cfg.keys.cast<BulkApiKey>();
    final activeProviders = typedKeys
        .where((k) => k.isActive)
        .map((k) => k.provider)
        .toSet()
        .toList();

    final availableProviders = activeProviders.isEmpty
        ? BulkApiProvider.values
        : activeProviders;

    final currentProvider = (_cfg.activeProvider as BulkApiProvider?) ?? BulkApiProvider.groq;
    final effectiveProvider = availableProviders.contains(currentProvider)
        ? currentProvider
        : availableProviders.first;

    return ListView(
      controller: sc,
      padding: const EdgeInsets.all(16),
      children: [
        _infoCard(
          cs,
          Icons.info_outline_rounded,
          'Model yang dipilih akan digunakan saat Bulk API aktif. '
          'Pastikan model kompatibel dengan provider key yang aktif.',
        ),
        const SizedBox(height: 16),

        Text('Provider Aktif', style: tt.labelLarge?.copyWith(color: cs.primary)),
        const SizedBox(height: 8),
        DropdownButtonFormField<BulkApiProvider>(
          value: effectiveProvider,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
          ),
          items: availableProviders.map((p) => DropdownMenuItem(
            value: p,
            child: Row(
              children: [
                Text(p.emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(p.label),
              ],
            ),
          )).toList(),
          onChanged: (v) {
            if (v == null) return;
            final defaultModel = _modelsForProvider(v).first;
            _saveField(_cfg.copyWith(
              activeProvider: v,
              selectedModel: defaultModel,
            ));
          },
        ),

        const SizedBox(height: 16),
        Text('Model', style: tt.labelLarge?.copyWith(color: cs.primary)),
        const SizedBox(height: 8),

        ..._modelsForProvider(effectiveProvider).map((m) => RadioListTile<String>(
          title: Text(m, style: tt.bodyMedium),
          subtitle: Text(effectiveProvider.label, style: tt.bodySmall?.copyWith(color: cs.outline)),
          value: m,
          groupValue: _cfg.selectedModel,
          onChanged: (v) {
            if (v == null) return;
            _saveField(_cfg.copyWith(selectedModel: v));
          },
        )),

        const SizedBox(height: 8),

        // Custom model override
        Text('Custom Model Override', style: tt.labelLarge?.copyWith(color: cs.primary)),
        const SizedBox(height: 6),
        TextField(
          decoration: InputDecoration(
            hintText: 'Isi untuk override model (kosongkan = pakai pilihan di atas)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
          ),
          onChanged: (v) => _saveField(_cfg.copyWith(customModelOverride: v.trim())),
          controller: TextEditingController(text: _cfg.customModelOverride),
        ),
      ],
    );
  }

  // ── TAB 3: Parameter ───────────────────────────────────────────────────────

  Widget _buildParameterTab(ColorScheme cs, TextTheme tt, ScrollController sc) {
    return ListView(
      controller: sc,
      padding: const EdgeInsets.all(16),
      children: [
        _sliderTile(
          cs: cs, tt: tt,
          label: 'Temperature',
          desc: 'Kreativitas jawaban AI. Rendah = lebih konsisten, Tinggi = lebih kreatif.',
          value: _cfg.temperature,
          min: 0.0, max: 2.0, divisions: 20,
          onChanged: (v) => _saveField(_cfg.copyWith(temperature: v)),
        ),
        const SizedBox(height: 4),
        _sliderTile(
          cs: cs, tt: tt,
          label: 'Max Tokens',
          desc: 'Panjang maksimum respons AI (dalam token).',
          value: _cfg.maxTokens.toDouble(),
          min: 128, max: 32768, divisions: 128,
          onChanged: (v) => _saveField(_cfg.copyWith(maxTokens: v.round())),
          valueLabel: _cfg.maxTokens.toString(),
        ),
        const SizedBox(height: 4),
        _sliderTile(
          cs: cs, tt: tt,
          label: 'Top-P',
          desc: 'Nucleus sampling. Nilai lebih kecil = pilihan kata lebih terfokus.',
          value: _cfg.topP,
          min: 0.0, max: 1.0, divisions: 20,
          onChanged: (v) => _saveField(_cfg.copyWith(topP: v)),
        ),
        const SizedBox(height: 4),
        _sliderTile(
          cs: cs, tt: tt,
          label: 'Frequency Penalty',
          desc: 'Mengurangi pengulangan kata yang sama. Nilai positif = lebih variatif.',
          value: _cfg.frequencyPenalty,
          min: -2.0, max: 2.0, divisions: 40,
          onChanged: (v) => _saveField(_cfg.copyWith(frequencyPenalty: v)),
        ),
        const SizedBox(height: 4),
        _sliderTile(
          cs: cs, tt: tt,
          label: 'Presence Penalty',
          desc: 'Mendorong AI membahas topik baru. Nilai positif = lebih eksploratif.',
          value: _cfg.presencePenalty,
          min: -2.0, max: 2.0, divisions: 40,
          onChanged: (v) => _saveField(_cfg.copyWith(presencePenalty: v)),
        ),
        const Divider(height: 24),
        SwitchListTile(
          title: const Text('Stream Response'),
          subtitle: const Text('Tampilkan respons kata per kata secara real-time'),
          value: _cfg.streamEnabled,
          onChanged: (v) => _saveField(_cfg.copyWith(streamEnabled: v)),
        ),
        SwitchListTile(
          title: const Text('Markdown Rendering'),
          subtitle: const Text('Render format markdown dalam respons'),
          value: _cfg.markdownEnabled,
          onChanged: (v) => _saveField(_cfg.copyWith(markdownEnabled: v)),
        ),
        SwitchListTile(
          title: const Text('Code Highlighting'),
          subtitle: const Text('Warnai blok kode di respons AI'),
          value: _cfg.codeHighlightEnabled,
          onChanged: (v) => _saveField(_cfg.copyWith(codeHighlightEnabled: v)),
        ),
      ],
    );
  }

  // ── TAB 4: Persona ─────────────────────────────────────────────────────────

  Widget _buildPersonaTab(ColorScheme cs, TextTheme tt, ScrollController sc) {
    return ListView(
      controller: sc,
      padding: const EdgeInsets.all(16),
      children: [
        _infoCard(
          cs,
          Icons.face_rounded,
          'Persona menentukan identitas dan gaya bicara AI di sesi Bulk API. '
          'System prompt akan dikirim sebagai instruksi awal ke semua model yang aktif.',
        ),
        const SizedBox(height: 16),

        Text('Nama Persona', style: tt.labelLarge?.copyWith(color: cs.primary)),
        const SizedBox(height: 6),
        TextField(
          controller: _personaNameCtrl,
          decoration: InputDecoration(
            hintText: 'Mis: KanMon Bulk Assistant',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
          ),
          onChanged: (_) => _save(),
        ),

        const SizedBox(height: 16),
        Text('System Prompt', style: tt.labelLarge?.copyWith(color: cs.primary)),
        const SizedBox(height: 6),
        TextField(
          controller: _systemPromptCtrl,
          maxLines: 6,
          decoration: InputDecoration(
            hintText:
                'Mis: Kamu adalah asisten AI yang membantu pengguna belajar bahasa Jepang. '
                'Jawab dalam bahasa Indonesia kecuali ditanya dalam bahasa lain. '
                'Gunakan contoh kalimat bahasa Jepang saat relevan.',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
          ),
          onChanged: (_) => _save(),
        ),

        const SizedBox(height: 16),
        Text('Preset Persona Cepat', style: tt.labelLarge?.copyWith(color: cs.primary)),
        const SizedBox(height: 8),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _presetChip('🤖 Asisten Umum',
              'Kamu adalah asisten AI yang ramah dan membantu. Jawab pertanyaan dengan jelas dan singkat.',
              cs),
            _presetChip('📚 Guru Bahasa Jepang',
              'Kamu adalah guru bahasa Jepang yang berpengalaman. Ajarkan dengan contoh kalimat nyata, '
              'jelaskan tata bahasa, dan koreksi kesalahan pengguna dengan sopan.',
              cs),
            _presetChip('💻 Programmer',
              'Kamu adalah senior software engineer. Tulis kode yang bersih, berikan penjelasan singkat, '
              'dan selalu sertakan contoh penggunaan.',
              cs),
            _presetChip('✍️ Penulis Kreatif',
              'Kamu adalah penulis kreatif yang berbakat. Bantu pengguna menulis cerita, esai, puisi, '
              'dan konten kreatif lainnya dengan gaya yang menarik.',
              cs),
            _presetChip('🔬 Analis Data',
              'Kamu adalah analis data berpengalaman. Bantu interpretasi data, statistik, dan visualisasi. '
              'Jelaskan temuan dengan bahasa yang mudah dipahami.',
              cs),
          ],
        ),
      ],
    );
  }

  Widget _presetChip(String label, String prompt, ColorScheme cs) {
    return ActionChip(
      label: Text(label),
      backgroundColor: cs.secondaryContainer,
      onPressed: () {
        setState(() {
          _systemPromptCtrl.text = prompt;
        });
        _save();
      },
    );
  }

  // ── TAB 5: Lanjutan ────────────────────────────────────────────────────────

  Widget _buildAdvancedTab(ColorScheme cs, TextTheme tt, ScrollController sc) {
    final currentLoadMode = (_cfg.loadMode as BulkLoadMode?) ?? BulkLoadMode.fallback;
    return ListView(
      controller: sc,
      padding: const EdgeInsets.all(16),
      children: [
        Text('Mode Load Key', style: tt.labelLarge?.copyWith(color: cs.primary)),
        const SizedBox(height: 4),
        Text(
          'Tentukan bagaimana Bulk API memilih key saat mengirim request.',
          style: tt.bodySmall?.copyWith(color: cs.outline),
        ),
        const SizedBox(height: 8),
        ...BulkLoadMode.values.map((mode) => RadioListTile<BulkLoadMode>(
          title: Text(mode.label),
          subtitle: Text(mode.description),
          value: mode,
          groupValue: currentLoadMode,
          onChanged: (v) {
            if (v == null) return;
            _saveField(_cfg.copyWith(loadMode: v));
          },
        )),

        const Divider(height: 24),

        Text('Retry & Timeout', style: tt.labelLarge?.copyWith(color: cs.primary)),
        const SizedBox(height: 8),

        _sliderTile(
          cs: cs, tt: tt,
          label: 'Retry Maksimum',
          desc: 'Berapa kali mencoba key lain jika terjadi error / rate limit.',
          value: _cfg.maxRetries.toDouble(),
          min: 0, max: 10, divisions: 10,
          valueLabel: _cfg.maxRetries.toString(),
          onChanged: (v) => _saveField(_cfg.copyWith(maxRetries: v.round())),
        ),

        _sliderTile(
          cs: cs, tt: tt,
          label: 'Timeout (detik)',
          desc: 'Batas waktu menunggu respons dari API sebelum dianggap gagal.',
          value: _cfg.timeoutSeconds.toDouble(),
          min: 10, max: 120, divisions: 22,
          valueLabel: '${_cfg.timeoutSeconds}s',
          onChanged: (v) => _saveField(_cfg.copyWith(timeoutSeconds: v.round())),
        ),

        const Divider(height: 24),

        Text('Bahasa & TTS', style: tt.labelLarge?.copyWith(color: cs.primary)),
        const SizedBox(height: 8),

        ListTile(
          title: const Text('Bahasa Respons'),
          subtitle: const Text('Petunjuk bahasa ke AI (tidak 100% dijamin)'),
          trailing: DropdownButton<String>(
            value: _cfg.language,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 'auto',  child: Text('Auto')),
              DropdownMenuItem(value: 'id',    child: Text('Indonesia')),
              DropdownMenuItem(value: 'en',    child: Text('English')),
              DropdownMenuItem(value: 'ja',    child: Text('日本語')),
            ],
            onChanged: (v) {
              if (v == null) return;
              _saveField(_cfg.copyWith(language: v));
            },
          ),
        ),

        SwitchListTile(
          title: const Text('Auto-detect Bahasa'),
          subtitle: const Text('Deteksi bahasa dari input user secara otomatis'),
          value: _cfg.autoDetectLanguage,
          onChanged: (v) => _saveField(_cfg.copyWith(autoDetectLanguage: v)),
        ),

        SwitchListTile(
          title: const Text('TTS (Text-to-Speech)'),
          subtitle: const Text('Bacakan respons AI menggunakan suara'),
          value: _cfg.ttsEnabled,
          onChanged: (v) => _saveField(_cfg.copyWith(ttsEnabled: v)),
        ),

        if (_cfg.ttsEnabled)
          ListTile(
            title: const Text('Suara TTS'),
            trailing: DropdownButton<String>(
              value: _cfg.ttsVoice,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'id-ID-GadisNeural',   child: Text('Gadis (ID)')),
                DropdownMenuItem(value: 'id-ID-ArdiNeural',    child: Text('Ardi (ID)')),
                DropdownMenuItem(value: 'en-US-JennyNeural',   child: Text('Jenny (EN)')),
                DropdownMenuItem(value: 'en-US-GuyNeural',     child: Text('Guy (EN)')),
                DropdownMenuItem(value: 'ja-JP-NanamiNeural',  child: Text('Nanami (JA)')),
                DropdownMenuItem(value: 'ja-JP-KeitaNeural',   child: Text('Keita (JA)')),
              ],
              onChanged: (v) {
                if (v == null) return;
                _saveField(_cfg.copyWith(ttsVoice: v));
              },
            ),
          ),

        const Divider(height: 24),

        // Reset
        ListTile(
          leading: Icon(Icons.restore_rounded, color: cs.error),
          title: Text('Reset ke Default',
            style: tt.bodyMedium?.copyWith(color: cs.error)),
          subtitle: const Text('Hapus semua pengaturan Bulk API dan kembali ke awal.'),
          onTap: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Reset Bulk API?'),
                content: const Text(
                  'Semua pengaturan Bulk API (kecuali key tersimpan) akan direset. '
                  'Key yang tersimpan TIDAK akan dihapus.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Batal'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Reset'),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              final keys = _cfg.keys; // preserve keys
              _cfg = BulkAiConfig(keys: keys);
              _cfg = _cfg.copyWith(
                activeProvider: BulkApiProvider.groq,
                loadMode: BulkLoadMode.fallback,
              );
              widget.svc.saveBulk(_cfg);
              _personaNameCtrl.text  = _cfg.personaName;
              _systemPromptCtrl.text = _cfg.systemPrompt;
              setState(() {});
            }
          },
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  // ── Shared Helpers ─────────────────────────────────────────────────────────

  Widget _sliderTile({
    required ColorScheme cs,
    required TextTheme tt,
    required String label,
    required String desc,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    String? valueLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: tt.labelLarge),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                valueLabel ?? value.toStringAsFixed(2),
                style: tt.labelMedium?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Text(desc, style: tt.bodySmall?.copyWith(color: cs.outline)),
        Slider(
          value: value.clamp(min, max),
          min: min, max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _infoCard(ColorScheme cs, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withAlpha(80),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text,
            style: TextStyle(fontSize: 13, color: cs.onSurface.withAlpha(200)))),
        ],
      ),
    );
  }
}
// END OF SESSION 3 — _BulkSettingsDialog

// =============================================================================
// OFFLINE AI SETTINGS POPUP — Session 4
// Full 6-tab settings for Offline AI (llama.cpp / GGUF models)
// =============================================================================

class _OfflineSettingsDialog extends StatefulWidget {
  final AiSourceSettingsService svc;
  const _OfflineSettingsDialog({required this.svc});

  @override
  State<_OfflineSettingsDialog> createState() => _OfflineSettingsDialogState();
}

class _OfflineSettingsDialogState extends State<_OfflineSettingsDialog>
    with SingleTickerProviderStateMixin {

  late TabController _tab;
  late OfflineAiConfig _cfg;

  // Persona controllers
  late TextEditingController _personaNameCtrl;
  late TextEditingController _systemPromptCtrl;

  // Stop sequences state
  final _stopSeqCtrl = TextEditingController();
  late List<String> _stopSequences;

  // Model state mirrors
  bool _isLoadingModel = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 6, vsync: this);
    _cfg = widget.svc.offline;
    _personaNameCtrl  = TextEditingController(text: _cfg.personaName);
    _systemPromptCtrl = TextEditingController(text: _cfg.systemPrompt);
    _stopSequences    = List<String>.from(_cfg.stopSequences);
  }

  @override
  void dispose() {
    _tab.dispose();
    _personaNameCtrl.dispose();
    _systemPromptCtrl.dispose();
    _stopSeqCtrl.dispose();
    super.dispose();
  }

  void _save() {
    _cfg = _cfg.copyWith(
      personaName:   _personaNameCtrl.text.trim(),
      systemPrompt:  _systemPromptCtrl.text.trim(),
      stopSequences: _stopSequences,
    );
    widget.svc.saveOffline(_cfg);
    setState(() {});
  }

  void _saveField(OfflineAiConfig updated) {
    _cfg = updated;
    widget.svc.saveOffline(_cfg);
    setState(() {});
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Scaffold(
            backgroundColor: cs.surface,
            appBar: AppBar(
              backgroundColor: cs.surface,
              automaticallyImplyLeading: false,
              centerTitle: false,
              title: Row(
                children: [
                  Icon(Icons.memory_rounded, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('Pengaturan Offline AI',
                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
              bottom: TabBar(
                controller: _tab,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(icon: Icon(Icons.memory_rounded),    text: 'Model'),
                  Tab(icon: Icon(Icons.tune_rounded),      text: 'Parameter'),
                  Tab(icon: Icon(Icons.science_rounded),   text: 'Lanjutan'),
                  Tab(icon: Icon(Icons.face_rounded),      text: 'Persona'),
                  Tab(icon: Icon(Icons.palette_rounded),   text: 'Tampilan'),
                  Tab(icon: Icon(Icons.info_rounded),      text: 'Info'),
                ],
              ),
            ),
            body: TabBarView(
              controller: _tab,
              children: [
                _buildModelTab(cs, tt, scrollCtrl),
                _buildParameterTab(cs, tt, scrollCtrl),
                _buildAdvancedTab(cs, tt, scrollCtrl),
                _buildPersonaTab(cs, tt, scrollCtrl),
                _buildDisplayTab(cs, tt, scrollCtrl),
                _buildInfoTab(cs, tt, scrollCtrl),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── TAB 1: Model ───────────────────────────────────────────────────────────

  Widget _buildModelTab(ColorScheme cs, TextTheme tt, ScrollController sc) {
    final offlineSvc = OfflineAiService.instance;
    final modelMgr   = ModelManagerService.instance;

    return StatefulBuilder(
      builder: (ctx, setLocal) {
        final loadedPath  = LlamaService.instance.currentModel?.path ?? offlineSvc.loadedModelPath;
        final isReady     = LlamaService.instance.isModelLoaded;
        final isLoading   = LlamaService.instance.status == ModelStatus.loading || _isLoadingModel;
        final localModels = modelMgr.localModels;

        return ListView(
          controller: sc,
          padding: const EdgeInsets.all(16),
          children: [
            // Status banner
            _statusBanner(cs, tt,
              isReady: isReady,
              isLoading: isLoading,
              loadedPath: loadedPath),

            const SizedBox(height: 16),

            // Load / Unload button
            if (isReady && loadedPath != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.eject_rounded),
                label: const Text('Unload Model dari Memori'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.error,
                  side: BorderSide(color: cs.error),
                ),
                onPressed: isLoading ? null : () async {
                  setLocal(() => _isLoadingModel = true);
                  await LlamaService.instance.releaseModel();
                  offlineSvc.syncUnload();
                  setLocal(() => _isLoadingModel = false);
                  setState(() {});
                },
              )
            else
              FilledButton.icon(
                icon: isLoading
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2,
                          color: Colors.white))
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(isLoading ? 'Memuat...' : 'Load Model Aktif'),
                onPressed: isLoading || _cfg.activeModelPath.isEmpty ? null : () async {
                  setLocal(() => _isLoadingModel = true);
                  final modelInfo = LlamaModelInfo(
                    id            : _cfg.activeModelPath.hashCode.toString(),
                    name          : _cfg.activeModelPath.split('/').last,
                    path          : _cfg.activeModelPath,
                    sizeBytes     : 0,
                    format        : 'gguf',
                    quantization  : QuantizationType.unknown,
                    estimatedRamMb: 0,
                    contextLength : _cfg.contextSize,
                    isDownloaded  : true,
                  );
                  final config = LlamaModelConfig(
                    contextSize      : _cfg.contextSize,
                    gpuLayers        : _cfg.gpuLayers,
                    nBatch           : 512,
                    nThreads         : 4,
                    useFlashAttention: false,
                    useMemoryLock    : false,
                    ropeFreqBase     : 0.0,
                    ropeFreqScale    : 0.0,
                    chatTemplate     : ChatTemplate.auto,
                  );
                  await LlamaService.instance.loadModel(modelInfo, config: config);
                  // Mirror state back to OfflineAiService for UI indicators
                  if (LlamaService.instance.isModelLoaded) {
                    offlineSvc.syncFromLlamaService(_cfg.activeModelPath);
                  }
                  setLocal(() => _isLoadingModel = false);
                  setState(() {});
                },
              ),

            const SizedBox(height: 24),

            // Model list
            Text('Model Tersimpan (${localModels.length})',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            if (localModels.isEmpty)
              _emptyModelCard(cs, tt)
            else
              ...localModels.map((model) => _buildModelCard(
                model: model,
                cs: cs,
                tt: tt,
                isActive: model.path == _cfg.activeModelPath,
                isLoaded: model.path == loadedPath && isReady,
                onSelect: () {
                  _saveField(_cfg.copyWith(activeModelPath: model.path));
                  setLocal(() {});
                },
                onLoad: isLoading ? null : () async {
                  setLocal(() => _isLoadingModel = true);
                  _saveField(_cfg.copyWith(activeModelPath: model.path));
                  final modelInfo = LlamaModelInfo(
                    id            : model.path.hashCode.toString(),
                    name          : model.name,
                    path          : model.path,
                    sizeBytes     : model.sizeBytes,
                    format        : 'gguf',
                    quantization  : QuantizationType.unknown,
                    estimatedRamMb: (model.sizeBytes / (1024 * 1024) * 1.2).toInt(),
                    contextLength : _cfg.contextSize,
                    isDownloaded  : true,
                  );
                  final config = LlamaModelConfig(
                    contextSize      : _cfg.contextSize,
                    gpuLayers        : _cfg.gpuLayers,
                    nBatch           : 512,
                    nThreads         : 4,
                    useFlashAttention: false,
                    useMemoryLock    : false,
                    ropeFreqBase     : 0.0,
                    ropeFreqScale    : 0.0,
                    chatTemplate     : ChatTemplate.auto,
                  );
                  await LlamaService.instance.loadModel(modelInfo, config: config);
                  if (LlamaService.instance.isModelLoaded) {
                    offlineSvc.syncFromLlamaService(model.path);
                  }
                  setLocal(() => _isLoadingModel = false);
                  setState(() {});
                },
              )),

            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.download_rounded),
              label: const Text('Buka Model Manager untuk Download'),
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/model-manager');
              },
            ),
          ],
        );
      },
    );
  }

  Widget _statusBanner(ColorScheme cs, TextTheme tt, {
    required bool isReady,
    required bool isLoading,
    String? loadedPath,
  }) {
    final Color bgColor;
    final Color fgColor;
    final IconData icon;
    final String label;

    if (isLoading) {
      bgColor = cs.tertiaryContainer;
      fgColor = cs.onTertiaryContainer;
      icon    = Icons.hourglass_top_rounded;
      label   = 'Memuat model...';
    } else if (isReady && loadedPath != null) {
      bgColor = Colors.green.withAlpha(30);
      fgColor = Colors.green.shade700;
      icon    = Icons.check_circle_rounded;
      label   = 'Model aktif: ${loadedPath.split('/').last}';
    } else {
      bgColor = cs.errorContainer;
      fgColor = cs.onErrorContainer;
      icon    = Icons.radio_button_off_rounded;
      label   = 'Tidak ada model yang di-load.';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          isLoading
              ? SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fgColor))
              : Icon(icon, size: 18, color: fgColor),
          const SizedBox(width: 10),
          Expanded(child: Text(label,
            style: tt.bodySmall?.copyWith(color: fgColor, fontWeight: FontWeight.w600),
            maxLines: 2, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildModelCard({
    required LocalModelInfo model,
    required ColorScheme cs,
    required TextTheme tt,
    required bool isActive,
    required bool isLoaded,
    required VoidCallback onSelect,
    required VoidCallback? onLoad,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isLoaded
          ? Colors.green.withAlpha(25)
          : isActive
              ? cs.primaryContainer
              : cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Radio<String>(
              value: model.path,
              groupValue: _cfg.activeModelPath,
              onChanged: (_) => onSelect(),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(model.name,
                          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis),
                      ),
                      if (isLoaded)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('LOADED',
                            style: tt.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            )),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${model.quantization}  •  ${model.sizeLabel}  •  ~${model.estimatedRamMb} MB RAM',
                    style: tt.bodySmall?.copyWith(color: cs.outline),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!isLoaded)
              IconButton(
                icon: const Icon(Icons.play_circle_rounded),
                color: cs.primary,
                tooltip: 'Load model ini',
                onPressed: onLoad,
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyModelCard(ColorScheme cs, TextTheme tt) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.storage_rounded, size: 48, color: cs.outline),
          const SizedBox(height: 8),
          Text('Belum ada model GGUF tersimpan.',
            style: tt.bodyMedium?.copyWith(color: cs.outline),
            textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text('Buka Model Manager untuk download model AI offline.',
            style: tt.bodySmall?.copyWith(color: cs.outline),
            textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // ── TAB 2: Parameter ───────────────────────────────────────────────────────

  Widget _buildParameterTab(ColorScheme cs, TextTheme tt, ScrollController sc) {
    return ListView(
      controller: sc,
      padding: const EdgeInsets.all(16),
      children: [
        _infoCard(cs, Icons.info_outline_rounded,
          'Parameter ini langsung mempengaruhi kualitas dan gaya output model GGUF. '
          'Perubahan berlaku pada sesi chat berikutnya.'),
        const SizedBox(height: 12),

        // Preset buttons
        Text('Preset', style: tt.labelLarge?.copyWith(color: cs.primary)),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _presetBtn('Default',       cs, _applyPresetDefault),
              const SizedBox(width: 8),
              _presetBtn('Kreatif',       cs, _applyPresetCreative),
              const SizedBox(width: 8),
              _presetBtn('Deterministik', cs, _applyPresetDeterministic),
              const SizedBox(width: 8),
              _presetBtn('Kode',          cs, _applyPresetCode),
            ],
          ),
        ),

        const Divider(height: 24),

        _sliderTile(
          cs: cs, tt: tt,
          label: 'Temperature',
          desc: 'Kreativitas output. Rendah = konsisten, Tinggi = variatif.',
          value: _cfg.temperature,
          min: 0.0, max: 2.0, divisions: 40,
          onChanged: (v) => _saveField(_cfg.copyWith(temperature: v)),
        ),
        _sliderTile(
          cs: cs, tt: tt,
          label: 'Top-P (Nucleus)',
          desc: 'Memilih token dari p% probabilitas kumulatif teratas.',
          value: _cfg.topP,
          min: 0.0, max: 1.0, divisions: 20,
          onChanged: (v) => _saveField(_cfg.copyWith(topP: v)),
        ),
        _sliderTile(
          cs: cs, tt: tt,
          label: 'Top-K',
          desc: 'Membatasi pilihan ke K token terbaik.',
          value: _cfg.topK.toDouble(),
          min: 1, max: 200, divisions: 199,
          valueLabel: _cfg.topK.toString(),
          onChanged: (v) => _saveField(_cfg.copyWith(topK: v.round())),
        ),
        _sliderTile(
          cs: cs, tt: tt,
          label: 'Min-P',
          desc: 'Token dengan prob < min-P × prob_max akan diabaikan.',
          value: _cfg.minP,
          min: 0.0, max: 0.5, divisions: 50,
          onChanged: (v) => _saveField(_cfg.copyWith(minP: v)),
        ),
        _sliderTile(
          cs: cs, tt: tt,
          label: 'Max Tokens',
          desc: 'Panjang maksimum token yang dihasilkan per respons.',
          value: _cfg.maxNewTokens.toDouble(),
          min: 64, max: 8192, divisions: 80,
          valueLabel: _cfg.maxNewTokens.toString(),
          onChanged: (v) => _saveField(_cfg.copyWith(maxNewTokens: v.round())),
        ),
        _sliderTile(
          cs: cs, tt: tt,
          label: 'Repeat Penalty',
          desc: 'Menghukum token yang sudah muncul sebelumnya. 1.0 = nonaktif.',
          value: _cfg.repeatPenalty,
          min: 1.0, max: 2.0, divisions: 20,
          onChanged: (v) => _saveField(_cfg.copyWith(repeatPenalty: v)),
        ),
        _sliderTile(
          cs: cs, tt: tt,
          label: 'Repeat Last N',
          desc: 'Jumlah token terakhir yang dicek untuk repeat penalty.',
          value: _cfg.repeatLastN.toDouble(),
          min: 0, max: 512, divisions: 32,
          valueLabel: _cfg.repeatLastN.toString(),
          onChanged: (v) => _saveField(_cfg.copyWith(repeatLastN: v.round())),
        ),
        SwitchListTile(
          title: const Text('Penalize Newline'),
          subtitle: const Text('Terapkan repeat penalty pada karakter newline'),
          value: _cfg.penalizeNl,
          onChanged: (v) => _saveField(_cfg.copyWith(penalizeNl: v)),
        ),
      ],
    );
  }

  void _applyPresetDefault() => _saveField(_cfg.copyWith(
    temperature: 0.7, topP: 0.9, topK: 40, minP: 0.05,
    repeatPenalty: 1.1, repeatLastN: 64, maxNewTokens: 1024,
  ));
  void _applyPresetCreative() => _saveField(_cfg.copyWith(
    temperature: 1.2, topP: 0.95, topK: 80, minP: 0.03,
    repeatPenalty: 1.05, repeatLastN: 128, maxNewTokens: 2048,
  ));
  void _applyPresetDeterministic() => _saveField(_cfg.copyWith(
    temperature: 0.1, topP: 0.9, topK: 20, minP: 0.0,
    repeatPenalty: 1.1, repeatLastN: 64, maxNewTokens: 1024,
  ));
  void _applyPresetCode() => _saveField(_cfg.copyWith(
    temperature: 0.2, topP: 0.9, topK: 40, minP: 0.0,
    repeatPenalty: 1.05, repeatLastN: 64, maxNewTokens: 2048,
  ));

  // ── TAB 3: Lanjutan ────────────────────────────────────────────────────────

  Widget _buildAdvancedTab(ColorScheme cs, TextTheme tt, ScrollController sc) {
    return ListView(
      controller: sc,
      padding: const EdgeInsets.all(16),
      children: [
        Text('Hardware', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),

        _sliderTile(
          cs: cs, tt: tt,
          label: 'GPU Layers',
          desc: '0 = CPU saja. Semakin tinggi, semakin banyak layer dioffload ke GPU. '
                'Mulai dari 10–20 jika ada GPU/NPU.',
          value: _cfg.gpuLayers.toDouble(),
          min: 0, max: 100, divisions: 100,
          valueLabel: _cfg.gpuLayers.toString(),
          onChanged: (v) => _saveField(_cfg.copyWith(gpuLayers: v.round())),
        ),

        _sliderTile(
          cs: cs, tt: tt,
          label: 'Context Size (tokens)',
          desc: 'Ukuran jendela konteks model. Lebih besar = ingatan lebih panjang, '
                'tapi lebih boros RAM.',
          value: _cfg.contextSize.toDouble(),
          min: 512, max: 32768, divisions: 63,
          valueLabel: _cfg.contextSize.toString(),
          onChanged: (v) {
            final snapped = (v / 512).round() * 512;
            _saveField(_cfg.copyWith(contextSize: snapped.clamp(512, 32768)));
          },
        ),

        const Divider(height: 24),

        Text('Mirostat Sampling', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          'Algoritma sampling adaptif yang mengontrol perplexity output. '
          'Mode 0 = nonaktif (gunakan Top-P/K). Mode 1 atau 2 mengaktifkan Mirostat.',
          style: tt.bodySmall?.copyWith(color: cs.outline),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          value: _cfg.mirostatMode,
          decoration: InputDecoration(
            labelText: 'Mode Mirostat',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
          ),
          items: const [
            DropdownMenuItem(value: 0, child: Text('0 — Nonaktif (pakai Top-P/K)')),
            DropdownMenuItem(value: 1, child: Text('1 — Mirostat v1')),
            DropdownMenuItem(value: 2, child: Text('2 — Mirostat v2 (direkomendasikan)')),
          ],
          onChanged: (v) {
            if (v == null) return;
            _saveField(_cfg.copyWith(mirostatMode: v));
          },
        ),

        if (_cfg.mirostatMode > 0) ...[
          const SizedBox(height: 8),
          _sliderTile(
            cs: cs, tt: tt,
            label: 'Mirostat Tau (τ)',
            desc: 'Target perplexity. Nilai lebih rendah = output lebih terfokus.',
            value: _cfg.mirostatTau,
            min: 0.1, max: 10.0, divisions: 99,
            onChanged: (v) => _saveField(_cfg.copyWith(mirostatTau: v)),
          ),
          _sliderTile(
            cs: cs, tt: tt,
            label: 'Mirostat Eta (η)',
            desc: 'Kecepatan adaptasi learning rate.',
            value: _cfg.mirostatEta,
            min: 0.01, max: 1.0, divisions: 99,
            onChanged: (v) => _saveField(_cfg.copyWith(mirostatEta: v)),
          ),
        ],

        const Divider(height: 24),

        Text('Sampling Tambahan', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),

        _sliderTile(
          cs: cs, tt: tt,
          label: 'TFS-Z (Tail Free Sampling)',
          desc: 'Memangkas token berekor kecil. 1.0 = nonaktif.',
          value: _cfg.tfsZ,
          min: 0.0, max: 1.0, divisions: 20,
          onChanged: (v) => _saveField(_cfg.copyWith(tfsZ: v)),
        ),
        _sliderTile(
          cs: cs, tt: tt,
          label: 'Typical-P',
          desc: 'Locally typical sampling. 1.0 = nonaktif.',
          value: _cfg.typicalP,
          min: 0.0, max: 1.0, divisions: 20,
          onChanged: (v) => _saveField(_cfg.copyWith(typicalP: v)),
        ),

        const Divider(height: 24),

        Text('Seed', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          'Seed menentukan pola acak output. -1 = acak setiap sesi. '
          'Set ke angka tetap untuk output yang bisa direproduksi.',
          style: tt.bodySmall?.copyWith(color: cs.outline),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Seed (-1 = acak)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                ),
                controller: TextEditingController(text: _cfg.seed.toString()),
                onChanged: (v) {
                  final parsed = int.tryParse(v);
                  if (parsed != null) _saveField(_cfg.copyWith(seed: parsed));
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              icon: const Icon(Icons.casino_rounded),
              tooltip: 'Random seed',
              onPressed: () {
                final rng = DateTime.now().millisecondsSinceEpoch % 999999;
                _saveField(_cfg.copyWith(seed: rng));
              },
            ),
            const SizedBox(width: 4),
            IconButton.filledTonal(
              icon: const Icon(Icons.all_inclusive_rounded),
              tooltip: 'Set ke -1 (acak)',
              onPressed: () => _saveField(_cfg.copyWith(seed: -1)),
            ),
          ],
        ),

        const Divider(height: 24),

        Text('Stop Sequences', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          'Model akan berhenti generate saat menemukan salah satu string ini.',
          style: tt.bodySmall?.copyWith(color: cs.outline),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _stopSeqCtrl,
                decoration: InputDecoration(
                  hintText: 'Mis: </s> atau ###',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                ),
                onSubmitted: (v) {
                  final val = v.trim();
                  if (val.isNotEmpty && !_stopSequences.contains(val)) {
                    _stopSequences.add(val);
                    _stopSeqCtrl.clear();
                    _save();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                final val = _stopSeqCtrl.text.trim();
                if (val.isNotEmpty && !_stopSequences.contains(val)) {
                  _stopSequences.add(val);
                  _stopSeqCtrl.clear();
                  _save();
                }
              },
              child: const Text('Tambah'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _stopSequences.map((seq) => Chip(
            label: Text(seq, style: const TextStyle(fontFamily: 'monospace')),
            deleteIcon: const Icon(Icons.close_rounded, size: 16),
            onDeleted: () {
              _stopSequences.remove(seq);
              _save();
            },
          )).toList(),
        ),

        const Divider(height: 24),

        SwitchListTile(
          title: const Text('Force Offline Mode'),
          subtitle: const Text(
            'Cegah app menggunakan koneksi internet saat mode offline aktif'),
          value: _cfg.forceOffline,
          onChanged: (v) => _saveField(_cfg.copyWith(forceOffline: v)),
        ),

        const SizedBox(height: 8),
      ],
    );
  }

  // ── TAB 4: Persona ─────────────────────────────────────────────────────────

  Widget _buildPersonaTab(ColorScheme cs, TextTheme tt, ScrollController sc) {
    return ListView(
      controller: sc,
      padding: const EdgeInsets.all(16),
      children: [
        _infoCard(cs, Icons.face_rounded,
          'System prompt dikirim sebagai instruksi awal ke model offline. '
          'Model yang berbeda merespons format system prompt yang berbeda.'),
        const SizedBox(height: 16),

        Text('Nama Persona', style: tt.labelLarge?.copyWith(color: cs.primary)),
        const SizedBox(height: 6),
        TextField(
          controller: _personaNameCtrl,
          decoration: InputDecoration(
            hintText: 'Mis: KanMon Offline Assistant',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
          ),
          onChanged: (_) => _save(),
        ),

        const SizedBox(height: 16),
        Text('System Prompt', style: tt.labelLarge?.copyWith(color: cs.primary)),
        const SizedBox(height: 6),
        TextField(
          controller: _systemPromptCtrl,
          maxLines: 7,
          decoration: InputDecoration(
            hintText:
              'Mis: You are a helpful AI assistant that runs entirely on device. '
              'Answer concisely and accurately. If you are unsure, say so.',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
          ),
          onChanged: (_) => _save(),
        ),

        const SizedBox(height: 16),
        Text('Format Template Chat', style: tt.labelLarge?.copyWith(color: cs.primary)),
        const SizedBox(height: 4),
        Text(
          'Beberapa model memerlukan format prompt khusus. Pilih sesuai model yang digunakan.',
          style: tt.bodySmall?.copyWith(color: cs.outline),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _cfg.chatTemplate,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
          ),
          items: const [
            DropdownMenuItem(value: 'auto',    child: Text('Auto (deteksi dari model)')),
            DropdownMenuItem(value: 'chatml',  child: Text('ChatML (Mistral, Qwen, dll)')),
            DropdownMenuItem(value: 'llama3',  child: Text('Llama 3 / Llama 3.1+')),
            DropdownMenuItem(value: 'llama2',  child: Text('Llama 2')),
            DropdownMenuItem(value: 'alpaca',  child: Text('Alpaca')),
            DropdownMenuItem(value: 'gemma',   child: Text('Gemma')),
            DropdownMenuItem(value: 'phi3',    child: Text('Phi-3')),
            DropdownMenuItem(value: 'zephyr',  child: Text('Zephyr')),
            DropdownMenuItem(value: 'none',    child: Text('Tanpa template (raw)')),
          ],
          onChanged: (v) {
            if (v == null) return;
            _saveField(_cfg.copyWith(chatTemplate: v));
          },
        ),

        const SizedBox(height: 16),
        Text('Preset Persona Cepat', style: tt.labelLarge?.copyWith(color: cs.primary)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _presetPersonaChip(cs, '🤖 Asisten',
              'You are a helpful and friendly AI assistant. Answer clearly and concisely.'),
            _presetPersonaChip(cs, '📚 Guru Bahasa Jepang',
              'Kamu adalah guru bahasa Jepang berpengalaman. Ajarkan dengan contoh nyata, '
              'jelaskan tata bahasa dalam bahasa Indonesia, dan koreksi kesalahan dengan sopan.'),
            _presetPersonaChip(cs, '💻 Senior Dev',
              'You are a senior software engineer. Provide clean, well-commented code. '
              'Explain your reasoning. Suggest best practices when relevant.'),
            _presetPersonaChip(cs, '🧙 Penulis Cerita',
              'Kamu adalah penulis cerita yang berbakat dan imajinatif. '
              'Tulis dengan deskripsi yang vivid, dialog yang natural, dan alur yang menarik.'),
            _presetPersonaChip(cs, '🔬 Ilmuwan',
              'You are a knowledgeable scientist. Explain concepts accurately, '
              'cite reasoning, and acknowledge uncertainty where appropriate.'),
          ],
        ),
      ],
    );
  }

  Widget _presetPersonaChip(ColorScheme cs, String label, String prompt) {
    return ActionChip(
      label: Text(label),
      backgroundColor: cs.secondaryContainer,
      onPressed: () {
        _systemPromptCtrl.text = prompt;
        _save();
      },
    );
  }

  // ── TAB 5: Tampilan ────────────────────────────────────────────────────────

  Widget _buildDisplayTab(ColorScheme cs, TextTheme tt, ScrollController sc) {
    return ListView(
      controller: sc,
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: const Text('Markdown Rendering'),
          subtitle: const Text('Render format **bold**, *italic*, dan tabel di respons'),
          value: _cfg.markdownEnabled,
          onChanged: (v) => _saveField(_cfg.copyWith(markdownEnabled: v)),
        ),
        SwitchListTile(
          title: const Text('Code Highlighting'),
          subtitle: const Text('Warnai blok kode dengan syntax highlighting'),
          value: _cfg.codeHighlightEnabled,
          onChanged: (v) => _saveField(_cfg.copyWith(codeHighlightEnabled: v)),
        ),
        SwitchListTile(
          title: const Text('Stream Token'),
          subtitle: const Text('Tampilkan respons kata per kata secara real-time'),
          value: _cfg.streamEnabled,
          onChanged: (v) => _saveField(_cfg.copyWith(streamEnabled: v)),
        ),

        const Divider(height: 24),

        Text('TTS (Text-to-Speech)',
          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        SwitchListTile(
          title: const Text('Aktifkan TTS'),
          subtitle: const Text('Bacakan respons AI menggunakan Edge-TTS'),
          value: _cfg.ttsEnabled,
          onChanged: (v) => _saveField(_cfg.copyWith(ttsEnabled: v)),
        ),

        if (_cfg.ttsEnabled) ...[
          ListTile(
            title: const Text('Suara TTS'),
            subtitle: Text(_cfg.ttsVoice),
            trailing: const Icon(Icons.arrow_drop_down_rounded),
            onTap: () async {
              final selected = await showDialog<String>(
                context: context,
                builder: (ctx) => _TtsVoicePickerDialog(current: _cfg.ttsVoice),
              );
              if (selected != null) {
                _saveField(_cfg.copyWith(ttsVoice: selected));
              }
            },
          ),
          _sliderTile(
            cs: cs, tt: tt,
            label: 'TTS Rate',
            desc: 'Kecepatan bicara TTS. 0 = normal, positif = lebih cepat.',
            value: _cfg.ttsRate,
            min: -50, max: 50, divisions: 20,
            valueLabel: '${_cfg.ttsRate > 0 ? '+' : ''}${_cfg.ttsRate.round()}%',
            onChanged: (v) => _saveField(_cfg.copyWith(ttsRate: v)),
          ),
          _sliderTile(
            cs: cs, tt: tt,
            label: 'TTS Volume',
            desc: 'Volume suara TTS.',
            value: _cfg.ttsVolume,
            min: -50, max: 50, divisions: 20,
            valueLabel: '${_cfg.ttsVolume > 0 ? '+' : ''}${_cfg.ttsVolume.round()}%',
            onChanged: (v) => _saveField(_cfg.copyWith(ttsVolume: v)),
          ),
        ],
      ],
    );
  }

  // ── TAB 6: Info ────────────────────────────────────────────────────────────

  Widget _buildInfoTab(ColorScheme cs, TextTheme tt, ScrollController sc) {
    final offlineSvc = OfflineAiService.instance;
    final loadedPath = offlineSvc.loadedModelPath;
    final modelMgr   = ModelManagerService.instance;
    LocalModelInfo? loadedModel;
    if (loadedPath != null) {
      try {
        loadedModel = modelMgr.localModels.firstWhere((m) => m.path == loadedPath);
      } catch (_) {
        loadedModel = null;
      }
    }

    return ListView(
      controller: sc,
      padding: const EdgeInsets.all(16),
      children: [
        _infoRow(cs, tt, '🔌 Status',
          offlineSvc.isReady ? 'Model aktif (ready)' : 'Tidak ada model yang dimuat'),
        _infoRow(cs, tt, '📂 Model dimuat',
          loadedPath != null ? loadedPath.split('/').last : '—'),
        _infoRow(cs, tt, '📁 Path lengkap',
          loadedPath ?? '—'),

        const Divider(height: 20),

        if (loadedModel != null) ...[
          Text('Informasi Model', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _infoRow(cs, tt, '🏷️ Nama',    loadedModel.name),
          _infoRow(cs, tt, '📦 Format',   loadedModel.format.toUpperCase()),
          _infoRow(cs, tt, '⚡ Quant',    loadedModel.quantization),
          _infoRow(cs, tt, '💾 Ukuran',   loadedModel.sizeLabel),
          _infoRow(cs, tt, '🧠 Est. RAM', '~${loadedModel.estimatedRamMb} MB'),
          if (loadedModel.lastUsed != null)
            _infoRow(cs, tt, '🕐 Terakhir dipakai',
              '${loadedModel.lastUsed!.day}/${loadedModel.lastUsed!.month}/${loadedModel.lastUsed!.year}'),
          if (loadedModel.tags.isNotEmpty)
            _infoRow(cs, tt, '🏷️ Tags', loadedModel.tags.join(', ')),
          const Divider(height: 20),
        ],

        Text('Konfigurasi Saat Ini', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _infoRow(cs, tt, '🌡️ Temperature',   _cfg.temperature.toStringAsFixed(2)),
        _infoRow(cs, tt, '🎯 Top-P',          _cfg.topP.toStringAsFixed(2)),
        _infoRow(cs, tt, '🔢 Top-K',          _cfg.topK.toString()),
        _infoRow(cs, tt, '📏 Max Tokens',     _cfg.maxNewTokens.toString()),
        _infoRow(cs, tt, '🔁 Repeat Penalty', _cfg.repeatPenalty.toStringAsFixed(2)),
        _infoRow(cs, tt, '📐 Context Size',   _cfg.contextSize.toString()),
        _infoRow(cs, tt, '🖥️ GPU Layers',     _cfg.gpuLayers.toString()),
        _infoRow(cs, tt, '🎲 Seed',           _cfg.seed == -1 ? 'Acak (-1)' : _cfg.seed.toString()),
        _infoRow(cs, tt, '🌐 Mirostat Mode',  _cfg.mirostatMode.toString()),
        _infoRow(cs, tt, '📝 Chat Template',  _cfg.chatTemplate),

        const Divider(height: 20),

        Text('Semua Model Lokal (${modelMgr.localModels.length})',
          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (modelMgr.localModels.isEmpty)
          Text('Tidak ada model.', style: tt.bodySmall?.copyWith(color: cs.outline))
        else
          ...modelMgr.localModels.map((m) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(Icons.fiber_manual_record_rounded,
                  size: 8,
                  color: m.path == loadedPath ? Colors.green : cs.outline),
                const SizedBox(width: 8),
                Expanded(child: Text(m.name, style: tt.bodySmall)),
                Text(m.sizeLabel,
                  style: tt.bodySmall?.copyWith(color: cs.outline)),
              ],
            ),
          )),

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _infoRow(ColorScheme cs, TextTheme tt, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: tt.bodySmall?.copyWith(color: cs.outline)),
          ),
          Expanded(
            child: Text(value,
              style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis, maxLines: 2),
          ),
        ],
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  Widget _presetBtn(String label, ColorScheme cs, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      child: Text(label),
    );
  }

  Widget _sliderTile({
    required ColorScheme cs,
    required TextTheme tt,
    required String label,
    required String desc,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    String? valueLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: tt.labelLarge),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                valueLabel ?? value.toStringAsFixed(2),
                style: tt.labelMedium?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Text(desc, style: tt.bodySmall?.copyWith(color: cs.outline)),
        Slider(
          value: value.clamp(min, max),
          min: min, max: max, divisions: divisions,
          onChanged: onChanged,
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _infoCard(ColorScheme cs, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withAlpha(80),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text,
            style: TextStyle(fontSize: 13, color: cs.onSurface.withAlpha(200)))),
        ],
      ),
    );
  }
}

// ── Helper: TTS Voice Picker Dialog ───────────────────────────────────────────

class _TtsVoicePickerDialog extends StatelessWidget {
  final String current;
  const _TtsVoicePickerDialog({required this.current});

  static const _voices = [
    ('id-ID-GadisNeural',    'Gadis — Indonesia (Wanita)'),
    ('id-ID-ArdiNeural',     'Ardi — Indonesia (Pria)'),
    ('en-US-JennyNeural',    'Jenny — English US (Wanita)'),
    ('en-US-GuyNeural',      'Guy — English US (Pria)'),
    ('en-GB-SoniaNeural',    'Sonia — English UK (Wanita)'),
    ('ja-JP-NanamiNeural',   'Nanami — 日本語 (女性)'),
    ('ja-JP-KeitaNeural',    'Keita — 日本語 (男性)'),
    ('ms-MY-YasminNeural',   'Yasmin — Melayu (Wanita)'),
    ('zh-CN-XiaoxiaoNeural', 'Xiaoxiao — 中文 (女性)'),
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pilih Suara TTS'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: _voices.map(((String id, String label) voice) {
            return RadioListTile<String>(
              title: Text(voice.$2),
              subtitle: Text(voice.$1,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              value: voice.$1,
              groupValue: current,
              onChanged: (v) => Navigator.pop(context, v),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
      ],
    );
  }
}
// END OF SESSION 4 — _OfflineSettingsDialog

// ── AiSourcePickerButton ──────────────────────────────────────────────────────
/// Tombol AppBar untuk memilih sumber AI (Online / Bulk / Offline).
class AiSourcePickerButton extends ConsumerWidget {
  final VoidCallback? onTap;
  const AiSourcePickerButton({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(aiSourceProvider);
    final mode   = choice?.mode ?? AiMode.none;

    IconData icon;
    String   tooltip;
    switch (mode) {
      case AiMode.offline:
        icon    = Icons.memory_rounded;
        tooltip = 'AI: Offline';
        break;
      case AiMode.bulkApi:
        icon    = Icons.bolt_rounded;
        tooltip = 'AI: Bulk API';
        break;
      case AiMode.online:
        icon    = Icons.cloud_rounded;
        tooltip = 'AI: Online';
        break;
      case AiMode.none:
        icon    = Icons.swap_horiz_rounded;
        tooltip = 'Pilih Sumber AI';
        break;
    }

    return IconButton(
      icon:    Icon(icon),
      tooltip: tooltip,
      onPressed: onTap ?? () => showAiSourcePicker(context, ref),
    );
  }
}

// ── showAiSourcePicker ────────────────────────────────────────────────────────
/// Tampilkan bottom sheet AiSourcePicker.
void showAiSourcePicker(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize:     0.4,
      maxChildSize:     0.95,
      expand: false,
      builder: (_, scrollCtrl) => SingleChildScrollView(
        controller: scrollCtrl,
        child:      const AiSourcePicker(),
      ),
    ),
  );
}
