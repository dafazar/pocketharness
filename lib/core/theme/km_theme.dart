// lib/core/theme/km_theme.dart — updated for Pocket Harness Premium
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'km_colors.dart';

class KmThemeData {
  final ThemeData light;
  final ThemeData dark;
  KmThemeData({required this.light, required this.dark});
}

class KmTheme {
  KmTheme._();

  static KmColors fromPack(KmThemePack pack) {
    switch (pack) {
      case KmThemePack.white:   return KmColors.light;
      case KmThemePack.dark:    return KmColors.dark;
      case KmThemePack.amoled:  return KmColors.original;
      case KmThemePack.sakura:  return KmColors.sakura;
    }
  }

  static ThemeData buildFor(KmThemePack pack) {
    final c = fromPack(pack);
    final isDark = c.isDark;
    final colorScheme = ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: c.accent, onPrimary: Colors.white,
      primaryContainer: c.accentSoft, onPrimaryContainer: c.accent,
      secondary: c.gold, onSecondary: Colors.white,
      secondaryContainer: c.accentSoft, onSecondaryContainer: c.gold,
      tertiary: c.info, onTertiary: Colors.white,
      surface: c.bg, onSurface: c.text,
      surfaceContainerHighest: c.card, onSurfaceVariant: c.textSub,
      outline: c.border, outlineVariant: c.borderSoft,
      error: c.wrong, onError: Colors.white,
      shadow: Colors.black, scrim: Colors.black.withValues(alpha: 0.87),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      cardColor: c.card,
      dividerColor: c.divider,
      extensions: [c],
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg, foregroundColor: c.text,
        elevation: 0, scrolledUnderElevation: 0, centerTitle: true,
        titleTextStyle: TextStyle(color: c.text, fontSize: 17, fontWeight: FontWeight.w700),
        iconTheme: IconThemeData(color: c.text, size: 22),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.navBar, selectedItemColor: c.navBarSelected,
        unselectedItemColor: c.navBarItem, type: BottomNavigationBarType.fixed, elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: c.card, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.border)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: c.inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.accent, width: 1.5)),
        hintStyle: TextStyle(color: c.textMuted, fontSize: 14),
        labelStyle: TextStyle(color: c.textSub, fontSize: 13),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.accent, foregroundColor: Colors.white, elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.accent, side: BorderSide(color: c.accent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.accent),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(color: c.text, fontSize: 18, fontWeight: FontWeight.w700),
        contentTextStyle: TextStyle(color: c.textSub, fontSize: 14, height: 1.6),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.elevated, contentTextStyle: TextStyle(color: c.text, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent, linearTrackColor: c.accentSoft, circularTrackColor: c.accentSoft,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.inputFill, selectedColor: c.accentSoft,
        labelStyle: TextStyle(color: c.textSub, fontSize: 12),
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      dividerTheme: DividerThemeData(color: c.divider, thickness: 1, space: 1),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : c.textMuted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accentSoft : c.inputFill),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.accent, thumbColor: c.accent,
        inactiveTrackColor: c.border, overlayColor: c.accentSoft,
      ),
    );
  }

  static KmThemeData buildPair(KmThemePack pack) {
    final t = buildFor(pack);
    final isLight = pack == KmThemePack.white || pack == KmThemePack.sakura;
    return KmThemeData(
      light: isLight ? t : buildFor(KmThemePack.white),
      dark:  isLight ? buildFor(KmThemePack.amoled) : t,
    );
  }
}
