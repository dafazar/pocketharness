// lib/core/theme/app_theme.dart
// KanMon GO — Professional Theme System
// ─────────────────────────────────────────────────────────────────────────────
// Typography: Nunito (UI) — bulat, ramah, terbaca — pair dengan Noto Sans JP
// Spacing: 8pt grid — konsisten di seluruh app
// Radius: 12px komponen kecil, 16px card, 20px modal
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// google_fonts import removed — menggunakan TextStyle biasa (offline-safe)
import 'km_colors.dart';

class AppTheme {
  AppTheme._();

  // ── Radius constants ─────────────────────────────────────────────────────
  static const double radiusSm  = 8.0;
  static const double radiusMd  = 12.0;
  static const double radiusLg  = 16.0;
  static const double radiusXl  = 20.0;
  static const double radiusXxl = 24.0;

  // ── Spacing constants (8pt grid) ────────────────────────────────────────
  static const double sp2  = 2.0;
  static const double sp4  = 4.0;
  static const double sp6  = 6.0;
  static const double sp8  = 8.0;
  static const double sp12 = 12.0;
  static const double sp16 = 16.0;
  static const double sp20 = 20.0;
  static const double sp24 = 24.0;
  static const double sp32 = 32.0;

  static ThemeData get darkTheme  => _build(KmColors.original, Brightness.dark);   // AMOLED Black + Red
  static ThemeData get lightTheme => _build(KmColors.light,    Brightness.light);  // White + Red

  static TextTheme _textTheme(KmColors c) {
    // Nunito untuk UI text — round, readable, professional
    // Fallback ke system font jika Nunito tidak tersedia (offline)
    // Gunakan TextStyle biasa — offline-safe, tidak perlu download font

    return const TextTheme().copyWith(
      // Display — jarang dipakai, untuk hero text
      displayLarge:  TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: c.text, letterSpacing: -1.0, height: 1.1),
      displayMedium: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: c.text, letterSpacing: -0.5, height: 1.15),

      // Headline — judul section, halaman
      headlineLarge:  TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: c.text, letterSpacing: -0.3, height: 1.25),
      headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.text, letterSpacing: -0.2, height: 1.3),
      headlineSmall:  TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text, letterSpacing: -0.1, height: 1.35),

      // Title — AppBar, card title
      titleLarge:  TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text, letterSpacing: 0.0,  height: 1.4),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text, letterSpacing: 0.1,  height: 1.4),
      titleSmall:  TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSub, letterSpacing: 0.1, height: 1.45),

      // Body — konten utama
      bodyLarge:  TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: c.text,    height: 1.6),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: c.textSub, height: 1.6),
      bodySmall:  TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: c.textMuted, height: 1.55),

      // Label — chip, badge, tag
      labelLarge:  TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text, letterSpacing: 0.3),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textSub, letterSpacing: 0.4),
      labelSmall:  TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.textMuted, letterSpacing: 0.5),
    );
  }

  static ThemeData _build(KmColors c, Brightness br) {
    final textTheme = _textTheme(c);

    return ThemeData(
      useMaterial3: true,
      brightness: br,
      // Prevent ghost ripple circles in dark containers
      splashColor: c.accent.withValues(alpha: 0.12),
      highlightColor: c.accent.withValues(alpha: 0.06),
      colorScheme: ColorScheme(
        brightness:            br,
        primary:               c.accent,
        onPrimary:             Colors.white,  // teks di atas tombol merah — selalu putih
        secondary:             c.accentSoft,
        onSecondary:           c.bg,
        tertiary:              c.gold,
        onTertiary:            c.bg,
        surface:               c.card,
        onSurface:             c.text,
        error:                 const Color(0xFFEF4444),
        onError:               Colors.white,
        outline:               c.border,
        outlineVariant:        c.borderSoft,
        surfaceContainerHighest: c.elevated,
        surfaceContainerHigh:  c.surface,
        shadow:                Colors.black,
        scrim:                 c.overlay,
        inverseSurface:        c.accent,
        onInverseSurface:      c.bg,
        inversePrimary:        c.bg,
      ),
      scaffoldBackgroundColor: c.bg,
      extensions: [c],
      textTheme: textTheme,

      // ── AppBar ──────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor:        c.bg,
        elevation:              0,
        scrolledUnderElevation: 0,
        centerTitle:            false,
        titleTextStyle: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700,
          color: c.text, letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: c.text, size: 22),
        actionsIconTheme: IconThemeData(color: c.textSub, size: 22),
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: br == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),

      // ── TabBar ──────────────────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        indicatorColor:         c.accent,
        indicatorSize:          TabBarIndicatorSize.tab,
        labelColor:             c.accent,
        unselectedLabelColor:   c.textMuted,
        labelStyle:    TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        dividerColor:           c.borderSoft,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
      ),

      // ── Card ─────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color:     c.card,
        elevation: 0,
        margin:    EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: c.border, width: 1),
        ),
      ),

      // ── Buttons ──────────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: Colors.white,  // teks tombol — selalu putih di atas merah
          elevation:       0,
          padding: const EdgeInsets.symmetric(horizontal: sp24, vertical: sp12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
          textStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2),
          minimumSize: const Size(0, 48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          side:            BorderSide(color: c.border, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: sp20, vertical: sp12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
          textStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          minimumSize: const Size(0, 44),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          padding: const EdgeInsets.symmetric(horizontal: sp12, vertical: sp8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          textStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      // ── Chip ─────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor:  c.surface,
        selectedColor:    c.accent.withValues(alpha: 0.15),
        labelStyle: TextStyle(color: c.textSub, fontSize: 12, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: sp8, vertical: sp4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
        side: BorderSide(color: c.border, width: 1),
        elevation: 0,
      ),

      // ── Input ─────────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled:           true,
        fillColor:        c.inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: sp16, vertical: sp14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide:   BorderSide(color: c.border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide:   BorderSide(color: c.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide:   BorderSide(color: c.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide:   const BorderSide(color: Color(0xFFEF4444), width: 1),
        ),
        hintStyle:         TextStyle(color: c.textMuted, fontSize: 14),
        labelStyle:        TextStyle(color: c.textSub,   fontSize: 14),
        prefixIconColor:   c.textMuted,
        suffixIconColor:   c.textMuted,
      ),

      // ── Divider ───────────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color:     c.divider,
        thickness: 1,
        space:     1,
      ),

      // ── Switch ────────────────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? c.bg : c.textMuted),
        trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? c.accent : c.surface),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      // ── Slider ────────────────────────────────────────────────────────────
      sliderTheme: SliderThemeData(
        activeTrackColor:         c.accent,
        inactiveTrackColor:       c.surface,
        thumbColor:               c.accent,
        overlayColor:             c.accent.withValues(alpha: 0.15),
        trackHeight:              3,
        thumbShape:               const RoundSliderThumbShape(enabledThumbRadius: 8),
        valueIndicatorColor:      c.elevated,
        valueIndicatorTextStyle:  TextStyle(color: c.text, fontSize: 12, fontWeight: FontWeight.w600),
      ),

      // ── Progress ──────────────────────────────────────────────────────────
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color:            c.accent,
        linearTrackColor: c.surface,
        circularTrackColor: c.surface,
        linearMinHeight:  3,
      ),

      // ── Dialog ────────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: c.card,
        elevation:       0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXxl),
          side: BorderSide(color: c.border, width: 1),
        ),
        titleTextStyle: TextStyle(
          color: c.text, fontSize: 18, fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(
          color: c.textSub, fontSize: 14, height: 1.6,
        ),
      ),

      // ── Bottom Sheet ──────────────────────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor:  c.card,
        elevation:        0,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXxl)),
        ),
        showDragHandle: false,
      ),

      // ── Snackbar ──────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor:  c.elevated,
        contentTextStyle: TextStyle(color: c.text, fontSize: 14),
        actionTextColor:  c.accent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: c.border, width: 1),
        ),
        behavior:   SnackBarBehavior.floating,
        elevation:  0,
        insetPadding: const EdgeInsets.all(sp16),
      ),

      // ── Popup Menu ────────────────────────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color:     c.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: c.border, width: 1),
        ),
        textStyle: TextStyle(color: c.text, fontSize: 14),
        surfaceTintColor: Colors.transparent,
      ),

      // ── List Tile ─────────────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: sp16, vertical: sp4),
        minLeadingWidth: 0,
        iconColor: c.textMuted,
        titleTextStyle: TextStyle(color: c.text, fontSize: 15, fontWeight: FontWeight.w600),
        subtitleTextStyle: TextStyle(color: c.textSub, fontSize: 13),
      ),

      // ── Bottom Nav ────────────────────────────────────────────────────────
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor:      c.card,
        selectedItemColor:    c.accent,
        unselectedItemColor:  c.textMuted,
        type:      BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle:   TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }

  static const double sp14 = 14.0;
}
