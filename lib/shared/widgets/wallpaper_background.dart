// lib/shared/widgets/wallpaper_background.dart
//
// Pocket Harness — WallpaperBackground
// Widget background wallpaper yang merender foto atau video secara looping
// di belakang konten layar menu. Otomatis tidak aktif di layar sesi soal.
//
// CARA PAKAI (di setiap layar menu):
//   Stack(children: [
//     const WallpaperBackground(),   // ← paling bawah
//     // ... konten layar
//   ])
//
// Atau gunakan WallpaperScaffold sebagai pengganti Scaffold standar.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import 'package:pocketharness/core/wallpaper/wallpaper_provider.dart';
import 'package:pocketharness/data/services/wallpaper_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// WallpaperBackground  — widget utama
// ═══════════════════════════════════════════════════════════════════════════

class WallpaperBackground extends ConsumerWidget {
  const WallpaperBackground({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(wallpaperProvider);
    if (!cfg.isActive) return const SizedBox.shrink();

    return Positioned.fill(
      child: cfg.isVideo
          ? _VideoWallpaper(cfg: cfg)
          : _PhotoWallpaper(cfg: cfg),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _PhotoWallpaper
// ═══════════════════════════════════════════════════════════════════════════

class _PhotoWallpaper extends StatelessWidget {
  final WallpaperConfig cfg;
  const _PhotoWallpaper({required this.cfg});

  @override
  Widget build(BuildContext context) {
    Widget img = Image.file(
      File(cfg.path),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );

    // Terapkan blur jika > 0
    if (cfg.blur > 0.1) {
      img = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: cfg.blur, sigmaY: cfg.blur),
        child: img,
      );
    }

    return Stack(fit: StackFit.expand, children: [
      img,
      // Overlay gelap/transparan agar teks tetap terbaca
      Container(color: Colors.black.withValues(alpha: cfg.opacity)),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _VideoWallpaper  — looping video tanpa suara
// ═══════════════════════════════════════════════════════════════════════════

class _VideoWallpaper extends StatefulWidget {
  final WallpaperConfig cfg;
  const _VideoWallpaper({required this.cfg});

  @override
  State<_VideoWallpaper> createState() => _VideoWallpaperState();
}

class _VideoWallpaperState extends State<_VideoWallpaper> {
  VideoPlayerController? _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init(widget.cfg.path);
  }

  @override
  void didUpdateWidget(_VideoWallpaper old) {
    super.didUpdateWidget(old);
    if (old.cfg.path != widget.cfg.path) {
      _ctrl?.dispose();
      _ready = false;
      _init(widget.cfg.path);
    } else if (_ctrl != null && _ready) {
      // Update kecepatan & volume tanpa restart video
      if (old.cfg.playbackSpeed != widget.cfg.playbackSpeed) {
        _ctrl!.setPlaybackSpeed(widget.cfg.playbackSpeed.clamp(0.25, 2.0));
      }
      if (old.cfg.muted != widget.cfg.muted) {
        _ctrl!.setVolume(widget.cfg.muted ? 0 : 1);
      }
    }
  }

  Future<void> _init(String path) async {
    final ctrl = VideoPlayerController.file(File(path));
    try {
      await ctrl.initialize();
      ctrl.setLooping(true);
      ctrl.setVolume(widget.cfg.muted ? 0 : 1);
      ctrl.setPlaybackSpeed(widget.cfg.playbackSpeed.clamp(0.25, 2.0));
      ctrl.play();
      if (mounted) setState(() { _ctrl = ctrl; _ready = true; });
    } catch (_) {
      ctrl.dispose();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _ctrl == null) return const SizedBox.shrink();

    return Stack(fit: StackFit.expand, children: [
      FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width:  _ctrl!.value.size.width,
          height: _ctrl!.value.size.height,
          child: VideoPlayer(_ctrl!),
        ),
      ),
      // Overlay untuk kontras teks
      Container(color: Colors.black.withValues(alpha: widget.cfg.opacity)),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WallpaperScaffold  — Scaffold siap pakai dengan wallpaper built-in
// ═══════════════════════════════════════════════════════════════════════════

/// Gunakan sebagai pengganti Scaffold standar di layar menu.
/// Wallpaper otomatis muncul di belakang semua konten.
class WallpaperScaffold extends ConsumerWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Color? backgroundColor;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  const WallpaperScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.backgroundColor,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(wallpaperProvider);

    return Scaffold(
      backgroundColor: cfg.isActive
          ? Colors.transparent  // biarkan wallpaper terlihat
          : backgroundColor,
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: cfg.isActive
          ? Stack(children: [
              const WallpaperBackground(),
              body,
            ])
          : body,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// wallpaperAwareBg() — helper untuk Scaffold backgroundColor di layar menu
//
// Gunakan sebagai pengganti `c.bg`:
//   backgroundColor: wallpaperAwareBg(context, ref, c.bg),
// Jika wallpaper aktif → transparent (wallpaper dari shell terlihat)
// Jika tidak → c.bg biasa
// ═══════════════════════════════════════════════════════════════════════════

Color wallpaperAwareBg(BuildContext context, WidgetRef ref, Color fallback) {
  final cfg = ref.watch(wallpaperProvider);
  return cfg.isActive ? Colors.transparent : fallback;
}

// ═══════════════════════════════════════════════════════════════════════════
// wallpaperAwareCard() — helper untuk AppBar / Card backgroundColor
//
// Gunakan sebagai pengganti `c.card` di AppBar agar semi-transparan saat
// wallpaper aktif, memberi efek frosted glass yang elegan:
//   backgroundColor: wallpaperAwareCard(context, ref, c.card),
// ═══════════════════════════════════════════════════════════════════════════

Color wallpaperAwareCard(BuildContext context, WidgetRef ref, Color fallback) {
  final cfg = ref.watch(wallpaperProvider);
  return cfg.isActive ? fallback.withValues(alpha: 0.72) : fallback;
}
