// lib/features/claude_code/presentation/screens/claude_code_screen.dart
// KanMonAI — Claude Code Screen (Zero Stub)
// Tidak memuat service apapun. Hanya menampilkan UI placeholder.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanmongo/core/theme/km_colors.dart';

class ClaudeCodeScreen extends ConsumerWidget {
  const ClaudeCodeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kmc = KmColors.of(context);
    return Scaffold(
      backgroundColor: kmc.bg,
      appBar: AppBar(
        backgroundColor: kmc.bg,
        foregroundColor: kmc.text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Claude Code',
          style: TextStyle(color: kmc.text, fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: const _StubBody(
        icon: Icons.smart_toy_outlined,
        iconColor: Color(0xFF10B981),
        title: 'Claude Code',
        subtitle: 'AI Coding Assistant · Terminal',
        description:
            'Fitur Claude Code membutuhkan Anthropic API key dan bundle '
            'tools (Node.js + Claude Code CLI) yang disertakan dalam APK.\n\n'
            'Tambahkan API key di Pengaturan → Online AI, lalu build ulang '
            'APK via GitHub Actions untuk mengaktifkan fitur ini.',
      ),
    );
  }
}


// ── Shared stub body ─────────────────────────────────────────────────────────
class _StubBody extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String description;

  const _StubBody({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final kmc = KmColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: iconColor.withValues(alpha: 0.25), width: 1.5),
              ),
              child: Icon(icon, color: iconColor, size: 44),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: iconColor.withValues(alpha: 0.30)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time_rounded, size: 13, color: iconColor),
                  const SizedBox(width: 5),
                  Text(
                    'Segera Hadir',
                    style: TextStyle(
                      color: iconColor, fontSize: 12,
                      fontWeight: FontWeight.w600, letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: kmc.text, fontSize: 22,
                fontWeight: FontWeight.bold, letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: TextStyle(color: kmc.textSub, fontSize: 13)),
            const SizedBox(height: 28),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: kmc.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kmc.border),
              ),
              child: Text(
                description,
                style: TextStyle(color: kmc.textSub, fontSize: 13.5, height: 1.65),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
