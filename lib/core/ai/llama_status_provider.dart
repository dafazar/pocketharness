// lib/core/ai/llama_status_provider.dart
// Convenience providers untuk status LlamaService — bisa di-watch dari widget mana saja
// Sesi 8 — Final Polish KanMon GO (PocketPal Architecture)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanmongo/core/ai/llama_context.dart';
import 'package:kanmongo/core/ai/inference_params_provider.dart';
import 'package:kanmongo/data/services/llama_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 1. STATUS STREAM PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

/// Stream status model AI — broadcast dari LlamaService
final llamaStatusProvider = StreamProvider<ModelStatus>((ref) {
  return LlamaService.instance.statusStream;
});

// ─────────────────────────────────────────────────────────────────────────────
// 2. LOAD PROGRESS STREAM PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

/// Stream progres pemuatan model (0.0 – 1.0)
final llamaLoadProgressProvider = StreamProvider<double>((ref) {
  return LlamaService.instance.loadProgressStream;
});

// ─────────────────────────────────────────────────────────────────────────────
// 3. MODEL LOADED CHECK (boolean, sinkron)
// ─────────────────────────────────────────────────────────────────────────────

/// Apakah model sudah siap digunakan (loaded atau sedang generating)
final isLlamaReadyProvider = Provider<bool>((ref) {
  final statusAsync = ref.watch(llamaStatusProvider);
  return statusAsync.maybeWhen(
    data: (status) =>
        status == ModelStatus.loaded || status == ModelStatus.generating,
    orElse: () => false,
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// 4. NAMA MODEL AKTIF
// ─────────────────────────────────────────────────────────────────────────────

/// Nama model yang sedang aktif, atau 'Belum ada model' jika belum dipilih
final llamaModelNameProvider = Provider<String>((ref) {
  final model = ref.watch(activeModelInfoProvider);
  return model?.name ?? 'Belum ada model';
});

// ─────────────────────────────────────────────────────────────────────────────
// 5. APAKAH SEDANG GENERATING
// ─────────────────────────────────────────────────────────────────────────────

/// True jika model sedang dalam proses menghasilkan token
final isLlamaGeneratingProvider = Provider<bool>((ref) {
  final statusAsync = ref.watch(llamaStatusProvider);
  return statusAsync.maybeWhen(
    data: (status) => status == ModelStatus.generating,
    orElse: () => false,
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// 6. LOAD PROGRESS VALUE (0.0 – 1.0)
// ─────────────────────────────────────────────────────────────────────────────

/// Nilai progres pemuatan model saat ini (0.0 jika tidak sedang memuat)
final llamaLoadProgressValueProvider = Provider<double>((ref) {
  final progressAsync = ref.watch(llamaLoadProgressProvider);
  return progressAsync.maybeWhen(
    data: (v) => v,
    orElse: () => 0.0,
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// 7. STATUS LABEL (Bahasa Indonesia)
// ─────────────────────────────────────────────────────────────────────────────

/// Label status model dalam Bahasa Indonesia untuk ditampilkan di UI
final llamaStatusLabelProvider = Provider<String>((ref) {
  final statusAsync = ref.watch(llamaStatusProvider);
  return statusAsync.maybeWhen(
    data: (status) {
      switch (status) {
        case ModelStatus.notLoaded:
          return 'Belum ada model';
        case ModelStatus.loading:
          return 'Memuat model...';
        case ModelStatus.loaded:
          return 'Siap';
        case ModelStatus.generating:
          return 'Menghasilkan...';
        case ModelStatus.error:
          return 'Error';
      }
    },
    orElse: () => 'Tidak diketahui',
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// 8. STATUS COLOR
// ─────────────────────────────────────────────────────────────────────────────

/// Warna indikator status model untuk ditampilkan di UI
final llamaStatusColorProvider = Provider<Color>((ref) {
  final statusAsync = ref.watch(llamaStatusProvider);
  return statusAsync.maybeWhen(
    data: (status) {
      switch (status) {
        case ModelStatus.loaded:
          return Colors.green;
        case ModelStatus.loading:
          return Colors.orange;
        case ModelStatus.generating:
          return Colors.blue;
        case ModelStatus.error:
          return Colors.red;
        default:
          return Colors.grey;
      }
    },
    orElse: () => Colors.grey,
  );
});
