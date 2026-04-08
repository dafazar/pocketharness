// lib/data/services/ai_source_settings_service.dart
// KanMon GO — Settings service for managing AI source configurations
// Provides singleton access to load/save/switch between Online, Bulk, Offline configs
// =============================================================================

import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/ai_source_config.dart';

class AiSourceSettingsService {
  static AiSourceSettingsService? _instance;

  late OnlineAiConfig _online;
  late BulkAiConfig _bulk;
  late OfflineAiConfig _offline;
  late String _activeSource; // "online", "bulk", or "offline"

  AiSourceSettingsService._();

  static AiSourceSettingsService get instance {
    _instance ??= AiSourceSettingsService._();
    return _instance!;
  }

  // ── Getters ───────────────────────────────────────────────────────────────
  OnlineAiConfig get online => _online;
  BulkAiConfig get bulk => _bulk;
  OfflineAiConfig get offline => _offline;
  String get activeSource => _activeSource;

  bool isEnabled(String sourceKey) {
    switch (sourceKey) {
      case 'online':
        return _online.enabled;
      case 'bulk':
        return _bulk.enabled;
      case 'offline':
        return _offline.enabled;
      default:
        return false;
    }
  }

  // ── Initialization ─────────────────────────────────────────────────────────
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Online config
    try {
      final onlineJson = prefs.getString('ai_source_online_config');
      _online = onlineJson != null
          ? OnlineAiConfig.fromJson(jsonDecode(onlineJson))
          : OnlineAiConfig();
    } catch (e) {
      _online = OnlineAiConfig();
    }

    // Load Bulk config
    try {
      final bulkJson = prefs.getString('ai_source_bulk_config');
      _bulk = bulkJson != null
          ? BulkAiConfig.fromJson(jsonDecode(bulkJson))
          : BulkAiConfig();
    } catch (e) {
      _bulk = BulkAiConfig();
    }

    // Load Offline config
    try {
      final offlineJson = prefs.getString('ai_source_offline_config');
      _offline = offlineJson != null
          ? OfflineAiConfig.fromJson(jsonDecode(offlineJson))
          : OfflineAiConfig();
    } catch (e) {
      _offline = OfflineAiConfig();
    }

    // Load active source
    _activeSource = prefs.getString('ai_source_active') ?? 'online';
  }

  // ── Setters ────────────────────────────────────────────────────────────────
  Future<void> setOnlineConfig(OnlineAiConfig cfg) async {
    _online = cfg;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_source_online_config', jsonEncode(cfg.toJson()));
  }

  /// Alias for setOnlineConfig — used by Session 2 popup
  Future<void> saveOnline(OnlineAiConfig cfg) => setOnlineConfig(cfg);

  Future<void> setBulkConfig(BulkAiConfig cfg) async {
    _bulk = cfg;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_source_bulk_config', jsonEncode(cfg.toJson()));
  }

  /// Alias for setBulkConfig — used by Session 3 popup
  Future<void> saveBulk(BulkAiConfig cfg) => setBulkConfig(cfg);

  Future<void> setOfflineConfig(OfflineAiConfig cfg) async {
    _offline = cfg;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_source_offline_config', jsonEncode(cfg.toJson()));
  }

  /// Alias for setOfflineConfig — used by Session 4 popup
  Future<void> saveOffline(OfflineAiConfig cfg) => setOfflineConfig(cfg);

  Future<void> setActiveSource(String sourceKey) async {
    _activeSource = sourceKey;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_source_active', sourceKey);
  }

  // ── Reset ──────────────────────────────────────────────────────────────────
  Future<void> resetToDefaults() async {
    _online = OnlineAiConfig();
    _bulk = BulkAiConfig();
    _offline = OfflineAiConfig();
    _activeSource = 'online';

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ai_source_online_config');
    await prefs.remove('ai_source_bulk_config');
    await prefs.remove('ai_source_offline_config');
    await prefs.remove('ai_source_active');
  }
}
