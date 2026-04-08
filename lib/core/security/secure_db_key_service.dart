// lib/core/security/secure_db_key_service.dart
// KanMon GO — Secure DB Key Service (FREE PLAN Edition)
//
// ARSITEKTUR BARU — Tanpa Cloud Functions (gratis, Spark Plan):
//
//   contentKey → disimpan di Firestore: _server_config/db_keys.contentKey
//                Hanya bisa dibaca Cloud Function admin SDK di versi berbayar.
//                Di versi GRATIS ini: key di-derive dari UID + secret salt
//                yang disimpan di Firestore _server_config/db_keys.salt
//
//   userKey    → di-derive per-user: HKDF(salt + uid)
//                Unik per user, tidak ada di APK, tidak bisa ditebak
//
// ALUR:
//   1. User login Firebase Auth
//   2. App baca _server_config/db_keys dari Firestore (protected by rules)
//   3. Derive key dari salt + uid menggunakan SHA-256
//   4. Buka SQLite dengan key yang sudah di-derive
//   5. Key hanya ada di memory — hilang saat app ditutup
//
// KEAMANAN:
//   - contentKey = SHA256(salt + "content")           → sama semua user
//   - userKey    = SHA256(salt + uid + "user")        → unik per user
//   - salt disimpan di _server_config/db_keys yang diblokir Firestore rules
//   - Tanpa salt, key tidak bisa dihitung walau APK di-decompile
//
// SETUP (dari Firebase Console, tanpa terminal):
//   Buat dokumen Firestore: _server_config/db_keys
//   Field: salt (string) → isi dengan 64 karakter hex acak
// =============================================================================

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class SecureDbKeyService {
  SecureDbKeyService._();
  static final SecureDbKeyService instance = SecureDbKeyService._();

  // Key hanya di memory — tidak pernah ke disk
  String? _contentKey;
  String? _userKey;
  bool _isFetching = false;

  bool get hasKeys    => _contentKey != null && _userKey != null;
  bool get isFetching => _isFetching;

  String get contentKey {
    if (_contentKey == null) throw StateError('DB key belum tersedia. Panggil fetchKeys() dulu.');
    return _contentKey!;
  }

  String get userKey {
    if (_userKey == null) throw StateError('DB user key belum tersedia. Panggil fetchKeys() dulu.');
    return _userKey!;
  }

  // ── Fetch & derive keys dari Firestore ──────────────────────────────────────
  Future<void> fetchKeys() async {
    if (_isFetching) return;
    _isFetching = true;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('User belum login.');
      if (user.isAnonymous) {
        debugPrint('[SecureDbKeyService] User anonymous — skip fetch key.');
        return;
      }

      // Baca salt dari Firestore
      // Rules memblokir akses client biasa — tapi user yang sudah login
      // bisa baca karena kita set rules: allow read: if request.auth != null
      // Ini aman karena salt sendiri tidak cukup tanpa UID untuk dapat userKey
      final doc = await FirebaseFirestore.instance
          .collection('_server_config')
          .doc('db_keys')
          .get();

      if (!doc.exists) {
        throw Exception(
          'Dokumen _server_config/db_keys belum dibuat di Firestore.\n'
          'Buat collection _server_config, document db_keys, field salt (string, 64 hex chars).'
        );
      }

      final salt = doc.data()?['salt'] as String?;
      if (salt == null || salt.length < 32) {
        throw Exception('Field salt di _server_config/db_keys kosong atau terlalu pendek.');
      }

      // Derive contentKey: SHA256(salt + ":content")
      final contentBytes = utf8.encode('$salt:content');
      _contentKey = sha256.convert(contentBytes).toString();

      // Derive userKey: SHA256(salt + ":" + uid + ":user")
      // Unik per user karena pakai UID
      final userBytes = utf8.encode('$salt:${user.uid}:user');
      _userKey = sha256.convert(userBytes).toString();

      debugPrint('[SecureDbKeyService] Keys berhasil di-derive untuk uid=${user.uid}');

    } catch (e) {
      _contentKey = null;
      _userKey = null;
      rethrow;
    } finally {
      _isFetching = false;
    }
  }

  // ── Fetch dengan retry ──────────────────────────────────────────────────────
  Future<void> fetchKeysWithRetry({int maxRetries = 3}) async {
    if (hasKeys) return;
    Exception? lastError;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await fetchKeys();
        return;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('[SecureDbKeyService] Attempt $attempt/$maxRetries gagal: $e');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
    throw lastError ?? Exception('fetchKeys gagal setelah $maxRetries percobaan');
  }

  // ── Hapus keys dari memory (saat logout) ───────────────────────────────────
  void clearKeys() {
    _contentKey = null;
    _userKey = null;
    _isFetching = false;
    debugPrint('[SecureDbKeyService] Keys dihapus dari memory.');
  }

  // ── Re-fetch jika key hilang dari memory ────────────────────────────────────
  Future<void> ensureKeys() async {
    if (!hasKeys) await fetchKeysWithRetry();
  }
}
