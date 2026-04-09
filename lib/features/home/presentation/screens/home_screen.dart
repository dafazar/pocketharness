// lib/features/home/presentation/screens/home_screen.dart
// KanMon GO — Home Screen (AI App Edition)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/theme/km_colors.dart';
import '../../../../core/router/app_router.dart';
// import '../../../../core/membership/premium_gate.dart'; // TODO: uncomment pre-release

// ── Menu items ────────────────────────────────────────────────────────────────
class _MenuItem {
  final String label, subtitle, route;
  final Color color;
  final IconData icon;
  const _MenuItem({
    required this.label,
    required this.subtitle,
    required this.route,
    required this.color,
    required this.icon,
  });
}

const _menuItems = [
  _MenuItem(
    label: 'AI Chat',
    subtitle: 'Chat dengan AI · File · Multi-session',
    route: '/chat',
    color: Color(0xFF6366F1),
    icon: Icons.auto_awesome_rounded,
  ),
  _MenuItem(
    label: 'OCR Scan',
    subtitle: 'Analisis gambar dengan AI',
    route: '/ocr',
    color: Color(0xFF0EA5E9),
    icon: Icons.document_scanner_rounded,
  ),
  _MenuItem(
    label: 'E-Book',
    subtitle: 'Baca & kelola dokumen',
    route: '/ebook',
    color: Color(0xFFD97706),
    icon: Icons.library_books_rounded,
  ),
  _MenuItem(
    label: 'Catatan',
    subtitle: 'Simpan catatan penting',
    route: '/notes',
    color: Color(0xFF64748B),
    icon: Icons.note_alt_rounded,
  ),
  _MenuItem(
    label: 'Reader',
    subtitle: 'Baca & analisis teks',
    route: '/reader',
    color: Color(0xFF14B8A6),
    icon: Icons.chrome_reader_mode_rounded,
  ),
  _MenuItem(
    label: 'Katalog AI',
    subtitle: '50+ model · Uncensored · Coding',
    route: '/settings/ai-catalog',
    color: Color(0xFFF59E0B),
    icon: Icons.explore_rounded,
  ),
  _MenuItem(
    label: 'Model Manager',
    subtitle: 'GGUF · TFLite · ONNX',
    route: '/settings/model-manager',
    color: Color(0xFF10B981),
    icon: Icons.folder_special_rounded,
  ),
  _MenuItem(
    label: 'Terminal',
    subtitle: 'Shell · AI · File Manager',
    route: '/terminal',
    color: Color(0xFF00C853),
    icon: Icons.terminal_rounded,
  ),
  _MenuItem(
    label: 'Media & AI',
    subtitle: 'Foto · Video · Analisis AI',
    route: '/media',
    color: Color(0xFFEC4899),
    icon: Icons.camera_alt_rounded,
  ),
  _MenuItem(
    label: 'AI Agent',
    subtitle: 'Otonom · Tools · Memory',
    route: '/agent',
    color: Color(0xFF7C3AED),
    icon: Icons.smart_toy_rounded,
  ),
];

// ── Home Screen ───────────────────────────────────────────────────────────────
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c      = KmColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user   = FirebaseAuth.instance.currentUser;
    final name   = user?.displayName?.split(' ').first ?? 'Pengguna';
    final hour   = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Selamat Pagi'
        : hour < 17
            ? 'Selamat Siang'
            : 'Selamat Malam';

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Header ──────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(greeting,
                            style: TextStyle(
                              fontSize: 14,
                              color: c.textMuted,
                            )),
                          const SizedBox(height: 2),
                          Text(name,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: c.text,
                              letterSpacing: -0.5,
                            )),
                        ],
                      ),
                    ),
                    // Avatar
                    GestureDetector(
                      onTap: () => context.push(KmRoutes.profile),
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: c.accent.withValues(alpha: 0.15),
                        backgroundImage: user?.photoURL != null
                            ? NetworkImage(user!.photoURL!)
                            : null,
                        child: user?.photoURL == null
                            ? Text(
                                name.isNotEmpty ? name[0].toUpperCase() : 'A',
                                style: TextStyle(
                                  color: c.accent,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── AI Chat Banner ────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    context.push(KmRoutes.chat);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [const Color(0xFF1e1b4b), const Color(0xFF312e81)]
                            : [const Color(0xFF6366F1), const Color(0xFF4F46E5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52, height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('AI Chat',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                )),
                              const SizedBox(height: 3),
                              Text(
                                'Chat · File · History · Multi-session',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.white.withValues(alpha: 0.7),
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Section label ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                child: Text('Fitur',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                    letterSpacing: -0.3,
                  )),
              ),
            ),

            // ── Menu Grid ────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.35,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _MenuCard(
                    item: _menuItems[i],
                    isDark: isDark,
                    c: c,
                  ),
                  childCount: _menuItems.length,
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

// ── Menu Card ─────────────────────────────────────────────────────────────────
class _MenuCard extends StatelessWidget {
  final _MenuItem item;
  final bool isDark;
  final KmColors c;

  const _MenuCard({required this.item, required this.isDark, required this.c});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        context.push(item.route);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: item.color.withValues(alpha: 0.2),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, color: item.color, size: 20),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  )),
                const SizedBox(height: 2),
                Text(item.subtitle,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: c.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
