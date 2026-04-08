// lib/core/config/remote_config_service.dart
import 'package:firebase_remote_config/firebase_remote_config.dart';

class RemoteConfigService {
  RemoteConfigService._();
  static final instance = RemoteConfigService._();

  final _config = FirebaseRemoteConfig.instance;

  Future<void> init() async {
    await _config.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval: const Duration(hours: 1),
    ));

    // Nilai default — dipakai jika gagal fetch (offline, dll)
    await _config.setDefaults({
      'free_quiz_limit_per_day':     10,
      'free_ai_messages_per_day':    5,
      'free_flashcard_decks':        3,
      'free_writing_levels':         'n5',
      'show_premium_banner':         true,
      'premium_banner_text':         'Buka semua fitur N1–N5 tanpa batas!',
      'monthly_price_idr':           49900,
      'yearly_price_idr':            399000,
      'lifetime_price_idr':          299000,
      'maintenance_mode':            false,
      'min_app_version':             '2.0.0',
    });

    try {
      await _config.fetchAndActivate();
    } catch (_) {
      // Gunakan nilai default jika fetch gagal
    }
  }

  // ── Getters feature flags ─────────────────────────────────────────────────
  int get freeQuizLimitPerDay    => _config.getInt('free_quiz_limit_per_day');
  int get freeAiMessagesPerDay   => _config.getInt('free_ai_messages_per_day');
  int get freeFlashcardDecks     => _config.getInt('free_flashcard_decks');
  String get freeWritingLevels   => _config.getString('free_writing_levels');
  bool get showPremiumBanner     => _config.getBool('show_premium_banner');
  String get premiumBannerText   => _config.getString('premium_banner_text');
  bool get maintenanceMode       => _config.getBool('maintenance_mode');

  // ── Getters harga ─────────────────────────────────────────────────────────
  int get monthlyPriceIdr        => _config.getInt('monthly_price_idr');
  int get yearlyPriceIdr         => _config.getInt('yearly_price_idr');
  int get lifetimePriceIdr       => _config.getInt('lifetime_price_idr');
}
