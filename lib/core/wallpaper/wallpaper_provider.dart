// lib/core/wallpaper/wallpaper_provider.dart
//
// KanMon GO — WallpaperProvider (Riverpod)
// Provider global untuk state wallpaper — reaktif di seluruh app.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanmongo/data/services/wallpaper_service.dart';

class WallpaperNotifier extends Notifier<WallpaperConfig> {
  @override
  WallpaperConfig build() => WallpaperService.instance.config;

  Future<void> set(WallpaperConfig cfg) async {
    await WallpaperService.instance.save(cfg);
    state = cfg;
  }

  Future<void> clear() async {
    await WallpaperService.instance.clear();
    state = const WallpaperConfig();
  }

  Future<void> setOpacity(double v) => set(state.copyWith(opacity: v));
  Future<void> setBlur(double v)    => set(state.copyWith(blur: v));
  Future<void> setSpeed(double v)   => set(state.copyWith(playbackSpeed: v));
  Future<void> setMuted(bool v)     => set(state.copyWith(muted: v));
}

final wallpaperProvider =
    NotifierProvider<WallpaperNotifier, WallpaperConfig>(WallpaperNotifier.new);
