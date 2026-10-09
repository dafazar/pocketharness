import 'package:flutter/material.dart';
import 'package:pocketharness/data/services/first_setup_service.dart';

/// Wrapper widget yang menampilkan progress setup pertama kali sebelum
/// menampilkan konten utama (child).
class FirstSetupScreen extends StatefulWidget {
  const FirstSetupScreen({super.key, required this.child});
  final Widget child;

  @override
  State<FirstSetupScreen> createState() => _FirstSetupScreenState();
}

class _FirstSetupScreenState extends State<FirstSetupScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SetupStatus>(
      stream: FirstSetupService.instance.statusStream,
      initialData: FirstSetupService.instance.currentStatus,
      builder: (context, snapshot) {
        final status = snapshot.data ?? SetupStatus.idle;

        if (status == SetupStatus.ready) return widget.child;

        if (status == SetupStatus.failed) {
          return _buildError();
        }

        return _buildProgress();
      },
    );
  }

  Widget _buildProgress() {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Color(0xFF7C3AED),
                  size: 40,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Pocket Harness',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              StreamBuilder<String>(
                stream: FirstSetupService.instance.messageStream,
                initialData: 'Mempersiapkan aplikasi...',
                builder: (context, snap) {
                  return Text(
                    snap.data ?? 'Mempersiapkan...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              StreamBuilder<double>(
                stream: FirstSetupService.instance.progressStream,
                initialData: 0.0,
                builder: (context, snap) {
                  final progress = snap.data ?? 0.0;
                  return Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress > 0 ? progress : null,
                          backgroundColor: const Color(0xFF1E1E2E),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF7C3AED)),
                          minHeight: 6,
                        ),
                      ),
                      if (progress > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${(progress * 100).toInt()}%',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: Color(0xFFEF4444),
                size: 56,
              ),
              const SizedBox(height: 20),
              const Text(
                'Setup Gagal',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              StreamBuilder<String>(
                stream: FirstSetupService.instance.messageStream,
                initialData: 'Terjadi kesalahan saat setup awal.',
                builder: (context, snap) {
                  return Text(
                    snap.data ?? 'Terjadi kesalahan.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    onPressed: () {
                      FirstSetupService.instance.skipSetup();
                    },
                    child: const Text('Lewati'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      await FirstSetupService.instance.forceReset();
                      await FirstSetupService.instance.runIfNeeded();
                    },
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
