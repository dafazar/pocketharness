// lib/data/repositories/user_repository.dart
// Pocket Harness — User Repository (Fixed)
//
// PERUBAHAN dari versi sebelumnya:
//   ✅ _uid menggunakan null-safe check — tidak crash jika currentUser null
//   ✅ Semua method public punya guard: return early jika user belum login
//   ✅ getUser() tidak throw jika dokumen belum ada (user baru)
//   ✅ userStream menggunakan DocumentReference<Map> cast yang benar
//   ✅ updateSettings() menggunakan merge agar tidak overwrite field lain
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserRepository {
  final _db = FirebaseFirestore.instance;

  // ✅ FIX: null-safe — tidak force-unwrap currentUser
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>>? get _userDoc {
    final uid = _uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid)
        as DocumentReference<Map<String, dynamic>>;
  }

  // ── Inisialisasi akun baru setelah register / login pertama ──────────────
  Future<void> initNewUser({
    required String uid,
    required String email,
    required String displayName,
  }) async {
    await _db.collection('users').doc(uid).set({
      'uid':         uid,
      'email':       email,
      'displayName': displayName,
      'avatarUrl':   null,
      'createdAt':   FieldValue.serverTimestamp(),
      'lastActiveAt': FieldValue.serverTimestamp(),
      'settings': {
        'theme':               'original',
        'dailyGoal':           20,
        'notificationEnabled': true,
        'ttsSpeed':            1.0,
        'language':            'id',
      },
      'stats': {
        'totalXp':             0,
        'currentStreak':       0,
        'longestStreak':       0,
        'totalStudyMinutes':   0,
        'quizzesTaken':        0,
        'flashcardsReviewed':  0,
      },
      'membership': {
        'tier':          'free',  // 'free' | 'premium' | 'lifetime'
        'expiresAt':     null,
        'platform':      null,    // 'android' | 'ios'
        'purchaseToken': null,
      },
    }, SetOptions(merge: true)); // merge: true agar tidak overwrite jika sudah ada
  }

  // ── Ambil data user ───────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> getUser() async {
    final ref = _userDoc;
    if (ref == null) return null; // ✅ guard: user belum login
    final doc = await ref.get();
    if (!doc.exists) return null;
    return doc.data();
  }

  // ── Update last active ────────────────────────────────────────────────────
  Future<void> touchActivity() async {
    final ref = _userDoc;
    if (ref == null) return;
    await ref.update({'lastActiveAt': FieldValue.serverTimestamp()});
  }

  // ── Tambah XP ─────────────────────────────────────────────────────────────
  Future<void> addXp(int xp) async {
    final ref = _userDoc;
    if (ref == null) return;
    await ref.update({
      'stats.totalXp':  FieldValue.increment(xp),
      'lastActiveAt':   FieldValue.serverTimestamp(),
    });
  }

  // ── Increment quiz counter ────────────────────────────────────────────────
  Future<void> incrementQuizCount() async {
    final ref = _userDoc;
    if (ref == null) return;
    await ref.update({'stats.quizzesTaken': FieldValue.increment(1)});
  }

  // ── Update streak ─────────────────────────────────────────────────────────
  Future<void> updateStreak(int streak) async {
    final ref = _userDoc;
    if (ref == null) return;
    final data    = await getUser();
    final longest = (data?['stats']?['longestStreak'] ?? 0) as int;
    await ref.update({
      'stats.currentStreak': streak,
      'stats.longestStreak': streak > longest ? streak : longest,
    });
  }

  // ── Sync settings ke cloud ────────────────────────────────────────────────
  // ✅ FIX: gunakan update dengan dot-notation agar tidak overwrite field lain
  Future<void> updateSettings(Map<String, dynamic> settings) async {
    final ref = _userDoc;
    if (ref == null) return;
    final mapped = settings.map((k, v) => MapEntry('settings.$k', v));
    await ref.update(mapped);
  }

  // ── Update display name ───────────────────────────────────────────────────
  Future<void> updateDisplayName(String name) async {
    final ref = _userDoc;
    if (ref == null) return;
    await ref.update({'displayName': name});
  }

  // ── Update avatar URL ─────────────────────────────────────────────────────
  Future<void> updateAvatarUrl(String url) async {
    final ref = _userDoc;
    if (ref == null) return;
    await ref.update({'avatarUrl': url});
  }

  
  // ── Ambil progress level ──────────────────────────────────────────────────
  Future<Map<String, dynamic>?> getProgress(String levelId) async {
    final ref = _userDoc;
    if (ref == null) return null;
    final doc = await ref.collection('progress').doc(levelId).get();
    if (!doc.exists) return null;
    return doc.data();
  }

  // ── Flashcard cloud sync ──────────────────────────────────────────────────
  Future<void> saveFlashcard(String cardId, Map<String, dynamic> card) async {
    final ref = _userDoc;
    if (ref == null) return;
    await ref.collection('flashcards').doc(cardId).set(
      {...card, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<void> deleteFlashcard(String cardId) async {
    final ref = _userDoc;
    if (ref == null) return;
    await ref.collection('flashcards').doc(cardId).delete();
  }

  Future<List<Map<String, dynamic>>> getAllFlashcards() async {
    final ref = _userDoc;
    if (ref == null) return [];
    final query = await ref.collection('flashcards').get();
    return query.docs.map((d) => d.data()).toList();
  }

  // ── Notes cloud sync ──────────────────────────────────────────────────────
  Future<void> saveNote(String noteId, Map<String, dynamic> note) async {
    final ref = _userDoc;
    if (ref == null) return;
    await ref.collection('notes').doc(noteId).set(
      {...note, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<void> deleteNote(String noteId) async {
    final ref = _userDoc;
    if (ref == null) return;
    await ref.collection('notes').doc(noteId).delete();
  }

  // ── Update membership (fallback manual, biasanya via Cloud Function) ──────
  Future<void> updateMembership({
    required String tier,
    DateTime? expiresAt,
    String? platform,
  }) async {
    final ref = _userDoc;
    if (ref == null) return;
    await ref.update({
      'membership.tier':      tier,
      'membership.expiresAt': expiresAt != null
          ? Timestamp.fromDate(expiresAt)
          : null,
      if (platform != null) 'membership.platform': platform,
    });
  }

  // ── Cek membership tier ───────────────────────────────────────────────────
  Future<String> getMembershipTier() async {
    final data = await getUser();
    return (data?['membership']?['tier'] as String?) ?? 'free';
  }

  Future<bool> isPremium() async {
    final tier = await getMembershipTier();
    return tier == 'premium' || tier == 'lifetime';
  }

  // ── Stream live update user ───────────────────────────────────────────────
  // ✅ FIX: guard jika _userDoc null (user belum login)
  Stream<DocumentSnapshot<Map<String, dynamic>>> get userStream {
    final ref = _userDoc;
    if (ref == null) return const Stream.empty();
    return ref.snapshots();
  }

  // ── Stream membership tier ────────────────────────────────────────────────
  Stream<String> get membershipTierStream => userStream.map((snap) {
    final data = snap.data();
    return (data?['membership']?['tier'] as String?) ?? 'free';
  });
}

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(),
);

/// Provider cepat untuk cek premium dari Firestore
final firestoreIsPremiumProvider = FutureProvider<bool>((ref) async {
  return ref.watch(userRepositoryProvider).isPremium();
});

/// Stream membership tier — Premium gate dinonaktifkan, return 'free' (tidak dipakai untuk blokir)
final membershipTierProvider = StreamProvider<String>((ref) async* {
  yield 'free';
});
