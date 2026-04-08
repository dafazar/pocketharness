// lib/features/settings/presentation/screens/bulk_api_settings_screen.dart
// KanMon GO — Bulk API Key Settings Screen
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/data/services/bulk_api_service.dart';
import 'package:kanmongo/data/services/ai_source_settings_service.dart';
import 'package:url_launcher/url_launcher.dart';

class BulkApiSettingsScreen extends StatefulWidget {
  const BulkApiSettingsScreen({super.key});

  @override
  State<BulkApiSettingsScreen> createState() => _BulkApiSettingsScreenState();
}

class _BulkApiSettingsScreenState extends State<BulkApiSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _svc = BulkApiService.instance;
  final Map<String, bool> _testing = {};
  final Map<String, String?> _testResult = {};
  final Map<String, bool> _testSuccess = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _svc.load().then((_) => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    // Sinkronisasi ke AiSourceSettingsService saat screen ditutup
    AiSourceSettingsService.instance.pullBulkFromService();
    super.dispose();
  }

  // ── Test koneksi per key ──────────────────────────────────────────────────
  Future<void> _testKey(BulkApiKey key) async {
    setState(() {
      _testing[key.id] = true;
      _testResult[key.id] = null;
    });
    try {
      final result = await _svc.testKey(key);
      setState(() {
        _testing[key.id] = false;
        _testSuccess[key.id] = result.success;
        _testResult[key.id] = result.success
            ? '✅ Koneksi OK — model merespons dengan baik.'
            : _friendlyError(result.error ?? 'Error tidak diketahui');
      });
    } catch (e) {
      setState(() {
        _testing[key.id] = false;
        _testSuccess[key.id] = false;
        _testResult[key.id] = '❌ Exception: ${e.toString()}';
      });
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('401') || raw.contains('Unauthorized') || raw.contains('invalid_api_key')) {
      return '❌ API Key tidak valid (401 Unauthorized).\n'
          '→ Periksa kembali API key Anda, mungkin salah copy atau sudah expired.';
    }
    if (raw.contains('429') || raw.contains('rate_limit') || raw.contains('quota')) {
      return '⚠️ Rate limit / Quota habis (429).\n'
          '→ Anda melebihi batas penggunaan gratis. Tunggu beberapa menit atau upgrade plan.';
    }
    if (raw.contains('403') || raw.contains('Forbidden')) {
      return '❌ Akses ditolak (403 Forbidden).\n'
          '\n'
          '⚠️ Jika menggunakan key dari google-services.json:\n'
          '   Firebase SDK key TIDAK bisa untuk Gemini AI!\n'
          '   Dapatkan AI Studio key di:\n'
          '   → aistudio.google.com/app/apikey\n'
          '\n'
          'Penyebab lain: model memerlukan upgrade plan/billing.';
    }
    if (raw.contains('404') || raw.contains('not found') || raw.contains('NotFound')) {
      return '❌ Model tidak ditemukan (404 Not Found).\n'
          '→ Nama model salah atau tidak didukung. Ganti nama model di field "Custom Model".';
    }
    if (raw.contains('500') || raw.contains('502') || raw.contains('503')) {
      return '⚠️ Server provider error (5xx).\n'
          '→ Masalah di sisi provider AI. Coba lagi beberapa menit kemudian.';
    }
    if (raw.contains('SocketException') || raw.contains('Connection refused')) {
      return '❌ Tidak bisa terhubung ke server.\n'
          '→ Periksa koneksi internet Anda, atau URL endpoint salah.';
    }
    if (raw.contains('TimeoutException') || raw.contains('timed out')) {
      return '❌ Koneksi timeout.\n'
          '→ Server tidak merespons dalam 60 detik. Coba lagi atau ganti provider.';
    }
    if (raw.contains('HandshakeException') || raw.contains('SSL') || raw.contains('certificate')) {
      return '❌ SSL/TLS Error.\n'
          '→ Sertifikat server bermasalah. Pastikan URL menggunakan https:// yang valid.';
    }
    if (raw.contains('Custom URL tidak diset')) {
      return '❌ Custom URL belum diisi.\n'
          '→ Untuk provider Custom, wajib isi URL endpoint di kolom "Custom URL".';
    }
    return '❌ Error: $raw';
  }

  // ── Firebase JSON / Plist parser ─────────────────────────────────────────
  /// Ekstrak SEMUA field dari google-services.json
  /// Returns Map berisi: key, projectId, projectNumber, storageBucket,
  /// mobileSdkAppId, packageName, clientId (SHA1), oauthClientId (web)
  Map<String, String> _parseGoogleServicesJson(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;

    // ── project_info ──────────────────────────────────────────────────────
    final projectInfo = json['project_info'] as Map<String, dynamic>?;
    final projectId     = projectInfo?['project_id']     as String? ?? '';
    final projectNumber = projectInfo?['project_number'] as String? ?? '';
    final storageBucket = projectInfo?['storage_bucket'] as String? ?? '';

    if (projectId.isEmpty) {
      throw Exception('Field "project_id" tidak ditemukan di project_info');
    }

    // ── client[0] ─────────────────────────────────────────────────────────
    final clients = json['client'] as List?;
    if (clients == null || clients.isEmpty) {
      throw Exception('Field "client" tidak ditemukan di google-services.json');
    }
    final first = clients[0] as Map<String, dynamic>;

    // api_key → current_key (Firebase/Google API key, bisa untuk Gemini)
    final apiKeys = first['api_key'] as List?;
    if (apiKeys == null || apiKeys.isEmpty) {
      throw Exception('Field "api_key" tidak ditemukan di client[0]');
    }
    final currentKey = (apiKeys[0] as Map<String, dynamic>)['current_key'] as String? ?? '';
    if (currentKey.isEmpty) {
      throw Exception('"current_key" kosong atau tidak ada');
    }

    // client_info → mobilesdk_app_id & package_name
    final clientInfo       = first['client_info'] as Map<String, dynamic>?;
    final mobileSdkAppId   = clientInfo?['mobilesdk_app_id'] as String? ?? '';
    final androidClientInfo = clientInfo?['android_client_info'] as Map<String, dynamic>?;
    final packageName      = androidClientInfo?['package_name'] as String? ?? '';

    // oauth_client — ambil client_id untuk type=1 (Android SHA1) & type=3 (Web)
    String androidClientId   = '';
    String webClientId       = '';
    String certificateHash   = '';
    final oauthClients = first['oauth_client'] as List?;
    if (oauthClients != null) {
      for (final oc in oauthClients) {
        final o = oc as Map<String, dynamic>;
        final type     = o['client_type'] as int? ?? 0;
        final cid      = o['client_id'] as String? ?? '';
        if (type == 1) {
          androidClientId = cid;
          final androidInfo = o['android_info'] as Map<String, dynamic>?;
          certificateHash  = androidInfo?['certificate_hash'] as String? ?? '';
        } else if (type == 3) {
          webClientId = cid;
        }
      }
    }

    return {
      'key':             currentKey,
      'projectId':       projectId,
      'projectNumber':   projectNumber,
      'storageBucket':   storageBucket,
      'mobileSdkAppId':  mobileSdkAppId,
      'packageName':     packageName,
      'androidClientId': androidClientId,
      'webClientId':     webClientId,
      'certificateHash': certificateHash,
    };
  }

  /// Ekstrak field dari GoogleService-Info.plist (iOS XML)
  Map<String, String> _parseGoogleServicePlist(String raw) {
    String _plistVal(String key) {
      final m = RegExp('<key>$key</key>\\s*<string>([^<]+)</string>').firstMatch(raw);
      return m?.group(1) ?? '';
    }
    final currentKey = _plistVal('API_KEY');
    if (currentKey.isEmpty) {
      throw Exception('API_KEY tidak ditemukan di GoogleService-Info.plist');
    }
    return {
      'key':            currentKey,
      'projectId':      _plistVal('PROJECT_ID'),
      'projectNumber':  _plistVal('PROJECT_NUMBER'),
      'storageBucket':  _plistVal('STORAGE_BUCKET'),
      'mobileSdkAppId': _plistVal('GOOGLE_APP_ID'),
      'packageName':    _plistVal('BUNDLE_ID'),
      'androidClientId':  '',
      'webClientId':    _plistVal('CLIENT_ID'),
      'certificateHash':  '',
    };
  }

  // ── Add/Edit key dialog ───────────────────────────────────────────────────
  Future<void> _showAddKeySheet({BulkApiKey? existing}) async {
    final kfc = KmColors.of(context);
    BulkApiProvider selProvider = existing?.provider ?? BulkApiProvider.groq;
    final keyCtrl        = TextEditingController(text: existing?.apiKey ?? '');
    final labelCtrl      = TextEditingController(text: existing?.label ?? '');
    final urlCtrl        = TextEditingController(text: existing?.customUrl ?? '');
    final modelCtrl      = TextEditingController(text: existing?.customModel ?? '');
    final firebaseCtrl   = TextEditingController();
    bool  obscure        = true;
    // Mode input: 0 = Manual, 1 = Firebase Import
    int   inputMode      = 0;
    String? fbError;
    String? fbSuccess;
    bool   fbParsed      = false;
    Map<String, String> fbConfig = {}; // ← menyimpan SEMUA field Firebase

    // ── Helper parse & apply Firebase JSON/Plist ──────────────────────────
    //
    // ⚠️  ARSITEKTUR PENTING:
    // google-services.json mengandung "current_key" (Firebase SDK key) —
    // key ini hanya untuk Firebase SDK (Auth, Storage, Remote Config, dll).
    // Key tersebut TIDAK bisa digunakan untuk Gemini AI karena:
    //   1. Firebase SDK key punya API restriction → hanya Firebase APIs
    //   2. Generative Language API (Gemini) tidak termasuk dalam scope-nya
    //   3. Hasilnya: 403 Forbidden saat memanggil Gemini endpoint
    //
    // Untuk Gemini AI, user HARUS menggunakan AI Studio key dari:
    //   → https://aistudio.google.com/app/apikey
    // (key ini juga dimulai AIzaSy... tapi berbeda scope / izin)
    //
    // Flow yang benar di sini:
    //   - Import: hanya ambil metadata project (projectId, dll) dari firebase file
    //   - API Key field: DIKOSONGKAN → user wajib isi AI Studio key sendiri
    // ─────────────────────────────────────────────────────────────────────
    void applyFirebase(String raw, void Function(void Function()) setS) {
      try {
        Map<String, String> result;
        final trimmed = raw.trim();

        if (trimmed.startsWith('{')) {
          result = _parseGoogleServicesJson(trimmed);
        } else if (trimmed.contains('<?xml') || trimmed.contains('<plist')) {
          result = _parseGoogleServicePlist(trimmed);
        } else if (trimmed.startsWith('AIza') && trimmed.length > 20) {
          // User paste langsung API key — cek apakah ini AI Studio key yang valid
          // (tidak bisa diverifikasi dari format saja, tapi setidaknya masukkan ke field)
          setS(() {
            keyCtrl.text   = trimmed;
            selProvider    = BulkApiProvider.gemini;
            fbError        = null;
            fbSuccess      = '🔑 API key dimasukkan ke field.\n\n'
                '⚠️ Pastikan ini adalah AI Studio key dari:\n'
                'https://aistudio.google.com/app/apikey\n\n'
                'BUKAN Firebase key dari google-services.json\n'
                '(keduanya diawali AIzaSy... tapi berbeda izin/scope)';
            fbParsed       = true;
            inputMode      = 0;
          });
          return;
        } else {
          throw Exception(
            'Format tidak dikenali.\n'
            'Pilih salah satu:\n'
            '① Paste isi google-services.json (untuk import metadata project)\n'
            '② Paste isi GoogleService-Info.plist (iOS)\n'
            '③ Paste langsung AI Studio key (AIzaSy...) dari aistudio.google.com\n\n'
            'Catatan: Firebase key dari google-services.json tidak dapat\n'
            'digunakan untuk Gemini AI.',
          );
        }

        // ── Berhasil parse firebase file → ambil metadata, KOSONGKAN key ──
        final firebaseKey = result['key'] ?? '';
        final projectId   = result['projectId'] ?? '';

        final lines = <String>[];
        if (result['projectId']?.isNotEmpty == true)
          lines.add('📁 Project ID: ${result['projectId']}');
        if (result['projectNumber']?.isNotEmpty == true)
          lines.add('🔢 Project Number: ${result['projectNumber']}');
        if (result['storageBucket']?.isNotEmpty == true)
          lines.add('🗄️ Storage Bucket: ${result['storageBucket']}');
        if (result['packageName']?.isNotEmpty == true)
          lines.add('📦 Package: ${result['packageName']}');
        if (result['mobileSdkAppId']?.isNotEmpty == true)
          lines.add('📱 App ID: ${result['mobileSdkAppId']}');
        if (result['webClientId']?.isNotEmpty == true)
          lines.add('🌐 Web Client ID: ${result['webClientId']!.substring(0, result['webClientId']!.length.clamp(0, 30))}...');
        if (result['androidClientId']?.isNotEmpty == true)
          lines.add('🤖 Android Client ID: ${result['androidClientId']!.substring(0, result['androidClientId']!.length.clamp(0, 30))}...');
        if (result['certificateHash']?.isNotEmpty == true)
          lines.add('🔑 SHA-1: ${result['certificateHash']}');

        setS(() {
          // ⚠️ SENGAJA dikosongkan: Firebase SDK key ≠ AI Studio key
          // User harus isi sendiri dengan key dari aistudio.google.com
          keyCtrl.text   = '';
          labelCtrl.text = labelCtrl.text.isEmpty
              ? '✨ Gemini — ${projectId.isNotEmpty ? projectId : 'project'}'
              : labelCtrl.text;
          selProvider    = BulkApiProvider.gemini;
          // Simpan metadata Firebase di firebaseConfig (tanpa key-nya)
          fbConfig       = Map<String, String>.from(result)..remove('key');
          fbError        = null;
          fbSuccess      = '✅ Firebase project config berhasil di-import!\n\n'
              'Metadata project tersimpan. Klik **Simpan Config Firebase** di bawah\n'
              'untuk menyimpan config ini ke pengaturan.\n\n'
              '⚠️  Catatan: Firebase SDK key di-ABAIKAN (tidak bisa untuk Gemini AI).\n'
              'Untuk Gemini AI, tambahkan AI Studio key terpisah via tab Manual.';
          fbParsed       = true;  // aktifkan tombol Simpan Config Firebase
          // inputMode TIDAK diubah — tetap di tab Firebase
        });
      } catch (e) {
        setS(() {
          fbError   = '❌ Gagal parse: ${e.toString().replaceFirst('Exception: ', '')}';
          fbSuccess = null;
          fbParsed  = false;
          fbConfig  = {};
        });
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kfc.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 24, left: 20, right: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [

                // ── Header ────────────────────────────────────────────────
                Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(existing == null ? 'Tambah API Key' : 'Edit API Key',
                            style: TextStyle(
                                color: kfc.text, fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          existing == null
                              ? 'Pilih cara memasukkan key Anda'
                              : 'Edit provider dan key yang tersimpan',
                          style: TextStyle(color: kfc.textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ]),

                // ── Mode Toggle (hanya untuk tambah key baru) ─────────────
                if (existing == null) ...[
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: kfc.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kfc.borderSoft),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(children: [
                      Expanded(child: _modeTab(kfc, inputMode == 0, kfc.accent,
                          Icons.edit_rounded, 'Manual',
                          () => setS(() => inputMode = 0))),
                      Expanded(child: _modeTab(kfc, inputMode == 1,
                          const Color(0xFFFF6D00),
                          Icons.local_fire_department_rounded, 'Import Firebase',
                          () => setS(() => inputMode = 1))),
                    ]),
                  ),
                ],

                const SizedBox(height: 20),

                // ══════════════════════════════════════════════════════════
                // MODE 1 — FIREBASE IMPORT
                // ══════════════════════════════════════════════════════════
                if (inputMode == 1) ...[
                  // Info chip
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6D00).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFFFF6D00).withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Text('🔥', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text('Import Metadata Firebase',
                              style: TextStyle(
                                  color: kfc.text,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 8),
                        // Warning box
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(children: [
                                Text('⚠️', style: TextStyle(fontSize: 12)),
                                SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Firebase SDK key ≠ AI Studio key!',
                                    style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 4),
                              Text(
                                'Key di google-services.json (current_key) hanya untuk '
                                'Firebase SDK. TIDAK bisa untuk Gemini AI → hasilnya 403 Forbidden!',
                                style: TextStyle(color: Colors.red.shade300, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Fitur ini hanya meng-import metadata project (Project ID, SHA-1, dll) '
                          'sebagai referensi. Setelah import, Anda WAJIB mengisi API Key dengan '
                          'AI Studio key dari:',
                          style: TextStyle(color: kfc.textMuted, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => launchUrl(
                              Uri.parse('https://aistudio.google.com/app/apikey')),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A73E8).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: const Color(0xFF1A73E8).withValues(alpha: 0.3)),
                            ),
                            child: const Row(children: [
                              Text('✨', style: TextStyle(fontSize: 13)),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'aistudio.google.com/app/apikey',
                                  style: TextStyle(
                                      color: Color(0xFF1A73E8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.underline),
                                ),
                              ),
                              Icon(Icons.open_in_new, size: 13, color: Color(0xFF1A73E8)),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Metadata yang akan di-import (bukan untuk AI):',
                          style: TextStyle(color: kfc.textMuted, fontSize: 11),
                        ),
                        const SizedBox(height: 4),
                        for (final s in [
                          '① Project ID & Project Number',
                          '② Storage Bucket',
                          '③ Package Name & Mobile SDK App ID',
                          '④ OAuth Client ID (Android SHA1 & Web)',
                          '⑤ Certificate Hash (SHA-1)',
                          '❌ Firebase SDK key → DIABAIKAN (tidak dipakai untuk AI)',
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(s,
                                style: TextStyle(
                                    color: s.startsWith('❌')
                                        ? Colors.red.shade300
                                        : kfc.textMuted,
                                    fontSize: 11)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Pick file button
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.any,
                          allowMultiple: false,
                        );
                        if (result == null || result.files.isEmpty) return;
                        final path = result.files.single.path;
                        if (path == null) return;
                        final content = await File(path).readAsString();
                        setS(() => firebaseCtrl.text = content);
                      } catch (e) {
                        setS(() => fbError =
                            '❌ Gagal membaca file: ${e.toString()}');
                      }
                    },
                    icon: const Icon(Icons.folder_open_rounded, size: 16),
                    label: const Text('Pilih File Firebase (JSON/Plist)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF6D00),
                      side: const BorderSide(color: Color(0xFFFF6D00)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      minimumSize: const Size(double.infinity, 44),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Divider
                  Row(children: [
                    Expanded(child: Divider(color: kfc.borderSoft)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('atau paste konten di bawah',
                          style: TextStyle(color: kfc.textMuted, fontSize: 11)),
                    ),
                    Expanded(child: Divider(color: kfc.borderSoft)),
                  ]),
                  const SizedBox(height: 10),

                  // Firebase paste area
                  Text('Paste konten / API Key',
                      style: TextStyle(color: kfc.textMuted, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: firebaseCtrl,
                    maxLines: 7,
                    style: TextStyle(
                        color: kfc.text, fontSize: 11, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText:
                          'Paste isi google-services.json, GoogleService-Info.plist,\natau langsung API key AIzaSy...',
                      hintStyle: TextStyle(color: kfc.textMuted, fontSize: 11),
                      filled: true,
                      fillColor: kfc.card,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: kfc.border)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: kfc.border)),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        final clip = await Clipboard.getData('text/plain');
                        if (clip?.text != null) {
                          setS(() => firebaseCtrl.text = clip!.text!);
                        }
                      },
                      icon: const Icon(Icons.paste_rounded, size: 14),
                      label: const Text('Paste dari Clipboard', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                          foregroundColor: kfc.accent,
                          padding: EdgeInsets.zero),
                    ),
                  ),

                  // Error
                  if (fbError != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Colors.red.withValues(alpha: 0.2)),
                      ),
                      child: Text(fbError!,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12)),
                    ),
                  ],

                  // Success card (tampil di Firebase tab setelah parse)
                  if (fbSuccess != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(fbSuccess!,
                                  style: const TextStyle(color: Colors.green, fontSize: 12)),
                            ),
                          ]),
                          if (fbConfig.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Divider(height: 1, color: Colors.green.withValues(alpha: 0.2)),
                            const SizedBox(height: 8),
                            const Text('🔥 Firebase Config Tersimpan:',
                                style: TextStyle(
                                    color: Colors.green, fontSize: 11, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            for (final entry in fbConfig.entries)
                              if (entry.value.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 110,
                                        child: Text(
                                          _fbFieldLabel(entry.key),
                                          style: TextStyle(
                                              color: Colors.green.withValues(alpha: 0.7),
                                              fontSize: 10),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          entry.value.length > 40
                                              ? '${entry.value.substring(0, 38)}...'
                                              : entry.value,
                                          style: const TextStyle(
                                              color: Colors.green,
                                              fontSize: 10,
                                              fontFamily: 'monospace'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      final raw = firebaseCtrl.text.trim();
                      if (raw.isEmpty) {
                        setS(() => fbError =
                            '❌ Konten kosong. Isi area di atas atau pilih file terlebih dahulu.');
                        return;
                      }
                      applyFirebase(raw, setS);
                    },
                    icon: const Icon(Icons.auto_fix_high_rounded,
                        size: 16, color: Colors.white),
                    label: const Text('Parse & Import',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6D00),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      minimumSize: const Size(double.infinity, 44),
                    ),
                  ),

                  // Tombol Simpan Config Firebase — aktif setelah parse berhasil
                  if (fbParsed && fbConfig.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        // Simpan Firebase config sebagai BulkApiKey khusus
                        // dengan marker firebaseConfigOnly = true, apiKey = '__firebase_config__'
                        // sehingga tidak dipakai untuk AI generation
                        await _svc.addKey(
                          provider: BulkApiProvider.gemini,
                          apiKey: '__firebase_config__',
                          label: labelCtrl.text.trim().isEmpty
                              ? '🔥 Firebase — ${fbConfig['projectId'] ?? 'project'}'
                              : labelCtrl.text.trim(),
                          customUrl: '',
                          customModel: '',
                          firebaseConfig: fbConfig,
                        );
                        if (context.mounted) setState(() {});
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Firebase config berhasil disimpan!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.save_rounded, size: 16, color: Colors.white),
                      label: const Text('Simpan Config Firebase',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '💡 Untuk Gemini AI, tambahkan AI Studio key via tab Manual',
                      style: TextStyle(color: kfc.textMuted, fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: kfc.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      minimumSize: const Size(double.infinity, 44),
                    ),
                    child: Text('Batal', style: TextStyle(color: kfc.textMuted)),
                  ),
                ],

                // ══════════════════════════════════════════════════════════
                // MODE 0 — MANUAL (default)
                // ══════════════════════════════════════════════════════════
                if (inputMode == 0) ...[

                  // Provider selector
                  Text('Provider', style: TextStyle(color: kfc.textMuted, fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: BulkApiProvider.values.map((p) {
                      final sel = selProvider == p;
                      return GestureDetector(
                        onTap: () => setS(() => selProvider = p),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: sel ? kfc.accent : kfc.card,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: sel ? kfc.accent : kfc.border,
                            ),
                          ),
                          child: Text(
                            '${p.emoji} ${p.label}',
                            style: TextStyle(
                              color: sel ? Colors.white : kfc.text,
                              fontSize: 12,
                              fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  // Link dapatkan key
                  if (selProvider != BulkApiProvider.custom &&
                      selProvider.getKeyUrl.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => launchUrl(Uri.parse(selProvider.getKeyUrl)),
                      child: Row(children: [
                        Icon(Icons.open_in_new, size: 13, color: kfc.accent),
                        const SizedBox(width: 4),
                        Text(
                          selProvider.isFree
                              ? 'Dapatkan API Key GRATIS →'
                              : 'Dapatkan API Key →',
                          style: TextStyle(
                              color: kfc.accent,
                              fontSize: 12,
                              decoration: TextDecoration.underline),
                        ),
                      ]),
                    ),
                  ],

                  // Gemini — info khusus Firebase key
                  if (selProvider == BulkApiProvider.gemini) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A73E8).withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFF1A73E8).withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Text('✨', style: TextStyle(fontSize: 13)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Gunakan AI Studio key (bukan Firebase key!)',
                                style: TextStyle(
                                    color: const Color(0xFF1A73E8),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 4),
                          Text(
                            '⚠️ Firebase key dari google-services.json → 403 Forbidden\n'
                            '✅ AI Studio key dari aistudio.google.com/app/apikey → OK',
                            style: TextStyle(color: kfc.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  _field(ctx, kfc, labelCtrl, 'Label (opsional)',
                      Icons.label_outline, 'Mis: Gemini AI Studio Key'),
                  const SizedBox(height: 12),

                  // API Key field
                  Text('API Key *',
                      style: TextStyle(color: kfc.textMuted, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: keyCtrl,
                    obscureText: obscure,
                    style: TextStyle(
                        color: kfc.text,
                        fontSize: 13,
                        fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: selProvider == BulkApiProvider.gemini
                          ? 'AIzaSy... (AI Studio key — bukan Firebase key!)'
                          : 'Paste API key di sini...',
                      hintStyle:
                          TextStyle(color: kfc.textMuted, fontSize: 13),
                      filled: true,
                      fillColor: kfc.card,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: kfc.border)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: kfc.border)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                                obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: kfc.textMuted,
                                size: 18),
                            onPressed: () =>
                                setS(() => obscure = !obscure),
                          ),
                          // Paste shortcut
                          IconButton(
                            icon: Icon(Icons.paste_rounded,
                                color: kfc.textMuted, size: 18),
                            tooltip: 'Paste dari clipboard',
                            onPressed: () async {
                              final clip =
                                  await Clipboard.getData('text/plain');
                              if (clip?.text != null) {
                                setS(() => keyCtrl.text = clip!.text!.trim());
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                  _field(
                      ctx,
                      kfc,
                      modelCtrl,
                      'Custom Model (opsional)',
                      Icons.smart_toy_outlined,
                      selProvider == BulkApiProvider.custom
                          ? 'Nama model dari endpoint Anda'
                          : 'Kosongkan = pakai default: ${selProvider.defaultModel}'),

                  if (selProvider == BulkApiProvider.custom) ...[
                    const SizedBox(height: 12),
                    _field(ctx, kfc, urlCtrl, 'Custom URL Endpoint *',
                        Icons.link_rounded,
                        'https://your-api.com/v1/chat/completions'),
                  ],

                  const SizedBox(height: 24),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: kfc.border),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('Batal',
                            style: TextStyle(color: kfc.textMuted)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final k = keyCtrl.text.trim();
                          if (k.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('API key tidak boleh kosong')),
                            );
                            return;
                          }
                          Navigator.pop(ctx);
                          if (existing == null) {
                            await _svc.addKey(
                              provider: selProvider,
                              apiKey: k,
                              label: labelCtrl.text.trim(),
                              customUrl: urlCtrl.text.trim(),
                              customModel: modelCtrl.text.trim(),
                              firebaseConfig: fbConfig.isNotEmpty ? fbConfig : null,
                            );
                          } else {
                            final updated = BulkApiKey(
                              id: existing.id,
                              provider: selProvider,
                              apiKey: k,
                              label: labelCtrl.text.trim(),
                              customUrl: urlCtrl.text.trim(),
                              customModel: modelCtrl.text.trim(),
                              isActive: existing.isActive,
                              successCount: existing.successCount,
                              failCount: existing.failCount,
                              firebaseConfig: fbConfig.isNotEmpty
                                  ? fbConfig
                                  : existing.firebaseConfig,
                            );
                            await _svc.updateKey(updated);
                          }
                          setState(() {});
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kfc.accent,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          fbParsed ? '✅ Simpan AI Studio Key' : 'Simpan',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Helper: label tampilan untuk field Firebase config ───────────────────
  String _fbFieldLabel(String key) {
    switch (key) {
      case 'projectId':       return 'Project ID';
      case 'projectNumber':   return 'Project Number';
      case 'storageBucket':   return 'Storage Bucket';
      case 'mobileSdkAppId':  return 'App ID (SDK)';
      case 'packageName':     return 'Package Name';
      case 'androidClientId': return 'Android Client ID';
      case 'webClientId':     return 'Web Client ID';
      case 'certificateHash': return 'SHA-1 Hash';
      default:                return key;
    }
  }

  // ── Mode tab button helper ────────────────────────────────────────────────
  Widget _modeTab(
    KmColors kfc,
    bool sel,
    Color clr,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: sel ? clr : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: sel ? Colors.white : kfc.textMuted),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: sel ? Colors.white : kfc.textMuted,
                    fontSize: 12,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  Widget _field(BuildContext ctx, KmColors kfc, TextEditingController ctrl,
      String label, IconData icon, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: kfc.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          style: TextStyle(color: kfc.text, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: kfc.textMuted.withValues(alpha: 0.6), fontSize: 12),
            prefixIcon: Icon(icon, color: kfc.textMuted, size: 18),
            filled: true,
            fillColor: kfc.card,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: kfc.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: kfc.border)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final kfc = KmColors.of(context);
    return Scaffold(
      backgroundColor: kfc.bg,
      appBar: AppBar(
        backgroundColor: kfc.surface,
        foregroundColor: kfc.text,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.vpn_key_rounded, color: Colors.orange, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('Bulk API Key', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
        bottom: TabBar(
          controller: _tab,
          labelColor: kfc.accent,
          unselectedLabelColor: kfc.textMuted,
          indicatorColor: kfc.accent,
          tabs: const [
            Tab(text: '🔑 API Keys'),
            Tab(text: '⚙️ Pengaturan'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [_keysTab(kfc), _settingsTab(kfc)],
      ),
      floatingActionButton: _tab.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => _showAddKeySheet(),
              backgroundColor: kfc.accent,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Tambah Key', style: TextStyle(color: Colors.white)),
            )
          : null,
    );
  }

  Widget _keysTab(KmColors kfc) {
    if (_svc.keys.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.vpn_key_off_rounded, size: 56, color: kfc.textMuted),
            const SizedBox(height: 16),
            Text('Belum ada API Key',
                style: TextStyle(color: kfc.text, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Tap tombol + untuk menambah key.\nGroq & Together.ai tersedia gratis!',
                style: TextStyle(color: kfc.textMuted, fontSize: 13),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _showAddKeySheet(),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Tambah Key Pertama', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: kfc.accent),
            ),
          ],
        ),
      );
    }

    // Group by provider
    final grouped = <BulkApiProvider, List<BulkApiKey>>{};
    for (final key in _svc.keys) {
      grouped.putIfAbsent(key.provider, () => []).add(key);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary bar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kfc.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statChip(kfc, '${_svc.keys.length}', 'Total Key', Icons.key),
              _statChip(kfc, '${_svc.keys.where((k) => k.canUse).length}',
                  'Aktif', Icons.check_circle_outline, Colors.green),
              _statChip(kfc, '${_svc.keys.where((k) => k.isLimitReached).length}',
                  'Rate Limit', Icons.block_rounded, Colors.red),
              _statChip(kfc, '${_svc.keys.where((k) => !k.isActive).length}',
                  'Nonaktif', Icons.pause_circle_outline, Colors.grey),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Keys grouped by provider
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Text(entry.key.emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(entry.key.label,
                    style: TextStyle(
                        color: kfc.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
                const Spacer(),
                if (entry.key.isFree)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: const Text('GRATIS',
                        style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
          for (final key in entry.value) _keyCard(kfc, key),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _statChip(KmColors kfc, String value, String label, IconData icon,
      [Color? color]) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color ?? kfc.accent),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: color ?? kfc.text, fontSize: 16, fontWeight: FontWeight.w700)),
        Text(label, style: TextStyle(color: kfc.textMuted, fontSize: 10)),
      ],
    );
  }

  Widget _keyCard(KmColors kfc, BulkApiKey key) {
    final isTesting = _testing[key.id] == true;
    final result = _testResult[key.id];
    final success = _testSuccess[key.id];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: kfc.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: key.isLimitReached
              ? Colors.red.withValues(alpha: 0.3)
              : !key.isActive
                  ? kfc.borderSoft
                  : kfc.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Status dot
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: key.isLimitReached
                        ? Colors.red
                        : !key.isActive
                            ? Colors.grey
                            : Colors.green,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(key.displayLabel,
                          style: TextStyle(
                              color: kfc.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        key.customModel.isNotEmpty
                            ? 'Model: ${key.customModel}'
                            : 'Model default: ${key.provider.defaultModel}',
                        style: TextStyle(color: kfc.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // Active toggle
                Switch(
                  value: key.isActive,
                  activeColor: kfc.accent,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) async {
                    key.isActive = v;
                    await _svc.updateKey(key);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),

          // Key preview + stats
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(Icons.key_rounded, size: 12, color: kfc.textMuted),
                const SizedBox(width: 4),
                Text(
                  key.apiKey == '__firebase_config__' ? '🔥 Config Firebase Only (tanpa AI key)' : '${key.apiKey.substring(0, key.apiKey.length.clamp(0, 12))}••••',
                  style: TextStyle(color: key.apiKey == '__firebase_config__' ? const Color(0xFFFF6D00) : kfc.textMuted, fontSize: 11, fontFamily: 'monospace'),
                ),
                const Spacer(),
                // Badge Firebase jika ada config
                if (key.firebaseConfig.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6D00).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFF6D00).withValues(alpha: 0.3)),
                    ),
                    child: const Text('🔥 Firebase',
                        style: TextStyle(color: Color(0xFFFF6D00), fontSize: 9, fontWeight: FontWeight.w700)),
                  ),
                if (key.firebaseConfig.isNotEmpty) const SizedBox(width: 6),
                Icon(Icons.check_circle, size: 12, color: Colors.green),
                const SizedBox(width: 2),
                Text('${key.successCount}',
                    style: TextStyle(color: kfc.textMuted, fontSize: 11)),
                const SizedBox(width: 8),
                Icon(Icons.cancel, size: 12, color: Colors.red),
                const SizedBox(width: 2),
                Text('${key.failCount}',
                    style: TextStyle(color: kfc.textMuted, fontSize: 11)),
              ],
            ),
          ),

          // Firebase config detail (jika tersedia)
          if (key.firebaseConfig.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6D00).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFFFF6D00).withValues(alpha: 0.15)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🔥 Firebase Project Config',
                        style: TextStyle(
                            color: Color(0xFFFF6D00),
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    for (final entry in key.firebaseConfig.entries)
                      if (entry.value.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 100,
                                child: Text(
                                  _fbFieldLabel(entry.key),
                                  style: TextStyle(
                                      color: kfc.textMuted, fontSize: 10),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  entry.value.length > 35
                                      ? '${entry.value.substring(0, 33)}...'
                                      : entry.value,
                                  style: TextStyle(
                                      color: kfc.text,
                                      fontSize: 10,
                                      fontFamily: 'monospace'),
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ],

          if (key.isLimitReached) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber, size: 12, color: Colors.red),
                    const SizedBox(width: 4),
                    Text('Rate limited — auto-reset dalam 1 jam',
                        style: const TextStyle(color: Colors.red, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],

          // Test result
          if (result != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (success == true
                          ? Colors.green
                          : Colors.red)
                      .withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: (success == true ? Colors.green : Colors.red)
                          .withValues(alpha: 0.2)),
                ),
                child: Text(result,
                    style: TextStyle(
                        color: success == true ? Colors.green.shade400 : Colors.red.shade300,
                        fontSize: 12)),
              ),
            ),
          ],

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                _actionBtn(kfc, Icons.play_arrow_rounded,
                    isTesting ? 'Testing...' : 'Test Koneksi',
                    isTesting ? null : () => _testKey(key),
                    isTesting
                        ? Colors.grey
                        : Colors.blue),
                const SizedBox(width: 8),
                _actionBtn(kfc, Icons.edit_rounded, 'Edit',
                    () => _showAddKeySheet(existing: key), kfc.accent),
                const SizedBox(width: 8),
                _actionBtn(kfc, Icons.copy_rounded, 'Copy',
                    () {
                      Clipboard.setData(ClipboardData(text: key.apiKey));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('API key disalin')),
                      );
                    }, Colors.orange),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade300, size: 20),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        backgroundColor: kfc.surface,
                        title: Text('Hapus Key?',
                            style: TextStyle(color: kfc.text)),
                        content: Text('Key "${key.displayLabel}" akan dihapus permanen.',
                            style: TextStyle(color: kfc.textMuted)),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: Text('Batal', style: TextStyle(color: kfc.textMuted))),
                          TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Hapus',
                                  style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await _svc.removeKey(key.id);
                      _testResult.remove(key.id);
                      _testSuccess.remove(key.id);
                      setState(() {});
                    }
                  },
                  tooltip: 'Hapus',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(KmColors kfc, IconData icon, String label,
      VoidCallback? onTap, Color color) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _settingsTab(KmColors kfc) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Enable toggle
        _sectionCard(kfc, [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.power_settings_new_rounded,
                  color: Colors.orange, size: 20),
            ),
            title: Text('Aktifkan Bulk API',
                style: TextStyle(color: kfc.text, fontWeight: FontWeight.w600)),
            subtitle: Text(
              _svc.enabled
                  ? 'Bulk API aktif dan siap digunakan'
                  : 'Bulk API tidak aktif — tap untuk mengaktifkan',
              style: TextStyle(color: kfc.textMuted, fontSize: 12),
            ),
            trailing: Switch(
              value: _svc.enabled,
              activeColor: kfc.accent,
              onChanged: (v) async {
                await _svc.setEnabled(v);
                // Sinkronisasi ke AiSourceSettingsService agar picker ikut update
                await AiSourceSettingsService.instance.pullBulkFromService();
                setState(() {});
              },
            ),
          ),
        ]),

        const SizedBox(height: 16),

        // Load mode selector
        _sectionTitle(kfc, '🔄 Mode Pemilihan Key'),
        const SizedBox(height: 8),
        _sectionCard(kfc, [
          for (final mode in BulkLoadMode.values) ...[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: Radio<BulkLoadMode>(
                value: mode,
                groupValue: _svc.mode,
                activeColor: kfc.accent,
                onChanged: (v) async {
                  if (v != null) {
                    await _svc.setMode(v);
                    setState(() {});
                  }
                },
              ),
              title: Text(mode.label,
                  style: TextStyle(
                      color: kfc.text,
                      fontWeight: _svc.mode == mode ? FontWeight.w600 : FontWeight.normal)),
              subtitle: Text(mode.description,
                  style: TextStyle(color: kfc.textMuted, fontSize: 12)),
              onTap: () async {
                await _svc.setMode(mode);
                setState(() {});
              },
            ),
            if (mode != BulkLoadMode.roundRobin)
              Divider(height: 1, color: kfc.borderSoft, indent: 48),
          ],
        ]),

        const SizedBox(height: 16),

        // Provider info
        _sectionTitle(kfc, '🌐 Provider yang Didukung'),
        const SizedBox(height: 8),
        _sectionCard(kfc, [
          for (final p in BulkApiProvider.values) ...[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Text(p.emoji, style: const TextStyle(fontSize: 22)),
              title: Row(
                children: [
                  Text(p.label,
                      style: TextStyle(
                          color: kfc.text, fontSize: 13, fontWeight: FontWeight.w600)),
                  if (p.isFree) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('GRATIS',
                          style: TextStyle(
                              color: Colors.green, fontSize: 9, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                '${_svc.keysForProvider(p).length} key tersimpan'
                '${p == BulkApiProvider.custom ? ' • Format OpenAI-compatible' : ''}',
                style: TextStyle(color: kfc.textMuted, fontSize: 11),
              ),
              trailing: _svc.keysForProvider(p).isEmpty && p.getKeyUrl.isNotEmpty
                  ? TextButton(
                      onPressed: () => launchUrl(Uri.parse(p.getKeyUrl)),
                      child: Text('Get Key',
                          style: TextStyle(color: kfc.accent, fontSize: 11)),
                    )
                  : null,
            ),
            if (p != BulkApiProvider.custom)
              Divider(height: 1, color: kfc.borderSoft, indent: 56),
          ],
        ]),

        const SizedBox(height: 16),

        // Danger zone
        _sectionTitle(kfc, '⚠️ Lainnya'),
        const SizedBox(height: 8),
        _sectionCard(kfc, [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Icon(Icons.refresh_rounded, color: Colors.orange),
            title: Text('Reset Semua Rate Limit',
                style: TextStyle(color: kfc.text, fontSize: 13)),
            subtitle: Text('Hapus status rate-limit dari semua key',
                style: TextStyle(color: kfc.textMuted, fontSize: 12)),
            onTap: () async {
              await _svc.resetAllLimits();
              setState(() {});
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Semua rate limit di-reset ✅')),
                );
              }
            },
          ),
          Divider(height: 1, color: kfc.borderSoft, indent: 56),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.delete_sweep_rounded, color: Colors.red),
            title: Text('Hapus Semua Key',
                style: TextStyle(color: Colors.red.shade300, fontSize: 13)),
            subtitle: Text('Hapus semua API key yang tersimpan',
                style: TextStyle(color: kfc.textMuted, fontSize: 12)),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  backgroundColor: kfc.surface,
                  title: Text('Hapus Semua Key?', style: TextStyle(color: kfc.text)),
                  content: Text('Semua ${_svc.keys.length} key akan dihapus permanen.',
                      style: TextStyle(color: kfc.textMuted)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: Text('Batal', style: TextStyle(color: kfc.textMuted))),
                    TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Hapus Semua',
                            style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (ok == true) {
                for (final k in List.from(_svc.keys)) {
                  await _svc.removeKey(k.id);
                }
                _testResult.clear();
                _testSuccess.clear();
                setState(() {});
              }
            },
          ),
        ]),

        const SizedBox(height: 32),
      ],
    );
  }

  Widget _sectionTitle(KmColors kfc, String text) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(text,
            style: TextStyle(
                color: kfc.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4)),
      );

  Widget _sectionCard(KmColors kfc, List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: kfc.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kfc.borderSoft),
        ),
        child: Column(children: children),
      );
}
