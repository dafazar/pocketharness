// lib/data/services/sfx_service.dart
//
// KanMon GO — SfxService
// Memutar sound effect dari assets/sounds/ menggunakan audioplayers.
// Singleton ringan dengan pool AudioPlayer agar tidak saling menabrak.
//
// Cara pakai:
//   SfxService.instance.play(Sfx.correct);
//   SfxService.instance.play(Sfx.wrong);
//
// SFX dimatikan otomatis jika user mematikan SFX di Settings.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Enum semua sound effect ──────────────────────────────────────────────────

enum Sfx {
  correct,        // jawaban benar (quiz, flashcard)
  wrong,          // jawaban salah
  perfect,        // quiz selesai / nilai tinggi
  tap,            // ketuk tombol umum
  flip,           // balik kartu flashcard
  swipeNext,      // next soal / swipe
  strokeOk,       // goresan menulis berhasil snap
  streak,         // combo / streak 3+
  levelUp,        // naik level
  openScreen,     // buka layar/menu baru
  back,           // kembali / tutup layar
  timerTick,      // tick timer tiap detik
  timerWarning,   // waktu mau habis
  bookmark,       // tambah/hapus bookmark
  notification,   // notifikasi / toast
  appStart,       // splash / buka app pertama kali
}

extension SfxAsset on Sfx {
  String get asset {
    switch (this) {
      case Sfx.correct:       return 'sounds/correct.wav';
      case Sfx.wrong:         return 'sounds/wrong.wav';
      case Sfx.perfect:       return 'sounds/perfect.wav';
      case Sfx.tap:           return 'sounds/tap.wav';
      case Sfx.flip:          return 'sounds/flip.wav';
      case Sfx.swipeNext:     return 'sounds/swipe_next.wav';
      case Sfx.strokeOk:      return 'sounds/stroke_ok.wav';
      case Sfx.streak:        return 'sounds/streak.wav';
      case Sfx.levelUp:       return 'sounds/level_up.wav';
      case Sfx.openScreen:    return 'sounds/open_screen.wav';
      case Sfx.back:          return 'sounds/back.wav';
      case Sfx.timerTick:     return 'sounds/timer_tick.wav';
      case Sfx.timerWarning:  return 'sounds/timer_warning.wav';
      case Sfx.bookmark:      return 'sounds/bookmark.wav';
      case Sfx.notification:  return 'sounds/notification.wav';
      case Sfx.appStart:      return 'sounds/app_start.wav';
    }
  }

  // Volume relatif per SFX (0.0 – 1.0)
  double get volume {
    switch (this) {
      case Sfx.correct:       return 0.85;
      case Sfx.wrong:         return 0.70;
      case Sfx.perfect:       return 0.90;
      case Sfx.tap:           return 0.50;
      case Sfx.flip:          return 0.55;
      case Sfx.swipeNext:     return 0.45;
      case Sfx.strokeOk:      return 0.65;
      case Sfx.streak:        return 0.80;
      case Sfx.levelUp:       return 0.88;
      case Sfx.openScreen:    return 0.40;
      case Sfx.back:          return 0.35;
      case Sfx.timerTick:     return 0.45;
      case Sfx.timerWarning:  return 0.75;
      case Sfx.bookmark:      return 0.65;
      case Sfx.notification:  return 0.60;
      case Sfx.appStart:      return 0.70;
    }
  }
}

// ── SfxService ───────────────────────────────────────────────────────────────

const _kSfxEnabledKey = 'kmg.settings.sfx_enabled';

class SfxService {
  SfxService._();
  static final SfxService instance = SfxService._();

  // Pool player agar SFX bisa overlap (misal correct + tap sekaligus)
  static const int _poolSize = 4;
  final List<AudioPlayer> _pool = [];
  int _poolIndex = 0;

  bool _enabled = true;
  bool _initialized = false;

  // ── Init (dipanggil sekali di main.dart) ──────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Load preferensi
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_kSfxEnabledKey) ?? true;

    // Buat pool AudioPlayer
    for (int i = 0; i < _poolSize; i++) {
      final p = AudioPlayer();
      await p.setReleaseMode(ReleaseMode.release);
      await p.setPlayerMode(PlayerMode.lowLatency);
      _pool.add(p);
    }
  }

  // ── Enabled getter/setter ─────────────────────────────────────────────────
  bool get enabled => _enabled;

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSfxEnabledKey, value);
    if (!value) _stopAll();
  }

  void _stopAll() {
    for (final p in _pool) {
      p.stop();
    }
  }

  /// Dipanggil saat app resume dari background.
  /// Stop semua player yang mungkin dalam state stale/corrupted setelah OS
  /// merebut audio focus, lalu reset pool index agar mulai dari fresh player.
  Future<void> stopAndReset() async {
    if (!_initialized) return;
    try {
      for (final p in _pool) {
        await p.stop();
      }
      _poolIndex = 0;
    } catch (_) {}
  }

  // ── Play ─────────────────────────────────────────────────────────────────
  Future<void> play(Sfx sfx) async {
    if (!_enabled || !_initialized) return;
    try {
      final player = _pool[_poolIndex % _poolSize];
      _poolIndex++;
      await player.setVolume(sfx.volume);
      await player.play(AssetSource(sfx.asset));
    } catch (_) {
      // Jangan crash jika audio gagal
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────
  Future<void> dispose() async {
    for (final p in _pool) {
      await p.dispose();
    }
    _pool.clear();
    _initialized = false;
  }
}

// ── Riverpod provider: sfx enabled state ─────────────────────────────────────

class SfxNotifier extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return SfxService.instance.enabled;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_kSfxEnabledKey) ?? true;
    if (state != v) state = v;
  }

  Future<void> toggle() async {
    final newVal = !state;
    state = newVal;
    await SfxService.instance.setEnabled(newVal);
  }

  Future<void> setValue(bool v) async {
    state = v;
    await SfxService.instance.setEnabled(v);
  }
}

final sfxProvider = NotifierProvider<SfxNotifier, bool>(SfxNotifier.new);
