// lib/core/theme/app_theme_service.dart
//
// Pocket Harness — AppThemeService (Singleton)
// Memuat config dari assets/theme/theme_config_original.json
// Pack: hanya ORIGINAL.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pocketharness/core/theme/km_colors.dart';
import 'package:pocketharness/core/theme/theme_provider.dart';

// ── Helper parse warna hex ────────────────────────────────────────────────────
Color _hexColor(String hex) {
  final h = hex.replaceAll('#', '');
  if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
  if (h.length == 8) return Color(int.parse(h, radix: 16));
  return const Color(0xFF777777);
}

// ── Model: item berimage ──────────────────────────────────────────────────────
class ThemeItem {
  final String id;
  final String image;
  final String label;
  final String icon;
  final String route;
  final Color color;
  final Color? badgeColor;
  final String subtitle;

  ThemeItem({
    required this.id,
    required this.image,
    required this.label,
    required this.icon,
    required this.route,
    required this.color,
    this.badgeColor,
    this.subtitle = '',
  });

  factory ThemeItem.fromJson(Map<String, dynamic> j, {String fallbackId = ''}) => ThemeItem(
    id:         j['id']    ?? j['level'] ?? fallbackId,
    image:      j['image'] ?? '',
    label:      j['label'] ?? j['level'] ?? '',
    icon:       j['icon']  ?? '',
    route:      j['route'] ?? '',
    color:      j['color']       != null ? _hexColor(j['color'] as String)       : const Color(0xFF777777),
    badgeColor: j['badge_color'] != null ? _hexColor(j['badge_color'] as String) : null,
    subtitle:   j['subtitle']    as String? ?? '',
  );
}

// ── Model: sub-tipe essay ─────────────────────────────────────────────────────
class EssaySubtypeTheme {
  final String key;
  final String icon;
  final Color color;
  final String label;
  final String subtitle;

  EssaySubtypeTheme({
    required this.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
  });

  factory EssaySubtypeTheme.fromJson(String key, Map<String, dynamic> j) =>
    EssaySubtypeTheme(
      key:      key,
      icon:     j['icon']     as String? ?? '',
      color:    j['color']    != null ? _hexColor(j['color'] as String) : const Color(0xFF777777),
      label:    j['label']    as String? ?? key,
      subtitle: j['subtitle'] as String? ?? '',
    );
}

// ── Model utama config tema ───────────────────────────────────────────────────
class AppThemeConfig {
  final Map<String, String> backgrounds;
  final Map<String, String> banners;
  final List<ThemeItem> homeMenu;

  final List<ThemeItem> quizJlpt;
  final List<ThemeItem> quizJft;
  final List<ThemeItem> quizKana;
  final List<ThemeItem> quizKanji;
  final List<ThemeItem> quizVocab;
  final List<ThemeItem> quizParticle;
  final List<ThemeItem> quizSentence;
  final List<ThemeItem> quizSentenceCard;
  final Map<String, EssaySubtypeTheme> quizSentenceSubtype;
  final String quizStatsBanner;

  final List<ThemeItem> flashcardKana;
  final List<ThemeItem> flashcardKanji;
  final List<ThemeItem> flashcardVocab;
  final String flashcardCustomMix;

  final List<String> notesBackgrounds;
  final Map<String, String> kanaGrid;
  final Map<String, dynamic> placeholders;
  final String navBarBackground;
  final Map<String, String> swatches;

  AppThemeConfig({
    required this.backgrounds,
    required this.banners,
    required this.homeMenu,
    required this.quizJlpt,
    required this.quizJft,
    required this.quizKana,
    required this.quizKanji,
    required this.quizVocab,
    required this.quizParticle,
    required this.quizSentence,
    required this.quizSentenceCard,
    required this.quizSentenceSubtype,
    required this.quizStatsBanner,
    required this.flashcardKana,
    required this.flashcardKanji,
    required this.flashcardVocab,
    required this.flashcardCustomMix,
    required this.notesBackgrounds,
    required this.kanaGrid,
    required this.placeholders,
    required this.navBarBackground,
    required this.swatches,
  });

  String background(String screen) => backgrounds[screen] ?? '';
  String banner(String screen)     => banners[screen] ?? '';

  ThemeItem? _byLevel(List<ThemeItem> list, String n) =>
      list.where((e) => e.id.toUpperCase() == n.toUpperCase()).firstOrNull;

  ThemeItem? quizJlptByLevel(String n)         => _byLevel(quizJlpt, n);
  ThemeItem? quizKanjiByLevel(String n)        => _byLevel(quizKanji, n);
  ThemeItem? quizVocabByLevel(String n)        => _byLevel(quizVocab, n);
  ThemeItem? quizParticleByLevel(String n)     => _byLevel(quizParticle, n);
  ThemeItem? quizSentenceByLevel(String n)     => _byLevel(quizSentence, n);
  ThemeItem? quizSentenceCardByLevel(String n) => _byLevel(quizSentenceCard, n);
  ThemeItem? flashcardKanjiByLevel(String n)   => _byLevel(flashcardKanji, n);
  ThemeItem? flashcardVocabByLevel(String n)   => _byLevel(flashcardVocab, n);

  EssaySubtypeTheme? essaySubtype(String key) => quizSentenceSubtype[key];

  String? placeholderKana(String type) {
    final kana = placeholders['kana'];
    if (kana is Map) return kana[type] as String?;
    return null;
  }
  String? placeholderKanji(String level) {
    final kanji = placeholders['kanji'];
    if (kanji is Map) return kanji[level] as String?;
    return null;
  }
  String? placeholderVocab(String level) {
    final vocab = placeholders['vocab'];
    if (vocab is Map) return vocab[level] as String?;
    return null;
  }

  factory AppThemeConfig.fromJson(Map<String, dynamic> j) {
    List<ThemeItem> items(dynamic src) => src == null
        ? []
        : (src as List).map((e) => ThemeItem.fromJson(e as Map<String, dynamic>)).toList();

    Map<String, String> strMap(dynamic src) => src == null
        ? {}
        : (src as Map<String, dynamic>)
            .where((k, v) => !k.startsWith('_'))
            .map((k, v) => MapEntry(k, v as String? ?? ''));

    final quiz = j['quiz'] as Map<String, dynamic>? ?? {};

    final subtypeRaw = quiz['sentence_subtype'] as Map<String, dynamic>? ?? {};
    final subtypeMap = <String, EssaySubtypeTheme>{};
    subtypeRaw.forEach((k, v) {
      if (!k.startsWith('_') && v is Map<String, dynamic>) {
        subtypeMap[k] = EssaySubtypeTheme.fromJson(k, v);
      }
    });

    return AppThemeConfig(
      backgrounds:         strMap(j['backgrounds']),
      banners:             strMap(j['banners']),
      homeMenu:            items(j['home_menu']),
      quizJlpt:            items(j['quiz_jlpt'] ?? quiz['jlpt']),
      quizJft:             items(quiz['jft']),
      quizKana:            items(quiz['kana']),
      quizKanji:           items(quiz['kanji']),
      quizVocab:           items(quiz['vocab']),
      quizParticle:        items(quiz['particle']),
      quizSentence:        items(quiz['sentence']),
      quizSentenceCard:    items(j['quiz_sentence_card']),
      quizSentenceSubtype: subtypeMap,
      quizStatsBanner:     j['quiz_stats_banner'] as String? ?? '',
      flashcardKana:       items((j['flashcard'] as Map?)?['kana']),
      flashcardKanji:      items((j['flashcard'] as Map?)?['kanji']),
      flashcardVocab:      items((j['flashcard'] as Map?)?['vocab']),
      flashcardCustomMix:  (j['flashcard'] as Map?)?['custom_mix'] as String? ?? '',
      notesBackgrounds:    (j['notes_backgrounds'] as List? ?? []).cast<String>(),
      kanaGrid:            strMap(j['kana_grid']),
      placeholders:        j['placeholders'] as Map<String, dynamic>? ?? {},
      navBarBackground:    (j['nav_bar'] as Map?)?['background'] as String? ?? '',
      swatches:            strMap(j['swatches']),
    );
  }
}

extension _MapWhere<K, V> on Map<K, V> {
  Map<K, V> where(bool Function(K k, V v) test) =>
      Map.fromEntries(entries.where((e) => test(e.key, e.value)));
}

// ── Singleton Service ─────────────────────────────────────────────────────────
class AppThemeService {
  AppThemeService._();
  static final AppThemeService instance = AppThemeService._();

  AppThemeConfig? _config;
  AppThemePack _currentPack = AppThemePack.original;
  bool _loading = false;
  final List<VoidCallback> _listeners = [];

  AppThemeConfig? get config     => _config;
  AppThemePack   get currentPack => _currentPack;
  bool           get isLoaded    => _config != null;

  /// Load awal — panggil di main().
  Future<void> load({AppThemePack pack = AppThemePack.original}) async {
    await _loadPack(pack);
  }

  /// Ganti pack tema & reload config.
  Future<void> switchPack(AppThemePack pack) async {
    if (pack == _currentPack && _config != null) return;
    await _loadPack(pack);
  }

  Future<void> _loadPack(AppThemePack pack) async {
    if (_loading) return;
    _loading = true;
    try {
      final raw = await rootBundle.loadString(pack.configPath);
      _config     = AppThemeConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _currentPack = pack;
      for (final cb in List.from(_listeners)) cb();
      _listeners.clear();
    } catch (e) {
      debugPrint('[AppThemeService] Gagal load theme pack ${pack.id}: $e');
    } finally {
      _loading = false;
    }
  }

  void whenLoaded(VoidCallback cb) {
    if (_config != null) { cb(); } else { _listeners.add(cb); }
  }

  String background(String screen) => _config?.background(screen) ?? '';
  String banner(String screen)     => _config?.banner(screen) ?? '';

  Color accentColor(String screen) {
    const defaults = <String, Color>{
      'kana':      Color(0xFFFFFFFF),
      'kanji':     Color(0xFFFFFFFF),
      'bunpou':    Color(0xFFFFFFFF),
      'partikel':  Color(0xFFFFFFFF),
      'vocab':     Color(0xFFFFFFFF),
      'writing':   Color(0xFFFFFFFF),
      'flashcard': Color(0xFFFFFFFF),
      'quiz':      Color(0xFFFFFFFF),
      'notes':     Color(0xFFFFFFFF),
      'home':      Color(0xFFFFFFFF),
    };
    return defaults[screen] ?? const Color(0xFFFFFFFF);
  }
}
