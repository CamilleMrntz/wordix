import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/daily_word_tab.dart';
import '../widgets/wordix_logo.dart';
import 'settings_page.dart';
import 'word_history_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Utilisateur non connecté',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const WordixLogo(height: 28),
          actions: [
            IconButton(
              tooltip: 'Historique des mots du jour',
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const WordHistoryPage(),
                  ),
                );
              },
              icon: const Icon(Icons.emoji_events_outlined),
            ),
            IconButton(
              tooltip: 'Paramètres',
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsPage(),
                  ),
                );
              },
              icon: const Icon(Icons.settings),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(child: Text('🇬🇧  English')),
              Tab(child: Text('🇪🇸  Español')),
            ],
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: TabBarView(
                children: [
                  DailyWordTab(
                    langCode: 'en',
                    assetPath: 'assets/words_en.txt',
                    apiEntriesPath: 'en',
                    titleDaily: 'Word of the day 🇬🇧',
                    titleRandom: '🎲 Random word',
                    androidWidgetSlot: 'en',
                  ),
                  DailyWordTab(
                    langCode: 'es',
                    assetPath: 'assets/words_es.txt',
                    apiEntriesPath: 'es',
                    titleDaily: 'Palabra del día 🇪🇸',
                    titleRandom: '🎲 Palabra aleatoria',
                    androidWidgetSlot: 'es',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
