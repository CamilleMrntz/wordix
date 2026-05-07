import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/lexicon_blocks.dart';

/// Same language markers as [DailyWordTab] titles (🇬🇧 / 🇪🇸).
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

/// Lists cached [daily_words](https://firebase.google.com/) entries from the user's
/// account creation date (UTC) through today. Requires Firestore read access on `daily_words`.
class WordHistoryPage extends StatefulWidget {
  const WordHistoryPage({super.key});

  @override
  State<WordHistoryPage> createState() => _WordHistoryPageState();
}

class _WordHistoryPageState extends State<WordHistoryPage> {
  late Future<List<_DailyWordHistoryEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadHistory();
  }

  static String _dayKeyUtc(DateTime d) {
    final u = d.toUtc();
    final mm = u.month.toString().padLeft(2, '0');
    final dd = u.day.toString().padLeft(2, '0');
    return '${u.year}-$mm-$dd';
  }

  static String _formatDateKey(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length != 3) return dateKey;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  Future<void> _reload() async {
    setState(() {
      _future = _loadHistory();
    });
    await _future;
  }

  Future<List<_DailyWordHistoryEntry>> _loadHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final created = user.metadata.creationTime ?? DateTime.now().toUtc().subtract(const Duration(days: 365));
    final minDateKey = _dayKeyUtc(created);

    final snapshot = await FirebaseFirestore.instance
        .collection('daily_words')
        .where('dateKey', isGreaterThanOrEqualTo: minDateKey)
        .orderBy('dateKey', descending: true)
        .limit(500)
        .get();

    final list = <_DailyWordHistoryEntry>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final lang = data['lang'] as String? ?? '';
      final dateKey = data['dateKey'] as String? ?? '';
      final word = data['word'] as String? ?? '';
      final definition = data['definition'] as String? ?? '';
      final partOfSpeech = data['partOfSpeech'] as String?;
      if (word.isEmpty || dateKey.isEmpty) continue;
      list.add(
        _DailyWordHistoryEntry(
          dateKey: dateKey,
          lang: lang,
          word: word,
          definition: definition,
          partOfSpeech: partOfSpeech,
        ),
      );
    }

    list.sort((a, b) {
      final byDate = b.dateKey.compareTo(a.dateKey);
      if (byDate != 0) return byDate;
      return a.lang.compareTo(b.lang);
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique des mots'),
      ),
      body: FutureBuilder<List<_DailyWordHistoryEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Impossible de charger l’historique.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Aucun mot du jour enregistré pour l’instant.\n'
                  'Les entrées apparaissent au fil des jours lorsque l’application met en cache le mot du jour.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                16 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final e = items[i];
                final theme = Theme.of(context);
                final scheme = theme.colorScheme;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: scheme.primaryContainer.withValues(alpha: 0.65),
                                child: Text(
                                  _langFlagEmoji(e.lang),
                                  style: const TextStyle(fontSize: 22, height: 1.05),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            e.word,
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.2,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: scheme.secondaryContainer.withValues(alpha: 0.55),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            _formatDateKey(e.dateKey),
                                            style: theme.textTheme.labelMedium?.copyWith(
                                              color: scheme.onSecondaryContainer,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (e.partOfSpeech != null && e.partOfSpeech!.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      LexiconPosBadge(text: e.partOfSpeech!),
                                    ],
                                    const SizedBox(height: 10),
                                    LexiconDefinitionPanel(
                                      child: Text(
                                        e.definition,
                                        maxLines: 5,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          height: 1.45,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _DailyWordHistoryEntry {
  const _DailyWordHistoryEntry({
    required this.dateKey,
    required this.lang,
    required this.word,
    required this.definition,
    this.partOfSpeech,
  });

  final String dateKey;
  final String lang;
  final String word;
  final String definition;
  final String? partOfSpeech;
}
