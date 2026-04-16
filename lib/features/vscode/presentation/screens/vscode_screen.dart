// lib/features/vscode/presentation/screens/vscode_screen.dart
// KanMon GO — VS Code Screen
//
// Tiga state:
//   1. SETUP   : code-server belum terinstall → wizard install dengan log realtime
//   2. READY   : sudah terinstall, belum jalan → tombol Start + input API key
//   3. RUNNING : code-server aktif → WebView fullscreen ke localhost:9191
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/data/services/code_server_service.dart';

// ── Screen Mode ───────────────────────────────────────────────────────────────
enum _Mode { checking, needsInstall, installing, ready, starting, running, error }

// ── Providers ─────────────────────────────────────────────────────────────────
final _modeProvider      = StateProvider<_Mode>((_) => _Mode.checking);
final _logProvider       = StateProvider<List<String>>((_) => []);
final _progressProvider  = StateProvider<double>((_) => 0.0);
final _apiKeyProvider    = StateProvider<String>((_) => '');
final _errorProvider     = StateProvider<String?>((_) => null);

// ── VS Code Screen ────────────────────────────────────────────────────────────
class VsCodeScreen extends ConsumerStatefulWidget {
  const VsCodeScreen({super.key});

  @override
  ConsumerState<VsCodeScreen> createState() => _VsCodeScreenState();
}

class _VsCodeScreenState extends ConsumerState<VsCodeScreen> {
  final _svc         = CodeServerService.instance;
  final _scrollCtrl  = ScrollController();
  final _keyCtrl     = TextEditingController();
  WebViewController? _webCtrl;
  bool _keyObscure   = true;
  StreamSubscription? _installSub;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  @override
  void dispose() {
    _installSub?.cancel();
    _keyCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Check current status ───────────────────────────────────────────────────
  Future<void> _checkStatus() async {
    ref.read(_modeProvider.notifier).state = _Mode.checking;

    final key = await _svc.getAnthropicKey();
    if (key != null && key.isNotEmpty) {
      _keyCtrl.text = key;
      ref.read(_apiKeyProvider.notifier).state = key;
    }

    final status = await _svc.checkStatus();
    if (!mounted) return;

    switch (status) {
      case CodeServerStatus.running:
        _initWebView();
        ref.read(_modeProvider.notifier).state = _Mode.running;
        break;
      case CodeServerStatus.installed:
        ref.read(_modeProvider.notifier).state = _Mode.ready;
        break;
      case CodeServerStatus.notInstalled:
        ref.read(_modeProvider.notifier).state = _Mode.needsInstall;
        break;
      case CodeServerStatus.error:
        ref.read(_errorProvider.notifier).state = 'Gagal memeriksa status code-server.';
        ref.read(_modeProvider.notifier).state = _Mode.error;
        break;
    }
  }

  // ── Start install ──────────────────────────────────────────────────────────
  void _startInstall() {
    ref.read(_modeProvider.notifier).state    = _Mode.installing;
    ref.read(_logProvider.notifier).state     = [];
    ref.read(_progressProvider.notifier).state = 0.0;

    _installSub = _svc.install().listen(
      (event) {
        if (!mounted) return;
        ref.read(_logProvider.notifier).state = [
          ...ref.read(_logProvider),
          event.message,
        ];
        ref.read(_progressProvider.notifier).state = event.progress;

        if (event.step == CodeServerStep.done) {
          ref.read(_modeProvider.notifier).state = _Mode.ready;
        } else if (event.isError) {
          ref.read(_errorProvider.notifier).state = event.message;
          ref.read(_modeProvider.notifier).state = _Mode.error;
        }
        _scrollToBottom();
      },
      onError: (e) {
        if (!mounted) return;
        ref.read(_errorProvider.notifier).state = e.toString();
        ref.read(_modeProvider.notifier).state = _Mode.error;
      },
    );
  }

  // ── Start server ───────────────────────────────────────────────────────────
  Future<void> _startServer() async {
    ref.read(_modeProvider.notifier).state = _Mode.starting;

    final key = _keyCtrl.text.trim();
    if (key.isNotEmpty) {
      await _svc.setAnthropicKey(key);
    }

    final ok = await _svc.start(anthropicKey: key);
    if (!mounted) return;

    if (ok) {
      _initWebView();
      ref.read(_modeProvider.notifier).state = _Mode.running;
    } else {
      ref.read(_errorProvider.notifier).state =
          'Gagal memulai code-server.\n'
          'Pastikan Termux berjalan dan port ${_svc.port} tidak dipakai.';
      ref.read(_modeProvider.notifier).state = _Mode.error;
    }
  }

  // ── Init WebView ───────────────────────────────────────────────────────────
  void _initWebView() {
    _webCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF1E1E1E))
      ..loadRequest(Uri.parse(_svc.serverUrl));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Stop server ────────────────────────────────────────────────────────────
  Future<void> _stopServer() async {
    await _svc.stop();
    if (!mounted) return;
    _webCtrl = null;
    ref.read(_modeProvider.notifier).state = _Mode.ready;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final kmc  = KmColors.of(context);
    final mode = ref.watch(_modeProvider);

    return Scaffold(
      backgroundColor: kmc.bg,
      body: _buildBody(kmc, mode),
    );
  }

  Widget _buildBody(KmColors kmc, _Mode mode) {
    switch (mode) {
      case _Mode.checking:
        return _buildChecking(kmc);
      case _Mode.needsInstall:
        return _buildNeedsInstall(kmc);
      case _Mode.installing:
        return _buildInstalling(kmc);
      case _Mode.ready:
        return _buildReady(kmc);
      case _Mode.starting:
        return _buildStarting(kmc);
      case _Mode.running:
        return _buildRunning(kmc);
      case _Mode.error:
        return _buildError(kmc);
    }
  }

  // ── Checking ───────────────────────────────────────────────────────────────
  Widget _buildChecking(KmColors kmc) => Scaffold(
    backgroundColor: kmc.bg,
    appBar: _appBar(kmc, 'VS Code', []),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: const Color(0xFF2563EB)),
          const SizedBox(height: 16),
          Text('Memeriksa status...', style: TextStyle(color: kmc.textSub)),
        ],
      ),
    ),
  );

  // ── Needs Install ──────────────────────────────────────────────────────────
  Widget _buildNeedsInstall(KmColors kmc) => Scaffold(
    backgroundColor: kmc.bg,
    appBar: _appBar(kmc, 'VS Code', []),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero
          Center(
            child: Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.code_rounded,
                  color: Color(0xFF2563EB), size: 44),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text('VS Code + Claude Code',
                style: TextStyle(
                    color: kmc.text, fontSize: 22,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text('IDE lengkap dengan AI coding assistant lokal',
                style: TextStyle(color: kmc.textSub, fontSize: 14)),
          ),
          const SizedBox(height: 32),

          // Info cards
          _infoCard(kmc, Icons.storage_rounded, 'Ukuran download',
              '~300–500MB (Node.js + code-server + Claude Code)'),
          const SizedBox(height: 12),
          _infoCard(kmc, Icons.wifi_rounded, 'Koneksi internet',
              'Dibutuhkan saat instalasi pertama'),
          const SizedBox(height: 12),
          _infoCard(kmc, Icons.android_rounded, 'Persyaratan',
              'Termux dari F-Droid harus terinstall'),
          const SizedBox(height: 12),
          _infoCard(kmc, Icons.auto_awesome_rounded, 'Claude Code',
              'Coding AI langsung di terminal VS Code'),

          const SizedBox(height: 40),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _startInstall,
              icon: const Icon(Icons.download_rounded),
              label: const Text('Install VS Code + Claude Code',
                  style: TextStyle(fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Proses instalasi ±5–10 menit tergantung kecepatan internet',
              style: TextStyle(color: kmc.textMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ),
  );

  // ── Installing ─────────────────────────────────────────────────────────────
  Widget _buildInstalling(KmColors kmc) {
    final logs     = ref.watch(_logProvider);
    final progress = ref.watch(_progressProvider);

    return Scaffold(
      backgroundColor: kmc.bg,
      appBar: _appBar(kmc, 'Menginstall VS Code', []),
      body: Column(
        children: [
          // Progress bar
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kmc.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kmc.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: const Color(0xFF2563EB)),
                    ),
                    const SizedBox(width: 10),
                    Text('Instalasi sedang berjalan...',
                        style: TextStyle(
                            color: kmc.text, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('${(progress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                            color: const Color(0xFF2563EB),
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: kmc.surface,
                    color: const Color(0xFF2563EB),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),

          // Log terminal
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kmc.border),
              ),
              child: ListView.builder(
                controller: _scrollCtrl,
                itemCount: logs.length,
                itemBuilder: (_, i) {
                  final line = logs[i];
                  final isError  = line.contains('❌');
                  final isOk     = line.contains('✅');
                  final color = isError
                      ? const Color(0xFFEF4444)
                      : isOk
                          ? const Color(0xFF10B981)
                          : const Color(0xFFB0B0C0);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(line,
                        style: TextStyle(
                            color: color, fontSize: 12,
                            fontFamily: 'monospace')),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Ready ──────────────────────────────────────────────────────────────────
  Widget _buildReady(KmColors kmc) => Scaffold(
    backgroundColor: kmc.bg,
    appBar: _appBar(kmc, 'VS Code', []),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status badge
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: Color(0xFF10B981), size: 16),
                  SizedBox(width: 6),
                  Text('Terinstall · Siap dijalankan',
                      style: TextStyle(
                          color: Color(0xFF10B981), fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          // API Key input
          Text('Anthropic API Key (opsional)',
              style: TextStyle(color: kmc.textSub,
                  fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _keyCtrl,
            obscureText: _keyObscure,
            style: TextStyle(color: kmc.text, fontSize: 13,
                fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: 'sk-ant-... (untuk claude CLI di terminal VS Code)',
              hintStyle: TextStyle(color: kmc.textMuted, fontSize: 12),
              filled: true,
              fillColor: kmc.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: kmc.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: kmc.border),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                        _keyObscure
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: kmc.textMuted, size: 18),
                    onPressed: () =>
                        setState(() => _keyObscure = !_keyObscure),
                  ),
                  IconButton(
                    icon: Icon(Icons.paste_rounded,
                        color: kmc.textMuted, size: 18),
                    onPressed: () async {
                      final clip = await Clipboard.getData('text/plain');
                      if (clip?.text != null) {
                        _keyCtrl.text = clip!.text!.trim();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Key disimpan lokal di perangkat. Digunakan untuk perintah claude '
            'di terminal VS Code.',
            style: TextStyle(color: kmc.textMuted, fontSize: 11),
          ),

          const SizedBox(height: 32),

          // Info port
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kmc.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kmc.border),
            ),
            child: Row(
              children: [
                Icon(Icons.lan_rounded,
                    color: const Color(0xFF2563EB), size: 20),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Server akan berjalan di',
                        style: TextStyle(color: kmc.textSub, fontSize: 12)),
                    Text('localhost:${_svc.port}',
                        style: const TextStyle(
                            color: Color(0xFF2563EB),
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace')),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _startServer,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Jalankan VS Code',
                  style: TextStyle(fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await _svc.resetInstallState();
                _checkStatus();
              },
              icon: Icon(Icons.refresh_rounded,
                  color: kmc.textMuted, size: 18),
              label: Text('Reinstall',
                  style: TextStyle(color: kmc.textMuted)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: kmc.border),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  // ── Starting ───────────────────────────────────────────────────────────────
  Widget _buildStarting(KmColors kmc) => Scaffold(
    backgroundColor: kmc.bg,
    appBar: _appBar(kmc, 'VS Code', []),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: const Color(0xFF2563EB)),
          const SizedBox(height: 20),
          Text('Memulai code-server...',
              style: TextStyle(color: kmc.textSub, fontSize: 15)),
          const SizedBox(height: 8),
          Text('Ini mungkin membutuhkan beberapa detik',
              style: TextStyle(color: kmc.textMuted, fontSize: 12)),
        ],
      ),
    ),
  );

  // ── Running — WebView fullscreen ───────────────────────────────────────────
  Widget _buildRunning(KmColors kmc) {
    if (_webCtrl == null) return _buildStarting(kmc);

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF252526),
        foregroundColor: Colors.white,
        title: Row(
          children: [
            const Icon(Icons.code_rounded, size: 18,
                color: Color(0xFF2563EB)),
            const SizedBox(width: 8),
            const Text('VS Code',
                style: TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Running',
                  style: TextStyle(
                      color: Color(0xFF10B981), fontSize: 11)),
            ),
          ],
        ),
        actions: [
          // Refresh WebView
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Reload',
            onPressed: () =>
                _webCtrl?.loadRequest(Uri.parse(_svc.serverUrl)),
          ),
          // Stop server
          IconButton(
            icon: const Icon(Icons.stop_rounded,
                color: Color(0xFFEF4444), size: 20),
            tooltip: 'Hentikan server',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor:
                      const Color(0xFF252526),
                  title: const Text('Hentikan VS Code?',
                      style: TextStyle(color: Colors.white)),
                  content: const Text(
                      'Server akan dimatikan dan WebView ditutup.',
                      style: TextStyle(color: Color(0xFFB0B0C0))),
                  actions: [
                    TextButton(
                        onPressed: () =>
                            Navigator.pop(context, false),
                        child: const Text('Batal')),
                    TextButton(
                        onPressed: () =>
                            Navigator.pop(context, true),
                        child: const Text('Hentikan',
                            style: TextStyle(
                                color: Color(0xFFEF4444)))),
                  ],
                ),
              );
              if (ok == true) _stopServer();
            },
          ),
        ],
      ),
      body: WebViewWidget(controller: _webCtrl!),
    );
  }

  // ── Error ──────────────────────────────────────────────────────────────────
  Widget _buildError(KmColors kmc) {
    final err = ref.watch(_errorProvider) ?? 'Terjadi kesalahan.';
    return Scaffold(
      backgroundColor: kmc.bg,
      appBar: _appBar(kmc, 'VS Code', []),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFEF4444), size: 52),
            const SizedBox(height: 16),
            Text('Terjadi Kesalahan',
                style: TextStyle(
                    color: kmc.text, fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFFEF4444).withOpacity(0.3)),
              ),
              child: Text(err,
                  style: const TextStyle(
                      color: Color(0xFFEF4444), fontSize: 13,
                      fontFamily: 'monospace')),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _checkStatus,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Coba Lagi'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  PreferredSizeWidget _appBar(
      KmColors kmc, String title, List<Widget> actions) =>
      AppBar(
        backgroundColor: kmc.bg,
        foregroundColor: kmc.text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(title,
            style: TextStyle(
                color: kmc.text, fontSize: 17,
                fontWeight: FontWeight.w600)),
        actions: actions,
      );

  Widget _infoCard(
          KmColors kmc, IconData icon, String title, String desc) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kmc.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kmc.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  Icon(icon, color: const Color(0xFF2563EB), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: kmc.text, fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: TextStyle(
                          color: kmc.textSub, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
}
