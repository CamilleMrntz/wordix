import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'word_history_page.dart';

/// Same language markers as [DailyWordTab] titles.
String _langFlagEmoji(String lang) {
  switch (lang) {
    case 'en':
      return '🇬🇧';
    case 'es':
      return '🇪🇸';
    default:
      return '🌐';
  }
}

String _formatSeenAt(Timestamp? t) {
  if (t == null) return '';
  final d = t.toDate().toLocal();
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd/$mm ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class AchievementsPage extends StatelessWidget {
  const AchievementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Succès')),
        body: const Center(child: Text('Connecte-toi pour voir tes stats.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Succès'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Erreur : ${snap.error}'));
          }
          final data = snap.data?.data();
          final streak = (data?['statsOpenStreak'] as num?)?.toInt() ?? 0;
          final lastOpen = data?['statsLastOpenDayUtc'] as String?;
          final recent = data?['recentWords'];
          final recentList = <Map<String, dynamic>>[];
          if (recent is List) {
            for (final e in recent) {
              if (e is Map<String, dynamic>) {
                recentList.add(e);
              } else if (e is Map) {
                recentList.add(Map<String, dynamic>.from(e.map((k, v) => MapEntry(k.toString(), v))));
              }
            }
          }

          return ListView(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + MediaQuery.viewPaddingOf(context).bottom),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.local_fire_department_outlined, color: scheme.primary, size: 28),
                          const SizedBox(width: 10),
                          Text(
                            'Série',
                            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '$streak',
                        style: textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.2,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Ouvertures d’affilée : une fois par jour calendaire (UTC).',
                        style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
                      ),
                      if (lastOpen != null && lastOpen.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Dernière ouverture comptée : $lastOpen (UTC)',
                          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.visibility_outlined, color: scheme.secondary, size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Derniers mots consultés',
                              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Mots affichés dans l’app (mot du jour ou aléatoire), les plus récents en premier.',
                        style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
                      ),
                      const SizedBox(height: 14),
                      if (recentList.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Aucun mot enregistré pour l’instant. Ouvre un onglet anglais ou espagnol pour remplir cette liste.',
                            style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        )
                      else
                        ...recentList.map((m) {
                          final w = m['word'] as String? ?? '';
                          final lang = m['lang'] as String? ?? '';
                          final at = m['at'];
                          final ts = at is Timestamp ? at : null;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Row(
                                  children: [
                                    Text(_langFlagEmoji(lang), style: const TextStyle(fontSize: 22, height: 1)),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            w,
                                            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                          ),
                                          if (ts != null)
                                            Text(
                                              _formatSeenAt(ts),
                                              style: textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(builder: (_) => const WordHistoryPage()),
                  );
                },
                icon: const Icon(Icons.history),
                label: const Text('Historique des mots du jour (cache)'),
              ),
            ],
          );
        },
      ),
    );
  }
}
