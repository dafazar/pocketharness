// lib/features/auth/presentation/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pocketharness/core/auth/auth_service.dart';
import 'package:pocketharness/core/router/app_router.dart';
import 'package:pocketharness/data/repositories/user_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
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
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 36, 28, 0),
              child: Column(children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Center(
                    child: Text('KM',
                      style: TextStyle(color: Colors.white, fontSize: 26,
                          fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Pocket Harness',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold,
                      color: cs.onSurface)),
                const SizedBox(height: 4),
                Text('Masuk untuk mulai belajar',
                  style: TextStyle(fontSize: 14,
                      color: cs.onSurface.withValues(alpha: 0.5))),
                const SizedBox(height: 28),
              ]),
            ),

            // ── Tabs ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
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
                    Tab(text: 'Email'),
                    Tab(text: 'Google'),
                    Tab(text: 'No. HP'),
                  ],
                ),
              ),
            ),

            // ── Tab Contents ───────────────────────────────────────────────
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

            // ── Footer ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Belum punya akun? ',
                    style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.6), fontSize: 13)),
                GestureDetector(
                  onTap: () => context.go(KmRoutes.register),
                  child: Text('Daftar',
                    style: TextStyle(color: cs.primary,
                        fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 1 — EMAIL
// ══════════════════════════════════════════════════════════════════════════════
class _EmailTab extends ConsumerStatefulWidget {
  const _EmailTab();
  @override
  ConsumerState<_EmailTab> createState() => _EmailTabState();
}

class _EmailTabState extends ConsumerState<_EmailTab> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey      = GlobalKey<FormState>();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authServiceProvider).loginWithEmail(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (mounted) context.go(KmRoutes.home);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = AuthService.mapError(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InputField(
              controller: _emailCtrl,
              label: 'Email',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (v) => (v == null || !v.contains('@'))
                  ? 'Email tidak valid' : null,
            ),
            const SizedBox(height: 14),
            _InputField(
              controller: _passwordCtrl,
              label: 'Password',
              icon: Icons.lock_outline,
              obscureText: _obscure,
              validator: (v) => (v == null || v.length < 6)
                  ? 'Min. 6 karakter' : null,
              suffix: IconButton(
                icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    size: 20),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.go(KmRoutes.forgotPassword),
                child: Text('Lupa Password?',
                    style: TextStyle(fontSize: 12, color: cs.primary)),
              ),
            ),
            if (_error != null) _ErrorBox(_error!),
            const SizedBox(height: 8),
            _PrimaryButton(
              label: 'Masuk dengan Email',
              loading: _loading,
              onPressed: _login,
              icon: Icons.login_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 2 — GOOGLE
// ══════════════════════════════════════════════════════════════════════════════
class _GoogleTab extends ConsumerStatefulWidget {
  const _GoogleTab();
  @override
  ConsumerState<_GoogleTab> createState() => _GoogleTabState();
}

class _GoogleTabState extends ConsumerState<_GoogleTab> {
  bool _loading = false;
  String? _error;

  Future<void> _loginGoogle() async {
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
      if (mounted) setState(() => _error = 'Login Google gagal. Coba lagi.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 16),
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
              Text('Masuk dengan Google',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
              const SizedBox(height: 6),
              Text('Cepat, aman, tanpa perlu ingat password.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.55))),
            ]),
          ),
          const SizedBox(height: 24),
          if (_error != null) ...[_ErrorBox(_error!), const SizedBox(height: 16)],
          OutlinedButton.icon(
            onPressed: _loading ? null : _loginGoogle,
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
// TAB 3 — NOMOR HP (OTP SMS)
// ══════════════════════════════════════════════════════════════════════════════
class _PhoneTab extends ConsumerStatefulWidget {
  const _PhoneTab();
  @override
  ConsumerState<_PhoneTab> createState() => _PhoneTabState();
}

class _PhoneTabState extends ConsumerState<_PhoneTab> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl   = TextEditingController();

  bool    _loading        = false;
  bool    _otpSent        = false;
  String? _verificationId;
  String? _error;
  int     _resendCountdown = 0;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  // Normalise ke format +628xxx
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
          if (!_otpSent) ...[
            // ── Step 1: input nomor ────────────────────────────────────────
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
                  border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
                ),
                child: const Text('+62 🇮🇩',
                    style: TextStyle(fontSize: 14,
                        fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    hintText: '08xxxxxxxxxx',
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
              const SizedBox(height: 10), _ErrorBox(_error!)],
            const SizedBox(height: 20),
            _PrimaryButton(
              label: 'Kirim Kode OTP',
              loading: _loading,
              onPressed: _sendOtp,
              icon: Icons.sms_outlined,
            ),
          ] else ...[
            // ── Step 2: input OTP ──────────────────────────────────────────
            Row(children: [
              Icon(Icons.check_circle_rounded,
                  color: Colors.green.shade400, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Kode dikirim ke $_fullPhone',
                  style: TextStyle(fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.7))),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _otpSent = false;
                  _otpCtrl.clear();
                  _error = null;
                }),
                child: const Text('Ubah', style: TextStyle(fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 20),
            Text('Masukkan 6 digit kode OTP dari SMS',
              style: TextStyle(fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 10),
            // OTP field besar
            TextField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 10),
              decoration: InputDecoration(
                counterText: '',
                hintText: '• • • • • •',
                hintStyle: TextStyle(fontSize: 22, letterSpacing: 8,
                    color: cs.onSurface.withValues(alpha: 0.2)),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: cs.primary, width: 2)),
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: _resendCountdown > 0
                  ? Text('Kirim ulang dalam ${_resendCountdown}s',
                      style: TextStyle(fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.5)))
                  : TextButton(
                      onPressed: () {
                        if (mounted) setState(() { _otpSent = false; });
                        Future.microtask(_sendOtp);
                      },
                      child: const Text('Kirim ulang kode OTP',
                          style: TextStyle(fontSize: 12)),
                    ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6), _ErrorBox(_error!)],
            const SizedBox(height: 16),
            _PrimaryButton(
              label: 'Verifikasi & Masuk',
              loading: _loading,
              onPressed: _verifyOtp,
              icon: Icons.verified_outlined,
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Tarif SMS normal berlaku. Kode OTP berlaku 60 detik.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.35)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

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
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600)),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
