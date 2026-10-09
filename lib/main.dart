// lib/main.dart
// Pocket Harness — Main Entry Point
// =============================================================================

import 'dart:io';
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

import 'package:pocketharness/core/router/app_router.dart';
import 'package:pocketharness/core/theme/app_theme.dart';
import 'package:pocketharness/core/theme/app_theme_service.dart';
import 'package:pocketharness/core/theme/theme_provider.dart';
import 'package:pocketharness/core/lifecycle/app_lifecycle_service.dart';
import 'package:pocketharness/core/config/remote_config_service.dart';
import 'package:pocketharness/core/security/secure_db_key_service.dart';
import 'package:pocketharness/core/membership/membership_service.dart';
import 'package:pocketharness/core/sync/sync_service.dart';
import 'package:pocketharness/core/ai/inference_params_provider.dart';
import 'package:pocketharness/core/ai/llama_context.dart';
import 'package:pocketharness/data/repositories/user_repository.dart';
import 'package:pocketharness/data/services/database_service.dart';
import 'package:pocketharness/data/services/ai_service.dart';
import 'package:pocketharness/data/services/llama_service.dart';
import 'package:pocketharness/data/services/model_manager_service.dart';
import 'package:pocketharness/data/services/offline_ai_service.dart';
import 'package:pocketharness/data/services/ai_persona_service.dart';
import 'package:pocketharness/data/services/terminal_service.dart';
import 'package:pocketharness/data/services/wallpaper_service.dart';
import 'package:pocketharness/data/services/sfx_service.dart';
import 'package:pocketharness/data/services/ai_source_settings_service.dart';
import 'package:pocketharness/firebase_options.dart';
import 'package:pocketharness/core/tools/tools_service.dart';
import 'package:pocketharness/core/tools/native_tools_manager.dart';
import 'package:pocketharness/data/services/first_setup_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 0. FirstSetupService — ekstrak bundled CLI tools di background ───────
  // Tidak blocking: UI akan subscribe ke statusStream via FirstSetupScreen.
  // Setelah tools ter-ekstrak, flag disimpan ke SharedPreferences agar
  // launch berikutnya langsung skip (< 1ms).
  // NativeToolsManager diakses via singleton — tidak perlu init eksplisit.
  unawaited(FirstSetupService.instance.runIfNeeded().then((_) {
    if (ToolsService.instance.isReady) {
      debugPrint('[main] Tools ready — NativeToolsManager: '
          '${NativeToolsManager.instance.presentTools.length} tools on disk');
    }
  }));

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
          // ── Jalur utama: model terdaftar & file ada ─────────────────────
          debugPrint('[main] Auto-loading active model via LlamaService: ${active.name}');
          final ok = await LlamaService.instance.loadModel(active);
          if (ok) {
            debugPrint('[main] Auto-load success: ${active.name}');
            // FIX #4: Sync OfflineAiService agar isReady = true
            OfflineAiService.instance.syncFromLlamaService(active.path);
          } else {
            debugPrint('[main] Auto-load failed — trying lastModelPath fallback');
            // ── FIX: Fallback ke lastModelPath jika load utama gagal ──────
            final lastPath = LlamaService.instance.lastLoadedModelPath;
            if (lastPath != null && File(lastPath).existsSync()) {
              final fallbackModel = LlamaModelInfo.fromPath(lastPath);
              final fallbackOk = await LlamaService.instance.loadModel(fallbackModel);
              debugPrint('[main] Fallback load ${fallbackOk ? "success" : "failed"}: $lastPath');
              if (fallbackOk) {
                // FIX #4: Sync OfflineAiService di jalur fallback
                OfflineAiService.instance.syncFromLlamaService(lastPath);
                final lastId = LlamaService.instance.lastLoadedModelId;
                if (lastId != null) {
                  await ModelManagerService.instance.setActive(lastId);
                }
              }
            }
          }
        } else if (activeRaw != null) {
          // ── Model terdaftar tapi file hilang — coba lastModelPath ────────
          debugPrint('[main] Registered model file missing: ${activeRaw.path}');
          final lastPath = LlamaService.instance.lastLoadedModelPath;
          if (lastPath != null && lastPath != activeRaw.path && File(lastPath).existsSync()) {
            debugPrint('[main] Trying lastModelPath fallback: $lastPath');
            final fallbackModel = LlamaModelInfo.fromPath(lastPath);
            final fallbackOk = await LlamaService.instance.loadModel(fallbackModel);
            debugPrint('[main] Fallback load ${fallbackOk ? "success" : "failed"}: $lastPath');
            // FIX #4: Sync OfflineAiService
            if (fallbackOk) {
              OfflineAiService.instance.syncFromLlamaService(lastPath);
            }
          }
        } else {
          // ── Tidak ada model aktif — coba langsung dari lastModelPath ─────
          final lastPath = LlamaService.instance.lastLoadedModelPath;
          if (lastPath != null && File(lastPath).existsSync()) {
            debugPrint('[main] No active model — loading from lastModelPath: $lastPath');
            final fallbackModel = LlamaModelInfo.fromPath(lastPath);
            final fallbackOk = await LlamaService.instance.loadModel(fallbackModel);
            debugPrint('[main] lastModelPath load ${fallbackOk ? "success" : "failed"}');
            if (fallbackOk) {
              // FIX #4: Sync OfflineAiService
              OfflineAiService.instance.syncFromLlamaService(lastPath);
              final lastId = LlamaService.instance.lastLoadedModelId;
              if (lastId != null) {
                await ModelManagerService.instance.setActive(lastId);
              }
            }
          } else {
            debugPrint('[main] No active model and no lastModelPath — skipping auto-load');
          }
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
      child: const PocketHarnessApp(),
    ));

  }, (error, stack) {
    debugPrint('[main] Uncaught error: $error');
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

// ── App root ──────────────────────────────────────────────────────────────────
class PocketHarnessApp extends StatefulWidget {
  const PocketHarnessApp({super.key});
  @override
  State<PocketHarnessApp> createState() => _PocketHarnessAppState();
}

class _PocketHarnessAppState extends State<PocketHarnessApp> {
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
      title: 'Pocket Harness',
      debugShowCheckedModeBanner: false,
      theme:     AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: appRouter,
    );
  }
}
