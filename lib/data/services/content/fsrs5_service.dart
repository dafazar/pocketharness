import 'dart:math' as math;

/// FSRS-5 (Free Spaced Repetition Scheduler v5)
/// Implementasi algoritma SRS terbaru 2024
/// Jauh lebih akurat dari SM-2 dalam memprediksi kapan user akan lupa.
///
/// Paper: https://github.com/open-spaced-repetition/fsrs4anki
class Fsrs5 {
  Fsrs5._();
  static final Fsrs5 instance = Fsrs5._();

  // ── FSRS-5 Parameters (default optimized) ──
  static const List<double> _w = [
    0.4072, 1.1829, 3.1262, 15.4722,  // w0–w3
    7.2102, 0.5316, 1.0651, 0.0589,   // w4–w7
    1.5330, 0.1544, 1.0070, 1.9395,   // w8–w11
    0.1100, 0.2900, 2.2700, 0.1100,   // w12–w15
    2.9898, 0.5100, 0.4320,            // w16–w18
  ];

  static const double _requestRetention = 0.9; // Target retensi 90%
  static const int _maxInterval = 36500; // ~100 tahun maksimum

  // ── Rating ────────────────────────────────────
  // 1 = Again (lupa total)
  // 2 = Hard (susah)
  // 3 = Good (ingat)
  // 4 = Easy (mudah)

  // ── Card States ───────────────────────────────
  // 0 = New
  // 1 = Learning
  // 2 = Review
  // 3 = Relearning

  /// Proses review card, return SrsResult dengan data terbaru
  SrsResult review(SrsCard card, int rating, DateTime reviewTime) {
    assert(rating >= 1 && rating <= 4);

    if (card.state == 0) {
      return _reviewNew(card, rating, reviewTime);
    } else if (card.state == 1 || card.state == 3) {
      return _reviewLearning(card, rating, reviewTime);
    } else {
      return _reviewReview(card, rating, reviewTime);
    }
  }

  SrsResult _reviewNew(SrsCard card, int rating, DateTime reviewTime) {
    double stability;
    double difficulty;
    int state;
    int scheduledDays = 0;

    // Initial stability berdasarkan rating
    stability = _w[rating - 1];
    difficulty = _initDifficulty(rating);
    state = 1; // Learning

    // Short interval untuk learning
    switch (rating) {
      case 1: scheduledDays = 0; break; // 1 menit
      case 2: scheduledDays = 0; break; // 5 menit
      case 3: scheduledDays = 1; break; // 10 menit
      case 4: scheduledDays = 1; break; // 4 hari
    }

    final dueDate = reviewTime.add(Duration(
      minutes: rating <= 2 ? (rating == 1 ? 1 : 5) : (rating == 3 ? 10 : 0),
      days: scheduledDays,
    ));

    return SrsResult(
      stability: stability,
      difficulty: difficulty,
      elapsedDays: 0,
      scheduledDays: scheduledDays,
      reps: card.reps + 1,
      lapses: card.lapses,
      state: state,
      dueDate: dueDate,
      lastReview: reviewTime,
    );
  }

  SrsResult _reviewLearning(SrsCard card, int rating, DateTime reviewTime) {
    if (rating == 1) {
      // Again - tetap learning
      return SrsResult(
        stability: card.stability,
        difficulty: _nextDifficulty(card.difficulty, rating),
        elapsedDays: card.elapsedDays,
        scheduledDays: 0,
        reps: card.reps + 1,
        lapses: card.state == 3 ? card.lapses + 1 : card.lapses,
        state: card.state == 3 ? 3 : 1,
        dueDate: reviewTime.add(const Duration(minutes: 1)),
        lastReview: reviewTime,
      );
    } else if (rating == 4) {
      // Easy - langsung ke review
      final interval = _nextInterval(card.stability, _easyBonus(card.stability));
      return SrsResult(
        stability: _shortTermStabilityAfterRating(card.stability, rating),
        difficulty: _nextDifficulty(card.difficulty, rating),
        elapsedDays: 0,
        scheduledDays: interval,
        reps: card.reps + 1,
        lapses: card.lapses,
        state: 2, // Review
        dueDate: reviewTime.add(Duration(days: interval)),
        lastReview: reviewTime,
      );
    } else {
      // Good - masuk review
      final nextStab = _shortTermStabilityAfterRating(card.stability, rating);
      final interval = _nextInterval(nextStab, 1.0);
      return SrsResult(
        stability: nextStab,
        difficulty: _nextDifficulty(card.difficulty, rating),
        elapsedDays: 0,
        scheduledDays: interval,
        reps: card.reps + 1,
        lapses: card.lapses,
        state: 2,
        dueDate: reviewTime.add(Duration(days: interval)),
        lastReview: reviewTime,
      );
    }
  }

  SrsResult _reviewReview(SrsCard card, int rating, DateTime reviewTime) {
    final elapsed = reviewTime.difference(card.lastReview ?? reviewTime).inDays;
    final retrievability = _forgettingCurve(elapsed.toDouble(), card.stability);
    final nextDiff = _nextDifficulty(card.difficulty, rating);

    if (rating == 1) {
      // Lupa — relearning
      final nextStab = _stabilityAfterForgetting(card.difficulty, card.stability, retrievability);
      return SrsResult(
        stability: nextStab,
        difficulty: nextDiff,
        elapsedDays: elapsed,
        scheduledDays: 0,
        reps: card.reps + 1,
        lapses: card.lapses + 1,
        state: 3, // Relearning
        dueDate: reviewTime.add(const Duration(minutes: 5)),
        lastReview: reviewTime,
      );
    } else {
      // Ingat
      final nextStab = _stabilityAfterRecall(
        card.difficulty, card.stability, retrievability, rating,
      );
      final interval = _nextInterval(nextStab, rating == 4 ? _easyBonus(nextStab) : 1.0);
      return SrsResult(
        stability: nextStab,
        difficulty: nextDiff,
        elapsedDays: elapsed,
        scheduledDays: interval,
        reps: card.reps + 1,
        lapses: card.lapses,
        state: 2,
        dueDate: reviewTime.add(Duration(days: interval)),
        lastReview: reviewTime,
      );
    }
  }

  // ── FSRS Math Functions ────────────────────────

  double _forgettingCurve(double t, double s) {
    return math.pow(1 + _w[17] * t / s, -_w[18]).toDouble();
  }

  double _initDifficulty(int rating) {
    return _clamp(_w[4] - math.exp(_w[5] * (rating - 1)) + 1, 1, 10);
  }

  double _nextDifficulty(double d, int rating) {
    final nextD = d - _w[6] * (rating - 3);
    return _clamp(_meanReversion(_w[4], nextD), 1, 10);
  }

  double _meanReversion(double init, double current) {
    return _w[7] * init + (1 - _w[7]) * current;
  }

  double _stabilityAfterRecall(double d, double s, double r, int rating) {
    final hardPenalty = rating == 2 ? _w[15] : 1.0;
    final easyBonus = rating == 4 ? _w[16] : 1.0;
    return s * (
      math.exp(_w[8]) *
      (11 - d) *
      math.pow(s, -_w[9]) *
      (math.exp((1 - r) * _w[10]) - 1) *
      hardPenalty *
      easyBonus
      + 1
    );
  }

  double _stabilityAfterForgetting(double d, double s, double r) {
    return _w[11] *
      math.pow(d, -_w[12]) *
      (math.pow(s + 1, _w[13]) - 1) *
      math.exp((1 - r) * _w[14]);
  }

  double _shortTermStabilityAfterRating(double s, int rating) {
    return s * math.exp(_w[17] * (rating - 3 + _w[18]));
  }

  double _easyBonus(double s) => _w[16];

  int _nextInterval(double stability, double modifier) {
    final interval = (stability / _requestRetention * modifier).round();
    return _clamp(interval, 1, _maxInterval).toInt();
  }

  T _clamp<T extends num>(T value, T min, T max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  /// Hitung tanggal retrievability sekarang (berapa % kemungkinan ingat)
  double getRetrievability(SrsCard card) {
    if (card.state == 0) return 0.0;
    final elapsed = DateTime.now().difference(card.lastReview ?? DateTime.now()).inDays;
    return _forgettingCurve(elapsed.toDouble(), card.stability);
  }

  /// Preview interval untuk semua rating
  Map<int, int> previewIntervals(SrsCard card) {
    final now = DateTime.now();
    final result = <int, int>{};
    for (int r = 1; r <= 4; r++) {
      final res = review(card, r, now);
      result[r] = res.scheduledDays;
    }
    return result;
  }
}

// ── Data Classes ──────────────────────────────

class SrsCard {
  final int id;
  final String itemType;
  final int itemId;
  final double stability;
  final double difficulty;
  final int elapsedDays;
  final int scheduledDays; // ← FIX: hapus = 0
  final int reps;
  final int lapses;
  final int state; // 0=New,1=Learning,2=Review,3=Relearning
  final DateTime dueDate;
  final DateTime? lastReview;

  const SrsCard({
    required this.id,
    required this.itemType,
    required this.itemId,
    this.stability = 1.0,
    this.difficulty = 5.0,
    this.elapsedDays = 0,
    this.scheduledDays = 1,
    this.reps = 0,
    this.lapses = 0,
    this.state = 0,
    required this.dueDate,
    this.lastReview,
  });

  factory SrsCard.fromMap(Map<String, dynamic> m) {
    return SrsCard(
      id: m['id'] as int,
      itemType: m['item_type'] as String,
      itemId: m['item_id'] as int,
      stability: (m['stability'] as num?)?.toDouble() ?? 1.0,
      difficulty: (m['difficulty'] as num?)?.toDouble() ?? 5.0,
      elapsedDays: m['elapsed_days'] as int? ?? 0,
      scheduledDays: m['scheduled_days'] as int? ?? 1,
      reps: m['reps'] as int? ?? 0,
      lapses: m['lapses'] as int? ?? 0,
      state: m['state'] as int? ?? 0,
      dueDate: DateTime.fromMillisecondsSinceEpoch(m['due_date'] as int),
      lastReview: m['last_review'] != null
          ? DateTime.fromMillisecondsSinceEpoch(m['last_review'] as int)
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'stability': stability,
    'difficulty': difficulty,
    'elapsed_days': elapsedDays,
    'scheduled_days': scheduledDays,
    'reps': reps,
    'lapses': lapses,
    'state': state,
    'due_date': dueDate.millisecondsSinceEpoch,
    'last_review': lastReview?.millisecondsSinceEpoch,
  };

  String get stateLabel {
    switch (state) {
      case 0: return 'Baru';
      case 1: return 'Belajar';
      case 2: return 'Review';
      case 3: return 'Mengulang';
      default: return '?';
    }
  }
}

class SrsResult {
  final double stability;
  final double difficulty;
  final int elapsedDays;
  final int scheduledDays; // ← FIX: hapus = 0
  final int reps;
  final int lapses;
  final int state;
  final DateTime dueDate;
  final DateTime? lastReview;

  const SrsResult({
    required this.stability,
    required this.difficulty,
    required this.elapsedDays,
    required this.scheduledDays,
    required this.reps,
    required this.lapses,
    required this.state,
    required this.dueDate,
    required this.lastReview,
  });

  Map<String, dynamic> toMap() => {
    'stability': stability,
    'difficulty': difficulty,
    'elapsed_days': elapsedDays,
    'scheduled_days': scheduledDays,
    'reps': reps,
    'lapses': lapses,
    'state': state,
    'due_date': dueDate.millisecondsSinceEpoch,
    'last_review': lastReview?.millisecondsSinceEpoch,
  };
}
