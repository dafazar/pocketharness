// lib/data/services/first_setup_service.dart
// Pocket Harness — First Setup Service
//
// Deteksi & ekstrak bundled CLI tools dari APK assets secara otomatis
// saat pertama kali app dibuka. Setelah selesai, flag disimpan ke
// SharedPreferences sehingga ekstraksi tidak diulang pada launch berikutnya.
//
// Gunakan forceReset() saat APK diupdate dengan tools baru (deteksi via run_id).
// =============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocketharness/core/tools/tools_service.dart';

enum SetupStatus { idle, extracting, ready, failed }

class FirstSetupService {
  FirstSetupService._();
  static final FirstSetupService instance = FirstSetupService._();

  static const _kSetupDone = 'first_setup_done_v1';

  final _statusController = StreamController<SetupStatus>.broadcast();
  final _messageController = StreamController<String>.broadcast();
  final _progressController = StreamController<double>.broadcast();

  Stream<SetupStatus> get statusStream => _statusController.stream;
  Stream<String> get messageStream => _messageController.stream;
  Stream<double> get progressStream => _progressController.stream;

  SetupStatus _status = SetupStatus.idle;
  SetupStatus get status => _status;
  SetupStatus get currentStatus => _status;

  double _progress = 0.0;
  double get progress => _progress;

  String _message = '';
  String get message => _message;

  /// Dipanggil di main.dart sebelum runApp (atau unawaited).
  /// Jika tools sudah pernah diekstrak & run_id sama → langsung return ready.
  Future<void> runIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyDone = prefs.getBool(_kSetupDone) ?? false;

    if (alreadyDone && ToolsService.instance.isReady) {
      _emit(SetupStatus.ready, '✅ Tools siap digunakan.', 1.0);
      return;
    }

    await _runSetup(prefs);
  }

  Future<void> _runSetup(SharedPreferences prefs) async {
    _emit(SetupStatus.extracting, 'Menyiapkan tools bawaan...', 0.05);
    try {
      await ToolsService.instance.initialize(
        onProgress: (pct) {
          _emit(
            SetupStatus.extracting,
            'Mengekstrak tools... ${(pct * 100).toStringAsFixed(0)}%',
            pct * 0.9,
          );
        },
      );

      if (!ToolsService.instance.isReady) {
        _emit(
          SetupStatus.failed,
          'Tools tidak ditemukan dalam APK.\n'
          'Rebuild via GitHub Actions diperlukan.',
          0.0,
        );
        return;
      }

      await prefs.setBool(_kSetupDone, true);
      _emit(
        SetupStatus.ready,
        '✅ Semua tools siap: Node.js, Claude Code, VSCode, git, python3...',
        1.0,
      );
    } catch (e) {
      _emit(SetupStatus.failed, 'Setup gagal: $e', 0.0);
      debugPrint('[FirstSetupService] error: $e');
    }
  }

  /// Paksa re-ekstrak — berguna saat APK update dengan tools baru.
  Future<void> forceReset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSetupDone);
    _emit(SetupStatus.idle, 'Mereset tools...', 0.0);
    await _runSetup(prefs);
  }

  /// Paksa emit ready — dipakai tombol "Lewati" di error screen.
  void skipSetup() => _emitReady();

  /// Internal: paksa emit ready state.
  void _emitReady() {
    _emit(SetupStatus.ready, 'Lanjut tanpa tools (mode terbatas).', 1.0);
  }

  void _emit(SetupStatus status, String msg, double progress) {
    _status = status;
    _message = msg;
    _progress = progress;
    if (!_statusController.isClosed) _statusController.add(status);
    if (!_messageController.isClosed) _messageController.add(msg);
    if (!_progressController.isClosed) _progressController.add(progress);
    debugPrint('[FirstSetupService] $status — $msg');
  }

  void dispose() {
    if (!_statusController.isClosed) _statusController.close();
    if (!_messageController.isClosed) _messageController.close();
    if (!_progressController.isClosed) _progressController.close();
  }
}
