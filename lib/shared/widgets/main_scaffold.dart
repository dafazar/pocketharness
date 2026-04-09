// lib/shared/widgets/main_scaffold.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/km_colors.dart';
import '../../core/wallpaper/wallpaper_provider.dart';
import '../../data/services/media/sfx_service.dart';
import 'wallpaper_background.dart';

class MainScaffold extends ConsumerWidget {
  final Widget child;
  const MainScaffold({super.key, required this.child});

  static const _items = [
    _NavItem(icon: Icons.home_outlined,     iconOn: Icons.home_rounded,     label: 'Beranda',    path: '/'),
    _NavItem(icon: Icons.history_outlined,  iconOn: Icons.history_rounded,  label: 'Riwayat',    path: '/history'),
    _NavItem(icon: Icons.person_outline,    iconOn: Icons.person_rounded,   label: 'Profil',     path: '/profile'),
    _NavItem(icon: Icons.settings_outlined, iconOn: Icons.settings_rounded, label: 'Setelan',    path: '/settings'),
  ];

  int _activeIndex(BuildContext context) {
    final loc = GoRouterState.of(context).uri.path;
    for (int i = _items.length - 1; i >= 0; i--) {
      if (_items[i].path == '/' ? loc == '/' : loc.startsWith(_items[i].path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c      = KmColors.of(context);
    final active = _activeIndex(context);
    final wCfg   = ref.watch(wallpaperProvider);

    return Scaffold(
      backgroundColor: wCfg.isActive ? Colors.transparent : c.bg,
      body: Stack(children: [
        if (wCfg.isActive) const WallpaperBackground(),
        child,
      ]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.navBar,
          border: Border(top: BorderSide(color: c.border, width: 1)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -2))],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(
              children: _items.asMap().entries.map((entry) {
                final i    = entry.key;
                final item = entry.value;
                final on   = active == i;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (!on) {
                        HapticFeedback.selectionClick();
                        SfxService.instance.play(Sfx.tap);
                        context.go(item.path);
                      }
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: on ? c.navBarSelected.withValues(alpha: 0.13) : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(on ? item.iconOn : item.icon, size: 23,
                            color: on ? c.navBarSelected : c.navBarItem),
                        ),
                        const SizedBox(height: 2),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                            color: on ? c.navBarSelected : c.navBarItem,
                          ),
                          child: Text(item.label),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: on ? 20 : 0, height: 3,
                          decoration: BoxDecoration(
                            color: on ? c.navBarSelected : Colors.transparent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon, iconOn;
  final String label, path;
  const _NavItem({required this.icon, required this.iconOn, required this.label, required this.path});
}
