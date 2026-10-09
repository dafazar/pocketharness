// lib/features/onboarding/presentation/screens/permission_onboarding_screen.dart
//
// Pocket Harness — Layar Onboarding Izin
// Ditampilkan satu kali saat pertama kali install/buka.
// Menampilkan setiap izin satu per satu dengan penjelasan yang jelas.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pocketharness/core/theme/km_colors.dart';
import 'package:pocketharness/data/services/permission_service.dart';
import 'package:pocketharness/data/services/sfx_service.dart';

class PermissionOnboardingScreen extends StatefulWidget {
  /// Dipanggil setelah user selesai (lewati atau izinkan semua)
  final VoidCallback onDone;

  const PermissionOnboardingScreen({super.key, required this.onDone});

  @override
  State<PermissionOnboardingScreen> createState() =>
      _PermissionOnboardingScreenState();
}

class _PermissionOnboardingScreenState
    extends State<PermissionOnboardingScreen>
    with TickerProviderStateMixin {

  late final List<PermissionItem> _items;
  int _currentIndex = 0;

  // Status tiap izin: null = belum diminta, true = granted, false = denied
  late final List<PermissionStatus?> _statuses;

  late AnimationController _cardCtrl;
  late Animation<double> _cardScale;
  late Animation<double> _cardOpacity;

  late AnimationController _iconCtrl;
  late Animation<double> _iconBounce;

  bool _requesting = false;
  bool _allDone = false;

  @override
  void initState() {
    super.initState();
    _items = buildPermissionList();
    _statuses = List.filled(_items.length, null);

    // Auto-check dan skip izin yang sudah diberikan sebelumnya
    _checkExistingPermissions();

    _cardCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _cardScale = Tween<double>(begin: 0.88, end: 1.0)
        .animate(CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutBack));
    _cardOpacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOut));

    _iconCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _iconBounce = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _iconCtrl, curve: Curves.elasticOut));

    _cardCtrl.forward();
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) _iconCtrl.forward();
    });
  }

  @override
  void dispose() {
    _cardCtrl.dispose();
    _iconCtrl.dispose();
    super.dispose();
  }

  // ── Auto-skip izin yang sudah diberikan ──────────────────────────────────

  Future<void> _checkExistingPermissions() async {
    for (int i = 0; i < _items.length; i++) {
      final already = await PermissionService.instance.isAlreadyGranted(_items[i].permission);
      if (already && mounted) {
        if (mounted) setState(() => _statuses[i] = PermissionStatus.granted);
      }
    }
    // Jika SEMUA sudah granted, langsung selesai
    if (mounted) {
      final allGranted = _statuses.every((s) => s?.isGranted == true || s?.isLimited == true);
      if (allGranted && _items.isNotEmpty) {
        // Tandai done dan langsung panggil onDone
        await PermissionService.instance.markOnboardingDone();
        widget.onDone();
      }
    }
  }

  // ── Navigasi antar izin ────────────────────────────────────────────────────

  void _animateToNext() async {
    await _cardCtrl.reverse();
    if (!mounted) return;
    if (mounted) setState(() {
      if (_currentIndex < _items.length - 1) {
        _currentIndex++;
      } else {
        _allDone = true;
      }
    });
    _iconCtrl.reset();
    _cardCtrl.forward();
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) _iconCtrl.forward();
    });
  }

  // ── Request izin ───────────────────────────────────────────────────────────

  Future<void> _requestPermission() async {
    if (_requesting) return;
    if (mounted) setState(() => _requesting = true);
    SfxService.instance.play(Sfx.tap);

    final item = _items[_currentIndex];
    final status = await PermissionService.instance.request(item.permission);

    if (mounted) setState(() {
      _statuses[_currentIndex] = status;
      _requesting = false;
    });

    if (status.isGranted || status.isLimited) {
      SfxService.instance.play(Sfx.correct);
    }

    await Future.delayed(const Duration(milliseconds: 600));
    _animateToNext();
  }

  // ── Skip izin ini ──────────────────────────────────────────────────────────

  void _skip() {
    SfxService.instance.play(Sfx.tap);
    _statuses[_currentIndex] = PermissionStatus.denied;
    _animateToNext();
  }

  // ── Selesai ────────────────────────────────────────────────────────────────

  Future<void> _finish() async {
    SfxService.instance.play(Sfx.perfect);
    await PermissionService.instance.markOnboardingDone();
    widget.onDone();
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: _allDone ? _buildDoneScreen(c) : _buildPermScreen(c),
      ),
    );
  }

  // ── Layar ringkasan selesai ────────────────────────────────────────────────

  Widget _buildDoneScreen(KmColors c) {
    final granted = _statuses.where((s) => s?.isGranted == true || s?.isLimited == true).length;
    final total = _items.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Ikon ceklis besar
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3), width: 2),
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: Color(0xFF10B981), size: 56),
          ),

          const SizedBox(height: 28),

          Text(
            'Siap Belajar! 🎉',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: c.text,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$granted dari $total izin diberikan',
            style: TextStyle(fontSize: 15, color: c.textMuted),
          ),

          const SizedBox(height: 32),

          // Ringkasan status tiap izin
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: Column(
              children: List.generate(_items.length, (i) {
                final item = _items[i];
                final status = _statuses[i];
                final isOk = status?.isGranted == true || status?.isLimited == true;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(item.icon, color: item.color, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(item.title,
                          style: TextStyle(color: c.text, fontSize: 14,
                              fontWeight: FontWeight.w500)),
                    ),
                    Icon(
                      isOk ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: isOk ? const Color(0xFF10B981) : c.textMuted,
                      size: 20,
                    ),
                  ]),
                );
              }),
            ),
          ),

          const SizedBox(height: 12),

          if (_statuses.any((s) => s?.isPermanentlyDenied == true))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextButton.icon(
                onPressed: () => openAppSettings(),
                icon: Icon(Icons.settings_rounded, size: 16, color: c.accent),
                label: Text('Aktifkan izin di Pengaturan Sistem',
                    style: TextStyle(color: c.accent, fontSize: 13)),
              ),
            ),

          const SizedBox(height: 8),

          // Tombol mulai
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _finish,
              style: ElevatedButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Mulai Belajar  →',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Layar per izin ─────────────────────────────────────────────────────────

  Widget _buildPermScreen(KmColors c) {
    final item = _items[_currentIndex];
    final isLast = _currentIndex == _items.length - 1;

    return Column(
      children: [
        // Progress dots + skip
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Row(children: [
            // Progress dots
            Row(
              children: List.generate(_items.length, (i) {
                final active = i == _currentIndex;
                final done = i < _currentIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.only(right: 6),
                  width: active ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: done
                        ? const Color(0xFF10B981)
                        : active
                            ? item.color
                            : c.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),

            const Spacer(),

            // Skip (hanya untuk izin tidak wajib)
            if (!item.required)
              TextButton(
                onPressed: _requesting ? null : _skip,
                child: Text(
                  'Lewati',
                  style: TextStyle(color: c.textMuted, fontSize: 13),
                ),
              ),
          ]),
        ),

        const Spacer(),

        // Kartu izin
        FadeTransition(
          opacity: _cardOpacity,
          child: ScaleTransition(
            scale: _cardScale,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: item.color.withValues(alpha: 0.25), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: item.color.withValues(alpha: 0.12),
                      blurRadius: 32,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // Ikon izin (animated bounce)
                    ScaleTransition(
                      scale: _iconBounce,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: item.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: item.color.withValues(alpha: 0.3)),
                        ),
                        child: Icon(item.icon, color: item.color, size: 36),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Badge "wajib / opsional"
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: item.required
                            ? const Color(0xFFDC2626).withValues(alpha: 0.1)
                            : item.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: item.required
                              ? const Color(0xFFDC2626).withValues(alpha: 0.3)
                              : item.color.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        item.required ? '● Diperlukan' : '○ Opsional',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: item.required
                              ? const Color(0xFFDC2626)
                              : item.color,
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Judul
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Subtitle
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: item.color,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Penjelasan panjang
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: c.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 16, color: c.textMuted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.reason,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: c.textSub,
                                  height: 1.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        const Spacer(),

        // Tombol izinkan
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
          child: Column(children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _requesting ? null : _requestPermission,
                style: ElevatedButton.styleFrom(
                  backgroundColor: item.color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                  disabledBackgroundColor: item.color.withValues(alpha: 0.5),
                ),
                child: _requesting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_rounded, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            isLast ? 'Izinkan & Lanjut' : 'Izinkan',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
              ),
            ),

            // Tombol lewati (hanya untuk opsional)
            if (!item.required) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _requesting ? null : _skip,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Tidak sekarang',
                    style: TextStyle(
                      fontSize: 14,
                      color: c.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ]),
        ),

        // Counter
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Text(
            '${_currentIndex + 1} / ${_items.length}',
            style: TextStyle(fontSize: 12, color: c.textMuted),
          ),
        ),
      ],
    );
  }
}
