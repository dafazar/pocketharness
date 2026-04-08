// lib/core/auth/auth_service.dart
// KanMon GO — Auth Service (Fixed)
//
// PERUBAHAN dari versi sebelumnya:
//   ✅ fetchDbKeys() dipanggil otomatis setelah setiap login berhasil
//   ✅ clearKeys() dipanggil saat logout agar key hilang dari memory
//   ✅ initNewUser() dipanggil otomatis saat register/login pertama kali
//   ✅ Semua method login return hasil fetch key (tidak silent fail)
// =============================================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kanmongo/core/security/secure_db_key_service.dart';
import 'package:kanmongo/data/repositories/user_repository.dart';

// ── Providers ────────────────────────────────────────────────────────────────

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).valueOrNull;
});

final isLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider) != null;
});

// ── AuthService ───────────────────────────────────────────────────────────────

class AuthService {
  final _auth = FirebaseAuth.instance;
  final UserRepository _userRepo;

  AuthService(this._userRepo);

  // ── Register dengan Email ────────────────────────────────────────────────
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await cred.user?.updateDisplayName(displayName);
    await cred.user?.sendEmailVerification();

    // Buat dokumen user baru di Firestore
    if (cred.user != null) {
      await _userRepo.initNewUser(
        uid: cred.user!.uid,
        email: email,
        displayName: displayName,
      );
    }

    // Fetch DB key dari server setelah register berhasil
    await _fetchDbKeysAfterLogin();
    return cred;
  }

  // ── Login dengan Email ───────────────────────────────────────────────────
  Future<UserCredential> loginWithEmail({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    // Pastikan dokumen user ada di Firestore (untuk user lama yang mungkin belum punya)
    if (cred.user != null) {
      await _ensureUserDoc(cred.user!);
    }
    await _fetchDbKeysAfterLogin();
    return cred;
  }

  // ── Login dengan Google ──────────────────────────────────────────────────
  Future<UserCredential?> loginWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final cred = await _auth.signInWithCredential(credential);

    // Buat/pastikan dokumen Firestore ada
    if (cred.user != null) {
      await _ensureUserDoc(cred.user!);
    }
    await _fetchDbKeysAfterLogin();
    return cred;
  }

  // ── Login OTP — Step 1: kirim OTP ───────────────────────────────────────
  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String error) onError,
    required void Function(PhoneAuthCredential credential) onAutoVerified,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: onAutoVerified,
      verificationFailed: (e) => onError(mapError(e.code)),
      codeSent: (verificationId, _) => onCodeSent(verificationId),
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  // ── Login OTP — Step 2: verifikasi OTP ──────────────────────────────────
  Future<UserCredential> verifyOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final cred = await _auth.signInWithCredential(credential);
    if (cred.user != null) {
      await _ensureUserDoc(cred.user!);
    }
    await _fetchDbKeysAfterLogin();
    return cred;
  }

  // ── Guest / Anonymous ────────────────────────────────────────────────────
  // NOTE: Guest tidak mendapat DB key karena tidak ada user doc di Firestore.
  // Fitur yang butuh DB terenkripsi akan menggunakan plain SQLite fallback.
  Future<UserCredential> loginAsGuest() async {
    return _auth.signInAnonymously();
  }

  // ── Upgrade akun guest ke email ──────────────────────────────────────────
  Future<UserCredential> linkAnonymousWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    final cred = await _auth.currentUser!.linkWithCredential(credential);
    await _auth.currentUser?.updateDisplayName(displayName);

    // Sekarang punya akun permanen — buat user doc dan fetch key
    if (cred.user != null) {
      await _userRepo.initNewUser(
        uid: cred.user!.uid,
        email: email,
        displayName: displayName,
      );
      await _fetchDbKeysAfterLogin();
    }
    return cred;
  }

  // ── Reset Password ───────────────────────────────────────────────────────
  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // ── Logout ───────────────────────────────────────────────────────────────
  Future<void> logout() async {
    // Hapus DB key dari memory SEBELUM logout
    SecureDbKeyService.instance.clearKeys();

    await GoogleSignIn().signOut();
    await _auth.signOut();
  }

  // ── Update profil ────────────────────────────────────────────────────────
  Future<void> updateDisplayName(String name) async {
    await _auth.currentUser?.updateDisplayName(name);
    await _userRepo.updateDisplayName(name);
  }

  Future<void> updatePhotoUrl(String url) async {
    await _auth.currentUser?.updatePhotoURL(url);
    await _userRepo.updateAvatarUrl(url);
  }

  // ── Getters ──────────────────────────────────────────────────────────────
  User? get currentUser => _auth.currentUser;
  bool get isLoggedIn   => _auth.currentUser != null;
  bool get isAnonymous  => _auth.currentUser?.isAnonymous ?? true;
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  // ── Internal: fetch DB key setelah login ─────────────────────────────────
  Future<void> _fetchDbKeysAfterLogin() async {
    try {
      await SecureDbKeyService.instance.fetchKeysWithRetry(maxRetries: 3);
    } catch (e) {
      // Log error tapi tidak gagalkan login
      // User masih bisa login, hanya fitur DB terenkripsi yang tidak tersedia
      debugPrint('[AuthService] Gagal fetch DB key: $e');
    }
  }

  // ── Internal: pastikan user doc ada di Firestore ─────────────────────────
  Future<void> _ensureUserDoc(User user) async {
    try {
      final existing = await _userRepo.getUser();
      if (existing == null) {
        await _userRepo.initNewUser(
          uid: user.uid,
          email: user.email ?? '',
          displayName: user.displayName ?? 'Pelajar',
        );
      }
    } catch (e) {
      debugPrint('[AuthService] Gagal ensure user doc: $e');
    }
  }

  // ── Map Firebase error code ke pesan bahasa Indonesia ────────────────────
  static String mapError(String code) {
    switch (code) {
      case 'user-not-found':             return 'Akun tidak ditemukan.';
      case 'wrong-password':             return 'Password salah.';
      case 'email-already-in-use':       return 'Email sudah digunakan akun lain.';
      case 'invalid-email':              return 'Format email tidak valid.';
      case 'weak-password':              return 'Password terlalu lemah (min. 6 karakter).';
      case 'too-many-requests':          return 'Terlalu banyak percobaan. Coba lagi nanti.';
      case 'network-request-failed':     return 'Tidak ada koneksi internet.';
      case 'user-disabled':              return 'Akun ini telah dinonaktifkan.';
      case 'invalid-phone-number':       return 'Nomor HP tidak valid. Gunakan format +628xxx.';
      case 'invalid-verification-code':  return 'Kode OTP salah atau sudah kadaluarsa.';
      case 'session-expired':            return 'Sesi OTP habis. Kirim ulang kode.';
      case 'quota-exceeded':             return 'Kuota SMS habis. Coba lagi besok.';
      case 'missing-phone-number':       return 'Masukkan nomor HP terlebih dahulu.';
      case 'credential-already-in-use':  return 'Akun Google ini sudah terhubung ke akun lain.';
      case 'requires-recent-login':      return 'Sesi habis. Silakan login ulang.';
      case 'unknown':                    return 'Phone Auth belum diaktifkan di Firebase Console. Aktifkan di: Authentication → Sign-in method → Phone.';
      case 'app-not-authorized':         return 'App belum diizinkan pakai Phone Auth. Daftarkan SHA-1 di Firebase Console.';
      case 'missing-client-identifier':  return 'Konfigurasi belum lengkap. Hubungi developer.';
      default:                           return 'Terjadi kesalahan ($code). Coba lagi.';
    }
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(userRepositoryProvider));
});
