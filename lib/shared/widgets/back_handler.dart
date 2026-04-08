// lib/shared/widgets/back_handler.dart
import 'package:flutter/material.dart';
import '../../core/theme/km_colors.dart';

// ── 1. SearchClearBack ───────────────────────────────────────────────────────
class SearchClearBack extends StatelessWidget {
  final Widget child;
  final TextEditingController searchCtrl;
  final FocusNode searchFocus;
  final VoidCallback onClear;

  const SearchClearBack({
    super.key,
    required this.child,
    required this.searchCtrl,
    required this.searchFocus,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (searchCtrl.text.isNotEmpty) {
          searchCtrl.clear();
          searchFocus.unfocus();
          onClear();
        } else {
          searchFocus.unfocus();
          Navigator.of(context).pop();
        }
      },
      child: child,
    );
  }
}

// ── 2. ConfirmExitBack ───────────────────────────────────────────────────────
/// Saat tombol back ditekan, tampilkan dialog konfirmasi.
/// [onBeforeConfirm] — opsional, dipanggil sebelum dialog (misal: pause video).
class ConfirmExitBack extends StatelessWidget {
  final Widget child;
  final String title;
  final String message;
  final String confirmLabel;
  final VoidCallback? onBeforeConfirm;

  const ConfirmExitBack({
    super.key,
    required this.child,
    this.title = 'Keluar?',
    this.message = 'Kemajuan kamu akan hilang. Yakin ingin keluar?',
    this.confirmLabel = 'Keluar',
    this.onBeforeConfirm,
  });

  Future<bool> _showConfirm(BuildContext context) async {
    final c = KmColors.of(context);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.87),
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: c.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.exit_to_app_rounded, color: c.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(color: c.text, fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ]),
          content: Text(
            message,
            style: TextStyle(color: c.textSub, fontSize: 14, height: 1.5),
          ),
          // FIX: jangan pakai Expanded di dalam actions (bukan Row/Column)
          // Gunakan Row manual di dalam satu widget saja
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.text,
                    side: BorderSide(color: c.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Lanjutkan',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(confirmLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ],
        );
      },
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        onBeforeConfirm?.call();
        final confirmed = await _showConfirm(context);
        if (confirmed && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: child,
    );
  }
}
