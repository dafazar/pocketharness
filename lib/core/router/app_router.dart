// lib/core/router/app_router.dart
// KanMon GO — App Router (AI App Edition)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kanmongo/features/splash/presentation/screens/splash_screen.dart';
import 'package:kanmongo/features/home/presentation/screens/home_screen.dart';
import 'package:kanmongo/features/notes/presentation/screens/notes_screen.dart';
import 'package:kanmongo/features/ebook/presentation/screens/ebook_screen.dart';
import 'package:kanmongo/features/profile/presentation/screens/profile_screen.dart';
import 'package:kanmongo/features/settings/presentation/screens/settings_screen.dart';
import 'package:kanmongo/features/settings/presentation/screens/offline_ai_screen.dart';
import 'package:kanmongo/features/settings/presentation/screens/model_manager_screen.dart';
import 'package:kanmongo/features/settings/presentation/screens/ai_persona_screen.dart';
import 'package:kanmongo/features/settings/presentation/screens/ai_catalog_screen.dart';
import 'package:kanmongo/features/settings/presentation/screens/online_ai_screen.dart';
import 'package:kanmongo/features/settings/presentation/screens/bulk_api_settings_screen.dart';
import 'package:kanmongo/features/settings/presentation/screens/puter_setup_screen.dart';
import 'package:kanmongo/features/settings/presentation/screens/ai_inference_params_screen.dart';
import 'package:kanmongo/features/terminal/presentation/screens/terminal_screen.dart';
import 'package:kanmongo/features/chat/presentation/screens/chat_screen.dart';
import 'package:kanmongo/features/agent/presentation/screens/agent_screen.dart';
import 'package:kanmongo/features/media/presentation/screens/media_creator_screen.dart';
import 'package:kanmongo/features/history/presentation/screens/history_screen.dart';
import 'package:kanmongo/features/ocr/presentation/screens/ocr_screen.dart';
import 'package:kanmongo/features/reader/presentation/screens/reader_screen.dart';
import 'package:kanmongo/features/auth/presentation/screens/login_screen.dart';
import 'package:kanmongo/features/auth/presentation/screens/register_screen.dart';
import 'package:kanmongo/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:kanmongo/features/membership/presentation/screens/paywall_screen.dart';
import 'package:kanmongo/features/membership/presentation/screens/membership_status_screen.dart';
import 'package:kanmongo/shared/widgets/main_scaffold.dart';
import 'package:kanmongo/shared/widgets/wallpaper_menu_shell.dart';

class KmRoutes {
  static const login           = '/auth/login';
  static const register        = '/auth/register';
  static const forgotPassword  = '/auth/forgot';
  static const home            = '/';
  static const ebook           = '/ebook';
  static const notes           = '/notes';
  static const profile         = '/profile';
  static const settings        = '/settings';
  static const offlineAi       = '/settings/offline-ai';
  static const modelManager    = '/settings/model-manager';
  static const aiPersona        = '/settings/ai-persona';
  static const aiCatalog        = '/settings/ai-catalog';
  static const onlineAi        = '/settings/online-ai';
  static const bulkApiSettings = '/settings/bulk-api';
  static const puterSetup      = '/settings/puter-setup';
  // ── Route baru Sesi 7 ────────────────────────────────────────────────────
  static const modelManagerAlt = '/model-manager';
  static const aiParams        = '/settings/ai-params';
  static const aiInference     = '/settings/ai-inference';
  // ────────────────────────────────────────────────────────────────────────
  static const terminal          = '/terminal';
  static const chat              = '/chat';
  static const media             = '/media';
  static const history         = '/history';
  static const ocr             = '/ocr';
  static const reader          = '/reader';
  static const paywall         = '/membership';
  static const membershipStatus = '/membership/status';
  static const agent           = '/agent';
  static const privacy         = '/privacy';
}

CustomTransitionPage<void> _slide(Widget child) => CustomTransitionPage(
  child: child,
  transitionDuration: const Duration(milliseconds: 300),
  transitionsBuilder: (_, anim, __, c) => SlideTransition(
    position: Tween(begin: const Offset(0.06, 0), end: Offset.zero)
        .chain(CurveTween(curve: Curves.easeOutCubic))
        .animate(anim),
    child: FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: c,
    ),
  ),
);

CustomTransitionPage<void> _fade(Widget child) => CustomTransitionPage(
  child: child,
  transitionDuration: const Duration(milliseconds: 200),
  transitionsBuilder: (_, anim, __, c) =>
      FadeTransition(opacity: anim, child: c),
);

final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  debugLogDiagnostics: false,
  routes: [
    GoRoute(path: '/splash', pageBuilder: (c, s) => _fade(const SplashScreen())),

    // Auth
    GoRoute(path: '/auth/login',    pageBuilder: (c, s) => _slide(const LoginScreen())),
    GoRoute(path: '/auth/register', pageBuilder: (c, s) => _slide(const RegisterScreen())),
    GoRoute(path: '/auth/forgot',   pageBuilder: (c, s) => _slide(const ForgotPasswordScreen())),

    // Membership
    GoRoute(path: '/membership',        pageBuilder: (c, s) => _slide(const PaywallScreen())),
    GoRoute(path: '/membership/status', pageBuilder: (c, s) => _slide(const MembershipStatusScreen())),

    // Main Shell (Bottom Nav)
    ShellRoute(
      builder: (context, state, child) => MainScaffold(child: child),
      routes: [
        GoRoute(path: '/',         pageBuilder: (c, s) => _fade(const HomeScreen())),
        GoRoute(path: '/history',  pageBuilder: (c, s) => _fade(const HistoryScreen())),
        GoRoute(path: '/profile',  pageBuilder: (c, s) => _fade(const ProfileScreen())),
        GoRoute(path: '/settings', pageBuilder: (c, s) => _fade(const SettingsScreen())),
        GoRoute(path: '/settings/offline-ai',     pageBuilder: (c, s) => _fade(const OfflineAiScreen())),
        GoRoute(path: '/settings/model-manager',  pageBuilder: (c, s) => _fade(const ModelManagerScreen())),
        GoRoute(path: '/settings/ai-persona',     pageBuilder: (c, s) => _fade(const AiPersonaScreen())),
        GoRoute(path: '/settings/ai-catalog',     pageBuilder: (c, s) => _fade(const AiCatalogScreen())),
        GoRoute(path: '/settings/online-ai',      pageBuilder: (c, s) => _fade(const OnlineAiScreen())),
        GoRoute(path: '/settings/bulk-api',       pageBuilder: (c, s) => _fade(const BulkApiSettingsScreen())),
        GoRoute(path: '/settings/puter-setup',    pageBuilder: (c, s) => _slide(const PuterSetupScreen())),
        // ── Route baru Sesi 7 ──────────────────────────────────────────────
        // /settings/ai-params → halaman parameter inferensi AI offline
        GoRoute(path: '/settings/ai-params',      pageBuilder: (c, s) => _slide(const AiInferenceParamsScreen())),
        // /settings/ai-inference → halaman fine-tuning parameter inferensi (suhu, top-p, dll)
        GoRoute(path: '/settings/ai-inference',   pageBuilder: (c, s) => _fade(const AiInferenceParamsScreen())),
        // ──────────────────────────────────────────────────────────────────
      ],
    ),

    // ── Route /model-manager di luar shell agar bisa dipush dari mana saja ─
    // Context.push('/model-manager') dari AiSourcePicker atau ChatScreen
    GoRoute(path: '/model-manager', pageBuilder: (c, s) => _slide(const ModelManagerScreen())),

    // Feature Shell
    ShellRoute(
      builder: (context, state, child) => WallpaperMenuShell(child: child),
      routes: [
        GoRoute(path: '/notes',    pageBuilder: (c, s) => _slide(const NotesScreen())),
        GoRoute(path: '/ebook',    pageBuilder: (c, s) => _slide(const EbookScreen())),
        GoRoute(path: '/ocr',      pageBuilder: (c, s) => _slide(const OcrScreen())),
        GoRoute(
          path: '/reader',
          pageBuilder: (c, s) {
            final extra = s.extra as Map<String, dynamic>?;
            return _slide(ReaderScreen(initialText: extra?['text'] as String?));
          },
        ),
      ],
    ),
    GoRoute(
      path: '/terminal',
      pageBuilder: (c, s) {
        final extra = s.extra as Map<String, dynamic>?;
        final initialCommand = extra?['initialCommand'] as String?;
        final autoRun = extra?['autoRun'] as bool? ?? false;
        return _fade(TerminalScreen(
          initialCommand: initialCommand,
          autoRun: autoRun,
        ));
      },
    ),
    GoRoute(path: '/chat',     pageBuilder: (c, s) => _fade(const ChatScreen())),
    GoRoute(path: '/agent',    pageBuilder: (c, s) => _fade(const AgentScreen())),
    GoRoute(path: '/media',    pageBuilder: (c, s) => _fade(const MediaCreatorScreen())),
    // C-005 fix: Privacy Policy screen
    GoRoute(
      path: '/privacy',
      pageBuilder: (c, s) => _slide(Scaffold(
        appBar: AppBar(title: const Text('Kebijakan Privasi')),
        body: const SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Text(
            'Kebijakan Privasi KanMon GO\n\n'
            'KanMon GO menghormati privasi pengguna. Data percakapan disimpan '
            'secara lokal di perangkat Anda dan tidak dikirim ke server tanpa izin.\n\n'
            'Untuk informasi lengkap, kunjungi: https://kanmongo.app/privacy',
            style: TextStyle(fontSize: 15, height: 1.6),
          ),
        ),
      )),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(child: Text('Route tidak ditemukan: ${state.uri}')),
  ),
);

final routerProvider = Provider<GoRouter>((ref) => appRouter);
