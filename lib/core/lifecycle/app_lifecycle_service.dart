// lib/core/lifecycle/app_lifecycle_service.dart
// KanMon GO — App Lifecycle Service (Fixed)
//
// PERUBAHAN dari versi sebelumnya:
//   ✅ _onResume() sekarang juga memanggil SecureDbKeyService.ensureKeys()
//      Jika app di-resume setelah lama di background dan key sudah hilang
//      dari memory (misal: OS reclaim memory), key akan di-fetch ulang otomatis
//   ✅ debugPrint menggantikan print
// =============================================================================

import 'package:flutter/material.dart';
import 'package:kanmongo/core/security/secure_db_key_service.dart';
import 'package:kanmongo/data/services/sfx_service.dart';

class AppLifecycleService extends WidgetsBindingObserver {
  AppLifecycleService._();
  static final AppLifecycleService instance = AppLifecycleService._();

  final Map<String, Future<void> Function()> _pauseCallbacks  = {};
  final Map<String, Future<void> Function()> _resumeCallbacks = {};

  void addPauseCallback(String key, Future<void> Function() cb) {
    _pauseCallbacks[key] = cb;
  }

  void addResumeCallback(String key, Future<void> Function() cb) {
    _resumeCallbacks[key] = cb;
  }

  void removeCallbacks(String key) {
    _pauseCallbacks.remove(key);
    _resumeCallbacks.remove(key);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _onPause();
        break;
      case AppLifecycleState.resumed:
        _onResume();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _onPause();
        break;
    }
  }

  Future<void> _onPause() async {
    await SfxService.instance.stopAndReset();
    for (final cb in _pauseCallbacks.values) {
      try { await cb(); } catch (_) {}
    }
  }

  Future<void> _onResume() async {
    // Reset audio pool
    await SfxService.instance.stopAndReset();

    // ✅ FIX: Re-fetch DB key jika hilang dari memory setelah OS reclaim
    // (misal: app di background > 30 menit, OS bisa clear memory)
    try {
      await SecureDbKeyService.instance.ensureKeys();
    } catch (e) {
      debugPrint('[AppLifecycleService] Gagal re-fetch DB key saat resume: $e');
    }

    for (final cb in _resumeCallbacks.values) {
      try { await cb(); } catch (_) {}
    }
  }
}
