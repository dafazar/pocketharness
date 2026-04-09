// lib/data/services/system/wallpaper_service.dart
//
// KanMon GO — WallpaperService
// Menyimpan & memuat konfigurasi wallpaper (foto/video) dari SharedPreferences.
// Wallpaper berlaku di semua layar menu utama, tidak aktif di dalam sesi soal.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

// ── Tipe wallpaper ────────────────────────────────────────────────────────────
enum WallpaperType { none, photo, video }

// ── Model konfigurasi wallpaper ───────────────────────────────────────────────
class WallpaperConfig {
  final WallpaperType type;
  final String path;       // absolute path ke file di storage device
  final double opacity;    // 0.0–1.0, default 0.35 (overlay hitam transparan)
  final double blur;       // 0.0–10.0 (blur background foto), default 0
  final double playbackSpeed; // 0.25–2.0 kecepatan video, default 1.0
  final bool   muted;     // video tanpa suara (default true)

  const WallpaperConfig({
    this.type    = WallpaperType.none,
    this.path    = '',
    this.opacity = 0.35,
    this.blur    = 0.0,
    this.playbackSpeed = 1.0,
    this.muted   = true,
  });

  bool get isActive => type != WallpaperType.none && path.isNotEmpty;
  bool get isPhoto  => type == WallpaperType.photo;
  bool get isVideo  => type == WallpaperType.video;

  WallpaperConfig copyWith({
    WallpaperType? type,
    String? path,
    double? opacity,
    double? blur,
    double? playbackSpeed,
    bool?   muted,
  }) => WallpaperConfig(
    type:          type          ?? this.type,
    path:          path          ?? this.path,
    opacity:       opacity       ?? this.opacity,
    blur:          blur          ?? this.blur,
    playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    muted:         muted         ?? this.muted,
  );
}

// ── Service singleton ─────────────────────────────────────────────────────────
class WallpaperService {
  WallpaperService._();
  static final WallpaperService instance = WallpaperService._();

  static const _kType    = 'kmg.wallpaper.type';
  static const _kPath    = 'kmg.wallpaper.path';
  static const _kOpacity = 'kmg.wallpaper.opacity';
  static const _kBlur    = 'kmg.wallpaper.blur';
  static const _kSpeed   = 'kmg.wallpaper.speed';
  static const _kMuted   = 'kmg.wallpaper.muted';

  WallpaperConfig _config = const WallpaperConfig();
  WallpaperConfig get config => _config;

  // Panggil sekali di main() setelah SharedPreferences siap
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final typeStr = prefs.getString(_kType) ?? 'none';
    final type = WallpaperType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => WallpaperType.none,
    );
    final path  = prefs.getString(_kPath)    ?? '';
    final opacity = prefs.getDouble(_kOpacity) ?? 0.35;
    final blur    = prefs.getDouble(_kBlur)    ?? 0.0;
    final speed   = prefs.getDouble(_kSpeed)   ?? 1.0;
    final muted   = prefs.getBool(_kMuted)     ?? true;

    // Validasi file masih ada
    final fileOk = path.isEmpty || await File(path).exists();

    _config = WallpaperConfig(
      type:          fileOk ? type : WallpaperType.none,
      path:          fileOk ? path : '',
      opacity:       opacity,
      blur:          blur,
      playbackSpeed: speed,
      muted:         muted,
    );
  }

  Future<void> save(WallpaperConfig cfg) async {
    _config = cfg;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kType,    cfg.type.name);
    await prefs.setString(_kPath,    cfg.path);
    await prefs.setDouble(_kOpacity, cfg.opacity);
    await prefs.setDouble(_kBlur,    cfg.blur);
    await prefs.setDouble(_kSpeed,   cfg.playbackSpeed);
    await prefs.setBool(_kMuted,     cfg.muted);
  }

  Future<void> clear() => save(const WallpaperConfig());
}
