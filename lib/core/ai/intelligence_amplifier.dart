// lib/core/ai/intelligence_amplifier.dart
// PocketHarness — Intelligence Amplifier Architecture v1.0 [NEW FILE]
//
// TUJUAN:
//   Meningkatkan kualitas respons semua mode AI (offline llama.cpp, bulk API,
//   online API) agar mendekati kemampuan Claude 4.6 opus melalui:
//
//   1. PROMPT ENHANCEMENT   — Chain-of-Thought injection otomatis
//   2. CONTEXT COMPRESSION  — Cerdas meringkas context window
//   3. RESPONSE REFINEMENT  — Post-processing quality check
//   4. REASONING SCAFFOLD   — Structural thinking template per task type
//   5. ADAPTIVE PERSONA     — Mode-aware personality tuning
//   6. QUALITY GATE         — Deteksi & recovery untuk respons buruk
//   7. TEMPERATURE TUNING   — Optimal temp per task type
// =============================================================================

import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────────────────────────────────────

/// Mode operasi AI yang sedang aktif
enum AiMode { offline, bulk, online }

/// Jenis tugas yang dideteksi dari pesan user
enum TaskType {
  coding,
  analysis,
  creative,
  factual,
  fileEdit,
  conversation,
  reasoning,
  math,
  unknown,
}

// ─────────────────────────────────────────────────────────────────────────────
// INTELLIGENCE AMPLIFIER — Singleton
// ─────────────────────────────────────────────────────────────────────────────

/// Singleton yang memperkuat kecerdasan semua mode AI di PocketHarness.
/// Inject dengan [IntelligenceAmplifier.instance].
class IntelligenceAmplifier {
  IntelligenceAmplifier._();
  static final IntelligenceAmplifier instance = IntelligenceAmplifier._();

  // ── Config (dapat diubah runtime) ──────────────────────────────────────────
  bool enableCoT           = true;   // Chain-of-Thought injection
  bool enableContextCompr  = true;   // Context compression
  bool enableQualityGate   = true;   // Post-process quality check
  bool enableReasonScaff   = true;   // Reasoning scaffold
  int  maxContextTokens    = 2048;   // Token budget untuk context

  // ── 1. TASK DETECTION ──────────────────────────────────────────────────────

  /// Deteksi jenis task dari pesan user untuk memilih strategi enhancement.
  TaskType detectTask(String userMessage) {
    final msg = userMessage.toLowerCase();

    if (_matchesAny(msg, [
      'buat', 'tulis', 'kode', 'code', 'fungsi', 'function', 'class',
      'bug', 'error', 'fix', 'debug', 'implement', 'refactor',
      '.dart', '.py', '.js', '.kt', '.java', 'flutter', 'python',
      'widget', 'snippet', 'script',
    ])) return TaskType.coding;

    if (_matchesAny(msg, [
      'edit', 'ubah', 'modifikasi', 'ganti', 'replace', 'update',
      'hapus baris', 'tambah', 'insert', 'file', 'dokumen', 'perbaiki',
    ])) return TaskType.fileEdit;

    if (_matchesAny(msg, [
      'hitung', 'kalkulasi', 'rumus', 'formula', 'matematik',
      'persamaan', 'integral', 'derivatif', 'statistik',
      'calculate', 'compute', 'solve',
    ])) return TaskType.math;

    if (_matchesAny(msg, [
      'analisa', 'analisis', 'jelaskan', 'bandingkan', 'evaluate',
      'kenapa', 'mengapa', 'bagaimana', 'explain', 'compare',
      'pros cons', 'kelebihan', 'kekurangan', 'review',
    ])) return TaskType.analysis;

    if (_matchesAny(msg, [
      'cerita', 'puisi', 'kreatif', 'fiksi', 'story', 'creative',
      'essay', 'artikel', 'blog', 'konten', 'narasi',
    ])) return TaskType.creative;

    if (_matchesAny(msg, [
      'apa itu', 'siapa', 'kapan', 'di mana', 'what is', 'who is',
      'when', 'where', 'berapa', 'how many', 'definisi',
    ])) return TaskType.factual;

    return TaskType.conversation;
  }

  bool _matchesAny(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));

  // ── 2. SYSTEM PROMPT ENHANCEMENT ───────────────────────────────────────────

  /// Inject intelligence-boosting prefix ke system prompt berdasarkan mode & task.
  String enhanceSystemPrompt(
    String baseSystemPrompt,
    AiMode mode,
    TaskType task,
  ) {
    final prefix = _buildIntelligencePrefix(mode, task);
    final suffix = _buildOutputRules(task);
    return '$prefix\n\n$baseSystemPrompt\n\n$suffix';
  }

  String _buildIntelligencePrefix(AiMode mode, TaskType task) {
    final modeLabel = switch (mode) {
      AiMode.offline => 'OFFLINE ON-DEVICE (llama.cpp)',
      AiMode.bulk    => 'BULK API',
      AiMode.online  => 'ONLINE CLOUD AI',
    };

    final cot = enableCoT ? _cotInstructions(task) : '';

    return '''
## INTELLIGENCE AMPLIFIER — $modeLabel
### Operational Mode: Claude-Grade Reasoning Protocol

Kamu adalah PocketHarness dengan kemampuan penalaran tingkat tinggi setara model AI terdepan.
Terlepas dari model yang mendasarimu ($modeLabel), kamu WAJIB menggunakan strategi
penalaran berikut untuk menghasilkan output berkualitas maksimal:

$cot

### Core Intelligence Rules:
1. **THINK BEFORE ANSWER** — Untuk setiap pertanyaan kompleks, evaluasi dulu
   sebelum memberikan jawaban final. Pertimbangkan edge cases dan alternatif.
2. **BE PRECISE** — Gunakan terminologi yang tepat. Hindari vagueness.
3. **STRUCTURED OUTPUT** — Jawaban terstruktur > wall of text.
4. **ACKNOWLEDGE UNCERTAINTY** — Jika tidak yakin, katakan dengan jelas.
5. **COMPLETE SOLUTIONS** — Jangan potong kode atau jawaban di tengah.
''';
  }

  String _cotInstructions(TaskType task) => switch (task) {
    TaskType.coding => '''
### Chain-of-Thought untuk Coding:
Sebelum menulis kode:
  → Pahami requirement sepenuhnya
  → Identifikasi edge cases
  → Pilih pattern/approach terbaik
  → Tulis kode lengkap tanpa stub
  → Verifikasi logic secara mental
''',
    TaskType.analysis => '''
### Chain-of-Thought untuk Analisis:
  → Identifikasi aspek kunci yang perlu dianalisis
  → Kumpulkan fakta/data yang relevan
  → Evaluasi dari berbagai perspektif
  → Sintesis kesimpulan yang berimbang
  → Berikan rekomendasi konkret
''',
    TaskType.math => '''
### Chain-of-Thought untuk Matematika:
  → Identifikasi variabel dan yang ditanyakan
  → Pilih metode/rumus yang tepat
  → Kerjakan langkah demi langkah
  → Verifikasi hasil dengan substitusi
  → Jelaskan setiap langkah
''',
    TaskType.fileEdit => '''
### Chain-of-Thought untuk File Edit:
  → Baca dan pahami seluruh konten file
  → Identifikasi perubahan spesifik yang diminta
  → Periksa dampak perubahan ke bagian lain
  → Terapkan perubahan secara presisi
  → Output SELURUH file yang sudah diedit (bukan hanya diff)
''',
    _ => '''
### Chain-of-Thought:
  → Pahami inti pertanyaan
  → Pertimbangkan jawaban terbaik
  → Susun respons yang jelas dan berguna
''',
  };

  String _buildOutputRules(TaskType task) {
    if (task == TaskType.coding || task == TaskType.fileEdit) {
      return '''
### Output Rules (WAJIB):
- JANGAN potong kode dengan "// ... rest of code" atau "// tambahkan sisanya"
- SELALU tampilkan kode lengkap dan dapat langsung digunakan
- Gunakan code block dengan language tag yang benar
- Setelah kode, berikan penjelasan singkat perubahan yang dilakukan
''';
    }
    return '''
### Output Rules:
- Jawaban padat dan informatif
- Gunakan Markdown untuk formatting
- Maksimal informatif dengan kata minimal
''';
  }

  // ── 3. USER MESSAGE ENHANCEMENT ────────────────────────────────────────────

  /// Enhance user message untuk meningkatkan kualitas respons dari model kecil.
  String enhanceUserMessage(
    String userMessage,
    AiMode mode,
    TaskType task, {
    String? filename,
    bool hasCode = false,
  }) {
    // Online mode: tidak perlu enhancement agresif — model sudah capable
    if (mode == AiMode.online) return userMessage;

    final enhancements = <String>[];

    if (mode == AiMode.offline) {
      enhancements.add(_offlineGuidance(task, filename));
    }

    if (mode == AiMode.bulk) {
      enhancements.add(_bulkGuidance(task));
    }

    if (enhancements.isEmpty) return userMessage;

    return '$userMessage\n\n[INSTRUCTION: ${enhancements.join(" ")}]';
  }

  String _offlineGuidance(TaskType task, String? filename) {
    if (task == TaskType.coding || task == TaskType.fileEdit) {
      final fileHint = filename != null ? 'untuk file $filename' : '';
      return 'Berikan KODE LENGKAP $fileHint tanpa dipotong. '
          'Pastikan sintaks benar dan semua import ada.';
    }
    if (task == TaskType.analysis) {
      return 'Berikan analisis terstruktur dengan poin-poin jelas.';
    }
    return 'Jawab dengan lengkap dan terstruktur.';
  }

  String _bulkGuidance(TaskType task) {
    if (task == TaskType.coding) {
      return 'Output HARUS berupa kode lengkap yang dapat langsung dijalankan.';
    }
    return 'Jawaban harus komprehensif dan terstruktur.';
  }

  // ── 4. CONTEXT COMPRESSION ─────────────────────────────────────────────────

  /// Kompres history chat untuk hemat token, pertahankan info penting.
  List<Map<String, String>> compressContext(
    List<Map<String, String>> history, {
    int targetTokens = 1500,
  }) {
    if (!enableContextCompr) return history;
    if (history.isEmpty) return history;

    // Estimasi token: ~4 chars per token
    final totalChars =
        history.fold(0, (sum, msg) => sum + (msg['content']?.length ?? 0));
    final estimatedTokens = totalChars ~/ 4;

    if (estimatedTokens <= targetTokens) return history;

    // Strategy: keep first message + summary marker + last 6 messages
    if (history.length <= 4) return history;

    final compressed = <Map<String, String>>[];

    // Always keep first message (sets initial context)
    compressed.add(history.first);

    // Add summary placeholder
    compressed.add({
      'role': 'system',
      'content': '[Context: ${history.length - 4} pesan sebelumnya '
          'telah diringkas untuk hemat memori. '
          'Fokus pada ${history.length > 6 ? 6 : history.length - 1} pesan terbaru.]',
    });

    // Keep last 6 messages (most recent context)
    final recent = history.length > 6
        ? history.sublist(history.length - 6)
        : history.sublist(1);
    compressed.addAll(recent);

    debugPrint('[IntelligenceAmplifier] Context compressed: '
        '${history.length} → ${compressed.length} messages');

    return compressed;
  }

  // ── 5. RESPONSE QUALITY GATE ───────────────────────────────────────────────

  /// Deteksi respons berkualitas rendah dari model kecil/offline.
  QualityIssue? detectQualityIssue(String response, TaskType task) {
    if (!enableQualityGate) return null;
    if (response.trim().length < 10) return QualityIssue.tooShort;

    // Deteksi stub/TODO patterns
    const stubPatterns = [
      '// TODO', '// FIXME', '// ...', 'pass  #',
      '/* TODO */', 'NotImplementedError', 'raise NotImplemented',
      '// implement later', '// add code here', '# TODO',
      '... (rest of', '// rest of code',
    ];
    for (final pattern in stubPatterns) {
      if (response.contains(pattern)) return QualityIssue.containsStub;
    }

    // Untuk coding task: cek apakah code block terpotong (tidak tertutup)
    if (task == TaskType.coding || task == TaskType.fileEdit) {
      final codeBlockCount = '```'.allMatches(response).length;
      if (codeBlockCount % 2 != 0) return QualityIssue.truncatedCode;
    }

    return null;
  }

  /// Generate recovery prompt saat kualitas buruk terdeteksi.
  String buildRecoveryPrompt(QualityIssue issue, String originalPrompt) {
    return switch (issue) {
      QualityIssue.tooShort =>
        '$originalPrompt\n\nPENTING: Berikan jawaban yang lebih lengkap dan detail.',
      QualityIssue.containsStub =>
        '$originalPrompt\n\nPENTING: JANGAN gunakan TODO/placeholder. '
            'Berikan implementasi LENGKAP dan nyata.',
      QualityIssue.truncatedCode =>
        '$originalPrompt\n\nPENTING: Kode terpotong. Lanjutkan dari titik terakhir '
            'dan pastikan semua code block tertutup dengan ```.',
    };
  }

  // ── 6. REASONING SCAFFOLD ──────────────────────────────────────────────────

  /// Inject scaffolding untuk model kecil agar berpikir lebih terstruktur.
  String buildReasoningScaffold(String userMessage, TaskType task) {
    if (!enableReasonScaff) return userMessage;

    // Hanya untuk task kompleks — conversation/factual tidak perlu scaffold
    if (task == TaskType.conversation || task == TaskType.factual) {
      return userMessage;
    }

    return switch (task) {
      TaskType.coding || TaskType.fileEdit => '''$userMessage

Jawab dengan format:
1. **Pemahaman:** [apa yang diminta]
2. **Pendekatan:** [strategi yang dipilih]
3. **Implementasi:** [kode lengkap]
4. **Penjelasan:** [ringkasan perubahan]''',

      TaskType.analysis => '''$userMessage

Jawab dengan format:
1. **Ringkasan:** [poin utama]
2. **Analisis:** [pembahasan mendalam]
3. **Kesimpulan:** [takeaway]''',

      TaskType.math => '''$userMessage

Tunjukkan langkah-langkah penyelesaian secara berurutan dengan penjelasan tiap langkah.''',

      _ => userMessage,
    };
  }

  // ── 7. TEMPERATURE RECOMMENDATION ─────────────────────────────────────────

  /// Rekomendasikan temperature optimal berdasarkan jenis task.
  double recommendTemperature(TaskType task) => switch (task) {
    TaskType.coding      => 0.2,  // Deterministic for code
    TaskType.fileEdit    => 0.15, // Very precise for file editing
    TaskType.math        => 0.1,  // Most deterministic for math
    TaskType.factual     => 0.3,  // Low temp for facts
    TaskType.analysis    => 0.5,  // Balanced for analysis
    TaskType.reasoning   => 0.4,  // Structured reasoning
    TaskType.creative    => 0.8,  // Higher creativity
    TaskType.conversation => 0.7, // Natural conversation
    TaskType.unknown     => 0.5,  // Default balanced
  };

  // ── 8. FULL ENHANCEMENT PIPELINE ──────────────────────────────────────────

  /// Pipeline lengkap: detect → enhance system → enhance user → compress → recommend temp.
  /// Gunakan ini sebagai entry point utama sebelum memanggil AI backend.
  EnhancedRequest buildEnhancedRequest({
    required String systemPrompt,
    required String userMessage,
    required List<Map<String, String>> history,
    required AiMode mode,
    String? filename,
  }) {
    final task = detectTask(userMessage);

    final enhancedSystem = enhanceSystemPrompt(systemPrompt, mode, task);

    final enhancedUser = enableReasonScaff && mode == AiMode.offline
        ? buildReasoningScaffold(
            enhanceUserMessage(userMessage, mode, task, filename: filename),
            task,
          )
        : enhanceUserMessage(userMessage, mode, task, filename: filename);

    final compressedHistory = compressContext(history);

    final temperature = recommendTemperature(task);

    debugPrint('[IntelligenceAmplifier] Task: $task | Mode: $mode | '
        'Temp: $temperature | History: ${history.length}→${compressedHistory.length}');

    return EnhancedRequest(
      systemPrompt: enhancedSystem,
      userMessage: enhancedUser,
      history: compressedHistory,
      temperature: temperature,
      task: task,
      mode: mode,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VALUE OBJECTS
// ─────────────────────────────────────────────────────────────────────────────

/// Hasil dari [IntelligenceAmplifier.buildEnhancedRequest].
class EnhancedRequest {
  final String systemPrompt;
  final String userMessage;
  final List<Map<String, String>> history;
  final double temperature;
  final TaskType task;
  final AiMode mode;

  const EnhancedRequest({
    required this.systemPrompt,
    required this.userMessage,
    required this.history,
    required this.temperature,
    required this.task,
    required this.mode,
  });
}

/// Jenis masalah kualitas yang terdeteksi pada respons AI.
enum QualityIssue { tooShort, containsStub, truncatedCode }
