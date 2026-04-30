import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const MethodChannel _widgetChannel = MethodChannel('wordix/widget');

  final Random _random = Random();
  List<String> _words = [];

  bool isLoadingDaily = true;
  bool isLoadingRandom = false;
  String? dailyWord;
  String? dailyDefinition;
  String? dailyPhonetic;
  String? dailyPartOfSpeech;
  String? randomWord;
  String? randomDefinition;
  String? randomPhonetic;
  String? randomPartOfSpeech;
  String? error;

  @override
  void initState() {
    super.initState();
    _initializeWordsAndDaily();
  }

  Future<void> _initializeWordsAndDaily() async {
    setState(() {
      isLoadingDaily = true;
      error = null;
    });

    try {
      final fileContent = await rootBundle.loadString('assets/words_en.txt');
      final loadedWords = fileContent
          .split('\n')
          .map((line) => line.trim().toLowerCase())
          .where((line) => line.isNotEmpty)
          .toSet()
          .toList();
      if (loadedWords.isEmpty) {
        throw Exception('Word list is empty');
      }
      _words = loadedWords;

      final dayKey = _dayKeyUtc();
      final cacheId = 'en_$dayKey';
      try {
        final cacheDoc = await FirebaseFirestore.instance
            .collection('daily_words')
            .doc(cacheId)
            .get();
        final cached = cacheDoc.data();
        if (cached != null &&
            cached['word'] is String &&
            cached['definition'] is String &&
            mounted) {
          final cachedWord = cached['word'] as String;
          final cachedDefinition = cached['definition'] as String;
          final cachedPos = cached['partOfSpeech'] as String?;
          setState(() {
            dailyWord = cachedWord;
            dailyDefinition = cachedDefinition;
            dailyPhonetic = cached['phonetic'] as String?;
            dailyPartOfSpeech = cachedPos;
            isLoadingDaily = false;
          });
          await _updateHomeWidget(
            word: cachedWord,
            partOfSpeech: cachedPos,
            definition: cachedDefinition,
          );
          return;
        }
      } on FirebaseException {
        // If Firestore access is denied/unavailable, continue with API fallback.
      }

      final startIndex = _stableHash(dayKey) % _words.length;
      for (var i = 0; i < 25; i++) {
        final idx = (startIndex + i) % _words.length;
        final candidate = _words[idx];
        final wordData = await _fetchWordData(candidate);
        if (wordData == null) continue;

        try {
          await FirebaseFirestore.instance.collection('daily_words').doc(cacheId).set({
            'lang': 'en',
            'dateKey': dayKey,
            'word': wordData.word,
            'definition': wordData.definition,
            'phonetic': wordData.phonetic,
            'partOfSpeech': wordData.partOfSpeech,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } on FirebaseException {
          // Non-blocking: UI still works even if cache write is denied.
        }

        if (!mounted) return;
        setState(() {
          dailyWord = wordData.word;
          dailyDefinition = wordData.definition;
          dailyPhonetic = wordData.phonetic;
          dailyPartOfSpeech = wordData.partOfSpeech;
          isLoadingDaily = false;
        });
        await _updateHomeWidget(
          word: wordData.word,
          partOfSpeech: wordData.partOfSpeech,
          definition: wordData.definition,
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        error = 'Impossible de recuperer le mot du jour.';
        isLoadingDaily = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'Erreur pendant le chargement du mot du jour.';
        isLoadingDaily = false;
      });
    }
  }

  Future<void> _loadRandomWord() async {
    if (_words.isEmpty) return;
    setState(() {
      isLoadingRandom = true;
      error = null;
    });

    try {
      for (var attempt = 0; attempt < 20; attempt++) {
        final word = _words[_random.nextInt(_words.length)];
        final wordData = await _fetchWordData(word);
        if (wordData == null) continue;

        if (!mounted) return;
        setState(() {
          randomWord = wordData.word;
          randomDefinition = wordData.definition;
          randomPhonetic = wordData.phonetic;
          randomPartOfSpeech = wordData.partOfSpeech;
          isLoadingRandom = false;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        error = 'Impossible de recuperer un mot aleatoire.';
        isLoadingRandom = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'Erreur reseau pendant la recherche aleatoire.';
        isLoadingRandom = false;
      });
    }
  }

  Future<_WordData?> _fetchWordData(String word) async {
    final uri = Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/en/$word');
    final response = await http.get(uri);
    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    if (decoded is! List || decoded.isEmpty) return null;
    final entry = decoded.first;
    if (entry is! Map<String, dynamic>) return null;
    final meanings = entry['meanings'];
    if (meanings is! List || meanings.isEmpty) return null;
    final firstMeaning = meanings.first;
    if (firstMeaning is! Map<String, dynamic>) return null;
    final definitions = firstMeaning['definitions'];
    if (definitions is! List || definitions.isEmpty) return null;
    final firstDefinition = definitions.first;
    if (firstDefinition is! Map<String, dynamic>) return null;
    final definition = firstDefinition['definition'];
    if (definition is! String || definition.isEmpty) return null;

    String? phonetic;
    if (entry['phonetic'] is String && (entry['phonetic'] as String).isNotEmpty) {
      phonetic = entry['phonetic'] as String;
    } else {
      final phonetics = entry['phonetics'];
      if (phonetics is List) {
        for (final p in phonetics) {
          if (p is Map<String, dynamic> &&
              p['text'] is String &&
              (p['text'] as String).isNotEmpty) {
            phonetic = p['text'] as String;
            break;
          }
        }
      }
    }

    String? partOfSpeech;
    final pos = firstMeaning['partOfSpeech'];
    if (pos is String && pos.isNotEmpty) {
      partOfSpeech = pos;
    }

    return _WordData(
      word: word,
      definition: definition,
      phonetic: phonetic,
      partOfSpeech: partOfSpeech,
    );
  }

  String _dayKeyUtc() {
    final now = DateTime.now().toUtc();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    return '${now.year}-$mm-$dd';
  }

  int _stableHash(String input) {
    var hash = 0;
    for (final unit in input.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }

  Future<void> _updateHomeWidget({
    required String word,
    required String definition,
    String? partOfSpeech,
  }) async {
    try {
      await _widgetChannel.invokeMethod('updateWordWidget', {
        'word': word,
        'partOfSpeech': partOfSpeech ?? '',
        'definition': definition,
      });
    } on PlatformException {
      // Non-blocking: app still works even if widget update fails.
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Utilisateur non connecté')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Word of the Day'),
        actions: [
          IconButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connecte: ${user.email ?? "inconnu"}'),
            const SizedBox(height: 20),
            const Text(
              'Mot du jour (anglais)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (isLoadingDaily) const CircularProgressIndicator(),
            if (!isLoadingDaily && error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            if (!isLoadingDaily && error == null && dailyWord != null) ...[
              Text(
                dailyWord!,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              if (dailyPartOfSpeech != null) ...[
                const SizedBox(height: 4),
                Text(
                  dailyPartOfSpeech!,
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ],
              const SizedBox(height: 8),
              Text(dailyDefinition ?? ''),
            ],
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            const Text(
              'Aleatoire',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (isLoadingRandom) const CircularProgressIndicator(),
            if (!isLoadingRandom && randomWord != null) ...[
              Text(
                randomWord!,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              if (randomPhonetic != null) ...[
                const SizedBox(height: 4),
                Text('/$randomPhonetic/'),
              ],
              if (randomPartOfSpeech != null) ...[
                const SizedBox(height: 4),
                Text(
                  randomPartOfSpeech!,
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ],
              const SizedBox(height: 8),
              Text(randomDefinition ?? ''),
              const SizedBox(height: 12),
            ],
            ElevatedButton(
              onPressed: isLoadingDaily || isLoadingRandom ? null : _loadRandomWord,
              child: const Text('Nouveau mot'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WordData {
  const _WordData({
    required this.word,
    required this.definition,
    this.phonetic,
    this.partOfSpeech,
  });

  final String word;
  final String definition;
  final String? phonetic;
  final String? partOfSpeech;
}