// lib/features/vscode/vscode_screen.dart
// SESSION 03 — VS Code Screen (Zero Stub)
// Tidak memuat service apapun. Hanya menampilkan UI placeholder.
import 'package:flutter/material.dart';
import 'package:kanmongo/core/theme/km_colors.dart';

class VscodeScreen extends StatelessWidget {
  final String? initialPath;
  const VscodeScreen({super.key, this.initialPath});

  @override
  Widget build(BuildContext context) {
    return const _VsCodeStubView();
  }
}

class _VsCodeStubView extends StatelessWidget {
  const _VsCodeStubView();

  @override
  Widget build(BuildContext context) {
    final kmc = KmColors.of(context);
    return Scaffold(
      backgroundColor: kmc.bg,
      appBar: AppBar(
        backgroundColor: kmc.bg,
        foregroundColor: kmc.text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'VS Code',
          style: TextStyle(color: kmc.text, fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: _StubBody(
        icon: Icons.code_rounded,
        iconColor: const Color(0xFF0EA5E9),
        title: 'VS Code',
        subtitle: 'IDE · code-server · Browser',
        description:
            'Fitur VS Code terintegrasi membutuhkan APK khusus yang '
            'di-build melalui GitHub Actions dengan bundle Node.js + code-server.\n\n'
            'Fitur ini akan tersedia pada versi berikutnya.',
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
                color: iconColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: iconColor.withOpacity(0.25), width: 1.5),
              ),
              child: Icon(icon, color: iconColor, size: 44),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: iconColor.withOpacity(0.30)),
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
