// lib/core/sync/sync_service.dart
// KanMon GO — Sync Service (Fixed)
//
// PERUBAHAN dari versi sebelumnya:
//   ✅ Connectivity().checkConnectivity() sekarang return List<ConnectivityResult>
//      (connectivity_plus v5+), bukan single ConnectivityResult
//   ✅ listenToConnectivity() difix untuk handle List result dari onConnectivityChanged
//   ✅ Tambah null-safety guard agar tidak crash jika user belum login
// =============================================================================

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanmongo/data/repositories/user_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SyncService {
  final UserRepository _repo;
  SyncService(this._repo);

  // ── Cek apakah ada koneksi aktif ─────────────────────────────────────────
  // FIX: connectivity_plus v5+ return List<ConnectivityResult>
  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet);

  // ── Sinkronisasi saat app start atau koneksi pulih ────────────────────────
  Future<void> syncOnConnect() async {
    // FIX: checkConnectivity() return List, bukan single value
    final results = await Connectivity().checkConnectivity();
    if (!_isOnline(results)) return;

    // Pastikan user sudah login sebelum sync ke Firestore
    if (FirebaseAuth.instance.currentUser == null) return;

    await _syncSettings();
  }

  // ── Sync settings dari SharedPreferences ke Firestore ────────────────────
  Future<void> _syncSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingSync = prefs.getBool('kmg.sync.settingsPending') ?? false;
      if (!pendingSync) return;

      final theme         = prefs.getString('kmg.theme.pack') ?? 'white';
      final dailyGoal     = prefs.getInt('kmg.dailyGoal') ?? 20;
      final notifications = prefs.getBool('kmg.notifications') ?? true;
      final ttsSpeed      = prefs.getDouble('kmg.ttsSpeed') ?? 1.0;

      await _repo.updateSettings({
        'theme': theme,
        'dailyGoal': dailyGoal,
        'notificationEnabled': notifications,
        'ttsSpeed': ttsSpeed,
      });

      await prefs.setBool('kmg.sync.settingsPending', false);
    } catch (_) {
      // Gagal sync — akan dicoba lagi di sesi berikutnya
    }
  }

  // ── Tandai settings perlu di-sync ke cloud ────────────────────────────────
  static Future<void> markSettingsDirty() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('kmg.sync.settingsPending', true);
  }

  // ── Listen perubahan koneksi, sync otomatis saat online ───────────────────
  // FIX: onConnectivityChanged sekarang emit List<ConnectivityResult>
  void listenToConnectivity() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (_isOnline(results)) {
        syncOnConnect();
      }
    });
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(ref.watch(userRepositoryProvider));
});
