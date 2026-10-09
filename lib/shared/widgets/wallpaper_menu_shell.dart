// lib/shared/widgets/wallpaper_menu_shell.dart
//
// Pocket Harness — WallpaperMenuShell
//
// Shell transparan yang membungkus semua layar menu fitur
// (Kana, Kanji, Vocab, Bunpou, Partikel, Writing, Flashcard, Notes, Mensetsu, Ebook).
//
// Cara kerja:
//   • Jika wallpaper AKTIF  → Stack([WallpaperBackground, child])
//   • Jika wallpaper NONAKTIF → langsung render child
//
// Screen child sudah mengatur backgroundColor-nya sendiri via wallpaperAwareBg():
//   • Wallpaper aktif   → backgroundColor: Colors.transparent → wallpaper terlihat
//   • Wallpaper nonaktif → backgroundColor: c.bg biasa
//
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pocketharness/core/wallpaper/wallpaper_provider.dart';
import 'wallpaper_background.dart';

class WallpaperMenuShell extends ConsumerWidget {
  final Widget child;
  const WallpaperMenuShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wCfg = ref.watch(wallpaperProvider);

    if (!wCfg.isActive) return child;

    // Wallpaper aktif: render background di paling bawah, konten di atas
    return Stack(
      fit: StackFit.expand,
      children: [
        const WallpaperBackground(),
        child,
      ],
    );
  }
}
