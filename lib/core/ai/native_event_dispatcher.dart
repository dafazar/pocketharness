// lib/core/ai/native_event_dispatcher.dart
// Pocket Harness — NativeEventDispatcher
//
// Singleton yang memiliki SATU EventChannel subscription ke native llama.cpp.
// Baik LlamaService maupun OfflineAiService mendaftar handler-nya di sini,
// sehingga tidak ada dua subscription ke EventChannel yang sama (race condition).
//
// Architecture:
//   LlamaService     ──┐
//                      ├── NativeEventDispatcher ── EventChannel(stream)
//   OfflineAiService ──┘
//
// Event di-broadcast ke SEMUA handler yang terdaftar. Masing-masing service
// memfilter event berdasarkan seq-nya sendiri.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeEventDispatcher {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final NativeEventDispatcher instance = NativeEventDispatcher._();
  NativeEventDispatcher._() { _init(); }

  // ── EventChannel ──────────────────────────────────────────────────────────
  static const _eventCh = EventChannel('com.pocketharness.llama/stream');

  // ── Registered handlers ────────────────────────────────────────────────────
  void Function(Map<dynamic, dynamic>)? _llamaServiceHandler;
  void Function(Map<dynamic, dynamic>)? _offlineAiHandler;

  // ── Subscription ──────────────────────────────────────────────────────────
  StreamSubscription<dynamic>? _sub;

  // ── Backoff state ──────────────────────────────────────────────────────────
  int _retryDelayMs = 200;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Daftarkan handler LlamaService. Dipanggil sekali saat LlamaService init.
  void registerLlamaService(void Function(Map<dynamic, dynamic>) handler) {
    _llamaServiceHandler = handler;
    debugPrint('[NativeEventDispatcher] LlamaService handler registered');
  }

  /// Daftarkan handler OfflineAiService. Dipanggil sekali saat OfflineAiService init.
  void registerOfflineAi(void Function(Map<dynamic, dynamic>) handler) {
    _offlineAiHandler = handler;
    debugPrint('[NativeEventDispatcher] OfflineAiService handler registered');
  }

  /// Hapus registrasi handler (opsional, untuk cleanup).
  void unregisterLlamaService() { _llamaServiceHandler = null; }
  void unregisterOfflineAi()   { _offlineAiHandler = null; }

  /// Bersihkan subscription (panggil saat app ditutup).
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    debugPrint('[NativeEventDispatcher] disposed');
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  void _init() {
    _sub?.cancel();
    _sub = _eventCh.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! Map) return;
        final map = Map<dynamic, dynamic>.from(event);
        // Broadcast ke semua handler yang terdaftar
        _llamaServiceHandler?.call(map);
        _offlineAiHandler?.call(map);
      },
      onError: (Object e) {
        debugPrint('[NativeEventDispatcher] EventChannel error: $e — retry ${_retryDelayMs}ms');
        Future<void>.delayed(Duration(milliseconds: _retryDelayMs), () {
          // Exponential backoff: 200 → 400 → 800 → 2000 (cap)
          _retryDelayMs = (_retryDelayMs * 2).clamp(200, 2000);
          _init();
        });
      },
      cancelOnError: false,
    );
    // Reset backoff setelah berhasil connect
    _retryDelayMs = 200;
    debugPrint('[NativeEventDispatcher] EventChannel subscribed (single)');
  }
}
