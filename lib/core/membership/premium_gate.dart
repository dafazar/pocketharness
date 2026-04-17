// lib/core/membership/premium_gate.dart
// Premium Gate — DISABLED (semua fitur gratis)
// Untuk mengaktifkan kembali, implementasikan RevenueCat dan
// kembalikan logika isPremium yang sesungguhnya.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PremiumGate extends ConsumerWidget {
  final Widget child;
  final Widget? lockedWidget;
  final String? featureLabel;

  const PremiumGate({
    super.key,
    required this.child,
    this.lockedWidget,
    this.featureLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Premium gate dinonaktifkan — tampilkan child langsung
    return child;
  }

  // Helper check — selalu return true (semua akses diizinkan)
  static Future<bool> check(
    BuildContext context,
    WidgetRef ref, {
    String? featureLabel,
  }) async {
    return true; // tidak ada blokir
  }
}

// PaywallBottomSheet — premium gate dinonaktifkan, tampilkan kosong
class PaywallBottomSheet extends StatelessWidget {
  final String? featureLabel;
  const PaywallBottomSheet({super.key, this.featureLabel});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
