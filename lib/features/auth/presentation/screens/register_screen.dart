// lib/features/auth/presentation/screens/register_screen.dart
// KanMon GO — Register Screen
// Semua metode pendaftaran wajib verifikasi OTP/email sebelum masuk
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:kanmongo/core/auth/auth_service.dart';
import 'package:kanmongo/core/router/app_router.dart';
import 'package:kanmongo/data/repositories/user_repository.dart';
import 'package:kanmongo/shared/utils/top_snack.dart';

// ══════════════════════════════════════════════════════════════════════════════
// REGISTER SCREEN SHELL
// ══════════════════════════════════════════════════════════════════════════════
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.go(KmRoutes.login),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TabBar(
              controller: _tabCtrl,
              indicator: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: cs.onSurface.withValues(alpha: 0.5),
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              dividerColor: Colors.transparent,
              padding: const EdgeInsets.all(4),
              tabs: const [
                Tab(text: 'Email'),
                Tab(text: 'Google'),
                Tab(text: 'No. HP'),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Buat Akun Baru',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold,
                      color: cs.onSurface)),
                const SizedBox(height: 4),
                Text('Daftar untuk mulai menggunakan KanMon GO',
                  style: TextStyle(fontSize: 13.5,
                      color: cs.onSurface.withValues(alpha: 0.55))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: const [
                _EmailTab(),
                _GoogleTab(),
                _PhoneTab(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Sudah punya akun? ',
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 13)),
                GestureDetector(
                  onTap: () => context.go(KmRoutes.login),
                  child: Text('Masuk',
                    style: TextStyle(color: cs.primary, fontSize: 13,
                        fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 1 — EMAIL (dengan OTP verifikasi email)
//
// ALUR:
//   [Isi form] → [Klik Daftar] → [Akun dibuat, email verifikasi dikirim]
//   → [Tampil halaman tunggu verifikasi] → [User cek email, klik link]
//   → [Klik "Saya sudah verifikasi"] → [App cek status] → [Masuk ke Home]
// ══════════════════════════════════════════════════════════════════════════════
class _EmailTab extends ConsumerStatefulWidget {
  const _EmailTab();
  @override
  ConsumerState<_EmailTab> createState() => _EmailTabState();
}

class _EmailTabState extends ConsumerState<_EmailTab> {
  final _nameCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  final _formKey      = GlobalKey<FormState>();

  bool _loading    = false;
  bool _obscure1   = true;
  bool _obscure2   = true;
  bool _agreeTerms = false;
  String? _errorMsg;

  // State setelah register — menunggu verifikasi email
  bool _waitingVerification = false;
  String _registeredEmail   = '';
  bool _checkingVerif       = false;
  int  _resendCountdown     = 60;
  Timer? _resendTimer;
  Timer? _autoCheckTimer;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _resendTimer?.cancel();
    _autoCheckTimer?.cancel();
    super.dispose();
  }

  // ── Step 1: Buat akun dan kirim email verifikasi ─────────────────────────
  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreeTerms) {
      if (mounted) setState(() => _errorMsg = 'Kamu harus menyetujui syarat & ketentuan.');
      return;
    }
    if (mounted) setState(() { _loading = true; _errorMsg = null; });
    try {
      final auth = ref.read(authServiceProvider);
      final result = await auth.registerWithEmail(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        displayName: _nameCtrl.text.trim(),
      );

      // Akun berhasil dibuat, email verifikasi sudah dikirim otomatis
      // Sekarang tampilkan halaman tunggu verifikasi
      if (mounted) {
        if (mounted) setState(() {
          _waitingVerification = true;
          _registeredEmail = result.user?.email ?? _emailCtrl.text.trim();
          _loading = false;
        });
        _startResendCountdown();
        _startAutoCheck();
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() { _errorMsg = AuthService.mapError(e.code); _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _errorMsg = 'Terjadi kesalahan. Coba lagi.'; _loading = false; });
    }
  }

  // ── Auto check setiap 5 detik apakah email sudah diverifikasi ────────────
  void _startAutoCheck() {
    _autoCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _checkVerification(silent: true);
    });
  }

  // ── Countdown resend ─────────────────────────────────────────────────────
  void _startResendCountdown() {
    if (mounted) setState(() => _resendCountdown = 60);
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (mounted) setState(() {
        if (_resendCountdown > 0) {
          _resendCountdown--;
        } else {
          t.cancel();
        }
      });
    });
  }

  // ── Kirim ulang email verifikasi ─────────────────────────────────────────
  Future<void> _resendEmail() async {
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      _startResendCountdown();
      if (mounted) {
        showTopSnack(context, 'Email verifikasi dikirim ulang!');
      }
    } catch (_) {
      if (mounted) {
        showTopSnack(context, 'Gagal kirim ulang. Coba lagi.', isError: true);
      }
    }
  }

  // ── Cek apakah email sudah diverifikasi ──────────────────────────────────
  Future<void> _checkVerification({bool silent = false}) async {
    if (_checkingVerif && !silent) return;
    if (!silent) setState(() => _checkingVerif = true);
    try {
      // Reload user untuk dapat status terbaru
      await FirebaseAuth.instance.currentUser?.reload();
      final user = FirebaseAuth.instance.currentUser;

      if (user?.emailVerified == true) {
        _autoCheckTimer?.cancel();
        _resendTimer?.cancel();
        if (mounted) context.go(KmRoutes.home);
      } else if (!silent && mounted) {
        if (mounted) setState(() => _checkingVerif = false);
        showTopSnack(context, 'Email belum diverifikasi. Cek kotak masuk kamu.');
      }
    } catch (_) {
      if (!silent && mounted) setState(() => _checkingVerif = false);
    }
  }

  // ── Batalkan pendaftaran ─────────────────────────────────────────────────
  Future<void> _cancel() async {
    try {
      // Hapus akun yang belum diverifikasi
      await FirebaseAuth.instance.currentUser?.delete();
    } catch (_) {}
    _autoCheckTimer?.cancel();
    _resendTimer?.cancel();
    if (mounted) {
      if (mounted) setState(() {
        _waitingVerification = false;
        _emailCtrl.clear();
        _passwordCtrl.clear();
        _confirmCtrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _waitingVerification
        ? _buildWaitingVerification()
        : _buildForm();
  }

  // ── UI: Form pendaftaran ──────────────────────────────────────────────────
  Widget _buildForm() {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InputField(
              controller: _nameCtrl,
              label: 'Nama Lengkap',
              icon: Icons.person_outline_rounded,
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'Nama tidak boleh kosong' : null,
            ),
            const SizedBox(height: 14),
            _InputField(
              controller: _emailCtrl,
              label: 'Email',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v?.trim().isEmpty ?? true) return 'Email tidak boleh kosong';
                if (!v!.contains('@') || !v.contains('.'))
                  return 'Format email tidak valid';
                return null;
              },
            ),
            const SizedBox(height: 14),
            _InputField(
              controller: _passwordCtrl,
              label: 'Password',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscure1,
              suffix: IconButton(
                icon: Icon(
                    _obscure1
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20),
                onPressed: () => setState(() => _obscure1 = !_obscure1),
              ),
              validator: (v) =>
                  (v?.length ?? 0) < 6 ? 'Password minimal 6 karakter' : null,
            ),
            const SizedBox(height: 14),
            _InputField(
              controller: _confirmCtrl,
              label: 'Konfirmasi Password',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscure2,
              suffix: IconButton(
                icon: Icon(
                    _obscure2
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20),
                onPressed: () => setState(() => _obscure2 = !_obscure2),
              ),
              validator: (v) =>
                  v != _passwordCtrl.text ? 'Password tidak sama' : null,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Checkbox(
                  value: _agreeTerms,
                  onChanged: (v) => setState(() => _agreeTerms = v ?? false),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                ),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurface.withValues(alpha: 0.7)),
                      children: [
                        const TextSpan(text: 'Saya menyetujui '),
                        TextSpan(
                            text: 'Syarat & Ketentuan',
                            style: TextStyle(
                                color: cs.primary,
                                fontWeight: FontWeight.w600)),
                        const TextSpan(text: ' dan '),
                        TextSpan(
                            text: 'Kebijakan Privasi',
                            style: TextStyle(
                                color: cs.primary,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_errorMsg != null) ...[
              const SizedBox(height: 8),
              _ErrorBox(_errorMsg!),
            ],
            const SizedBox(height: 16),
            _PrimaryButton(
              label: 'Daftar Sekarang',
              loading: _loading,
              onPressed: _register,
              icon: Icons.person_add_outlined,
            ),
          ],
        ),
      ),
    );
  }

  // ── UI: Tunggu verifikasi email ───────────────────────────────────────────
  Widget _buildWaitingVerification() {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        children: [
          // Ikon animasi
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withValues(alpha: 0.1),
            ),
            child: Icon(Icons.mark_email_unread_outlined,
                size: 48, color: cs.primary),
          ),
          const SizedBox(height: 24),

          Text('Cek Email Kamu',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                color: cs.onSurface)),
          const SizedBox(height: 10),
          Text(
            'Kami kirim link verifikasi ke:',
            style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.6)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
            ),
            child: Text(_registeredEmail,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                  color: cs.primary),
            ),
          ),

          const SizedBox(height: 24),

          // Steps panduan
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cara verifikasi:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
                const SizedBox(height: 10),
                _VerifStep(num: '1', text: 'Buka aplikasi email di HP kamu'),
                _VerifStep(num: '2', text: 'Cari email dari KanMon GO atau Firebase'),
                _VerifStep(num: '3', text: 'Klik link "Verify Email" di dalam email'),
                _VerifStep(num: '4', text: 'Kembali ke sini dan klik tombol di bawah'),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Peringatan cek spam
          Row(
            children: [
              Icon(Icons.info_outline, size: 14,
                  color: cs.onSurface.withValues(alpha: 0.4)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Tidak ada email? Cek folder Spam / Promosi.',
                  style: TextStyle(fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.4)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Tombol utama: sudah verifikasi
          _PrimaryButton(
            label: 'Saya Sudah Verifikasi ✓',
            loading: _checkingVerif,
            onPressed: () => _checkVerification(silent: false),
            icon: Icons.verified_outlined,
          ),

          const SizedBox(height: 12),

          // Kirim ulang
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _resendCountdown > 0 ? null : _resendEmail,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                _resendCountdown > 0
                    ? 'Kirim ulang dalam ${_resendCountdown}s'
                    : 'Kirim Ulang Email',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500),
              ),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Batalkan
          TextButton(
            onPressed: _cancel,
            child: Text('Batalkan Pendaftaran',
              style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.4), fontSize: 13)),
          ),

          const SizedBox(height: 8),
          Text(
            'App akan otomatis masuk setelah verifikasi berhasil.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11, color: cs.onSurface.withValues(alpha: 0.3)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 2 — GOOGLE (tidak perlu OTP, Google yang verifikasi)
// ══════════════════════════════════════════════════════════════════════════════
class _GoogleTab extends ConsumerStatefulWidget {
  const _GoogleTab();
  @override
  ConsumerState<_GoogleTab> createState() => _GoogleTabState();
}

class _GoogleTabState extends ConsumerState<_GoogleTab> {
  bool _loading = false;
  String? _error;

  Future<void> _registerGoogle() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final auth   = ref.read(authServiceProvider);
      final result = await auth.loginWithGoogle();
      if (result == null) { setState(() => _loading = false); return; }
      if (result.additionalUserInfo?.isNewUser ?? false) {
        await ref.read(userRepositoryProvider).initNewUser(
          uid: result.user!.uid,
          email: result.user!.email ?? '',
          displayName: result.user!.displayName ?? 'Pengguna',
        );
      }
      if (mounted) context.go(KmRoutes.home);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = AuthService.mapError(e.code));
    } catch (_) {
      if (mounted) setState(() => _error = 'Daftar dengan Google gagal. Coba lagi.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
            ),
            child: Column(children: [
              const Text('🔐', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text('Daftar dengan Google',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
              const SizedBox(height: 8),
              Text(
                'Google sudah memverifikasi identitasmu.\nTidak perlu verifikasi tambahan.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.5,
                    color: cs.onSurface.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 10),
              // Badge verifikasi
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.shade600.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.green.shade600.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_rounded,
                        size: 16, color: Colors.green.shade600),
                    const SizedBox(width: 6),
                    Text('Terverifikasi otomatis oleh Google',
                      style: TextStyle(fontSize: 12,
                          color: Colors.green.shade600,
                          fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          if (_error != null) ...[_ErrorBox(_error!), const SizedBox(height: 16)],
          OutlinedButton.icon(
            onPressed: _loading ? null : _registerGoogle,
            icon: _loading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.g_mobiledata_rounded, size: 26),
            label: const Text('Lanjutkan dengan Google',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 3 — NO. HP (OTP via SMS)
// OTP sudah otomatis — Firebase kirim SMS dan verifikasi
// ══════════════════════════════════════════════════════════════════════════════
class _PhoneTab extends ConsumerStatefulWidget {
  const _PhoneTab();
  @override
  ConsumerState<_PhoneTab> createState() => _PhoneTabState();
}

class _PhoneTabState extends ConsumerState<_PhoneTab> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl   = TextEditingController();

  bool    _loading         = false;
  bool    _otpSent         = false;
  String? _verificationId;
  String? _error;
  int     _resendCountdown = 0;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  String get _fullPhone {
    final raw = _phoneCtrl.text.trim().replaceAll(' ', '').replaceAll('-', '');
    if (raw.startsWith('+'))  return raw;
    if (raw.startsWith('62')) return '+$raw';
    if (raw.startsWith('0'))  return '+62${raw.substring(1)}';
    return '+62$raw';
  }

  Future<void> _sendOtp() async {
    if (_phoneCtrl.text.trim().isEmpty) {
      if (mounted) setState(() => _error = 'Masukkan nomor HP terlebih dahulu.');
      return;
    }
    if (mounted) setState(() { _loading = true; _error = null; });
    await ref.read(authServiceProvider).sendOtp(
      phoneNumber: _fullPhone,
      onCodeSent: (vid) {
        if (!mounted) return;
        if (mounted) setState(() {
          _verificationId  = vid;
          _otpSent         = true;
          _loading         = false;
          _resendCountdown = 60;
        });
        _startCountdown();
      },
      onError: (msg) {
        if (!mounted) return;
        if (mounted) setState(() { _error = msg; _loading = false; });
      },
      onAutoVerified: (credential) async {
        if (!mounted) return;
        await _signIn(credential);
      },
    );
  }

  void _startCountdown() async {
    while (_resendCountdown > 0 && mounted) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) setState(() => _resendCountdown--);
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpCtrl.text.trim().length < 6) {
      if (mounted) setState(() => _error = 'Masukkan 6 digit kode OTP.');
      return;
    }
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final result = await ref.read(authServiceProvider).verifyOtp(
        verificationId: _verificationId!,
        smsCode: _otpCtrl.text.trim(),
      );
      if (result.additionalUserInfo?.isNewUser ?? false) {
        await ref.read(userRepositoryProvider).initNewUser(
          uid: result.user!.uid,
          email: '',
          displayName: result.user!.phoneNumber ?? 'Pengguna',
        );
      }
      if (mounted) context.go(KmRoutes.home);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() { _error = AuthService.mapError(e.code); _loading = false; });
    }
  }

  Future<void> _signIn(PhoneAuthCredential credential) async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final result =
          await FirebaseAuth.instance.signInWithCredential(credential);
      if (result.additionalUserInfo?.isNewUser ?? false) {
        await ref.read(userRepositoryProvider).initNewUser(
          uid: result.user!.uid,
          email: '',
          displayName: result.user!.phoneNumber ?? 'Pengguna',
        );
      }
      if (mounted) context.go(KmRoutes.home);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() { _error = AuthService.mapError(e.code); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_otpSent) ...[ // ── Input nomor ──────────────────────────
            // Badge OTP
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sms_outlined, size: 16, color: cs.primary),
                    const SizedBox(width: 6),
                    Text('Verifikasi via SMS OTP',
                      style: TextStyle(fontSize: 12, color: cs.primary,
                          fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Nomor HP',
              style: TextStyle(fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 8),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 17),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: cs.outline.withValues(alpha: 0.3)),
                ),
                child: const Text('+62 🇮🇩',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  decoration: InputDecoration(
                    hintText: '08xxxxxxxxxx',
                    filled: true,
                    fillColor:
                        cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: cs.outline.withValues(alpha: 0.3))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: cs.primary, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 16),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text('Contoh: 081234567890',
              style: TextStyle(fontSize: 11,
                  color: cs.onSurface.withValues(alpha: 0.4))),
            if (_error != null) ...[
              const SizedBox(height: 10), _ErrorBox(_error!)
            ],
            const SizedBox(height: 20),
            _PrimaryButton(
              label: 'Kirim Kode OTP',
              loading: _loading,
              onPressed: _sendOtp,
              icon: Icons.sms_outlined,
            ),

          ] else ...[ // ── Input OTP ──────────────────────────────────
            // Status kirim
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.shade600.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Colors.green.shade600.withValues(alpha: 0.25)),
              ),
              child: Row(children: [
                Icon(Icons.check_circle_rounded,
                    color: Colors.green.shade600, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Kode OTP dikirim ke $_fullPhone',
                    style: TextStyle(fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.8))),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _otpSent = false;
                    _otpCtrl.clear();
                    _error = null;
                  }),
                  child: const Text('Ubah',
                      style: TextStyle(fontSize: 12)),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            Text('Masukkan 6 digit kode OTP dari SMS',
              style: TextStyle(fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 10),
            TextField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly
              ],
              style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 12),
              decoration: InputDecoration(
                counterText: '',
                hintText: '• • • • • •',
                hintStyle: TextStyle(
                    fontSize: 22,
                    letterSpacing: 8,
                    color: cs.onSurface.withValues(alpha: 0.2)),
                filled: true,
                fillColor:
                    cs.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: cs.primary, width: 2)),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 18),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: _resendCountdown > 0
                  ? Text(
                      'Kirim ulang dalam ${_resendCountdown}s',
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.5)))
                  : TextButton(
                      onPressed: () {
                        if (mounted) setState(() => _otpSent = false);
                        Future.microtask(_sendOtp);
                      },
                      child: const Text('Kirim ulang kode OTP',
                          style: TextStyle(fontSize: 12)),
                    ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6), _ErrorBox(_error!)
            ],
            const SizedBox(height: 16),
            _PrimaryButton(
              label: 'Verifikasi & Daftar',
              loading: _loading,
              onPressed: _verifyOtp,
              icon: Icons.verified_outlined,
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Tarif SMS normal berlaku. Kode OTP berlaku 60 detik.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 10, color: cs.onSurface.withValues(alpha: 0.35)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _VerifStep extends StatelessWidget {
  final String num;
  final String text;
  const _VerifStep({required this.num, required this.text});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withValues(alpha: 0.15),
            ),
            alignment: Alignment.center,
            child: Text(num,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: cs.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
              style: TextStyle(fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.75))),
          ),
        ],
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final String? Function(String?)? validator;
  final Widget? suffix;
  const _InputField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.validator,
    this.suffix,
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.3))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: cs.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: cs.error)),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox(this.message);
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(children: [
        Icon(Icons.error_outline, size: 16, color: Colors.red.shade600),
        const SizedBox(width: 8),
        Expanded(child: Text(message,
            style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
      ]),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onPressed;
  final IconData icon;
  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onPressed,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : Icon(icon, size: 20),
      label: Text(label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
