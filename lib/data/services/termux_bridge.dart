// lib/data/services/termux_bridge.dart
//
// KanMon GO — TermuxBridge (Sesi 7A Bagian 1)
// Jembatan Dart ↔ Native Android untuk integrasi Termux.
//
// Arsitektur:
//   • TermuxResult  — data class untuk menampung hasil eksekusi command
//   • TermuxBridge  — singleton via MethodChannel 'com.kanmongo.app/termux'
//
// Method Channel (native side harus mengimplementasi handler):
//   • isTermuxInstalled → bool
//   • runCommand        → Map { stdout, stderr, exitCode }
//   • openTermux        → void
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// ── TermuxResult ──────────────────────────────────────────────────────────────

/// Menampung hasil eksekusi satu command lewat Termux.
class TermuxResult {
  /// Output standar dari command (stdout).
  final String stdout;

  /// Output error dari command (stderr).
  final String stderr;

  /// Kode keluar proses. 0 = sukses, non-zero = gagal.
  final int exitCode;

  /// Apakah Termux tersedia saat command dijalankan.
  final bool termuxAvailable;

  const TermuxResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.termuxAvailable,
  });

  // ── Getters ----------------------------------------------------------------

  /// `true` jika exitCode == 0 (command selesai tanpa error).
  bool get isSuccess => exitCode == 0;

  /// Gabungan stdout + stderr dalam format yang rapi untuk ditampilkan.
  /// Separator '---' hanya muncul jika kedua bagian terisi.
  String get combinedOutput {
    final hasOut = stdout.trim().isNotEmpty;
    final hasErr = stderr.trim().isNotEmpty;

    if (hasOut && hasErr) {
      return '${stdout.trim()}\n---\n${stderr.trim()}';
    } else if (hasOut) {
      return stdout.trim();
    } else if (hasErr) {
      return stderr.trim();
    }
    return '(no output)';
  }

  // ── Factory helpers --------------------------------------------------------

  /// Hasil dummy saat Termux tidak terinstall.
  factory TermuxResult.termuxNotFound() => const TermuxResult(
        stdout: '',
        stderr: 'Termux tidak terinstall atau tidak dapat diakses.',
        exitCode: -1,
        termuxAvailable: false,
      );

  /// Hasil dummy saat terjadi error pada sisi native/channel.
  factory TermuxResult.error(String message) => TermuxResult(
        stdout: '',
        stderr: message,
        exitCode: -1,
        termuxAvailable: true,
      );

  @override
  String toString() =>
      'TermuxResult(exitCode: $exitCode, available: $termuxAvailable, '
      'stdout: ${stdout.length}c, stderr: ${stderr.length}c)';
}

// ── TermuxBridge ──────────────────────────────────────────────────────────────

/// Singleton yang menjembatani Dart dengan native Android untuk menjalankan
/// perintah melalui Termux via [MethodChannel].
///
/// Sisi native (Kotlin/Java) wajib mengimplementasi:
/// ```
/// MethodChannel("com.kanmongo.app/termux")
/// ```
/// dengan handler untuk method:
/// - `isTermuxInstalled`
/// - `runCommand`
/// - `openTermux`
class TermuxBridge {
  TermuxBridge._();
  static final TermuxBridge instance = TermuxBridge._();

  static const _channelName = 'com.kanmongo.app/termux';
  static const _channel = MethodChannel(_channelName);

  // ── Public API -------------------------------------------------------------

  /// Mengecek apakah package `com.termux` terinstall di perangkat.
  ///
  /// Mengembalikan `true` jika terinstall, `false` jika tidak atau terjadi
  /// error pada native side.
  Future<bool> isTermuxInstalled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isTermuxInstalled');
      final installed = result ?? false;
      debugPrint('[TermuxBridge] isTermuxInstalled → $installed');
      return installed;
    } on PlatformException catch (e) {
      debugPrint('[TermuxBridge] isTermuxInstalled error: ${e.code} — ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[TermuxBridge] isTermuxInstalled unexpected error: $e');
      return false;
    }
  }

  /// Menjalankan [command] di lingkungan Termux.
  ///
  /// [command]  — perintah shell yang ingin dieksekusi (contoh: `'ls -la'`).
  /// [timeout]  — batas waktu eksekusi (default 60 detik).
  ///
  /// Mengembalikan [TermuxResult] dengan stdout, stderr, exitCode, dan
  /// status ketersediaan Termux.
  Future<TermuxResult> run(
    String command, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    debugPrint('[TermuxBridge] run: "$command" (timeout: ${timeout.inSeconds}s)');

    // Cek ketersediaan Termux terlebih dahulu
    final available = await isTermuxInstalled();
    if (!available) {
      debugPrint('[TermuxBridge] run aborted — Termux not found');
      return TermuxResult.termuxNotFound();
    }

    try {
      final raw = await _channel
          .invokeMethod<Map>('runCommand', {
            'command': command,
            'timeoutSeconds': timeout.inSeconds,
          })
          .timeout(
            // Tambahkan buffer 5 detik di sisi Dart agar native sempat
            // membersihkan proses sebelum kita cancel
            timeout + const Duration(seconds: 5),
            onTimeout: () => null,
          );

      if (raw == null) {
        debugPrint('[TermuxBridge] run: native returned null (timeout?)');
        return TermuxResult.error('Perintah timeout atau tidak ada respons dari native.');
      }

      final result = TermuxResult(
        stdout: (raw['stdout'] as String?) ?? '',
        stderr: (raw['stderr'] as String?) ?? '',
        exitCode: (raw['exitCode'] as int?) ?? -1,
        termuxAvailable: true,
      );

      debugPrint('[TermuxBridge] run result: $result');
      return result;

    } on PlatformException catch (e) {
      debugPrint('[TermuxBridge] run PlatformException: ${e.code} — ${e.message}');
      return TermuxResult.error('PlatformException [${e.code}]: ${e.message ?? 'unknown'}');
    } catch (e) {
      debugPrint('[TermuxBridge] run unexpected error: $e');
      return TermuxResult.error('Error tidak terduga: $e');
    }
  }

  /// Membuka aplikasi Termux secara eksternal.
  ///
  /// Mengembalikan `true` jika berhasil membuka, `false` jika gagal
  /// (misal Termux tidak terinstall atau intent ditolak sistem).
  Future<bool> openTermux() async {
    debugPrint('[TermuxBridge] openTermux');
    try {
      await _channel.invokeMethod<void>('openTermux');
      debugPrint('[TermuxBridge] openTermux — berhasil');
      return true;
    } on PlatformException catch (e) {
      debugPrint('[TermuxBridge] openTermux error: ${e.code} — ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[TermuxBridge] openTermux unexpected error: $e');
      return false;
    }
  }
}
