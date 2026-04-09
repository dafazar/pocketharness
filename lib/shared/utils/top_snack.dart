// lib/shared/utils/top_snack.dart
// Utility: tampilkan SnackBar di bagian ATAS layar
// Gunakan ini sebagai pengganti ScaffoldMessenger.of(context).showSnackBar(...)
// di seluruh aplikasi agar notifikasi tidak menutup area chat.

import 'package:flutter/material.dart';

/// Tampilkan snackbar di bagian atas layar.
///
/// Contoh:
/// ```dart
/// showTopSnack(context, 'Pesan disalin.');
/// showTopSnack(context, 'Gagal: $e', isError: true);
/// ```
void showTopSnack(
  BuildContext context,
  String message, {
  Duration duration    = const Duration(seconds: 2),
  bool   isError       = false,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  if (!context.mounted) return;

  final mq         = MediaQuery.of(context);
  final topPadding = mq.padding.top + 8;          // di bawah status bar
  final screenW    = mq.size.width;
  final snackW     = screenW - 32;                 // 16px kiri+kanan margin
  // margin atas mendorong snack ke atas; margin bawah besar menekan snack
  // keluar dari posisi default bawah.
  final bottomPush = mq.size.height - topPadding - 56; // sisakan 56 untuk snack

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration,
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.only(
        left:   16,
        right:  16,
        bottom: bottomPush,
      ),
      width: snackW,
      backgroundColor: isError ? Colors.red.shade800 : null,
      action: actionLabel != null && onAction != null
          ? SnackBarAction(label: actionLabel, onPressed: onAction)
          : null,
    ),
  );
}
