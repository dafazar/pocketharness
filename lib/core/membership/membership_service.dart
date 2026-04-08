// lib/core/membership/membership_service.dart
// KanMon GO — Membership Service
// Premium gate DINONAKTIFKAN — semua fitur gratis.
// Untuk mengaktifkan RevenueCat, ganti implementasi di sini.
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class MembershipService {
  // Init dinonaktifkan — tidak perlu RevenueCat key
  static Future<void> init(String userId) async {
    debugPrint('[MembershipService] Premium gate dinonaktifkan — skip init');
  }

  // Semua user dianggap premium
  Future<bool> isPremium() async => true;

  // Tidak ada produk yang dijual
  Future<List<Package>> getOfferings() async => [];

  // Purchase selalu "berhasil" (tidak ada transaksi nyata)
  Future<bool> purchasePackage(Package package) async => true;

  // Restore selalu "berhasil"
  Future<bool> restorePurchases() async => true;

  Future<CustomerInfo?> getCustomerInfo() async => null;
  Future<void> logout() async {}

  Stream<CustomerInfo> get customerInfoStream => const Stream.empty();
}

// Provider tetap ada untuk backward compatibility
final membershipServiceProvider = Provider<MembershipService>(
  (ref) => MembershipService(),
);

// isPremiumProvider selalu return true
final isPremiumProvider = FutureProvider<bool>((ref) async => true);

// customerInfoStreamProvider — stream kosong
final customerInfoStreamProvider = StreamProvider<CustomerInfo>((ref) {
  return const Stream.empty();
});
