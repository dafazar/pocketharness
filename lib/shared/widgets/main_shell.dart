// lib/shared/widgets/main_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/km_colors.dart';
import '../../data/services/sfx_service.dart';
import '../../data/services/import_progress_service.dart';
import 'back_handler.dart';

class MainShell extends ConsumerStatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});
  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _idx = 0;
  final _importSvc = ImportProgressService.instance;

  static const _tabs = [
    _TabItem(icon: Icons.home_rounded,     label: 'Beranda',  route: KmRoutes.home),
    _TabItem(icon: Icons.bar_chart_rounded, label: 'Statistik', route: KmRoutes.analytics),
    _TabItem(icon: Icons.person_rounded,   label: 'Profil',   route: KmRoutes.profile),
    _TabItem(icon: Icons.settings_rounded, label: 'Setelan',  route: KmRoutes.settings),
  ];

  @override
  void initState() {
    super.initState();
    _importSvc.addListener(_onImportChanged);
  }

  @override
  void dispose() {
    _importSvc.removeListener(_onImportChanged);
    super.dispose();
  }

  void _onImportChanged() {
    if (mounted) setState(() {});
  }

  void _onTap(int i) {
    if (_idx == i) return;
    setState(() => _idx = i);
    HapticFeedback.selectionClick();
    SfxService.instance.play(Sfx.tap);
    context.go(_tabs[i].route);
  }

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return ConfirmExitBack(
      message: 'Keluar dari KanMon GO?',
      confirmLabel: 'Keluar',
      child: Scaffold(
        backgroundColor: c.bg,
        body: widget.child,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Banner import progress — tetap tampil di semua halaman ───
            _ImportProgressBanner(importSvc: _importSvc, c: c),
            // ── Bottom nav ───────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: c.navBar,
                border: Border(top: BorderSide(color: c.border, width: 1)),
                boxShadow: c.isDark ? null : [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -4)),
                ],
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 60,
                  child: Row(
                    children: List.generate(_tabs.length, (i) {
                      final tab = _tabs[i];
                      final selected = i == _idx;
                      return Expanded(
                        child: InkWell(
                          onTap: () => _onTap(i),
                          borderRadius: BorderRadius.circular(12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedScale(
                                scale: selected ? 1.15 : 1.0,
                                duration: const Duration(milliseconds: 200),
                                child: Icon(tab.icon, size: 22,
                                  color: selected ? c.navBarSelected : c.navBarItem),
                              ),
                              const SizedBox(height: 3),
                              Text(tab.label, style: TextStyle(
                                fontSize: 10,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                                color: selected ? c.navBarSelected : c.navBarItem,
                              )),
                              const SizedBox(height: 2),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                height: 2, width: selected ? 20 : 0,
                                decoration: BoxDecoration(
                                  color: c.navBarSelected,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabItem {
  final IconData icon;
  final String label, route;
  const _TabItem({required this.icon, required this.label, required this.route});
}

// ── Import Progress Banner ────────────────────────────────────────────────────
// Banner tipis di atas bottom nav yang muncul saat ada import/download aktif.
// Tetap tampil di semua halaman agar user tidak kehilangan info progress
// meski sudah keluar dari ModelManagerScreen.

class _ImportProgressBanner extends StatelessWidget {
  final ImportProgressService importSvc;
  final KmColors c;

  const _ImportProgressBanner({
    required this.importSvc,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    // Cari progress aktif (import atau download)
    final activeImport = importSvc.activeImportProgress;
    final hasDownload  = importSvc.hasActiveDownload;

    if (activeImport == null && !hasDownload) {
      return const SizedBox.shrink(); // tidak ada yang aktif
    }

    // Pilih progress pertama yang aktif
    DownloadProgress? active = activeImport;
    if (active == null) {
      try {
        active = importSvc.downloads.values
            .firstWhere((p) => !p.isComplete && !p.hasError);
      } catch (_) {}
    }

    if (active == null) return const SizedBox.shrink();

    final pct      = active.fraction;
    final isImport = active.isImport;
    final name     = active.modelName ?? (isImport ? 'Import file...' : 'Download...');
    final color    = isImport ? Colors.teal : Theme.of(context).colorScheme.primary;
    final pctLabel = pct > 0
        ? '${(pct * 100).toStringAsFixed(0)}%'
        : (isImport ? 'Mempersiapkan...' : 'Connecting...');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border(
          top: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
      ),
      child: Stack(
        children: [
          // Progress bar background
          if (pct > 0)
            FractionallySizedBox(
              widthFactor: pct.clamp(0.0, 1.0),
              child: Container(
                color: color.withValues(alpha: 0.15),
              ),
            ),
          // Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                    value: pct > 0 ? pct : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${isImport ? "📥 Mengimport" : "⬇️ Mengunduh"}: $name',
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  pctLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (active.etaLabel != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    active.etaLabel!,
                    style: TextStyle(
                      fontSize: 10,
                      color: color.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
