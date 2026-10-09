// lib/shared/widgets/no_internet_screen.dart
// Pocket Harness — Internet Guard (Premium Edition)
//
// FITUR:
//   ✅ Desain premium dengan animasi sinyal
//   ✅ Info detail tips koneksi
//   ✅ Kembali ke layar terakhir saat reconnect (tidak kembali ke awal)
//   ✅ Auto-detect reconnect via stream
//   ✅ Tombol Coba Lagi dengan loading state
// =============================================================================


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pocketharness/core/theme/km_colors.dart';
import 'package:pocketharness/shared/utils/top_snack.dart';

// ── Provider (definisi TUNGGAL) ───────────────────────────────────────────────
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final conn = Connectivity();
  final initial = await conn.checkConnectivity();
  yield _hasConnection(initial);
  await for (final results in conn.onConnectivityChanged) {
    yield _hasConnection(results);
  }
});

bool _hasConnection(List<ConnectivityResult> results) =>
    results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);

// ── OnlineGuard ───────────────────────────────────────────────────────────────
class OnlineGuard extends ConsumerWidget {
  final Widget child;
  const OnlineGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectivityProvider);
    return conn.when(
      data: (isOnline) => isOnline ? child : const NoInternetScreen(),
      loading: () => child,
      error: (_, __) => child,
    );
  }
}

// ── NoInternetScreen ──────────────────────────────────────────────────────────
class NoInternetScreen extends StatefulWidget {
  const NoInternetScreen({super.key});
  @override
  State<NoInternetScreen> createState() => _NoInternetScreenState();
}

class _NoInternetScreenState extends State<NoInternetScreen>
    with TickerProviderStateMixin {

  // Animasi gelombang sinyal
  late AnimationController _waveCtrl;
  late AnimationController _floatCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _float;
  late Animation<double> _fadeIn;

  bool _isChecking = false;
  int _retryCount  = 0;

  @override
  void initState() {
    super.initState();

    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _float = Tween<double>(begin: -8, end: 8).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );

    _fadeIn = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    _floatCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_isChecking) return;
    setState(() { _isChecking = true; _retryCount++; });
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    final result = await Connectivity().checkConnectivity();
    if (!mounted) return;
    setState(() => _isChecking = false);
    if (!_hasConnection(result)) {
      showTopSnack(context, 'Masih offline. Percobaan ke-$_retryCount gagal.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c       = KmColors.of(context);
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final size    = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: c.bg,
      body: FadeTransition(
        opacity: _fadeIn,
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: size.height - 80),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),

                    // ── Ilustrasi sinyal animasi ─────────────────────────
                    AnimatedBuilder(
                      animation: Listenable.merge([_waveCtrl, _floatCtrl]),
                      builder: (_, child) => Transform.translate(
                        offset: Offset(0, _float.value),
                        child: child,
                      ),
                      child: SizedBox(
                        width: 200,
                        height: 200,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Gelombang ping
                            ...[0.3, 0.6, 0.9].map((delay) =>
                              _WaveRing(
                                controller: _waveCtrl,
                                delay: delay,
                                color: const Color(0xFFDC2626),
                                maxRadius: 90,
                              ),
                            ),
                            // Lingkaran utama
                            Container(
                              width: 110, height: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isDark
                                    ? const Color(0xFF1A0505)
                                    : const Color(0xFFFEF2F2),
                                border: Border.all(
                                  color: const Color(0xFFDC2626).withValues(alpha: 0.3),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFDC2626).withValues(alpha: 0.15),
                                    blurRadius: 30,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: const _SignalIcon(),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Judul & deskripsi ────────────────────────────────
                    Text(
                      'Koneksi Terputus',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: c.text,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Tidak dapat terhubung ke internet.\nProgress belajarmu aman — akan lanjut\notomatis saat koneksi pulih.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.7,
                        color: c.textMuted,
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── Info cards ───────────────────────────────────────
                    _InfoCard(
                      isDark: isDark,
                      children: [
                        _InfoRow(
                          icon: Icons.wifi_rounded,
                          iconColor: const Color(0xFF3B82F6),
                          title: 'Periksa WiFi',
                          desc: 'Pastikan WiFi aktif & terhubung ke jaringan',
                        ),
                        _Divider(isDark: isDark),
                        _InfoRow(
                          icon: Icons.signal_cellular_alt_rounded,
                          iconColor: const Color(0xFF10B981),
                          title: 'Data Seluler',
                          desc: 'Aktifkan data seluler jika WiFi tidak tersedia',
                        ),
                        _Divider(isDark: isDark),
                        _InfoRow(
                          icon: Icons.airplanemode_off_rounded,
                          iconColor: const Color(0xFFF59E0B),
                          title: 'Mode Pesawat',
                          desc: 'Matikan mode pesawat jika sedang aktif',
                        ),
                        _Divider(isDark: isDark),
                        _InfoRow(
                          icon: Icons.router_rounded,
                          iconColor: const Color(0xFF8B5CF6),
                          title: 'Router / Modem',
                          desc: 'Coba restart router atau ganti ke hotspot HP',
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ── Tombol Coba Lagi ─────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isChecking ? null : _retry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFDC2626).withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: _isChecking
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white.withValues(alpha: 0.8),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text('Memeriksa koneksi...',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                ],
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.refresh_rounded, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    _retryCount > 0
                                        ? 'Coba Lagi (${_retryCount}x)'
                                        : 'Coba Lagi',
                                    style: const TextStyle(
                                        fontSize: 15, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ── Status auto-monitor ──────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PulsingDot(color: const Color(0xFF10B981)),
                          const SizedBox(width: 8),
                          Text(
                            'Memantau koneksi secara otomatis...',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: c.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Wave Ring Animation ───────────────────────────────────────────────────────
class _WaveRing extends AnimatedWidget {
  final double delay;
  final Color color;
  final double maxRadius;

  const _WaveRing({
    required AnimationController controller,
    required this.delay,
    required this.color,
    required this.maxRadius,
  }) : super(listenable: controller);

  @override
  Widget build(BuildContext context) {
    final ctrl = listenable as AnimationController;
    // Offset value by delay (0.0 - 1.0)
    final value = ((ctrl.value + delay) % 1.0);
    final opacity = (1.0 - value).clamp(0.0, 0.6);
    final radius  = maxRadius * value;

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: opacity),
          width: 1.5,
        ),
      ),
    );
  }
}

// ── Signal Icon (animasi bar sinyal) ─────────────────────────────────────────
class _SignalIcon extends StatelessWidget {
  const _SignalIcon();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(52, 42),
      painter: _SignalPainter(
        color: const Color(0xFFDC2626),
      ),
    );
  }
}

class _SignalPainter extends CustomPainter {
  final Color color;
  const _SignalPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5;

    final paintActive = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5;

    const barCount = 4;
    final barWidth = size.width / (barCount * 2 - 1);
    final spacing  = barWidth;

    for (int i = 0; i < barCount; i++) {
      final x      = i * (barWidth + spacing) + barWidth / 2;
      final barH   = size.height * (0.3 + 0.7 * (i / (barCount - 1)));
      final top    = size.height - barH;
      // Hanya bar pertama yang "aktif" (sinyal lemah)
      final p = i == 0 ? paintActive : paint;
      canvas.drawLine(Offset(x, top), Offset(x, size.height), p);
    }

    // Garis X di atas
    final xPaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      const Offset(32, 4), const Offset(46, 16), xPaint);
    canvas.drawLine(
      const Offset(46, 4), const Offset(32, 16), xPaint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Info Card ─────────────────────────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;

  const _InfoCard({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.07),
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String desc;

  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: c.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(desc,
                  style: TextStyle(
                    fontSize: 12,
                    color: c.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final bool isDark;
  const _Divider({required this.isDark});
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 68,
      endIndent: 16,
      color: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.06),
    );
  }
}

// ── Pulsing dot indicator ─────────────────────────────────────────────────────
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 8, height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: _anim.value),
        ),
      ),
    );
  }
}
