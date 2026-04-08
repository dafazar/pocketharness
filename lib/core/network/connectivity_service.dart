// lib/core/network/connectivity_service.dart
// KanMon GO — Connectivity Service (Fixed)
//
// PERUBAHAN dari versi sebelumnya:
//   ✅ connectivityProvider DIHAPUS dari file ini (sudah ada di no_internet_screen.dart)
//      Mendefinisikan provider yang sama di dua file akan menyebabkan
//      ProviderAlreadyInitializedException saat runtime.
//   ✅ ConnectivityGate DIHAPUS — gunakan OnlineGuard dari no_internet_screen.dart
//   ✅ SyncService.listenToConnectivity() difix support List<ConnectivityResult>
//
// Import connectivityProvider dari:
//   package:kanmongo/shared/widgets/no_internet_screen.dart
// =============================================================================

// File ini sengaja dikosongkan dari provider dan widget duplikat.
// Semua connectivity logic ada di:
//   lib/shared/widgets/no_internet_screen.dart
//
// Jika perlu cek koneksi secara manual di service lain, gunakan:
//
//   import 'package:connectivity_plus/connectivity_plus.dart';
//
//   Future<bool> isOnline() async {
//     final results = await Connectivity().checkConnectivity();
//     return results.any((r) =>
//       r == ConnectivityResult.wifi ||
//       r == ConnectivityResult.mobile ||
//       r == ConnectivityResult.ethernet);
//   }
