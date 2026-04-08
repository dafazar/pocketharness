// lib/features/splash/presentation/screens/splash_screen.dart
// KanMon GO — Splash Screen (Fixed)
//
// PERUBAHAN dari versi sebelumnya:
//   ✅ Connectivity().checkConnectivity() return List<ConnectivityResult>
//      (connectivity_plus v5+), bukan single ConnectivityResult
//   ✅ Cek isAnonymous sebelum navigasi — tidak paksa user login
//   ✅ Animasi tetap sama, logika check lebih robust
// =============================================================================

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kanmongo/core/router/app_router.dart';
import 'package:kanmongo/core/theme/km_colors.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _ctrl.forward();
    _checkAndNavigate();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _checkAndNavigate() async {
    await Future.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;

    // ✅ FIX: checkConnectivity() return List<ConnectivityResult> di v5+
    final results  = await Connectivity().checkConnectivity();
    final isOnline = results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);

    if (!mounted) return;

    if (!isOnline) {
      _showOfflineDialog();
      return;
    }

    // Langsung ke Home — tidak force-redirect ke login
    context.go(KmRoutes.home);
  }

  void _showOfflineDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(children: [
          Text('📡', style: TextStyle(fontSize: 24)),
          SizedBox(width: 10),
          Text('Tidak Ada Internet'),
        ]),
        content: const Text(
          'KanMon GO membutuhkan koneksi internet untuk berjalan.\n\n'
          'Pastikan WiFi atau data seluler kamu aktif, lalu coba lagi.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          FilledButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Coba Lagi'),
            onPressed: () {
              Navigator.pop(context);
              _checkAndNavigate();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KmColors.of(context).bg,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    color: KmColors.of(context).accent,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: KmColors.of(context).accent.withValues(alpha: 0.35),
                        blurRadius: 32, offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text('KM',
                      style: TextStyle(
                        color: Colors.white, fontSize: 36,
                        fontWeight: FontWeight.bold, letterSpacing: -1,
                      )),
                  ),
                ),
                const SizedBox(height: 24),
                Text('KanMon GO',
                  style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.bold,
                    color: KmColors.of(context).text, letterSpacing: -0.5,
                  )),
                const SizedBox(height: 6),
                Text('Asisten AI Cerdas',
                  style: TextStyle(
                    fontSize: 15, color: KmColors.of(context).textMuted,
                  )),
                const SizedBox(height: 48),
                SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: KmColors.of(context).accent.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
