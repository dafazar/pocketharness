// lib/main.dart
// KanMon GO — Main Entry Point
// =============================================================================

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:kanmongo/core/router/app_router.dart';
import 'package:kanmongo/core/theme/app_theme.dart';
import 'package:kanmongo/core/theme/app_theme_service.dart';
import 'package:kanmongo/core/theme/theme_provider.dart';
import 'package:kanmongo/core/lifecycle/app_lifecycle_service.dart';
import 'package:kanmongo/core/config/remote_config_service.dart';
import 'package:kanmongo/core/security/secure_db_key_service.dart';
import 'package:kanmongo/core/membership/membership_service.dart';
import 'package:kanmongo/core/sync/sync_service.dart';
import 'package:kanmongo/core/ai/inference_params_provider.dart';
import 'package:kanmongo/data/repositories/user_repository.dart';
import 'package:kanmongo/data/services/database_service.dart';
import 'package:kanmongo/data/services/ai_service.dart';
import 'package:kanmongo/data/services/llama_service.dart';
import 'package:kanmongo/data/services/model_manager_service.dart';
import 'package:kanmongo/data/services/ai_persona_service.dart';
import 'package:kanmongo/data/services/terminal_service.dart';
import 'package:kanmongo/data/services/wallpaper_service.dart';
import 'package:kanmongo/data/services/sfx_service.dart';
import 'package:kanmongo/data/services/ai_source_settings_service.dart';
import 'package:kanmongo/firebase_options.dart';
import 'package:kanmongo/core/tools/tools_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 0. ToolsService — extract bundled CLI tools on first launch ──────────
  // No-op after first extraction (<1ms due to SharedPreferences check).
  try {
    await ToolsService.instance.initialize(
      onProgress: (p) {
        debugPrint('[ToolsService] Extraction progress: ${(p * 100).toInt()}%');
      },
    );
    debugPrint('[main] ToolsService ready (isReady=${ToolsService.instance.isReady})');
  } catch (e) {
    debugPrint('[main] ToolsService.initialize() gagal (lanjut): $e');
  }

  // ── 1. Firebase ─────────────────────────────────────────────────────────────
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  FlutterError.onError = (details) {
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };

  // Tangkap error dari platform/isolate agar tidak force close
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[PlatformDispatcher] Uncaught: $error');
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true; // true = error sudah ditangani, app tidak crash
  };

  // ── 2. Hive — inisialisasi penyimpanan chat history & cache model ──────────
  try {
    await Hive.initFlutter();
    await Hive.openBox('chat_history');
    await Hive.openBox('model_cache');
    await Hive.openBox('ai_settings');
    debugPrint('[main] Hive boxes berhasil dibuka');
  } catch (e) {
    debugPrint('[main] Hive init gagal (lanjut): $e');
  }

  // ── 3. Jalankan app — semua init di dalam try/catch agar layar hitam tidak terjadi
  runZonedGuarded<Future<void>>(() async {

    // ── Remote Config — timeout ketat, tidak blocking jika gagal ─────────────
    try {
      await RemoteConfigService.instance.init()
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[main] RemoteConfig gagal (lanjut dengan default): $e');
    }

    // ── App theme ─────────────────────────────────────────────────────────────
    late SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final packId  = prefs.getString('kmg.theme.pack') ?? 'original';
      final savedPack = AppThemePack.values.firstWhere(
        (p) => p.id == packId,
        orElse: () => AppThemePack.original,
      );
      await AppThemeService.instance.load(pack: savedPack);
      await WallpaperService.instance.load();
      await SfxService.instance.init();
    } catch (e) {
      debugPrint('[main] Theme/SFX init gagal (lanjut): $e');
      prefs = await SharedPreferences.getInstance().catchError((_) async => SharedPreferences.getInstance());
      try { await AppThemeService.instance.load(); } catch (_) {}
    }

    // ── DB Key — opsional, tidak blocking ─────────────────────────────────────
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && !currentUser.isAnonymous) {
        await SecureDbKeyService.instance.fetchKeysWithRetry(maxRetries: 2)
            .timeout(const Duration(seconds: 10));
      }
    } catch (e) {
      debugPrint('[main] DB key fetch gagal (lanjut tanpa enkripsi): $e');
    }

    // ── SQLite Database ───────────────────────────────────────────────────────
    try {
      await DatabaseService.instance.init();
      await ModelManagerService.instance.load();

      // KM-FAST: init connectivity watcher & warm-up model
      AiService.instance.initConnectivityWatcher();
      AiService.instance.syncOfflineSettings().ignore(); // load forceOfflineMode
      AiService.instance.warmUp().ignore();

      // ── Inisialisasi LlamaService (arsitektur baru PocketPal) ─────────────
      // Harus dipanggil SETELAH ModelManagerService.load() agar activeModel tersedia.
      // initialize() membaca settings dan menyiapkan context llama.cpp.
      try {
        await LlamaService.instance.initialize();
        debugPrint('[main] LlamaService berhasil diinisialisasi');
      } catch (e) {
        debugPrint('[main] LlamaService.initialize() gagal (lanjut): $e');
      }

      // ── AUTO-LOAD active model via LlamaService (single authority) ──────────
      // LlamaService is the canonical owner of the native bridge.
      // OfflineAiService settings are loaded for UI state (forceOffline, etc.)
      // but model loading itself is delegated to LlamaService.loadModel().
      LlamaService.instance.loadSettings().then((_) async {
        final active    = ModelManagerService.instance.activeModel;
        final activeRaw = ModelManagerService.instance.activeModelRaw;
        if (active != null) {
          debugPrint('[main] Auto-loading active model via LlamaService: ${active.name}');
          final ok = await LlamaService.instance.loadModel(active);
          if (ok) {
            debugPrint('[main] Auto-load success: ${active.name}');
          } else {
            debugPrint('[main] Auto-load failed: ${active.name}');
          }
        } else if (activeRaw != null) {
          debugPrint('[main] Model registered but file missing: ${activeRaw.path}');
        }
      }).ignore();

      AiPersonaService.instance.load().ignore();
      TerminalService.instance.init().ignore();
    } catch (e) {
      debugPrint('[main] DatabaseService.init() gagal: $e');
    }

    // ── Membership — no-op (premium gate dinonaktifkan) ───────────────────────
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && !currentUser.isAnonymous) {
        await MembershipService.init(currentUser.uid)
            .timeout(const Duration(seconds: 5));
      }
    } catch (e) {
      debugPrint('[main] MembershipService.init gagal (lanjut): $e');
    }

    // ── SyncService — auto-sync saat online ───────────────────────────────────
    try {
      final syncSvc = SyncService(UserRepository());
      syncSvc.listenToConnectivity();
      syncSvc.syncOnConnect().ignore();
      debugPrint('[main] SyncService started');
    } catch (e) {
      debugPrint('[main] SyncService init gagal (lanjut): $e');
    }

    // ── Auth listener — re-init MembershipService saat login ─────────────────
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null && !user.isAnonymous) {
        try {
          await MembershipService.init(user.uid);
        } catch (e) {
          debugPrint('[AuthListener] MembershipService re-init error: $e');
        }
      }
    });

    // ── Load AI source settings from persistent storage ───────────────────────
    await AiSourceSettingsService.instance.load();

    // ── Jalankan app — SELALU dipanggil walau ada error di atas ──────────────
    runApp(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const KanMonGOApp(),
    ));

  }, (error, stack) {
    debugPrint('[main] Uncaught error: $error');
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

// ── App root ──────────────────────────────────────────────────────────────────
class KanMonGOApp extends StatefulWidget {
  const KanMonGOApp({super.key});
  @override
  State<KanMonGOApp> createState() => _KanMonGOAppState();
}

class _KanMonGOAppState extends State<KanMonGOApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(AppLifecycleService.instance);
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(AppLifecycleService.instance);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => const _AppContent();
}

class _AppContent extends ConsumerWidget {
  const _AppContent();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeProvider);
    ref.listen<AppThemePack>(themePackProvider, (_, next) {
      AppThemeService.instance.switchPack(next);
    });
    return MaterialApp.router(
      title: 'KanMon GO',
      debugShowCheckedModeBanner: false,
      theme:     AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: appRouter,
    );
  }
}
