// lib/features/settings/presentation/screens/puter_setup_screen.dart
// Pocket Harness — Setup Puter.js
// Konfigurasi API key, endpoint, parameter, dan test koneksi
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pocketharness/core/theme/km_colors.dart';
import 'package:pocketharness/data/services/puter_ai_service.dart';
import 'package:pocketharness/data/services/bulk_api_service.dart';
import 'package:pocketharness/data/services/ai_source_settings_service.dart';
import 'package:pocketharness/shared/utils/top_snack.dart';

class PuterSetupScreen extends StatefulWidget {
  const PuterSetupScreen({super.key});
  @override
  State<PuterSetupScreen> createState() => _PuterSetupScreenState();
}

class _PuterSetupScreenState extends State<PuterSetupScreen> {
  final _svc = PuterAiService.instance;
  final _bulk = BulkApiService.instance;

  final _apiKeyCtrl  = TextEditingController();
  final _baseUrlCtrl = TextEditingController();

  bool   _obscureKey    = true;
  bool   _testing       = false;
  bool?  _testResult;   // null=belum, true=OK, false=FAIL
  String _testMessage   = '';
  double _temperature   = 0.7;
  int    _maxTokens     = 1024;
  bool   _streamMode    = true;
  bool   _enabled       = false;
  bool   _saving        = false;

  // Bulk API state
  BulkApiProvider _bulkProvider = BulkApiProvider.groq;
  final _bulkKeyCtrl   = TextEditingController();
  final _bulkLabelCtrl = TextEditingController();
  final _bulkUrlCtrl   = TextEditingController();
  final _bulkModelCtrl = TextEditingController();
  bool _bulkTesting    = false;
  String _bulkTestMsg  = '';

  @override
  void initState() {
    super.initState();
    _svc.loadSettings().then((_) {
      if (!mounted) return;
      if (mounted) setState(() {
        _apiKeyCtrl.text  = _svc.apiKey;
        _baseUrlCtrl.text = _svc.baseUrl;
        _temperature      = _svc.temperature;
        _maxTokens        = _svc.maxTokens;
        _streamMode       = _svc.streamMode;
        _enabled          = _svc.isEnabled;
      });
    });
    _bulk.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _baseUrlCtrl.dispose();
    _bulkKeyCtrl.dispose();
    _bulkLabelCtrl.dispose();
    _bulkUrlCtrl.dispose();
    _bulkModelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (mounted) setState(() => _saving = true);
    await _svc.saveSettings(
      enabled:       _enabled,
      apiKey:        _apiKeyCtrl.text.trim(),
      baseUrl:       _baseUrlCtrl.text.trim().isEmpty
          ? 'https://api.puter.com/puterai/openai/v1/chat/completions'
          : _baseUrlCtrl.text.trim(),
      maxTokens:     _maxTokens,
      temperature:   _temperature,
      streamMode:    _streamMode,
    );
    // Sinkronisasi balik ke AiSourceSettingsService agar picker ikut update
    await AiSourceSettingsService.instance.pullOnlineFromService();
    if (mounted) setState(() => _saving = false);
    if (mounted) {
      showTopSnack(context, '✅ Pengaturan tersimpan');
    }
  }

  Future<void> _testConnection() async {
    if (mounted) setState(() { _testing = true; _testResult = null; _testMessage = ''; });
    try {
      final ok = await _svc.testConnection();
      if (mounted) {
        if (mounted) setState(() {
          _testing = false;
          _testResult = ok;
          _testMessage = ok ? 'Koneksi berhasil! API key valid.' : 'Koneksi gagal. Periksa API key.';
        });
      }
    } catch (e) {
      if (mounted) {
        if (mounted) setState(() { _testing = false; _testResult = false; _testMessage = 'Error: $e'; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final kfc = KmColors.of(context);
    return Scaffold(
      backgroundColor: kfc.bg,
      appBar: AppBar(
        backgroundColor: kfc.surface,
        foregroundColor: kfc.text,
        elevation: 0,
        title: const Text('Setup Puter.js',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Enable toggle ─────────────────────────────────────────────
            _card(kfc, child: Row(children: [
              Icon(Icons.cloud_rounded, color: kfc.accent, size: 24),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Aktifkan Puter.js AI',
                    style: TextStyle(color: kfc.text, fontWeight: FontWeight.w700, fontSize: 14)),
                Text('Gunakan AI online via Puter.js sebagai sumber',
                    style: TextStyle(color: kfc.textMuted, fontSize: 11)),
              ])),
              Switch(
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                activeColor: const Color(0xFF6C5CE7),
              ),
            ])),

            const SizedBox(height: 20),

            // ── API Key ───────────────────────────────────────────────────
            _sectionLabel('API KEY PUTER.JS', kfc),
            _card(kfc, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: _apiKeyCtrl,
                obscureText: _obscureKey,
                style: TextStyle(color: kfc.text, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Masukkan API key Puter.js...',
                  hintStyle: TextStyle(color: kfc.textMuted, fontSize: 12),
                  labelText: 'API Key',
                  labelStyle: TextStyle(color: kfc.textSub),
                  prefixIcon: Icon(Icons.key_rounded, color: kfc.textMuted, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureKey ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        color: kfc.textMuted, size: 20),
                    onPressed: () => setState(() => _obscureKey = !_obscureKey),
                  ),
                  filled: true,
                  fillColor: kfc.inputFill,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: kfc.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: kfc.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF6C5CE7), width: 1.5)),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null && mounted) {
                      if (mounted) setState(() => _apiKeyCtrl.text = data!.text!.trim());
                      showTopSnack(context, '✅ Key ditempel dari clipboard');
                    }
                  },
                  icon: const Icon(Icons.paste_rounded, size: 16),
                  label: const Text('Tempel dari Clipboard'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kfc.textSub,
                    side: BorderSide(color: kfc.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                )),
              ]),
            ])),

          const SizedBox(height: 20),

          // ── Base URL (advanced) ──────────────────────────────────────────
          _sectionLabel('ENDPOINT (OPSIONAL)', kfc),
          _card(kfc, child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('Biarkan kosong untuk menggunakan endpoint default Puter.js.',
                style: TextStyle(color: kfc.textSub, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: _baseUrlCtrl,
              style: TextStyle(color: kfc.text, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'https://api.puter.com/puterai/openai/v1/chat/completions',
                hintStyle: TextStyle(color: kfc.textMuted, fontSize: 12),
                labelText: 'Base URL',
                labelStyle: TextStyle(color: kfc.textSub),
                prefixIcon: Icon(Icons.link_rounded, color: kfc.textMuted, size: 20),
                filled: true,
                fillColor: kfc.inputFill,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: kfc.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: kfc.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: Color(0xFF6C5CE7), width: 1.5)),
              ),
            ),
          ])),

          const SizedBox(height: 20),

          // ── Parameter ────────────────────────────────────────────────────
          _sectionLabel('PARAMETER MODEL', kfc),
          _card(kfc, child: Column(children: [
            // Temperature
            Row(children: [
              Icon(Icons.thermostat_rounded, color: kfc.accent, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Temperature',
                  style: TextStyle(color: kfc.text, fontWeight: FontWeight.w600,
                      fontSize: 14))),
              Text(_temperature.toStringAsFixed(1),
                  style: TextStyle(color: kfc.accent, fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ]),
            const SizedBox(height: 2),
            Text('Rendah = fokus/deterministik, Tinggi = kreatif/beragam',
                style: TextStyle(color: kfc.textMuted, fontSize: 11)),
            Slider(
              value: _temperature,
              min: 0.0, max: 2.0, divisions: 20,
              activeColor: const Color(0xFF6C5CE7),
              onChanged: (v) => setState(() => _temperature = v),
            ),
            const SizedBox(height: 8),
            Divider(color: kfc.borderSoft),
            const SizedBox(height: 8),

            // Max tokens
            Row(children: [
              Icon(Icons.token_outlined, color: kfc.accent, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Max Tokens',
                  style: TextStyle(color: kfc.text, fontWeight: FontWeight.w600,
                      fontSize: 14))),
              Text('$_maxTokens',
                  style: TextStyle(color: kfc.accent, fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ]),
            const SizedBox(height: 2),
            Text('Panjang maksimal respons AI',
                style: TextStyle(color: kfc.textMuted, fontSize: 11)),
            Slider(
              value: _maxTokens.toDouble(),
              min: 256, max: 4096, divisions: 15,
              activeColor: const Color(0xFF6C5CE7),
              onChanged: (v) => setState(() => _maxTokens = v.round()),
            ),
            const SizedBox(height: 8),
            Divider(color: kfc.borderSoft),
            const SizedBox(height: 8),

            // Stream mode
            Row(children: [
              Icon(Icons.stream_rounded, color: kfc.accent, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Mode Streaming',
                    style: TextStyle(color: kfc.text, fontWeight: FontWeight.w600,
                        fontSize: 14)),
                Text('Tampilkan respons kata per kata (lebih responsif)',
                    style: TextStyle(color: kfc.textMuted, fontSize: 11)),
              ])),
              Switch(
                value: _streamMode,
                onChanged: (v) => setState(() => _streamMode = v),
                activeColor: const Color(0xFF6C5CE7),
              ),
            ]),
          ])),

          const SizedBox(height: 20),

          // ── Test koneksi ─────────────────────────────────────────────────
          _sectionLabel('TEST KONEKSI', kfc),
          _card(kfc, child: Column(children: [
            if (_testResult != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testResult!
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _testResult!
                          ? Colors.green.withValues(alpha: 0.3)
                          : Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  Text(_testResult! ? '✅' : '❌',
                      style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_testMessage,
                      style: TextStyle(
                          color: _testResult!
                              ? Colors.green.shade400
                              : Colors.red.shade400,
                          fontSize: 13))),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.wifi_tethering_rounded, size: 18),
                label: Text(_testing ? 'Menguji...' : 'Test Koneksi Sekarang'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C5CE7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ])),

          const SizedBox(height: 20),

          // ── Info Puter.js ─────────────────────────────────────────────────
          _sectionLabel('TENTANG PUTER.JS', kfc),
          _card(kfc, child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            _infoRow('🌐', 'Website', 'puter.com', kfc),
            Divider(color: kfc.borderSoft, height: 20),
            _infoRow('📄', 'Dokumentasi', 'docs.puter.com', kfc),
            Divider(color: kfc.borderSoft, height: 20),
            _infoRow('🆓', 'Harga', 'Gratis untuk akses dasar', kfc),
            Divider(color: kfc.borderSoft, height: 20),
            _infoRow('🔒', 'Keamanan', 'API key terenkripsi di perangkat', kfc),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Puter.js adalah platform cloud open-source yang menyediakan '
                'akses ke berbagai model AI premium. API key disimpan lokal di '
                'perangkat kamu dan tidak dikirim ke server Pocket Harness.',
                style: TextStyle(color: kfc.textSub, fontSize: 12, height: 1.5),
              ),
            ),
          ])),

          const SizedBox(height: 28),

          // ═══════════════════════════════════════════════════════════════════
          // BULK API KEY MANAGER
          // ═══════════════════════════════════════════════════════════════════
          _sectionLabel('BULK API KEY MANAGER', kfc),

          _card(kfc, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header + enable toggle
            Row(children: [
              const Text('🗝️', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Bulk API Key', style: TextStyle(color: kfc.text, fontSize: 14, fontWeight: FontWeight.w700)),
                Text('Kelola banyak API key dari berbagai AI provider', style: TextStyle(color: kfc.textMuted, fontSize: 11)),
              ])),
              Switch(
                value: _bulk.enabled,
                onChanged: (v) async {
                  await _bulk.setEnabled(v);
                  if (mounted) setState(() {});
                },
                activeColor: const Color(0xFF6C5CE7),
              ),
            ]),

            if (_bulk.enabled) ...[
              const SizedBox(height: 16),
              Divider(color: kfc.borderSoft),
              const SizedBox(height: 12),

              // Mode selection
              Text('Mode Load Key', style: TextStyle(color: kfc.textSub, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(children: BulkLoadMode.values.map((m) {
                final sel = _bulk.mode == m;
                return Expanded(child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () async {
                      await _bulk.setMode(m);
                      if (mounted) setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFF6C5CE7) : kfc.borderSoft.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: sel ? const Color(0xFF6C5CE7) : kfc.borderSoft),
                      ),
                      child: Column(children: [
                        Text(m.label, style: TextStyle(color: sel ? Colors.white : kfc.text, fontSize: 11, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ));
              }).toList()),
              const SizedBox(height: 4),
              Text(_bulk.mode.description, style: TextStyle(color: kfc.textMuted, fontSize: 10)),

              const SizedBox(height: 16),
              Divider(color: kfc.borderSoft),
              const SizedBox(height: 12),

              // Provider selector
              Text('Provider', style: TextStyle(color: kfc.textSub, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: BulkApiProvider.values.map((p) {
                  final sel = _bulkProvider == p;
                  final count = _bulk.keysForProvider(p).length;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _bulkProvider = p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: sel ? const Color(0xFF6C5CE7).withValues(alpha: 0.15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: sel ? const Color(0xFF6C5CE7) : kfc.borderSoft,
                            width: sel ? 1.5 : 1,
                          ),
                        ),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(p.emoji, style: const TextStyle(fontSize: 16)),
                          Text(p.label.split(' ').first, style: TextStyle(
                            color: sel ? const Color(0xFF6C5CE7) : kfc.textSub,
                            fontSize: 10, fontWeight: FontWeight.w600,
                          )),
                          if (count > 0) Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C5CE7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 9)),
                          ),
                          if (p.isFree) Text('FREE', style: TextStyle(color: Colors.green.shade600, fontSize: 8, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                  );
                }).toList()),
              ),

              const SizedBox(height: 16),

              // Form tambah key baru
              Text('Tambah API Key — ${_bulkProvider.label}', style: TextStyle(color: kfc.textSub, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),

              // API Key input
              TextField(
                controller: _bulkKeyCtrl,
                style: TextStyle(color: kfc.text, fontSize: 13),
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  labelStyle: TextStyle(color: kfc.textMuted, fontSize: 12),
                  prefixIcon: const Icon(Icons.vpn_key_rounded, size: 18, color: Color(0xFF6C5CE7)),
                  filled: true,
                  fillColor: kfc.borderSoft.withValues(alpha: 0.2),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 8),

              // Label input
              TextField(
                controller: _bulkLabelCtrl,
                style: TextStyle(color: kfc.text, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Label (opsional)',
                  labelStyle: TextStyle(color: kfc.textMuted, fontSize: 12),
                  prefixIcon: const Icon(Icons.label_rounded, size: 18, color: Color(0xFF6C5CE7)),
                  filled: true,
                  fillColor: kfc.borderSoft.withValues(alpha: 0.2),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),

              // Custom URL & model untuk custom provider
              if (_bulkProvider == BulkApiProvider.custom) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _bulkUrlCtrl,
                  style: TextStyle(color: kfc.text, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Base URL (misal: https://api.custom.com/v1/chat/completions)',
                    labelStyle: TextStyle(color: kfc.textMuted, fontSize: 11),
                    prefixIcon: const Icon(Icons.link_rounded, size: 18, color: Color(0xFF6C5CE7)),
                    filled: true,
                    fillColor: kfc.borderSoft.withValues(alpha: 0.2),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ],

              // Model override (opsional untuk semua provider)
              const SizedBox(height: 8),
              TextField(
                controller: _bulkModelCtrl,
                style: TextStyle(color: kfc.text, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Model (opsional, default: ${_bulkProvider.defaultModel})',
                  labelStyle: TextStyle(color: kfc.textMuted, fontSize: 11),
                  prefixIcon: const Icon(Icons.memory_rounded, size: 18, color: Color(0xFF6C5CE7)),
                  filled: true,
                  fillColor: kfc.borderSoft.withValues(alpha: 0.2),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),

              const SizedBox(height: 10),
              if (_bulkProvider.getKeyUrl.isNotEmpty)
                GestureDetector(
                  onTap: () => Clipboard.setData(ClipboardData(text: _bulkProvider.getKeyUrl)),
                  child: Row(children: [
                    Icon(Icons.open_in_new_rounded, size: 14, color: const Color(0xFF6C5CE7)),
                    const SizedBox(width: 4),
                    Text('Dapatkan API Key gratis: ${_bulkProvider.getKeyUrl}',
                      style: const TextStyle(color: Color(0xFF6C5CE7), fontSize: 11, decoration: TextDecoration.underline),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ]),
                ),

              const SizedBox(height: 12),

              // Tombol Tambah Key
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final key = _bulkKeyCtrl.text.trim();
                    if (key.isEmpty) {
                      showTopSnack(context, 'API Key tidak boleh kosong', isError: true);
                      return;
                    }
                    await _bulk.addKey(
                      provider: _bulkProvider,
                      apiKey: key,
                      label: _bulkLabelCtrl.text.trim(),
                      customUrl: _bulkUrlCtrl.text.trim(),
                      customModel: _bulkModelCtrl.text.trim(),
                    );
                    _bulkKeyCtrl.clear();
                    _bulkLabelCtrl.clear();
                    _bulkUrlCtrl.clear();
                    _bulkModelCtrl.clear();
                    if (mounted) setState(() {});
                    if (mounted) showTopSnack(context, '✅ API Key berhasil ditambahkan');
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Tambah Key', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C5CE7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),

              // Daftar key untuk provider yang dipilih
              const SizedBox(height: 16),
              ..._buildKeyList(kfc),

              // Statistik semua key
              const SizedBox(height: 12),
              if (_bulk.keys.isNotEmpty) ...[
                Divider(color: kfc.borderSoft),
                const SizedBox(height: 8),
                Row(children: [
                  _statChip('Total', '${_bulk.keys.length}', Colors.blue, kfc),
                  const SizedBox(width: 6),
                  _statChip('Aktif', '${_bulk.keys.where((k) => k.canUse).length}', Colors.green, kfc),
                  const SizedBox(width: 6),
                  _statChip('Limit', '${_bulk.keys.where((k) => k.isLimitReached && !k.isLimitExpired).length}', Colors.red, kfc),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () async {
                      await _bulk.resetAllLimits();
                      if (mounted) setState(() {});
                      if (mounted) showTopSnack(context, '✅ Semua limit di-reset');
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text('Reset Limit', style: TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF6C5CE7)),
                  ),
                ]),
              ],
            ],
          ])),

          const SizedBox(height: 20),

          // ── Save button besar ─────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C5CE7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white))
                  : const Text('Simpan Pengaturan',
                      style: TextStyle(fontWeight: FontWeight.bold,
                          fontSize: 15)),
            ),
          ),
        ],
      ),
    ),
  );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _card(KmColors kfc, {required Widget child}) => Container(
    margin: const EdgeInsets.only(bottom: 0),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: kfc.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: kfc.border),
    ),
    child: child,
  );

  Widget _sectionLabel(String label, KmColors kfc) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label,
        style: TextStyle(color: kfc.textMuted, fontSize: 11,
            fontWeight: FontWeight.w700, letterSpacing: 0.8)),
  );

  Widget _featureChip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label,
        style: const TextStyle(color: Colors.white, fontSize: 12,
            fontWeight: FontWeight.w600)),
  );

  Widget _stepRow(String num, String text, KmColors kfc) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          color: const Color(0xFF6C5CE7).withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Center(child: Text(num,
            style: const TextStyle(color: Color(0xFF6C5CE7), fontSize: 11,
                fontWeight: FontWeight.w700))),
      ),
      const SizedBox(width: 8),
      Text(text, style: TextStyle(color: kfc.textSub, fontSize: 12)),
    ]),
  );

  Widget _infoRow(String emoji, String label, String value, KmColors kfc) =>
      Row(children: [
    Text(emoji, style: const TextStyle(fontSize: 16)),
    const SizedBox(width: 10),
    Text(label,
        style: TextStyle(color: kfc.textSub, fontSize: 13,
            fontWeight: FontWeight.w500)),
    const Spacer(),
    Text(value,
        style: TextStyle(color: kfc.text, fontSize: 13,
            fontWeight: FontWeight.w600)),
  ]);

  // ── Bulk API helpers ──────────────────────────────────────────────────────
  List<Widget> _buildKeyList(KmColors kfc) {
    final keys = _bulk.keysForProvider(_bulkProvider);
    if (keys.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kfc.borderSoft.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            const Text('🔑', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Text('Belum ada key untuk ${_bulkProvider.label}',
              style: TextStyle(color: kfc.textMuted, fontSize: 12)),
          ]),
        ),
      ];
    }
    return keys.map((key) => _buildKeyTile(key, kfc)).toList();
  }

  Widget _buildKeyTile(BulkApiKey key, KmColors kfc) {
    final isSelected = _bulk.mode == BulkLoadMode.select && _bulk.selectedKeyId == key.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF6C5CE7).withValues(alpha: 0.08)
            : kfc.borderSoft.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? const Color(0xFF6C5CE7) : kfc.borderSoft,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(key.statusEmoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(key.displayLabel,
              style: TextStyle(color: kfc.text, fontSize: 13, fontWeight: FontWeight.w600)),
            Text(
              key.isLimitReached && !key.isLimitExpired
                  ? '🔴 Rate limited — auto-reset 1 jam'
                  : '✅ ${key.successCount} sukses · ❌ ${key.failCount} gagal',
              style: TextStyle(color: kfc.textMuted, fontSize: 10),
            ),
          ])),
          // Select button (mode select)
          if (_bulk.mode == BulkLoadMode.select)
            GestureDetector(
              onTap: () async {
                await _bulk.setSelectedKey(key.id);
                if (mounted) setState(() {});
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF6C5CE7) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF6C5CE7)),
                ),
                child: Text(isSelected ? 'Aktif' : 'Pilih',
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF6C5CE7),
                    fontSize: 11, fontWeight: FontWeight.w700,
                  )),
              ),
            ),
          const SizedBox(width: 6),
          // Test button
          GestureDetector(
            onTap: _bulkTesting ? null : () async {
              if (mounted) setState(() { _bulkTesting = true; _bulkTestMsg = ''; });
              final result = await _bulk.testKey(key);
              if (mounted) setState(() {
                _bulkTesting = false;
                _bulkTestMsg = result.success ? '✅ ${key.displayLabel}: OK' : '❌ ${result.error ?? 'Failed'}';
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Test', style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 6),
          // Delete button
          GestureDetector(
            onTap: () async {
              await _bulk.removeKey(key.id);
              if (mounted) setState(() {});
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red),
            ),
          ),
          // Active toggle
          Switch(
            value: key.isActive,
            onChanged: (v) async {
              key.isActive = v;
              await _bulk.updateKey(key);
              if (mounted) setState(() {});
            },
            activeColor: const Color(0xFF6C5CE7),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ]),
        if (_bulkTestMsg.isNotEmpty && _bulkTestMsg.contains(key.displayLabel)) ...[
          const SizedBox(height: 6),
          Text(_bulkTestMsg, style: TextStyle(
            color: _bulkTestMsg.startsWith('✅') ? Colors.green : Colors.red,
            fontSize: 11,
          )),
        ],
      ]),
    );
  }

  Widget _statChip(String label, String value, Color color, KmColors kfc) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: RichText(text: TextSpan(children: [
        TextSpan(text: value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800)),
        TextSpan(text: ' $label', style: TextStyle(color: kfc.textMuted, fontSize: 10)),
      ])),
    );
}
