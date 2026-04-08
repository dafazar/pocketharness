import 'package:kanmongo/data/services/ai_persona_service.dart';
import 'package:kanmongo/data/services/puter_ai_service.dart';
import 'package:kanmongo/data/services/bulk_api_service.dart';
import 'package:kanmongo/data/services/ai_service.dart';
import 'package:kanmongo/data/services/sfx_service.dart';
import 'package:kanmongo/core/sync/sync_service.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/core/router/app_router.dart';
import 'package:kanmongo/data/services/model_manager_service.dart';
import 'package:kanmongo/data/services/offline_ai_service.dart';
import 'package:kanmongo/core/ai/inference_params_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:kanmongo/core/theme/theme_provider.dart';
import 'package:kanmongo/core/wallpaper/wallpaper_provider.dart';
import 'package:kanmongo/data/services/tts_service.dart';
import 'package:kanmongo/data/services/edge_tts_service.dart';
import 'package:kanmongo/data/services/wallpaper_service.dart';
import 'package:kanmongo/shared/widgets/wallpaper_background.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool   _notifications = true;
  double _ttsSpeed      = 0.8;
  double _ttsPitch      = 1.0;
  String _ttsEngine     = 'google';  // 'edge' | 'google'
  String _edgeJpVoice   = kDefaultJpVoice;
  String _edgeIdVoice   = kDefaultIdVoice;
  bool   _edgeTesting   = false;

  static const _kNotifications = 'kmg.settings.notifications';
  static const _kTtsSpeed      = 'kmg.settings.tts_speed';
  static const _kTtsPitch      = 'kmg.settings.tts_pitch';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final engine   = await TtsEnginePrefs.getEngine();
    final jpVoice  = await TtsEnginePrefs.getJpVoice();
    final idVoice  = await TtsEnginePrefs.getIdVoice();
    setState(() {
      _notifications = prefs.getBool(_kNotifications) ?? true;
      _ttsSpeed      = prefs.getDouble(_kTtsSpeed)    ?? 0.8;
      _ttsPitch      = prefs.getDouble(_kTtsPitch)    ?? 1.0;
      _ttsEngine     = engine;
      _edgeJpVoice   = jpVoice;
      _edgeIdVoice   = idVoice;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotifications, _notifications);
    await prefs.setDouble(_kTtsSpeed, _ttsSpeed);
    await prefs.setDouble(_kTtsPitch, _ttsPitch);
    // Tandai settings perlu di-sync ke cloud
    await SyncService.markSettingsDirty();
  }

  @override
  Widget build(BuildContext context) {
    final kfc        = KmColors.of(context);
    final isDark     = ref.watch(themeProvider);
    final sfxEnabled = ref.watch(sfxProvider);

    return Scaffold(
      backgroundColor: wallpaperAwareBg(context, ref, kfc.bg),
      appBar: AppBar(
        backgroundColor: wallpaperAwareCard(context, ref, kfc.card),
        automaticallyImplyLeading: false,
        title: Text('Setelan',
            style: TextStyle(color: kfc.text, fontWeight: FontWeight.bold)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(color: kfc.border, height: 1, thickness: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [

          // ── TAMPILAN ──────────────────────────────────────────────────────
          _sectionLabel('TAMPILAN', kfc),
          _group(kfc, [_darkModeRow(kfc, isDark), _sfxRow(kfc, sfxEnabled)]),

          const SizedBox(height: 20),

          // ── WALLPAPER MENU ──────────────────────────────────────────────
          _sectionLabel('WALLPAPER MENU', kfc),
          _WallpaperSection(kfc: kfc),

          const SizedBox(height: 20),

          // ── TEXT-TO-SPEECH ────────────────────────────────────────────────
          _sectionLabel('TEXT-TO-SPEECH', kfc),

          // Engine selector
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: kfc.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: kfc.border)),
            child: Column(children: [
              // Engine toggle
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.record_voice_over_rounded, color: kfc.accent, size: 18),
                    const SizedBox(width: 8),
                    Text('Engine Suara', style: TextStyle(color: kfc.text, fontWeight: FontWeight.w700, fontSize: 14)),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    // Google TTS option
                    Expanded(child: GestureDetector(
                      onTap: () async {
                        setState(() => _ttsEngine = 'google');
                        await TtsEnginePrefs.setEngine('google');
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _ttsEngine == 'google' ? const Color(0xFF4285F4).withValues(alpha: 0.15) : kfc.inputFill,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _ttsEngine == 'google' ? const Color(0xFF4285F4) : kfc.border, width: _ttsEngine == 'google' ? 2 : 1),
                        ),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('🤖', style: const TextStyle(fontSize: 22)),
                          const SizedBox(height: 4),
                          Text('Google TTS', style: TextStyle(color: _ttsEngine == 'google' ? const Color(0xFF4285F4) : kfc.textSub, fontSize: 12, fontWeight: FontWeight.w700)),
                          Text('Bawaan Android', style: TextStyle(color: kfc.textMuted, fontSize: 10)),
                        ]),
                      ),
                    )),
                    const SizedBox(width: 10),
                    // Edge TTS option
                    Expanded(child: GestureDetector(
                      onTap: () async {
                        setState(() => _ttsEngine = 'edge');
                        await TtsEnginePrefs.setEngine('edge');
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _ttsEngine == 'edge' ? const Color(0xFF0078D4).withValues(alpha: 0.15) : kfc.inputFill,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _ttsEngine == 'edge' ? const Color(0xFF0078D4) : kfc.border, width: _ttsEngine == 'edge' ? 2 : 1),
                        ),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('🎙️', style: const TextStyle(fontSize: 22)),
                          const SizedBox(height: 4),
                          Text('Edge TTS', style: TextStyle(color: _ttsEngine == 'edge' ? const Color(0xFF0078D4) : kfc.textSub, fontSize: 12, fontWeight: FontWeight.w700)),
                          Text('Microsoft Neural', style: TextStyle(color: kfc.textMuted, fontSize: 10)),
                        ]),
                      ),
                    )),
                  ]),
                  if (_ttsEngine == 'edge') ...[
                    const SizedBox(height: 8),
                    Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF0078D4).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        const Icon(Icons.info_outline_rounded, color: Color(0xFF0078D4), size: 14),
                        const SizedBox(width: 6),
                        Expanded(child: Text('Butuh koneksi internet. Suara jauh lebih natural dari Google TTS.', style: TextStyle(color: kfc.textSub, fontSize: 11, height: 1.4))),
                      ])),
                  ],
                ]),
              ),

              // Voice selector (hanya jika Edge aktif)
              if (_ttsEngine == 'edge') ...[
                Divider(color: kfc.borderSoft, height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('Pilih Suara TTS', style: TextStyle(color: kfc.textSub, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                ...kEdgeVoices.where((v) => v.locale == 'ja-JP').map((voice) =>
                  RadioListTile<String>(
                    dense: true,
                    value: voice.id,
                    groupValue: _edgeJpVoice,
                    activeColor: const Color(0xFF0078D4),
                    title: Row(children: [
                      Text(voice.gender == 'F' ? '👩' : '👨', style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Text(voice.label, style: TextStyle(color: kfc.text, fontSize: 13)),
                    ]),
                    onChanged: (v) async {
                      if (v == null) return;
                      setState(() => _edgeJpVoice = v);
                      await TtsEnginePrefs.setJpVoice(v);
                    },
                  )
                ).toList(),

                Divider(color: kfc.borderSoft, height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('Pilih Suara Indonesia', style: TextStyle(color: kfc.textSub, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                ...kEdgeVoices.where((v) => v.locale == 'id-ID').map((voice) =>
                  RadioListTile<String>(
                    dense: true,
                    value: voice.id,
                    groupValue: _edgeIdVoice,
                    activeColor: const Color(0xFF0078D4),
                    title: Row(children: [
                      Text(voice.gender == 'F' ? '👩' : '👨', style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Text(voice.label, style: TextStyle(color: kfc.text, fontSize: 13)),
                    ]),
                    onChanged: (v) async {
                      if (v == null) return;
                      setState(() => _edgeIdVoice = v);
                      await TtsEnginePrefs.setIdVoice(v);
                    },
                  )
                ).toList(),

                // Preview button
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: _edgeTesting ? null : () async {
                        setState(() => _edgeTesting = true);
                        await EdgeTtsService.instance.speak('Halo! Saya AI asisten kamu.', voice: _edgeJpVoice, isJapanese: false);
                        setState(() => _edgeTesting = false);
                      },
                      icon: _edgeTesting ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text(_edgeTesting ? 'Memutar...' : 'Preview Suara'),
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF0078D4), side: const BorderSide(color: Color(0xFF0078D4))),
                    )),
                  ]),
                ),
              ],
            ]),
          ),

          _group(kfc, [
            _sliderRow(kfc,
              label: 'Kecepatan Bicara (Google TTS)',
              value: _ttsSpeed, min: 0.5, max: 1.5,
              onChanged: (v) { setState(() => _ttsSpeed = v); _saveSettings(); },
              valueLabel: _ttsSpeed.toStringAsFixed(1)),
            Divider(color: kfc.borderSoft, height: 1, indent: 16, endIndent: 16),
            _sliderRow(kfc,
              label: 'Nada Suara (Google TTS)',
              value: _ttsPitch, min: 0.5, max: 2.0,
              onChanged: (v) { setState(() => _ttsPitch = v); _saveSettings(); },
              valueLabel: _ttsPitch.toStringAsFixed(1)),
          ]),

          const SizedBox(height: 20),

          // ── NOTIFIKASI ────────────────────────────────────────────────────
          _sectionLabel('NOTIFIKASI', kfc),
          _group(kfc, [
            _switchRow(kfc,
              label:    'Pengingat Belajar',
              subtitle: 'Ingatkan saya untuk belajar setiap hari',
              value:    _notifications,
              onChanged: (v) { setState(() => _notifications = v); _saveSettings(); }),
          ]),

          const SizedBox(height: 20),

          const SizedBox(height: 20),

          // ── AI ────────────────────────────────────────────────────────────
          _sectionLabel('AI', kfc),

          // ── AI Mode status card ──────────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AiService.instance.currentMode == AiMode.online
                    ? [const Color(0xFF6C5CE7).withValues(alpha: 0.15),
                       const Color(0xFF00B4D8).withValues(alpha: 0.08)]
                    : AiService.instance.currentMode == AiMode.offline
                        ? [Colors.green.withValues(alpha: 0.10),
                           Colors.teal.withValues(alpha: 0.06)]
                        : [Colors.orange.withValues(alpha: 0.10),
                           Colors.red.withValues(alpha: 0.06)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AiService.instance.currentMode == AiMode.online
                    ? const Color(0xFF6C5CE7).withValues(alpha: 0.35)
                    : AiService.instance.currentMode == AiMode.offline
                        ? Colors.green.withValues(alpha: 0.3)
                        : Colors.orange.withValues(alpha: 0.3),
              ),
            ),
            child: Row(children: [
              Text(
                AiService.instance.currentMode == AiMode.online ? '🌐'
                    : AiService.instance.currentMode == AiMode.offline ? '📱' : '⚠️',
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Mode Aktif',
                    style: TextStyle(color: kfc.textMuted, fontSize: 10,
                        fontWeight: FontWeight.w600)),
                Text(AiService.instance.modeLabelShort,
                    style: TextStyle(color: kfc.text, fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ])),
              Icon(Icons.circle,
                color: AiService.instance.currentMode == AiMode.none
                    ? Colors.orange : Colors.green,
                size: 8),
            ]),
          ),

          _group(kfc, [
            // ── AI Online (Puter.js) ────────────────────────────────────────
            _navRow(
              kfc,
              icon: Icons.cloud_rounded,
              label: 'AI Online',
              subtitle: PuterAiService.instance.isEnabled
                  ? 'Aktif — ${PuterAiService.instance.selectedModel?.name ?? 'Pilih model'}'
                  : 'Claude, Gemini, Grok, GPT-4o & 20+ model cloud',
              onTap: () => context.push(KmRoutes.onlineAi),
              trailing: PuterAiService.instance.isEnabled
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF6C5CE7).withValues(alpha: 0.4)),
                      ),
                      child: const Text('ON',
                          style: TextStyle(fontSize: 11, color: Color(0xFF6C5CE7),
                              fontWeight: FontWeight.w700)),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kfc.inputFill,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kfc.border),
                      ),
                      child: Text('OFF',
                          style: TextStyle(fontSize: 11, color: kfc.textMuted,
                              fontWeight: FontWeight.w600)),
                    ),
            ),
            Divider(color: kfc.borderSoft, height: 1, indent: 16, endIndent: 16),

            // ── Setup Puter.js ──────────────────────────────────────────────
            _navRow(
              kfc,
              icon: Icons.settings_ethernet_rounded,
              label: 'Setup Puter.js',
              subtitle: PuterAiService.instance.apiKey.isNotEmpty
                  ? 'API Key terpasang — endpoint & parameter'
                  : 'Atur API Key untuk mengaktifkan AI Online',
              onTap: () => context.push(KmRoutes.puterSetup),
              trailing: PuterAiService.instance.apiKey.isNotEmpty
                  ? Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.check_rounded,
                          color: Colors.green.shade400, size: 14),
                    )
                  : Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.warning_amber_rounded,
                          color: Colors.orange.shade400, size: 14),
                    ),
            ),
            Divider(color: kfc.borderSoft, height: 1, indent: 16, endIndent: 16),

            // ── Bulk API Key ────────────────────────────────────────────────
            _navRow(
              kfc,
              icon: Icons.vpn_key_rounded,
              label: 'Bulk API Key',
              subtitle: BulkApiService.instance.enabled
                  ? 'Aktif — ${BulkApiService.instance.keys.length} key (Groq, Gemini, Claude, dll)'
                  : 'Tambah API key sendiri untuk AI online alternatif',
              onTap: () => context.push(KmRoutes.bulkApiSettings),
              trailing: BulkApiService.instance.enabled
                  ? Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.check_rounded,
                          color: Colors.orange.shade400, size: 14),
                    )
                  : Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: kfc.borderSoft.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.add_rounded,
                          color: kfc.textMuted, size: 14),
                    ),
            ),
            Divider(color: kfc.borderSoft, height: 1, indent: 16, endIndent: 16),

            // ── Persona & Parameter ─────────────────────────────────────────
            _navRow(
              kfc,
              icon: Icons.psychology_rounded,
              label: 'Persona & Parameter AI',
              subtitle: 'Karakter, system prompt, temperature, max tokens',
              onTap: () => context.push(KmRoutes.aiPersona),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${AiPersonaService.instance.activePersona.emoji} ${AiPersonaService.instance.activePersona.name}',
                  style: TextStyle(fontSize: 11,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
            Divider(color: kfc.borderSoft, height: 1, indent: 16, endIndent: 16),

            // ── Terminal ────────────────────────────────────────────────────
            _navRow(
              kfc,
              icon: Icons.terminal_rounded,
              label: 'Terminal',
              subtitle: 'Shell, edit file, download, AI script',
              onTap: () => context.push(KmRoutes.terminal),
            ),
            Divider(color: kfc.borderSoft, height: 1, indent: 16, endIndent: 16),

            // ── Katalog Model ───────────────────────────────────────────────
            _navRow(
              kfc,
              icon: Icons.explore_rounded,
              label: 'Katalog Model AI',
              subtitle: '50+ model — Search, filter, download langsung',
              onTap: () => context.push(KmRoutes.aiCatalog),
            ),
            Divider(color: kfc.borderSoft, height: 1, indent: 16, endIndent: 16),

            // ── Model Manager ───────────────────────────────────────────────
            _navRow(
              kfc,
              icon: Icons.folder_special_rounded,
              label: 'Model Manager',
              subtitle: 'Load model GGUF, TFLite, ONNX dari URL atau file lokal',
              onTap: () => context.push(KmRoutes.modelManager),
            ),
            Divider(color: kfc.borderSoft, height: 1, indent: 16, endIndent: 16),

            // ── AI Offline ──────────────────────────────────────────────────
            _navRow(
              kfc,
              icon: Icons.smart_toy_outlined,
              label: 'AI Offline',
              subtitle: OfflineAiService.instance.isReady
                  ? 'Aktif — Model tersedia di HP'
                  : 'Download/import model GGUF untuk pakai tanpa internet',
              onTap: () => context.push(KmRoutes.offlineAi),
              trailing: OfflineAiService.instance.isReady
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.shade600.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade600.withValues(alpha: 0.3)),
                      ),
                      child: Text('ON',
                          style: TextStyle(fontSize: 11,
                              color: Colors.green.shade400,
                              fontWeight: FontWeight.w700)),
                    )
                  : null,
            ),
            Divider(color: kfc.borderSoft, height: 1, indent: 16, endIndent: 16),
          ]),

          // ── AI & MODEL (section baru Sesi 5) ──────────────────────────────────
          _sectionLabel('AI & MODEL', kfc),

          // Status model aktif + navigasi ke model manager
          Consumer(builder: (context, ref, _) {
            final model = ref.watch(activeModelInfoProvider);
            return _group(kfc, [
              InkWell(
                onTap: () => context.push(KmRoutes.modelManager),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: (model != null ? Colors.green : kfc.textMuted).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.memory_rounded, size: 20, color: model != null ? Colors.green : kfc.textMuted),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Model Aktif', style: TextStyle(color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(model?.name ?? 'Belum ada model yang dipilih',
                          style: TextStyle(color: kfc.textMuted, fontSize: 12), overflow: TextOverflow.ellipsis),
                    ])),
                    if (model != null)
                      Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6),
                          decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                    Icon(Icons.chevron_right_rounded, color: kfc.textMuted, size: 20),
                  ]),
                ),
              ),
              Divider(color: kfc.borderSoft, height: 1, indent: 16, endIndent: 16),
              // Navigasi ke Pengaturan AI Lokal
              _navRow(kfc,
                icon: Icons.tune_rounded,
                label: 'Pengaturan AI Lokal',
                subtitle: 'Parameter inferensi, context size, GPU',
                onTap: () => context.push(KmRoutes.offlineAi),
              ),
              Divider(color: kfc.borderSoft, height: 1, indent: 16, endIndent: 16),
              // Navigasi ke halaman unduh model
              _navRow(kfc,
                icon: Icons.download_rounded,
                label: 'Unduh Model',
                subtitle: 'Browse & download model dari HuggingFace',
                onTap: () => context.push(KmRoutes.modelManager),
              ),
            ]);
          }),

          const SizedBox(height: 8),

          // Quick Temperature Slider — pengaturan cepat tanpa masuk ke screen lain
          Consumer(builder: (context, ref, _) {
            final config = ref.watch(inferenceConfigProvider);
            return Container(
              decoration: BoxDecoration(
                color: kfc.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kfc.border),
              ),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: kfc.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.thermostat_rounded, size: 20, color: kfc.accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Temperature', style: TextStyle(color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text('${config.temperature.toStringAsFixed(2)} — kreativitas respons AI',
                          style: TextStyle(color: kfc.textMuted, fontSize: 12)),
                    ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kfc.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: kfc.border),
                      ),
                      child: Text(config.temperature.toStringAsFixed(2),
                          style: TextStyle(color: kfc.accent, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ]),
                ),
                Slider(
                  value: config.temperature,
                  min: 0.0, max: 2.0, divisions: 200,
                  activeColor: kfc.accent,
                  onChanged: (v) => ref.read(inferenceConfigProvider.notifier).updateTemperature(v),
                ),
              ]),
            );
          }),

          const SizedBox(height: 20),


          // ── TENTANG ───────────────────────────────────────────────────────
          _sectionLabel('TENTANG', kfc),
          _group(kfc, [
            _infoRow(kfc, label: 'Versi Aplikasi', value: '1.0.0'),
            Divider(color: kfc.borderSoft, height: 1, indent: 16, endIndent: 16),
            _infoRow(kfc, label: 'Developer', value: 'KanMon GO Team'),
            Divider(color: kfc.borderSoft, height: 1, indent: 16, endIndent: 16),
            _infoRow(kfc, label: 'Mode Warna', value: 'Hitam & Putih'),
          ]),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _sectionLabel(String label, KmColors kfc) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(label,
        style: TextStyle(color: kfc.textMuted, fontSize: 11,
            fontWeight: FontWeight.w700, letterSpacing: 1.2)),
  );

  Widget _group(KmColors kfc, List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: kfc.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: kfc.border, width: 1),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: children),
  );

  Widget _sfxRow(KmColors kfc, bool sfxEnabled) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(children: [
      Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: kfc.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kfc.border),
        ),
        child: Icon(
          sfxEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          color: kfc.accent, size: 22),
      ),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Text('Efek Suara (SFX)', style: TextStyle(
            color: kfc.text, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          sfxEnabled
              ? 'Aktif — Suara tombol & jawaban quiz'
              : 'Nonaktif — Tanpa efek suara',
          style: TextStyle(color: kfc.textMuted, fontSize: 12)),
      ])),
      GestureDetector(
        onTap: () {
          SfxService.instance.play(Sfx.tap);
          ref.read(sfxProvider.notifier).toggle();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 52, height: 28,
          decoration: BoxDecoration(
            color: sfxEnabled ? kfc.accent : kfc.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kfc.border),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 250),
            alignment: sfxEnabled ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 22, height: 22,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: sfxEnabled ? kfc.bg : kfc.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    ]),
  );

  Widget _darkModeRow(KmColors kfc, bool isDark) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(children: [
      Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: kfc.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kfc.border),
        ),
        child: Icon(
          isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
          color: kfc.accent, size: 22),
      ),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Text('Mode Gelap', style: TextStyle(
            color: kfc.text, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          isDark
              ? 'Aktif — Latar hitam, teks putih'
              : 'Nonaktif — Latar putih, teks hitam',
          style: TextStyle(color: kfc.textMuted, fontSize: 12)),
      ])),
      GestureDetector(
        onTap: () => ref.read(themeProvider.notifier).toggle(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 52, height: 28,
          decoration: BoxDecoration(
            color: isDark ? kfc.accent : kfc.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kfc.border),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 250),
            alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 22, height: 22,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: isDark ? kfc.bg : kfc.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    ]),
  );

  Widget _switchRow(KmColors kfc, {
    required String label, required String subtitle,
    required bool value, required ValueChanged<bool> onChanged,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Text(label, style: TextStyle(
            color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(color: kfc.textMuted, fontSize: 12)),
      ])),
      Switch(value: value, onChanged: onChanged),
    ]),
  );

  Widget _sliderRow(KmColors kfc, {
    required String label, required double value,
    required double min,   required double max,
    required ValueChanged<double> onChanged, required String valueLabel,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(
            color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: kfc.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kfc.border),
          ),
          child: Text(valueLabel, style: TextStyle(
              color: kfc.accent, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ]),
      Slider(value: value, min: min, max: max, onChanged: onChanged),
    ]),
  );

  Widget _infoRow(KmColors kfc, {
    required String label, required String value,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(color: kfc.text, fontSize: 14)),
      Text(value,  style: TextStyle(color: kfc.textMuted, fontSize: 14)),
    ]),
  );

  Widget _navRow(KmColors kfc, {
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20,
              color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(
                color: kfc.text, fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(
                color: kfc.textMuted, fontSize: 12)),
          ]),
        ),
        trailing ?? Icon(Icons.chevron_right_rounded,
            color: kfc.textMuted, size: 20),
      ]),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// _WallpaperSection — Picker foto/video wallpaper
// ═══════════════════════════════════════════════════════════════════════════

class _WallpaperSection extends ConsumerWidget {
  final KmColors kfc;
  const _WallpaperSection({required this.kfc});

  Future<void> _pickPhoto(BuildContext ctx, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    final cfg = ref.read(wallpaperProvider).copyWith(
      type: WallpaperType.photo,
      path: path,
    );
    await ref.read(wallpaperProvider.notifier).set(cfg);

    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: const Text('Wallpaper foto berhasil dipasang ✓'),
        backgroundColor: KmColors.of(ctx).accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Future<void> _pickVideo(BuildContext ctx, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    final cfg = ref.read(wallpaperProvider).copyWith(
      type: WallpaperType.video,
      path: path,
    );
    await ref.read(wallpaperProvider.notifier).set(cfg);

    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: const Text('Wallpaper video berhasil dipasang ✓'),
        backgroundColor: KmColors.of(ctx).accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Future<void> _remove(BuildContext ctx, WidgetRef ref) async {
    await ref.read(wallpaperProvider.notifier).clear();
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: const Text('Wallpaper dihapus'),
        backgroundColor: KmColors.of(ctx).card,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(wallpaperProvider);
    final active = cfg.isActive;

    return Container(
      decoration: BoxDecoration(
        color: kfc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kfc.border),
      ),
      child: Column(children: [

        // ── Preview / Status ───────────────────────────────────────────────
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: SizedBox(
            height: 120,
            width: double.infinity,
            child: active
                ? _WallpaperPreview(cfg: cfg)
                : Container(
                    color: kfc.surface,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.wallpaper_rounded, size: 36, color: kfc.textMuted),
                      const SizedBox(height: 8),
                      Text('Belum ada wallpaper',
                          style: TextStyle(color: kfc.textMuted, fontSize: 13)),
                    ]),
                  ),
          ),
        ),

        // ── Status badge ──────────────────────────────────────────────────
        if (active) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: kfc.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kfc.accent.withValues(alpha: 0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(cfg.isVideo ? Icons.videocam_rounded : Icons.image_rounded,
                      size: 13, color: kfc.accent),
                  const SizedBox(width: 4),
                  Text(cfg.isVideo ? 'Video Live' : 'Foto',
                      style: TextStyle(color: kfc.accent, fontSize: 11, fontWeight: FontWeight.bold)),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cfg.path.split('/').last,
                  style: TextStyle(color: kfc.textMuted, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),

          // ── Opacity slider ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Kegelapan overlay',
                    style: TextStyle(color: kfc.textSub, fontSize: 13, fontWeight: FontWeight.w500)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: kfc.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${(cfg.opacity * 100).round()}%',
                      style: TextStyle(color: kfc.accent, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ]),
              Slider(
                value: cfg.opacity,
                min: 0.0, max: 0.85,
                divisions: 17,
                activeColor: kfc.accent,
                onChanged: (v) => ref.read(wallpaperProvider.notifier).setOpacity(v),
              ),
            ]),
          ),

          // ── Blur slider (foto saja) ────────────────────────────────────
          if (cfg.isPhoto)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Blur',
                      style: TextStyle(color: kfc.textSub, fontSize: 13, fontWeight: FontWeight.w500)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: kfc.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${cfg.blur.round()}px',
                        style: TextStyle(color: kfc.accent, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ]),
                Slider(
                  value: cfg.blur,
                  min: 0.0, max: 10.0,
                  divisions: 10,
                  activeColor: kfc.accent,
                  onChanged: (v) => ref.read(wallpaperProvider.notifier).setBlur(v),
                ),
              ]),
            ),

          // ── Kecepatan video (video saja) ───────────────────────────────
          if (cfg.isVideo) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Kecepatan Video',
                      style: TextStyle(color: kfc.textSub, fontSize: 13, fontWeight: FontWeight.w500)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: kfc.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${cfg.playbackSpeed.toStringAsFixed(2)}×',
                        style: TextStyle(color: kfc.accent, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ]),
                Slider(
                  value: cfg.playbackSpeed,
                  min: 0.25, max: 2.0,
                  divisions: 7,
                  activeColor: kfc.accent,
                  onChanged: (v) => ref.read(wallpaperProvider.notifier).setSpeed(v),
                ),
              ]),
            ),
            // ── Mute toggle ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Icon(cfg.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    size: 18, color: kfc.textSub),
                const SizedBox(width: 8),
                Text('Suara Video',
                    style: TextStyle(color: kfc.textSub, fontSize: 13, fontWeight: FontWeight.w500)),
                const Spacer(),
                Switch(
                  value: !cfg.muted,
                  activeColor: kfc.accent,
                  onChanged: (v) => ref.read(wallpaperProvider.notifier).setMuted(!v),
                ),
              ]),
            ),
          ],
        ],

        // ── Tombol aksi ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(children: [
            // Pilih Foto
            Expanded(
              child: _ActionBtn(
                icon: Icons.image_rounded,
                label: 'Foto',
                color: kfc.accent,
                onTap: () => _pickPhoto(context, ref),
              ),
            ),
            const SizedBox(width: 8),
            // Pilih Video
            Expanded(
              child: _ActionBtn(
                icon: Icons.videocam_rounded,
                label: 'Video',
                color: kfc.accent,
                onTap: () => _pickVideo(context, ref),
              ),
            ),
            if (active) ...[
              const SizedBox(width: 8),
              // Hapus
              _ActionBtn(
                icon: Icons.delete_outline_rounded,
                label: 'Hapus',
                color: const Color(0xFFDC2626),
                onTap: () => _remove(context, ref),
              ),
            ],
          ]),
        ),

        // ── Info teks ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Wallpaper aktif di semua layar menu utama (Home, Kana, Kanji, Kosakata, Bunpou, Partikel, Writing, Flashcard, Catatan, Mensetsu, Ebook, Riwayat, Profil, Pengaturan).',
              style: TextStyle(color: kfc.textMuted, fontSize: 11, height: 1.5),
            ),
            const SizedBox(height: 4),
            Text(
              'Wallpaper otomatis NONAKTIF saat kamu mengerjakan soal (Quiz, Writing Quiz, Flashcard Deck) agar tidak mengganggu konsentrasi.',
              style: TextStyle(color: kfc.accent.withValues(alpha: 0.8), fontSize: 11, height: 1.5),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Preview thumbnail ─────────────────────────────────────────────────────────
class _WallpaperPreview extends StatefulWidget {
  final WallpaperConfig cfg;
  const _WallpaperPreview({required this.cfg});

  @override
  State<_WallpaperPreview> createState() => _WallpaperPreviewState();
}

class _WallpaperPreviewState extends State<_WallpaperPreview> {
  VideoPlayerController? _ctrl;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.cfg.isVideo) _initVideo(widget.cfg.path);
  }

  @override
  void didUpdateWidget(_WallpaperPreview old) {
    super.didUpdateWidget(old);
    if (old.cfg.path != widget.cfg.path || old.cfg.type != widget.cfg.type) {
      _ctrl?.dispose();
      _videoReady = false;
      if (widget.cfg.isVideo) _initVideo(widget.cfg.path);
    }
  }

  Future<void> _initVideo(String path) async {
    final ctrl = VideoPlayerController.file(File(path));
    try {
      await ctrl.initialize();
      ctrl.setLooping(true);
      ctrl.setVolume(0);
      ctrl.play();
      if (mounted) setState(() { _ctrl = ctrl; _videoReady = true; });
    } catch (_) {
      ctrl.dispose();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kfc = KmColors.of(context);
    return Stack(fit: StackFit.expand, children: [
      // Background: foto atau video player
      if (widget.cfg.isPhoto)
        Image.file(File(widget.cfg.path), fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: kfc.surface))
      else if (_videoReady && _ctrl != null)
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width:  _ctrl!.value.size.width,
            height: _ctrl!.value.size.height,
            child:  VideoPlayer(_ctrl!),
          ),
        )
      else
        Container(
          color: kfc.surface,
          child: Center(child: Icon(Icons.videocam_rounded, size: 40, color: kfc.accent)),
        ),

      // Overlay kegelapan sesuai pengaturan
      Container(color: Colors.black.withValues(alpha: widget.cfg.opacity * 0.6)),

      // Badge status
      Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              widget.cfg.isVideo
                  ? (_videoReady ? Icons.play_circle_outline_rounded : Icons.hourglass_bottom_rounded)
                  : Icons.check_circle_outline_rounded,
              size: 16, color: Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              widget.cfg.isVideo
                  ? (_videoReady ? 'Video live aktif ✓' : 'Memuat video...')
                  : 'Foto wallpaper aktif ✓',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ]),
        ),
      ),
    ]);
  }
}

// ── Tombol aksi kecil ─────────────────────────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final kfc = KmColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}
