import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/daily_word_tab.dart';
import 'settings_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Utilisateur non connecté')));
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Word of the Day'),
          actions: [
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
              Tab(text: 'English'),
              Tab(text: 'Español'),
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
