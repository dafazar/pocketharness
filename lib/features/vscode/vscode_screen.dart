// lib/features/vscode/vscode_screen.dart
// KanMonAI — VS Code Screen (Functional, Native)
//
// Architecture:
//   • Cek ToolsService.isReady + CodeServerService status
//   • Jika bundle tidak ada → tampilkan info "Perlu rebuild APK"
//   • Jika bundle ada, belum install → setup pipeline
//   • Jika installed, belum running → tombol "Mulai VS Code"
//   • Jika running → WebView ke localhost:9191
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/core/tools/tools_service.dart';
import 'package:kanmongo/data/services/code_server_service.dart';

enum _Phase {
  checking, noBundle, setupNeeded, installing, startNeeded, starting, running, error
}

class VscodeScreen extends ConsumerStatefulWidget {
  final String? initialPath;
  const VscodeScreen({super.key, this.initialPath});
  @override
  ConsumerState<VscodeScreen> createState() => _VscodeScreenState();
}

class _VscodeScreenState extends ConsumerState<VscodeScreen> {
  _Phase _phase = _Phase.checking;
  String _msg = 'Memeriksa bundle...';
  double _progress = 0;
  String? _errMsg;
  WebViewController? _wvc;
  final _svc = CodeServerService.instance;

  @override
  void initState() { super.initState(); _checkStatus(); }

  @override
  void dispose() { _svc.stop(); super.dispose(); }

  Future<void> _checkStatus() async {
    setState(() { _phase = _Phase.checking; _msg = 'Memeriksa bundle tools...'; _progress = 0; });
    final status = await _svc.checkStatus();
    if (!mounted) return;
    switch (status) {
      case CodeServerStatus.notInstalled:
        final hasBundle = ToolsService.instance.isReady || await _tryInitBundle();
        setState(() {
          _phase = hasBundle ? _Phase.setupNeeded : _Phase.noBundle;
          _msg = hasBundle ? 'Bundle ditemukan. Siap setup.' : 'Bundle tools tidak ditemukan dalam APK.';
        });
      case CodeServerStatus.installed:
        setState(() { _phase = _Phase.startNeeded; _msg = 'code-server siap.'; });
      case CodeServerStatus.running:
        _attachWebView();
      case CodeServerStatus.error:
        setState(() { _phase = _Phase.error; _errMsg = _svc.lastStartError ?? 'Kesalahan tidak diketahui.'; });
    }
  }

  Future<bool> _tryInitBundle() async {
    try { await ToolsService.instance.initialize(); return ToolsService.instance.isReady; }
    catch (_) { return false; }
  }

  Future<void> _runInstall() async {
    setState(() { _phase = _Phase.installing; _msg = 'Memulai setup...'; _progress = 0.05; _errMsg = null; });
    await for (final e in _svc.install()) {
      if (!mounted) return;
      setState(() {
        _msg = e.message; _progress = e.progress;
        if (e.isError) { _phase = _Phase.error; _errMsg = e.message; }
        else if (e.step == CodeServerStep.done) { _phase = _Phase.startNeeded; }
      });
    }
  }

  Future<void> _startServer() async {
    setState(() { _phase = _Phase.starting; _msg = 'Memulai VS Code server...'; _progress = 0.1; _errMsg = null; });
    final ok = await _svc.start();
    if (!mounted) return;
    if (ok) { _attachWebView(); }
    else { setState(() { _phase = _Phase.error; _errMsg = _svc.lastStartError ?? 'Gagal memulai server.'; }); }
  }

  void _attachWebView() {
    final url = _svc.serverUrl + (widget.initialPath != null ? '?folder=${widget.initialPath}' : '');
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF1E1E1E))
      ..loadRequest(Uri.parse(url));
    setState(() { _wvc = ctrl; _phase = _Phase.running; });
  }

  Future<void> _stopServer() async {
    await _svc.stop();
    if (!mounted) return;
    setState(() { _wvc = null; _phase = _Phase.startNeeded; _msg = 'VS Code dihentikan.'; });
  }

  @override
  Widget build(BuildContext context) {
    final kmc = KmColors.of(context);
    final isRun = _phase == _Phase.running;
    return Scaffold(
      backgroundColor: isRun ? const Color(0xFF1E1E1E) : kmc.bg,
      appBar: AppBar(
        backgroundColor: isRun ? const Color(0xFF333333) : kmc.bg,
        foregroundColor: isRun ? Colors.white : kmc.text,
        elevation: 0, surfaceTintColor: Colors.transparent,
        title: Text('VS Code', style: TextStyle(color: isRun ? Colors.white : kmc.text, fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          if (isRun) ...[
            IconButton(icon: const Icon(Icons.refresh_rounded, size: 20), onPressed: () => _wvc?.reload(), tooltip: 'Refresh'),
            IconButton(icon: const Icon(Icons.stop_circle_outlined, size: 20, color: Color(0xFFEF4444)), onPressed: _stopServer, tooltip: 'Stop'),
          ],
        ],
      ),
      body: _buildBody(kmc),
    );
  }

  Widget _buildBody(KmColors kmc) {
    const blue = Color(0xFF0EA5E9);
    switch (_phase) {
      case _Phase.running:
        return _wvc != null ? WebViewWidget(controller: _wvc!) : const Center(child: CircularProgressIndicator());
      case _Phase.checking:
        return _Loading(kmc: kmc, msg: _msg, color: blue);
      case _Phase.noBundle:
        return _NoBundle(kmc: kmc);
      case _Phase.setupNeeded:
        return _Action(kmc: kmc, icon: Icons.code_rounded, color: blue, title: 'VS Code',
          subtitle: 'IDE · code-server · Browser',
          msg: 'Bundle tools ditemukan dalam APK.\nSetup sekali untuk mengekstrak dan mengonfigurasi code-server.',
          btnLabel: 'Setup VS Code', onTap: _runInstall);
      case _Phase.installing:
        return _Progress(kmc: kmc, icon: Icons.code_rounded, color: blue, title: 'Menyiapkan VS Code...', msg: _msg, progress: _progress);
      case _Phase.startNeeded:
        return _Action(kmc: kmc, icon: Icons.code_rounded, color: blue, title: 'VS Code',
          subtitle: 'IDE · code-server · Browser',
          msg: 'code-server siap.\nTekan tombol di bawah untuk membuka IDE.',
          btnLabel: 'Mulai VS Code', onTap: _startServer);
      case _Phase.starting:
        return _Progress(kmc: kmc, icon: Icons.code_rounded, color: blue, title: 'Memulai VS Code...', msg: _msg, progress: _progress);
      case _Phase.error:
        return _Error(kmc: kmc, color: blue, errMsg: _errMsg ?? 'Kesalahan.', onRetry: _checkStatus);
    }
  }
}

// ── Sub-views ─────────────────────────────────────────────────────────────────

class _Loading extends StatelessWidget {
  final KmColors kmc; final String msg; final Color color;
  const _Loading({required this.kmc, required this.msg, required this.color});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    CircularProgressIndicator(color: color, strokeWidth: 2.5),
    const SizedBox(height: 16),
    Text(msg, style: TextStyle(color: kmc.textSub, fontSize: 13)),
  ]));
}

class _NoBundle extends StatelessWidget {
  final KmColors kmc;
  const _NoBundle({required this.kmc});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
    _IconBox(icon: Icons.code_rounded, color: const Color(0xFF0EA5E9)),
    const SizedBox(height: 20),
    Text('VS Code', style: TextStyle(color: kmc.text, fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 6),
    Text('IDE · code-server · Browser', style: TextStyle(color: kmc.textSub, fontSize: 13)),
    const SizedBox(height: 28),
    Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: kmc.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: kmc.border)),
      child: Text(
        'APK ini tidak menyertakan bundle tools.\n\nBuild APK melalui GitHub Actions dengan workflow build.yml yang sudah dikonfigurasi agar bundle tools ter-sertakan.',
        style: TextStyle(color: kmc.textSub, fontSize: 13.5, height: 1.65), textAlign: TextAlign.center,
      ),
    ),
  ])));
}

class _Action extends StatelessWidget {
  final KmColors kmc; final IconData icon; final Color color;
  final String title, subtitle, msg, btnLabel; final VoidCallback onTap;
  const _Action({required this.kmc, required this.icon, required this.color, required this.title, required this.subtitle, required this.msg, required this.btnLabel, required this.onTap});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
    _IconBox(icon: icon, color: color),
    const SizedBox(height: 20),
    Text(title, style: TextStyle(color: kmc.text, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.3)),
    const SizedBox(height: 6),
    Text(subtitle, style: TextStyle(color: kmc.textSub, fontSize: 13)),
    const SizedBox(height: 28),
    Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: kmc.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: kmc.border)),
      child: Text(msg, style: TextStyle(color: kmc.textSub, fontSize: 13.5, height: 1.65), textAlign: TextAlign.center),
    ),
    const SizedBox(height: 28),
    SizedBox(width: double.infinity, height: 50,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.play_arrow_rounded, size: 20, color: Colors.white),
        label: Text(btnLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
        style: ElevatedButton.styleFrom(backgroundColor: color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
      ),
    ),
  ])));
}

class _Progress extends StatelessWidget {
  final KmColors kmc; final IconData icon; final Color color;
  final String title, msg; final double progress;
  const _Progress({required this.kmc, required this.icon, required this.color, required this.title, required this.msg, required this.progress});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
    _IconBox(icon: icon, color: color),
    const SizedBox(height: 24),
    Text(title, style: TextStyle(color: kmc.text, fontSize: 18, fontWeight: FontWeight.bold)),
    const SizedBox(height: 20),
    ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: progress > 0 ? progress : null, minHeight: 6, backgroundColor: kmc.border, color: color)),
    const SizedBox(height: 14),
    Text(msg, style: TextStyle(color: kmc.textSub, fontSize: 13, height: 1.5), textAlign: TextAlign.center),
  ])));
}

class _Error extends StatelessWidget {
  final KmColors kmc; final Color color; final String errMsg; final VoidCallback onRetry;
  const _Error({required this.kmc, required this.color, required this.errMsg, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
    _IconBox(icon: Icons.error_outline_rounded, color: const Color(0xFFEF4444)),
    const SizedBox(height: 20),
    Text('Terjadi Kesalahan', style: TextStyle(color: kmc.text, fontSize: 18, fontWeight: FontWeight.bold)),
    const SizedBox(height: 16),
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)),
      ),
      child: Text(errMsg, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13, height: 1.6), textAlign: TextAlign.center),
    ),
    const SizedBox(height: 24),
    SizedBox(width: double.infinity, height: 48,
      child: OutlinedButton.icon(
        onPressed: onRetry,
        icon: Icon(Icons.refresh_rounded, size: 18, color: color),
        label: Text('Coba Lagi', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(side: BorderSide(color: color), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      ),
    ),
  ])));
}

class _IconBox extends StatelessWidget {
  final IconData icon; final Color color;
  const _IconBox({required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: 88, height: 88,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
    ),
    child: Icon(icon, color: color, size: 44),
  );
}
