import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Lightweight stats on `users/{uid}`: open streak (UTC calendar days) and
/// [recentWords] (last 15 views).
abstract final class UserStatsService {
  static const int _recentCap = 15;

  static String _utcDayKey(DateTime utc) {
    final u = utc.toUtc();
    final m = u.month.toString().padLeft(2, '0');
    final d = u.day.toString().padLeft(2, '0');
    return '${u.year}-$m-$d';
  }

  /// Call when the user opens the app (e.g. home resumed). Idempotent per UTC day.
  static Future<void> recordAppOpen() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data() ?? {};
        final today = _utcDayKey(DateTime.now());
        final last = data['statsLastOpenDayUtc'] as String?;
        final streak = (data['statsOpenStreak'] as num?)?.toInt() ?? 0;
        if (last == today) {
          return;
        }
        final yesterday = _utcDayKey(DateTime.now().toUtc().subtract(const Duration(days: 1)));
        final nextStreak = last == null || last.isEmpty
            ? 1
            : (last == yesterday ? streak + 1 : 1);
        tx.set(
          ref,
          {
            'statsLastOpenDayUtc': today,
            'statsOpenStreak': nextStreak,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
    } on FirebaseException {
      // ignore
    }
  }

  /// Records that the user viewed a word (daily or random). Newest first, capped.
  static Future<void> recordWordViewed(String langCode, String word) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final trimmed = word.trim();
    if (trimmed.isEmpty) return;
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final raw = snap.data()?['recentWords'];
        final list = <Map<String, dynamic>>[];
        if (raw is List) {
          for (final e in raw) {
            if (e is Map<String, dynamic>) {
              list.add(Map<String, dynamic>.from(e));
            } else if (e is Map) {
              list.add(Map<String, dynamic>.from(e.map((k, v) => MapEntry(k.toString(), v))));
            }
          }
        }
        list.removeWhere((m) => m['word'] == trimmed && m['lang'] == langCode);
        list.insert(0, {
          'word': trimmed,
          'lang': langCode,
          'at': Timestamp.now(),
        });
        while (list.length > _recentCap) {
          list.removeLast();
        }
        tx.set(
          ref,
          {
            'recentWords': list,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
    } on FirebaseException {
      // ignore
    }
  }
}
