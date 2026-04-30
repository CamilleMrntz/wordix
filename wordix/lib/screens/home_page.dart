import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/daily_word_tab.dart';

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
              onPressed: () => FirebaseAuth.instance.signOut(),
              icon: const Icon(Icons.logout),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Anglais'),
              Tab(text: 'Espagnol'),
            ],
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text('Connecté: ${user.email ?? "inconnu"}'),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  DailyWordTab(
                    langCode: 'en',
                    assetPath: 'assets/words_en.txt',
                    apiEntriesPath: 'en',
                    titleDaily: 'Mot du jour (anglais)',
                    titleRandom: 'Aléatoire (anglais)',
                    androidWidgetSlot: 'en',
                  ),
                  DailyWordTab(
                    langCode: 'es',
                    assetPath: 'assets/words_es.txt',
                    apiEntriesPath: 'es',
                    titleDaily: 'Mot du jour (espagnol)',
                    titleRandom: 'Aléatoire (espagnol)',
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
