// lib/shared/widgets/screen_theme_banner.dart
//
// Widget banner + background yang reaktif terhadap perubahan theme pack.
// Menggunakan ConsumerWidget agar rebuild otomatis saat pack berubah.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme_service.dart';
import '../../core/theme/theme_provider.dart';
import 'package:kanmongo/core/theme/km_colors.dart';

/// Banner di bawah AppBar — reaktif terhadap perubahan theme pack.
class ScreenThemeBanner extends ConsumerWidget {
  final String screenKey;
  final double height;
  final double horizontalPadding;

  const ScreenThemeBanner({
    super.key,
    required this.screenKey,
    this.height = 100,
    this.horizontalPadding = 16,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch pack agar widget rebuild saat pack berubah
    ref.watch(themePackProvider);

    final path = AppThemeService.instance.banner(screenKey);
    if (path.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset(
          path,
          key: ValueKey(path), // force rebuild gambar saat path berubah
          width: double.infinity,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Background penuh satu screen — reaktif terhadap perubahan theme pack.
class ScreenThemeBackground extends ConsumerWidget {
  final String screenKey;
  const ScreenThemeBackground({super.key, required this.screenKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themePackProvider);

    final path = AppThemeService.instance.background(screenKey);
    if (path.isEmpty) return const SizedBox.shrink();
    return Positioned.fill(
      child: Image.asset(
        path,
        key: ValueKey(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}

/// Kartu sub-menu dengan gambar dari theme — reaktif terhadap perubahan pack.
class ThemeImageCard extends ConsumerWidget {
  final ThemeItem? item;
  final Color fallbackColor;
  final String fallbackIcon;
  final String fallbackLabel;
  final VoidCallback? onTap;
  final Widget? overlay;

  const ThemeImageCard({
    super.key,
    required this.item,
    required this.fallbackColor,
    required this.fallbackIcon,
    required this.fallbackLabel,
    this.onTap,
    this.overlay,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themePackProvider);

    final color     = item?.color ?? fallbackColor;
    final imagePath = item?.image ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imagePath.isNotEmpty)
                Image.asset(
                  imagePath,
                  key: ValueKey(imagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.60),
                    ],
                  ),
                ),
              ),
              if (overlay != null) overlay!,
            ],
          ),
        ),
      ),
    );
  }
}
