import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'km_colors.dart';
import 'km_theme.dart';

// ── SharedPreferences provider ─────────────────
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override in main()'),
);

// ── Theme Pack Notifier ────────────────────────
class ThemePackNotifier extends Notifier<KmThemePack> {
  static const _key = 'kf_theme_pack';

  @override
  KmThemePack build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final saved = prefs.getString(_key);
    if (saved != null) {
      return KmThemePack.values.firstWhere(
        (p) => p.name == saved,
        orElse: () => KmThemePack.amoled,
      );
    }
    return KmThemePack.amoled; // default
  }

  void set(KmThemePack pack) {
    state = pack;
    ref.read(sharedPreferencesProvider).setString(_key, pack.name);
  }
}

final themePackProvider =
    NotifierProvider<ThemePackNotifier, KmThemePack>(ThemePackNotifier.new);

// ── ThemeMode provider ─────────────────────────
final themeModeProvider = Provider<ThemeMode>((ref) {
  final pack = ref.watch(themePackProvider);
  switch (pack) {
    case KmThemePack.white:
    case KmThemePack.sakura:
      return ThemeMode.light;
    case KmThemePack.dark:
    case KmThemePack.amoled:
      return ThemeMode.dark;
  }
});

// ── ThemeData provider ─────────────────────────
final themeDataProvider = Provider<KmThemeData>((ref) {
  final pack = ref.watch(themePackProvider);
  return KmThemeData(
    light: KmTheme.buildFor(pack),
    dark: KmTheme.buildFor(pack),
  );
});

// ── Active KmColors provider ───────────────────
final kfColorsProvider = Provider<KmColors>((ref) {
  final pack = ref.watch(themePackProvider);
  return KmColors.fromPack(pack);
});
