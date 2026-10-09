import 'package:flutter/material.dart';

enum KmThemePack { white, dark, amoled, sakura }

/// Sistem warna Pocket Harness — responsive terhadap tema aktif.
class KmColors extends ThemeExtension<KmColors> {
  final KmThemePack pack;
  final Color bg, card, surface, elevated;
  final Color accent, accentSoft, gold;
  final Color text, textSub, textMuted;
  final Color border, borderSoft, divider, overlay;
  final Color canvasBg, canvasInk, canvasShadow, canvasGrid, inputFill;
  final Color navBar, navBarItem, navBarSelected, streak;
  final Color correct, wrong, warning, info;

  const KmColors({
    required this.pack,
    required this.bg, required this.card, required this.surface, required this.elevated,
    required this.accent, required this.accentSoft, required this.gold,
    required this.text, required this.textSub, required this.textMuted,
    required this.border, required this.borderSoft, required this.divider, required this.overlay,
    required this.canvasBg, required this.canvasInk, required this.canvasShadow,
    required this.canvasGrid, required this.inputFill,
    required this.navBar, required this.navBarItem, required this.navBarSelected, required this.streak,
    required this.correct, required this.wrong, required this.warning, required this.info,
  });

  bool get isDark  => pack == KmThemePack.dark || pack == KmThemePack.amoled;
  bool get isLight => pack == KmThemePack.white || pack == KmThemePack.sakura;
  Color get onSurface => text; // Warna teks yang kontras dengan surface

  // ── AMOLED Black + Red (default) ──────────────────────────────────────────
  static const KmColors original = KmColors(
    pack: KmThemePack.amoled,
    bg: Color(0xFF000000), card: Color(0xFF0A0A10), surface: Color(0xFF101018), elevated: Color(0xFF161620),
    accent: Color(0xFFFF2040), accentSoft: Color(0x25FF2040), gold: Color(0xFFFFB820),
    text: Color(0xFFF5F0E8), textSub: Color(0xFF8A8A9A), textMuted: Color(0xFF404050),
    border: Color(0xFF1A1A22), borderSoft: Color(0xFF0E0E18), divider: Color(0xFF0E0E18), overlay: Color(0xDD000000),
    canvasBg: Color(0xFF0D0D0D), canvasInk: Color(0xFFEF4444), canvasShadow: Color(0xFFFFFFFF), canvasGrid: Color(0xFF2A0000), inputFill: Color(0xFF110000),
    navBar: Color(0xFF000000), navBarItem: Color(0xFF3A3A4A), navBarSelected: Color(0xFFFF2040), streak: Color(0xFFFF4010),
    correct: Color(0xFF00D060), wrong: Color(0xFFFF2040), warning: Color(0xFFFFB820), info: Color(0xFF4090FF),
  );

  // ── Dark Blue-Black ────────────────────────────────────────────────────────
  static const KmColors dark = KmColors(
    pack: KmThemePack.dark,
    bg: Color(0xFF0D0D18), card: Color(0xFF161625), surface: Color(0xFF1E1E30), elevated: Color(0xFF252538),
    accent: Color(0xFFE8203A), accentSoft: Color(0x20E8203A), gold: Color(0xFFD4A020),
    text: Color(0xFFF0EDE8), textSub: Color(0xFFAAAAAC), textMuted: Color(0xFF555560),
    border: Color(0xFF252535), borderSoft: Color(0xFF1E1E2E), divider: Color(0xFF1E1E2E), overlay: Color(0xDD000000),
    canvasBg: Color(0xFF0F0F1A), canvasInk: Color(0xFFEF4444), canvasShadow: Color(0xFFFFFFFF), canvasGrid: Color(0xFF2A0030), inputFill: Color(0xFF110020),
    navBar: Color(0xFF0E0E1A), navBarItem: Color(0xFF555568), navBarSelected: Color(0xFFE8203A), streak: Color(0xFFFF5020),
    correct: Color(0xFF20A060), wrong: Color(0xFFE82038), warning: Color(0xFFD4A020), info: Color(0xFF2080E0),
  );

  // ── Clean White + Red ──────────────────────────────────────────────────────
  static const KmColors light = KmColors(
    pack: KmThemePack.white,
    bg: Color(0xFFF8F5F0), card: Color(0xFFFFFFFF), surface: Color(0xFFF0EDE8), elevated: Color(0xFFFFFFFF),
    accent: Color(0xFFC8002A), accentSoft: Color(0x18C8002A), gold: Color(0xFFB8860B),
    text: Color(0xFF0F0F14), textSub: Color(0xFF4A4A5A), textMuted: Color(0xFF9A9AAA),
    border: Color(0xFFE8E4DE), borderSoft: Color(0xFFF0EDE8), divider: Color(0xFFEEEAE4), overlay: Color(0xEEFFFFFF),
    canvasBg: Color(0xFFFFFFFF), canvasInk: Color(0xFF111111), canvasShadow: Color(0xFFFFCCCC), canvasGrid: Color(0xFFFFE8E8), inputFill: Color(0xFFFFF8F8),
    navBar: Color(0xFFFFFFFF), navBarItem: Color(0xFF9A9AAA), navBarSelected: Color(0xFFC8002A), streak: Color(0xFFE05010),
    correct: Color(0xFF1A7A4A), wrong: Color(0xFFBF0020), warning: Color(0xFFB07000), info: Color(0xFF1A5A9A),
  );

  // ── Sakura Pink ────────────────────────────────────────────────────────────
  static const KmColors sakura = KmColors(
    pack: KmThemePack.sakura,
    bg: Color(0xFFFDF0F5), card: Color(0xFFFFFFFF), surface: Color(0xFFF8E8EF), elevated: Color(0xFFFFFFFF),
    accent: Color(0xFFD4006A), accentSoft: Color(0x18D4006A), gold: Color(0xFFB86A00),
    text: Color(0xFF2A1520), textSub: Color(0xFF6A3A50), textMuted: Color(0xFFB08090),
    border: Color(0xFFEDD8E4), borderSoft: Color(0xFFF5DDE8), divider: Color(0xFFF5DDE8), overlay: Color(0xEEFFFAFC),
    canvasBg: Color(0xFFFFFFFF), canvasInk: Color(0xFF2A1520), canvasShadow: Color(0xFFFFCCDD), canvasGrid: Color(0xFFFFE8EF), inputFill: Color(0xFFFFF0F5),
    navBar: Color(0xFFFFFFFF), navBarItem: Color(0xFFB08090), navBarSelected: Color(0xFFD4006A), streak: Color(0xFFE04080),
    correct: Color(0xFF28804A), wrong: Color(0xFFB8002A), warning: Color(0xFFAA6800), info: Color(0xFF4A40B8),
  );

  static KmColors of(BuildContext context) {
    final ext = Theme.of(context).extension<KmColors>();
    return ext ?? original;
  }

  static KmColors fromPack(KmThemePack pack) {
    switch (pack) {
      case KmThemePack.white:   return light;
      case KmThemePack.dark:    return dark;
      case KmThemePack.amoled:  return original;
      case KmThemePack.sakura:  return sakura;
    }
  }

  Color levelColor(String level) {
    switch (level.toUpperCase()) {
      case 'N5': return const Color(0xFF4CAF50);
      case 'N4': return const Color(0xFF2196F3);
      case 'N3': return const Color(0xFFFF9800);
      case 'N2': return const Color(0xFFE91E63);
      case 'N1': return const Color(0xFF9C27B0);
      default: return textMuted;
    }
  }

  @override
  KmColors copyWith({KmThemePack? pack, Color? bg, Color? card, Color? surface, Color? elevated,
    Color? accent, Color? accentSoft, Color? gold, Color? text, Color? textSub, Color? textMuted,
    Color? border, Color? borderSoft, Color? divider, Color? overlay, Color? canvasBg,
    Color? canvasInk, Color? canvasShadow, Color? canvasGrid, Color? inputFill,
    Color? navBar, Color? navBarItem, Color? navBarSelected, Color? streak,
    Color? correct, Color? wrong, Color? warning, Color? info}) => KmColors(
    pack: pack ?? this.pack, bg: bg ?? this.bg, card: card ?? this.card,
    surface: surface ?? this.surface, elevated: elevated ?? this.elevated,
    accent: accent ?? this.accent, accentSoft: accentSoft ?? this.accentSoft, gold: gold ?? this.gold,
    text: text ?? this.text, textSub: textSub ?? this.textSub, textMuted: textMuted ?? this.textMuted,
    border: border ?? this.border, borderSoft: borderSoft ?? this.borderSoft,
    divider: divider ?? this.divider, overlay: overlay ?? this.overlay,
    canvasBg: canvasBg ?? this.canvasBg, canvasInk: canvasInk ?? this.canvasInk,
    canvasShadow: canvasShadow ?? this.canvasShadow, canvasGrid: canvasGrid ?? this.canvasGrid,
    inputFill: inputFill ?? this.inputFill, navBar: navBar ?? this.navBar,
    navBarItem: navBarItem ?? this.navBarItem, navBarSelected: navBarSelected ?? this.navBarSelected,
    streak: streak ?? this.streak, correct: correct ?? this.correct, wrong: wrong ?? this.wrong,
    warning: warning ?? this.warning, info: info ?? this.info,
  );

  @override
  KmColors lerp(KmColors? other, double t) => this;
}
