// lib/data/services/ai_source_settings_service.dart
// KanMon GO — Settings service for managing AI source configurations
// Provides singleton access to load/save/switch between Online, Bulk, Offline configs
// =============================================================================
// FIX: Sinkronisasi dua arah dengan PuterAiService, BulkApiService, dan
//      OfflineAiService + SharedPreferences OfflineAiConfig.
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/ai_source_config.dart';
import 'package:kanmongo/data/services/puter_ai_service.dart';
import 'package:kanmongo/data/services/bulk_api_service.dart';
import 'package:kanmongo/data/services/offline_ai_service.dart';
import 'package:kanmongo/data/services/model_manager_service.dart';
import 'package:kanmongo/data/services/llama_service.dart';

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

    // Sinkronisasi satu arah: ambil state aktual dari masing-masing service
    // agar data picker selalu mencerminkan kondisi nyata services
    await _pullFromServices();
  }

  // ── Pull state dari masing-masing service ke config picker ────────────────
  // Dipanggil saat load() agar picker selalu sinkron dengan settings screens.
  Future<void> _pullFromServices() async {
    // ── Online: ambil dari PuterAiService ────────────────────────────────
    try {
      final puter = PuterAiService.instance;
      await puter.loadSettings();
      _online = _online.copyWith(
        enabled:       puter.isEnabled,
        selectedModel: puter.selectedModelId,
        temperature:   puter.temperature,
        maxTokens:     puter.maxTokens,
        streamEnabled: puter.streamMode,
        apiKey:        puter.apiKey,
      );
    } catch (e) {
      debugPrint('[AiSourceSettings] _pullFromServices online error: $e');
    }

    // ── Bulk: ambil dari BulkApiService ──────────────────────────────────
    try {
      final bulk = BulkApiService.instance;
      await bulk.load();
      _bulk = _bulk.copyWith(
        enabled: bulk.enabled,
        keys:    bulk.keys,
      );
    } catch (e) {
      debugPrint('[AiSourceSettings] _pullFromServices bulk error: $e');
    }

    // ── Offline: ambil dari OfflineAiService ──────────────────────────────
    try {
      final offline = OfflineAiService.instance;
      _offline = _offline.copyWith(
        temperature: offline.temperature,
        topP:        offline.topP,
        topK:        offline.topK,
        // FIX #1: Sync activeModelPath agar tombol "Load Model Aktif" tidak selalu disabled
        activeModelPath: ModelManagerService.instance.activeModel?.path
            ?? LlamaService.instance.currentModel?.path
            ?? _offline.activeModelPath,
      );
    } catch (e) {
      debugPrint('[AiSourceSettings] _pullFromServices offline error: $e');
    }
  }

  // ── Setters ────────────────────────────────────────────────────────────────

  Future<void> setOnlineConfig(OnlineAiConfig cfg) async {
    _online = cfg;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_source_online_config', jsonEncode(cfg.toJson()));
    // Push ke PuterAiService
    await _pushOnlineToService(cfg);
  }

  /// Alias for setOnlineConfig — used by Session 2 popup
  Future<void> saveOnline(OnlineAiConfig cfg) => setOnlineConfig(cfg);

  Future<void> setBulkConfig(BulkAiConfig cfg) async {
    _bulk = cfg;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_source_bulk_config', jsonEncode(cfg.toJson()));
    // Push ke BulkApiService
    await _pushBulkToService(cfg);
  }

  /// Alias for setBulkConfig — used by Session 3 popup
  Future<void> saveBulk(BulkAiConfig cfg) => setBulkConfig(cfg);

  Future<void> setOfflineConfig(OfflineAiConfig cfg) async {
    _offline = cfg;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_source_offline_config', jsonEncode(cfg.toJson()));
    // Push ke OfflineAiService
    await _pushOfflineToService(cfg);
  }

  /// Alias for setOfflineConfig — used by Session 4 popup
  Future<void> saveOffline(OfflineAiConfig cfg) => setOfflineConfig(cfg);

  Future<void> setActiveSource(String sourceKey) async {
    _activeSource = sourceKey;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_source_active', sourceKey);
  }

  // ── Push Online config → PuterAiService ──────────────────────────────────
  Future<void> _pushOnlineToService(OnlineAiConfig cfg) async {
    try {
      await PuterAiService.instance.saveSettings(
        enabled:       cfg.enabled,
        apiKey:        cfg.apiKey.isEmpty ? null : cfg.apiKey,
        selectedModel: cfg.selectedModel,
        temperature:   cfg.temperature,
        maxTokens:     cfg.maxTokens,
        streamMode:    cfg.streamEnabled,
      );
      debugPrint('[AiSourceSettings] pushed online config → PuterAiService');
    } catch (e) {
      debugPrint('[AiSourceSettings] _pushOnlineToService error: $e');
    }
  }

  // ── Push Bulk config → BulkApiService ────────────────────────────────────
  Future<void> _pushBulkToService(BulkAiConfig cfg) async {
    try {
      final svc = BulkApiService.instance;
      await svc.setEnabled(cfg.enabled);
      debugPrint('[AiSourceSettings] pushed bulk config → BulkApiService (enabled=${cfg.enabled})');
    } catch (e) {
      debugPrint('[AiSourceSettings] _pushBulkToService error: $e');
    }
  }

  // ── Push Offline config → OfflineAiService ───────────────────────────────
  Future<void> _pushOfflineToService(OfflineAiConfig cfg) async {
    try {
      final svc = OfflineAiService.instance;
      await svc.setTemperature(cfg.temperature);
      await svc.setTopP(cfg.topP);
      await svc.setTopK(cfg.topK);
      debugPrint('[AiSourceSettings] pushed offline config → OfflineAiService');
    } catch (e) {
      debugPrint('[AiSourceSettings] _pushOfflineToService error: $e');
    }
  }

  // ── Pull dari PuterAiService (dipanggil saat settings screen kembali) ─────
  // Agar picker selalu mencerminkan perubahan dari settings screen puter_setup.
  Future<void> pullOnlineFromService() async {
    try {
      final puter = PuterAiService.instance;
      await puter.loadSettings();
      _online = _online.copyWith(
        enabled:       puter.isEnabled,
        selectedModel: puter.selectedModelId,
        temperature:   puter.temperature,
        maxTokens:     puter.maxTokens,
        streamEnabled: puter.streamMode,
        apiKey:        puter.apiKey,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_source_online_config', jsonEncode(_online.toJson()));
      debugPrint('[AiSourceSettings] pulled online from PuterAiService');
    } catch (e) {
      debugPrint('[AiSourceSettings] pullOnlineFromService error: $e');
    }
  }

  // ── Pull dari BulkApiService ──────────────────────────────────────────────
  Future<void> pullBulkFromService() async {
    try {
      final svc = BulkApiService.instance;
      await svc.load();
      _bulk = _bulk.copyWith(
        enabled: svc.enabled,
        keys:    svc.keys,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_source_bulk_config', jsonEncode(_bulk.toJson()));
      debugPrint('[AiSourceSettings] pulled bulk from BulkApiService');
    } catch (e) {
      debugPrint('[AiSourceSettings] pullBulkFromService error: $e');
    }
  }

  // ── Pull dari OfflineAiService ────────────────────────────────────────────
  Future<void> pullOfflineFromService() async {
    try {
      final svc = OfflineAiService.instance;
      _offline = _offline.copyWith(
        temperature: svc.temperature,
        topP:        svc.topP,
        topK:        svc.topK,
        // FIX #1: Selalu sinkronkan activeModelPath
        activeModelPath: ModelManagerService.instance.activeModel?.path
            ?? LlamaService.instance.currentModel?.path
            ?? _offline.activeModelPath,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_source_offline_config', jsonEncode(_offline.toJson()));
      debugPrint('[AiSourceSettings] pulled offline from OfflineAiService');
    } catch (e) {
      debugPrint('[AiSourceSettings] pullOfflineFromService error: $e');
    }
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
