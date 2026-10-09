// lib/core/theme/theme_provider.dart
//
// Pocket Harness — ThemeNotifier + ThemePackNotifier
// Menyimpan & mengubah mode tema (gelap/terang).
// Pack: hanya ORIGINAL (AMOLED Black + Red) — default dan satu-satunya.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SharedPreferences provider — override with actual instance in main()
// ─────────────────────────────────────────────────────────────────────────────

// This provider MUST be overridden in main() via ProviderScope.overrides.
// The throw is intentional and unreachable at runtime if main() is correct.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw StateError(
  '[Pocket Harness] sharedPreferencesProvider must be overridden in ProviderScope. '
  'Check main.dart → runApp(ProviderScope(overrides: [...])).', 
),
);

// ─────────────────────────────────────────────────────────────────────────────
// AppThemePack — hanya original
// ─────────────────────────────────────────────────────────────────────────────

enum AppThemePack {
  original;

  String get id => 'original';

  String get label => 'Original';

  String get emoji => '☀️';

  String get svgIcon => 'assets/icons/logo/icon_theme_light.svg';

  String get description => 'AMOLED hitam, aksen merah, teks putih';

  String get previewImage => 'assets/theme/original/banners/banner_home.png';

  String get configPath => 'assets/theme/theme_config_original.json';
}

// ─────────────────────────────────────────────────────────────────────────────
// Keys SharedPreferences
// ─────────────────────────────────────────────────────────────────────────────

const _kDarkModeKey    = 'kmg.theme.dark_mode';
const _kDarkModeLegacy = 'kf_dark_mode';
const _kThemePackKey   = 'kmg.theme.pack';

// ─────────────────────────────────────────────────────────────────────────────
// ThemeNotifier — dark / light mode
// ─────────────────────────────────────────────────────────────────────────────

class ThemeNotifier extends Notifier<bool> {
  @override
  bool build() {
    _loadFromPrefs();
    return false; // Default: light mode (install pertama)
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    // Migrasi key lama → key baru (jalankan sekali)
    if (prefs.containsKey(_kDarkModeLegacy)) {
      final legacyValue = prefs.getBool(_kDarkModeLegacy) ?? false;
      await prefs.setBool(_kDarkModeKey, legacyValue);
      await prefs.remove(_kDarkModeLegacy);
    }

    final isDark = prefs.getBool(_kDarkModeKey) ?? false;
    if (state != isDark) state = isDark;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDarkModeKey, state);
  }

  Future<void> setDark(bool isDark) async {
    state = isDark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDarkModeKey, state);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ThemePackNotifier — selalu original
// ─────────────────────────────────────────────────────────────────────────────

class ThemePackNotifier extends Notifier<AppThemePack> {
  @override
  AppThemePack build() {
    _migrateOldPack();
    return AppThemePack.original;
  }

  /// Migrasi: hapus key pack lama yang tidak valid (white/dark)
  Future<void> _migrateOldPack() async {
    final prefs = await SharedPreferences.getInstance();
    // Selalu set ke original, menghapus nilai lama jika ada
    await prefs.setString(_kThemePackKey, AppThemePack.original.id);
  }

  Future<void> setPack(AppThemePack pack) async {
    state = AppThemePack.original; // selalu original
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemePackKey, AppThemePack.original.id);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers global
// ─────────────────────────────────────────────────────────────────────────────

/// Provider dark/light mode
final themeProvider = NotifierProvider<ThemeNotifier, bool>(ThemeNotifier.new);

/// Provider pilihan pack gambar tema (selalu original)
final themePackProvider = NotifierProvider<ThemePackNotifier, AppThemePack>(
  ThemePackNotifier.new,
);



/// Active KmColors for the current theme pack.
/// Used by offline_ai_screen and other screens that need direct color access.
final kfColorsProvider = Provider<dynamic>((ref) {
  final pack = ref.watch(themePackProvider);
  return pack;
});
