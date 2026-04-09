// lib/features/auth/presentation/screens/forgot_password_screen.dart
// KanMon GO — Forgot Password Screen
// Tab 1: Reset via Email (link reset dikirim ke email)
// Tab 2: Reset via No. HP (OTP SMS → ganti password baru)
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:kanmongo/core/auth/auth_service.dart';
import 'package:kanmongo/core/router/app_router.dart';
import 'package:kanmongo/shared/utils/top_snack.dart';

// ══════════════════════════════════════════════════════════════════════════════
// SHELL
// ══════════════════════════════════════════════════════════════════════════════
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState
    extends ConsumerState<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
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
              labelStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600),
              dividerColor: Colors.transparent,
              padding: const EdgeInsets.all(4),
              tabs: const [
                Tab(text: 'Via Email'),
                Tab(text: 'Via No. HP'),
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
                Text('Lupa Password?',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface)),
                const SizedBox(height: 4),
                Text('Pilih metode untuk reset password kamu',
                  style: TextStyle(
                      fontSize: 13.5,
                      color: cs.onSurface.withValues(alpha: 0.55))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: const [
                _EmailResetTab(),
                _PhoneResetTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 1 — RESET VIA EMAIL
//
// ALUR:
//   [Input email] → [Klik Kirim] → [Firebase kirim link reset ke email]
//   → [Halaman sukses + instruksi] → [User klik link di email]
//   → [Firebase buka halaman ganti password] → [Password berhasil diganti]
//   → [Kembali login dengan password baru]
// ══════════════════════════════════════════════════════════════════════════════
class _EmailResetTab extends ConsumerStatefulWidget {
  const _EmailResetTab();
  @override
  ConsumerState<_EmailResetTab> createState() => _EmailResetTabState();
}

class _EmailResetTabState extends ConsumerState<_EmailResetTab> {
  final _emailCtrl = TextEditingController();
  final _formKey   = GlobalKey<FormState>();
  bool _loading    = false;
  bool _sent       = false;
  String? _error;
  int _resendCountdown = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendReset() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authServiceProvider)
          .resetPassword(_emailCtrl.text.trim());
      setState(() { _sent = true; _loading = false; });
      _startResendCountdown();
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = AuthService.mapError(e.code);
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Terjadi kesalahan. Coba lagi.';
        _loading = false;
      });
    }
  }

  Future<void> _resend() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authServiceProvider)
          .resetPassword(_emailCtrl.text.trim());
      if (mounted) {
        showTopSnack(context, 'Email reset dikirim ulang!')
        _startResendCountdown();
      }
    } catch (_) {
      if (mounted) {
        showTopSnack(context, 'Gagal kirim ulang. Coba lagi.', isError: true)
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startResendCountdown() {
    setState(() => _resendCountdown = 60);
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_resendCountdown > 0) {
          _resendCountdown--;
        } else {
          t.cancel();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return _sent ? _buildSuccess() : _buildForm();
  }

  Widget _buildForm() {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ilustrasi
            Center(
              child: Container(
                width: 88, height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary.withValues(alpha: 0.1),
                ),
                child: Icon(Icons.lock_reset_rounded,
                    size: 44, color: cs.primary),
              ),
            ),
            const SizedBox(height: 24),

            Text('Masukkan email yang terdaftar.\nKami kirim link untuk reset password.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.6,
                  color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 24),

            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: const Icon(Icons.email_outlined, size: 20),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: cs.outline.withValues(alpha: 0.3))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: cs.primary, width: 1.5)),
                errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.error)),
              ),
              validator: (v) => (v == null ||
                      !v.contains('@') ||
                      !v.contains('.'))
                  ? 'Email tidak valid'
                  : null,
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorBox(_error!),
            ],
            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _loading ? null : _sendReset,
              icon: _loading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 20),
              label: const Text('Kirim Link Reset',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        children: [
          // Ikon sukses
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.shade600.withValues(alpha: 0.1),
            ),
            child: Icon(Icons.mark_email_read_rounded,
                size: 50, color: Colors.green.shade600),
          ),
          const SizedBox(height: 20),

          Text('Email Terkirim!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                color: cs.onSurface)),
          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
            ),
            child: Text(_emailCtrl.text.trim(),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                  color: cs.primary)),
          ),
          const SizedBox(height: 20),

          // Panduan
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
                Text('Langkah selanjutnya:',
                  style: TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w700, color: cs.onSurface)),
                const SizedBox(height: 10),
                _Step(num: '1',
                    text: 'Buka aplikasi email di HP kamu'),
                _Step(num: '2',
                    text: 'Cari email dari Firebase / KanMon GO'),
                _Step(num: '3',
                    text: 'Klik tombol "Reset Password" di dalam email'),
                _Step(num: '4',
                    text: 'Isi password baru minimal 6 karakter'),
                _Step(num: '5',
                    text: 'Kembali ke app dan login dengan password baru'),
              ],
            ),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Icon(Icons.info_outline, size: 13,
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

          // Kirim ulang
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: (_resendCountdown > 0 || _loading)
                  ? null
                  : _resend,
              icon: _loading
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, size: 18),
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

          FilledButton.icon(
            onPressed: () => context.go(KmRoutes.login),
            icon: const Icon(Icons.login_rounded, size: 20),
            label: const Text('Kembali ke Login',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
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
// TAB 2 — RESET VIA NO. HP
//
// ALUR:
//   [Input nomor HP] → [Kirim OTP] → [Input 6 digit OTP]
//   → [Verifikasi OTP] → [Input password baru] → [Update password]
//   → [Masuk ke Home]
//
// CATATAN: Firebase Phone Auth tidak bisa langsung reset password.
// Workaround: verifikasi nomor HP via OTP → sign in dengan credential
// → update password via updatePassword()
// ══════════════════════════════════════════════════════════════════════════════
class _PhoneResetTab extends ConsumerStatefulWidget {
  const _PhoneResetTab();
  @override
  ConsumerState<_PhoneResetTab> createState() => _PhoneResetTabState();
}

enum _PhoneResetStep { inputPhone, inputOtp, inputNewPassword, done }

class _PhoneResetTabState extends ConsumerState<_PhoneResetTab> {
  final _phoneCtrl    = TextEditingController();
  final _otpCtrl      = TextEditingController();
  final _pass1Ctrl    = TextEditingController();
  final _pass2Ctrl    = TextEditingController();

  _PhoneResetStep _step = _PhoneResetStep.inputPhone;
  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  String? _error;
  String? _verificationId;
  PhoneAuthCredential? _credential;
  int _resendCountdown = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _pass1Ctrl.dispose();
    _pass2Ctrl.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  String get _fullPhone {
    final raw = _phoneCtrl.text.trim()
        .replaceAll(' ', '').replaceAll('-', '');
    if (raw.startsWith('+'))  return raw;
    if (raw.startsWith('62')) return '+$raw';
    if (raw.startsWith('0'))  return '+62${raw.substring(1)}';
    return '+62$raw';
  }

  // ── Step 1: Kirim OTP ke nomor HP ────────────────────────────────────────
  Future<void> _sendOtp() async {
    if (_phoneCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Masukkan nomor HP terlebih dahulu.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    await ref.read(authServiceProvider).sendOtp(
      phoneNumber: _fullPhone,
      onCodeSent: (vid) {
        if (!mounted) return;
        setState(() {
          _verificationId  = vid;
          _step            = _PhoneResetStep.inputOtp;
          _loading         = false;
          _resendCountdown = 60;
        });
        _startCountdown();
      },
      onError: (msg) {
        if (!mounted) return;
        setState(() { _error = msg; _loading = false; });
      },
      onAutoVerified: (credential) async {
        if (!mounted) return;
        _credential = credential;
        setState(() { _step = _PhoneResetStep.inputNewPassword; _loading = false; });
      },
    );
  }

  void _startCountdown() {
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_resendCountdown > 0) _resendCountdown--;
        else t.cancel();
      });
    });
  }

  // ── Step 2: Verifikasi OTP ────────────────────────────────────────────────
  Future<void> _verifyOtp() async {
    if (_otpCtrl.text.trim().length < 6) {
      setState(() => _error = 'Masukkan 6 digit kode OTP.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      _credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpCtrl.text.trim(),
      );
      // Test credential dengan sign in sementara
      await FirebaseAuth.instance.signInWithCredential(_credential!);
      if (mounted) {
        setState(() {
          _step    = _PhoneResetStep.inputNewPassword;
          _loading = false;
        });
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error   = AuthService.mapError(e.code);
        _loading = false;
      });
    }
  }

  // ── Step 3: Update password baru ─────────────────────────────────────────
  Future<void> _updatePassword() async {
    if (_pass1Ctrl.text.length < 6) {
      setState(() => _error = 'Password minimal 6 karakter.');
      return;
    }
    if (_pass1Ctrl.text != _pass2Ctrl.text) {
      setState(() => _error = 'Password tidak sama.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Sesi habis, coba ulang.');
      await user.updatePassword(_pass1Ctrl.text);
      if (mounted) setState(() { _step = _PhoneResetStep.done; _loading = false; });
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error   = AuthService.mapError(e.code);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error   = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _PhoneResetStep.inputPhone:
        return _buildInputPhone();
      case _PhoneResetStep.inputOtp:
        return _buildInputOtp();
      case _PhoneResetStep.inputNewPassword:
        return _buildInputNewPassword();
      case _PhoneResetStep.done:
        return _buildDone();
    }
  }

  // ── UI: Input nomor HP ────────────────────────────────────────────────────
  Widget _buildInputPhone() {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary.withValues(alpha: 0.1),
              ),
              child: Icon(Icons.phone_outlined, size: 44, color: cs.primary),
            ),
          ),
          const SizedBox(height: 20),
          Text('Masukkan nomor HP yang terdaftar.\nKami kirim kode OTP via SMS.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.6,
                color: cs.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 24),

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
                border:
                    Border.all(color: cs.outline.withValues(alpha: 0.3)),
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
          Text('Nomor harus sama dengan yang dipakai saat daftar.',
            style: TextStyle(fontSize: 11,
                color: cs.onSurface.withValues(alpha: 0.4))),
          if (_error != null) ...[
            const SizedBox(height: 10), _ErrorBox(_error!)],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _loading ? null : _sendOtp,
            icon: _loading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.sms_outlined, size: 20),
            label: const Text('Kirim Kode OTP',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  // ── UI: Input OTP ─────────────────────────────────────────────────────────
  Widget _buildInputOtp() {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                child: Text('Kode dikirim ke $_fullPhone',
                  style: TextStyle(fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.8))),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _step = _PhoneResetStep.inputPhone;
                  _otpCtrl.clear();
                  _error = null;
                }),
                child: const Text('Ubah',
                    style: TextStyle(fontSize: 12)),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          Text('Masukkan 6 digit kode OTP dari SMS',
            style: TextStyle(fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 10),

          TextField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
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
                ? Text('Kirim ulang dalam ${_resendCountdown}s',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.5)))
                : TextButton(
                    onPressed: () {
                      setState(() => _step = _PhoneResetStep.inputPhone);
                      Future.microtask(_sendOtp);
                    },
                    child: const Text('Kirim ulang kode OTP',
                        style: TextStyle(fontSize: 12)),
                  ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 6), _ErrorBox(_error!)],
          const SizedBox(height: 16),

          FilledButton.icon(
            onPressed: _loading ? null : _verifyOtp,
            icon: _loading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.verified_outlined, size: 20),
            label: const Text('Verifikasi OTP',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  // ── UI: Input password baru ───────────────────────────────────────────────
  Widget _buildInputNewPassword() {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Badge OTP verified
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade600.withValues(alpha: 0.1),
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
                  Text('OTP Terverifikasi ✓',
                    style: TextStyle(fontSize: 13,
                        color: Colors.green.shade600,
                        fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          Text('Buat Password Baru',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                color: cs.onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text('Minimal 6 karakter.',
            style: TextStyle(fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.5)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Password baru
          TextField(
            controller: _pass1Ctrl,
            obscureText: _obscure1,
            decoration: InputDecoration(
              labelText: 'Password Baru',
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscure1
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20),
                onPressed: () =>
                    setState(() => _obscure1 = !_obscure1),
              ),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: cs.outline.withValues(alpha: 0.3))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: cs.primary, width: 1.5)),
            ),
          ),
          const SizedBox(height: 14),

          // Konfirmasi password
          TextField(
            controller: _pass2Ctrl,
            obscureText: _obscure2,
            decoration: InputDecoration(
              labelText: 'Konfirmasi Password Baru',
              prefixIcon:
                  const Icon(Icons.lock_outline_rounded, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscure2
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20),
                onPressed: () =>
                    setState(() => _obscure2 = !_obscure2),
              ),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: cs.outline.withValues(alpha: 0.3))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: cs.primary, width: 1.5)),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 10), _ErrorBox(_error!)],
          const SizedBox(height: 24),

          FilledButton.icon(
            onPressed: _loading ? null : _updatePassword,
            icon: _loading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded, size: 20),
            label: const Text('Simpan Password Baru',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  // ── UI: Berhasil ──────────────────────────────────────────────────────────
  Widget _buildDone() {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
      child: Column(
        children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.shade600.withValues(alpha: 0.1),
            ),
            child: Icon(Icons.check_circle_rounded,
                size: 52, color: Colors.green.shade600),
          ),
          const SizedBox(height: 24),
          Text('Password Berhasil Diubah!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                color: cs.onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text('Kamu bisa login dengan password baru sekarang.',
            style: TextStyle(fontSize: 14,
                color: cs.onSurface.withValues(alpha: 0.6)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => context.go(KmRoutes.home),
            icon: const Icon(Icons.home_rounded, size: 20),
            label: const Text('Ke Beranda',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
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
// SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _Step extends StatelessWidget {
  final String num;
  final String text;
  const _Step({required this.num, required this.text});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Container(
          width: 22, height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.primary.withValues(alpha: 0.12),
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
      ]),
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
