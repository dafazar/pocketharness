// lib/features/profile/presentation/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:kanmongo/core/auth/auth_service.dart';
import 'package:kanmongo/core/router/app_router.dart';
import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/core/theme/theme_provider.dart';
import 'package:kanmongo/data/repositories/user_repository.dart';
import 'package:kanmongo/shared/widgets/wallpaper_background.dart';
import 'package:kanmongo/shared/utils/top_snack.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themePackProvider);
    final user      = ref.watch(currentUserProvider);
    final isLoggedIn = user != null;

    return Scaffold(
      backgroundColor: wallpaperAwareBg(context, ref, KmColors.of(context).bg),
      body: CustomScrollView(
        slivers: [
          // ── Header ────────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            backgroundColor:
                wallpaperAwareCard(context, ref, KmColors.of(context).card),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      KmColors.of(context).card,
                      KmColors.of(context).card
                    ],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    // Avatar
                    Container(
                      width: 84, height: 84,
                      decoration: BoxDecoration(
                        color: isLoggedIn
                            ? KmColors.of(context).accent
                            : KmColors.of(context).accent.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: user?.photoURL != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: Image.network(user!.photoURL!,
                                  fit: BoxFit.cover),
                            )
                          : Center(
                              child: Icon(
                                isLoggedIn
                                    ? Icons.person_rounded
                                    : Icons.person_outline_rounded,
                                color: Colors.white,
                                size: 40,
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isLoggedIn
                          ? (user!.displayName ?? 'Pelajar KanMon GO')
                          : 'Belum Masuk',
                      style: TextStyle(
                          color: KmColors.of(context).text,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    if (!isLoggedIn)
                      Text('Masuk untuk sync progress',
                          style: TextStyle(
                              fontSize: 12,
                              color: KmColors.of(context).textMuted)),
                  ],
                ),
              ),
            ),
          ),

          // ── Body ──────────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // ── BELUM LOGIN: tampilkan tombol masuk ──────────────────────
                if (!isLoggedIn) ...[
                  _LoginPromptCard(context),
                  const SizedBox(height: 16),
                ],

                // ── SUDAH LOGIN: stats & menu ─────────────────────────────
                if (isLoggedIn) ...[ 
                  _StatsGridFromFirestore(),
                  const SizedBox(height: 16),
                  _ProfileMenuItem(
                    icon: Icons.sync_rounded,
                    label: 'Sinkronisasi Data',
                    onTap: () => showTopSnack(context, 'Data disinkronisasi ke cloud.'),
                  ),
                  const SizedBox(height: 16),
                  _ProfileMenuItem(
                    icon: Icons.logout_rounded,
                    label: 'Keluar',
                    textColor: Colors.red.shade400,
                    onTap: () => _confirmLogout(context, ref),
                  ),
                  const SizedBox(height: 24),
                  if (user!.email != null && user.email!.isNotEmpty)
                    Center(
                      child: Text(user.email!,
                          style: TextStyle(
                              color: KmColors.of(context).textMuted,
                              fontSize: 12)),
                    ),
                ],

                const SizedBox(height: 8),
                Center(
                  child: Text('KanMon GO v2.1',
                      style: TextStyle(
                          color: KmColors.of(context).textMuted,
                          fontSize: 11)),
                ),
                const SizedBox(height: 16),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // Kartu prompt login
  Widget _LoginPromptCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('💾  Simpan Progress Kamu',
              style: TextStyle(color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Masuk atau daftar untuk menyimpan progress belajar, sinkronisasi antar device, dan akses fitur Premium.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: () => context.push(KmRoutes.login),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: cs.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Masuk',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () => context.push(KmRoutes.register),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white60),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Daftar'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Keluar dari KanMon GO?'),
        content:
            const Text('Progress yang tersinkronisasi tidak akan hilang.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authServiceProvider).logout();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
  }
}

// ── Stats grid dari Firestore ─────────────────────────────────────────────────
class _StatsGridFromFirestore extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox();
    return FutureBuilder<Map<String, dynamic>?>(
      future: ref.read(userRepositoryProvider).getUser(),
      builder: (context, snapshot) {
        final stats =
            snapshot.data?['stats'] as Map<String, dynamic>? ?? {};
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2,
          children: [
            _StatItem(label: 'AI Agent',
                value: '${stats['totalXp'] ?? 0} sesi',
                iconPath: 'assets/icons/logo/icon_star.svg'),
            _StatItem(label: 'Streak',
                value: '${stats['currentStreak'] ?? 0} hari',
                iconPath: 'assets/icons/ic_fire.svg'),
            _StatItem(label: 'Quiz Selesai',
                value: '${stats['quizzesTaken'] ?? 0} scan',
                iconPath: 'assets/icons/logo/icon_quiz.svg'),  // OCR Scan count
            _StatItem(label: 'Streak Terbaik',
                value: '${stats['longestStreak'] ?? 0} hari',
                iconPath: 'assets/icons/ic_heart.svg'),
          ],
        );
      },
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label, value, iconPath;
  const _StatItem(
      {required this.label, required this.value, required this.iconPath});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KmColors.of(context).card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        SvgPicture.asset(iconPath, width: 24, height: 24,
            colorFilter: ColorFilter.mode(
                KmColors.of(context).accent, BlendMode.srcIn)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: KmColors.of(context).text)),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: KmColors.of(context).textMuted)),
            ],
          ),
        ),
      ]),
    );
  }
}

class _ProfileMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accentColor;
  final Color? textColor;

  const _ProfileMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accentColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? KmColors.of(context).accent;
    final text   = textColor ?? KmColors.of(context).text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: KmColors.of(context).card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(icon, size: 22, color: accent),
              const SizedBox(width: 14),
              Expanded(
                  child: Text(label,
                      style: TextStyle(fontSize: 15, color: text))),
              Icon(Icons.chevron_right_rounded,
                  color: KmColors.of(context).textMuted, size: 20),
            ]),
          ),
        ),
      ),
    );
  }
}
