// lib/shared/widgets/view_toggle.dart
// Widget tombol toggle Grid ↔ List + helper persist SharedPreferences
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/km_colors.dart';

/// Load view mode dari prefs.
/// [defaultValue] menentukan tampilan awal saat belum pernah diubah user.
/// Gunakan false untuk screen yang default-nya list (bunpou, quiz).
Future<bool> loadViewMode(String key, {bool defaultValue = true}) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('kmg.view.$key') ?? defaultValue;
}

/// Simpan view mode ke prefs
Future<void> saveViewMode(String key, bool isGrid) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('kmg.view.$key', isGrid);
}

/// Tombol toggle Grid/List untuk AppBar actions
class ViewToggleButton extends StatelessWidget {
  final bool isGrid;
  final VoidCallback onToggle;

  const ViewToggleButton({
    super.key,
    required this.isGrid,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onToggle();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: c.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.accent.withValues(alpha: 0.30), width: 1.2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
              child: Icon(
                isGrid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                key: ValueKey(isGrid),
                size: 18,
                color: c.accent,
              ),
            ),
            const SizedBox(width: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                isGrid ? 'List' : 'Grid',
                key: ValueKey(isGrid),
                style: TextStyle(
                  color: c.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
