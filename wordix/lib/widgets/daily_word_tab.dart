import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

/// One language tab: word of the day (deterministic + Firestore cache) + random word.
class DailyWordTab extends StatefulWidget {
  const DailyWordTab({
    super.key,
    required this.langCode,
    required this.assetPath,
    required this.apiEntriesPath,
    required this.titleDaily,
    required this.titleRandom,
    this.androidWidgetSlot,
  });

  /// Firestore + hash seed, e.g. `en`, `es`.
  final String langCode;

  final String assetPath;

  /// Free Dictionary API path segment for English only (`en`). Spanish uses Wiktionary REST HTML.
  final String apiEntriesPath;

  final String titleDaily;
  final String titleRandom;

  /// Android home widget slot: `'en'`, `'es'`, or `null` to skip updates.
  final String? androidWidgetSlot;

  @override
  State<DailyWordTab> createState() => _DailyWordTabState();
}

class _DailyWordTabState extends State<DailyWordTab> with AutomaticKeepAliveClientMixin {
  static const MethodChannel _widgetChannel = MethodChannel('wordix/widget');

  /// Bumps when the Spanish definition source/format changes (invalidate Firestore cache).
  static const int _spanishDefinitionCacheVersion = 5;

  final Random _random = Random();
  List<String> _words = [];

  bool isLoadingDaily = true;
  bool isLoadingRandom = false;
  String? dailyWord;
  String? dailyDefinition;
  String? dailyPartOfSpeech;
  String? randomWord;
  String? randomDefinition;
  String? randomPartOfSpeech;
  String? error;

  @override
  bool get wantKeepAlive => true;

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
      final fileContent = await rootBundle.loadString(widget.assetPath);
      final loadedWords = fileContent
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toSet()
          .toList();
      if (loadedWords.isEmpty) {
        throw Exception('Word list is empty');
      }
      _words = loadedWords;

      final dayKey = _dayKeyUtc();
      final cacheId = '${widget.langCode}_$dayKey';
      try {
        final cacheDoc = await FirebaseFirestore.instance.collection('daily_words').doc(cacheId).get();
        final cached = cacheDoc.data();
        final staleSpanishCache = widget.langCode == 'es' &&
            cached != null &&
            cached['definitionVersion'] != _spanishDefinitionCacheVersion;
        if (cached != null &&
            !staleSpanishCache &&
            cached['word'] is String &&
            cached['definition'] is String &&
            mounted) {
          final cachedWord = cached['word'] as String;
          final cachedDefinition = cached['definition'] as String;
          final cachedPos = cached['partOfSpeech'] as String?;
          setState(() {
            dailyWord = cachedWord;
            dailyDefinition = cachedDefinition;
            dailyPartOfSpeech = cachedPos;
            isLoadingDaily = false;
          });
          await _maybePushWidget(
            word: cachedWord,
            partOfSpeech: cachedPos,
            definition: cachedDefinition,
          );
          return;
        }
      } on FirebaseException {
        // continue with API
      }

      final seed = '${widget.langCode}_$dayKey';
      final startIndex = _stableHash(seed) % _words.length;
      final maxLinear = widget.langCode == 'es' ? 32 : 25;
      final maxRandomExtra = widget.langCode == 'es' ? 48 : 0;
      final tried = <int>{};

      Future<bool> tryCandidateAt(int idx) async {
        final i = idx % _words.length;
        if (!tried.add(i)) return false;
        final candidate = _words[i];
        final wordData = await _fetchWordData(candidate);
        if (wordData == null) return false;

        try {
          await FirebaseFirestore.instance.collection('daily_words').doc(cacheId).set({
            'lang': widget.langCode,
            'dateKey': dayKey,
            'word': wordData.word,
            'definition': wordData.definition,
            'partOfSpeech': wordData.partOfSpeech,
            if (widget.langCode == 'es') 'definitionVersion': _spanishDefinitionCacheVersion,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } on FirebaseException {
          // non-blocking
        }

        if (!mounted) return true;
        setState(() {
          dailyWord = wordData.word;
          dailyDefinition = wordData.definition;
          dailyPartOfSpeech = wordData.partOfSpeech;
          isLoadingDaily = false;
        });
        await _maybePushWidget(
          word: wordData.word,
          partOfSpeech: wordData.partOfSpeech,
          definition: wordData.definition,
        );
        return true;
      }

      for (var k = 0; k < maxLinear; k++) {
        if (await tryCandidateAt(startIndex + k)) return;
      }
      if (maxRandomExtra > 0) {
        final rng = Random(_stableHash('${seed}_es_daily2'));
        for (var k = 0; k < maxRandomExtra; k++) {
          if (await tryCandidateAt(rng.nextInt(_words.length))) return;
        }
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
      final maxRandom = widget.langCode == 'es' ? 28 : 20;
      for (var attempt = 0; attempt < maxRandom; attempt++) {
        final word = _words[_random.nextInt(_words.length)];
        final wordData = await _fetchWordData(word);
        if (wordData == null) continue;

        if (!mounted) return;
        setState(() {
          randomWord = wordData.word;
          randomDefinition = wordData.definition;
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
    if (widget.langCode == 'es') {
      return _fetchSpanishFromWiktionary(word);
    }
    return _fetchEnglishFromFreeDictionary(word);
  }

  /// https://dictionaryapi.dev — English only (no `/entries/es/`).
  Future<_WordData?> _fetchEnglishFromFreeDictionary(String word) async {
    final encoded = Uri.encodeComponent(word);
    final uri = Uri.parse(
      'https://api.dictionaryapi.dev/api/v2/entries/${widget.apiEntriesPath}/$encoded',
    );
    http.Response response;
    try {
      response = await http.get(uri).timeout(const Duration(seconds: 14));
    } on TimeoutException {
      return null;
    }
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

    String? partOfSpeech;
    final pos = firstMeaning['partOfSpeech'];
    if (pos is String && pos.isNotEmpty) {
      partOfSpeech = pos;
    }

    return _WordData(
      word: word,
      definition: definition.trim(),
      partOfSpeech: partOfSpeech,
    );
  }

  static const _wiktionaryRestHeaders = {
    'User-Agent': 'Wordix/1.0 (Flutter; es.wiktionary REST; educational)',
  };

  /// Spanish definitions via [Wiktionary REST v1](https://www.mediawiki.org/wiki/API:REST_API) (`/page/{title}/html`).
  /// The response is Parsoid **HTML** (not Markdown): `h2#Español` and `dl`/`dt`/`dd` senses.
  Future<_WordData?> _fetchSpanishFromWiktionary(String word) async {
    final path = '/w/rest.php/v1/page/${Uri.encodeComponent(word)}/html';
    final uri = Uri.https('es.wiktionary.org', path);

    http.Response response;
    try {
      response = await http.get(uri, headers: _wiktionaryRestHeaders).timeout(const Duration(seconds: 12));
    } on TimeoutException {
      return null;
    }
    if (response.statusCode == 429) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      try {
        response = await http.get(uri, headers: _wiktionaryRestHeaders).timeout(const Duration(seconds: 12));
      } on TimeoutException {
        return null;
      }
    }
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) return null;

    final raw = _unwrapWiktionaryRestBody(response.body);
    final doc = html_parser.parse(raw);
    final fromHtml = _parseSpanishWiktionaryRestHtml(word, doc);
    if (fromHtml != null) return fromHtml;

    final section = _sliceSpanishRestMarkdown(raw);
    if (section == null || section.isEmpty) return null;

    return _parseSpanishRestMarkdown(word, section);
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

  Future<void> _maybePushWidget({
    required String word,
    required String definition,
    String? partOfSpeech,
  }) async {
    final slot = widget.androidWidgetSlot;
    if (slot == null) return;
    try {
      await _widgetChannel.invokeMethod('updateWordWidget', {
        'slot': slot,
        'word': word,
        'partOfSpeech': partOfSpeech ?? '',
        'definition': definition,
      });
    } on PlatformException {
      // non-blocking
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.titleDaily,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
          Text(
            widget.titleRandom,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (isLoadingRandom) const CircularProgressIndicator(),
          if (!isLoadingRandom && randomWord != null) ...[
            Text(
              randomWord!,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
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
    );
  }
}

/// If the REST client ever returns JSON `{ "html": "..." }`, unwrap it; otherwise return [body].
String _unwrapWiktionaryRestBody(String body) {
  final t = body.trimLeft();
  if (!t.startsWith('{')) return body;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      for (final k in const ['html', 'body', 'source', 'text']) {
        final v = decoded[k];
        if (v is String && v.isNotEmpty) return v;
      }
    }
  } catch (_) {}
  return body;
}

/// Parsoid HTML: [h2 id="Español"] inside a [section], numbered senses in [dl]/[dt]/[dd].
_WordData? _parseSpanishWiktionaryRestHtml(String word, dom.Document doc) {
  final body = doc.body;
  if (body == null) return null;
  final h2 = body.querySelector('h2#Español');
  if (h2 == null) return null;
  final section = h2.parent;
  if (section == null) return null;

  String? partOfSpeech;
  for (final h4 in section.querySelectorAll('h4')) {
    final t = h4.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length < 3 || t.length > 80) continue;
    if (!RegExp(
      r'^(Sustantivo|Verbo|Adjetivo|Adverbio|Forma|Numeral|Artículo|Interjección|'
      r'Preposición|Conjunción|Nombre propio|Sigla|Prefijo|Abreviatura|Participio)',
      caseSensitive: false,
    ).hasMatch(t)) {
      continue;
    }
    partOfSpeech = t;
    break;
  }

  var glosses = _extractSpanishHtmlNumberedGlosses(section, maxCount: 2);
  if (glosses.isEmpty) {
    final et = _spanishEtymologyFromHtmlSection(section);
    if (et != null) {
      return _WordData(word: word, definition: et, partOfSpeech: partOfSpeech);
    }
    return null;
  }

  return _WordData(
    word: word,
    definition: glosses.join('\n\n'),
    partOfSpeech: partOfSpeech,
  );
}

List<String> _extractSpanishHtmlNumberedGlosses(dom.Element section, {required int maxCount}) {
  final out = <String>[];
  for (final dl in section.querySelectorAll('dl')) {
    for (final g in _ddTextsFromNumberedDl(dl)) {
      if (g.length < 8) continue;
      out.add(g);
      if (out.length >= maxCount) return out;
    }
  }
  return out;
}

List<String> _ddTextsFromNumberedDl(dom.Element dl) {
  final out = <String>[];
  final kids = dl.children;
  for (var i = 0; i < kids.length; i++) {
    if (kids[i].localName != 'dt') continue;
    final dtText = kids[i].text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (!RegExp(r'^\d+').hasMatch(dtText)) continue;
    dom.Element? ddEl;
    for (var j = i + 1; j < kids.length; j++) {
      final name = kids[j].localName;
      if (name == 'dd') {
        ddEl = kids[j];
        break;
      }
      if (name == 'dt') break;
    }
    if (ddEl == null) continue;
    var text = ddEl.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    text = text.replaceAll(RegExp(r'\s*\[\d+\]\s*'), ' ').trim();
    if (text.length >= 8) out.add(text);
  }
  return out;
}

String? _spanishEtymologyFromHtmlSection(dom.Element section) {
  dom.Element? h3;
  for (final el in section.querySelectorAll('h3')) {
    if (el.id.startsWith('Etimolog')) {
      h3 = el;
      break;
    }
    final plain = el.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (plain.toLowerCase().startsWith('etimolog')) {
      h3 = el;
      break;
    }
  }
  if (h3 == null) return null;
  final buf = StringBuffer();
  for (var el = h3.nextElementSibling; el != null; el = el.nextElementSibling) {
    final n = el.localName?.toLowerCase();
    if (n == 'h2' || n == 'h3' || n == 'h4' || n == 'section') break;
    final t = el.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isNotEmpty) {
      buf.write(t);
      buf.write(' ');
    }
  }
  var s = buf.toString().trim();
  if (s.length < 22) return null;
  return s.length > 450 ? '${s.substring(0, 450)}…' : s;
}

/// Legacy: if the body were Markdown, keep `## Español` through the next top-level `##` section.
String? _sliceSpanishRestMarkdown(String body) {
  final m = RegExp(r'^## Español\s*$', multiLine: true).firstMatch(body);
  if (m == null) return null;
  final start = m.start;
  final afterHeader = body.substring(m.end);
  final nextH2 = RegExp(r'^## (?!Español\s*$)[^\r\n]+', multiLine: true).firstMatch(afterHeader);
  if (nextH2 == null) return body.substring(start).trim();
  return body.substring(start, m.end + nextH2.start).trim();
}

String _stripMarkdownLinks(String s) {
  return s.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1)!).replaceAllMapped(
    RegExp(r'\*\*([^*]+)\*\*'),
    (m) => m.group(1)!,
  );
}

String _trimSpanishDefRegion(String fromPos) {
  final stop = RegExp(
    r'^#### (Locuciones|Traducciones|Véase también|Derivados|Refranes)|^### Forma flexiva|^## (?!#)',
    multiLine: true,
  ).firstMatch(fromPos);
  final end = stop?.start ?? fromPos.length;
  return fromPos.substring(0, end).trim();
}

_WordData? _parseSpanishRestMarkdown(String word, String section) {
  final stripped = _stripMarkdownLinks(section);
  final pos4 = RegExp(
    r'^#### (Sustantivo[^\n]*|Verbo[^\n]*|Adjetivo[^\n]*|Adverbio[^\n]*|'
    r'Interjección[^\n]*|Nombre propio[^\n]*|Sigla[^\n]*|Prefijo[^\n]*|'
    r'Conjunción[^\n]*|Preposición[^\n]*|Numeral[^\n]*|Artículo[^\n]*)\s*$',
    multiLine: true,
  ).firstMatch(stripped);
  final pos3 = RegExp(
    r'^### (Sustantivo[^\n]*|Verbo[^\n]*|Adjetivo[^\n]*)\s*$',
    multiLine: true,
  ).firstMatch(stripped);

  final posMatch = pos4 ?? pos3;
  final partOfSpeech = posMatch?.group(1)?.trim();
  final fromPos = posMatch != null ? stripped.substring(posMatch.end) : stripped;

  final defRegion = _trimSpanishDefRegion(fromPos);
  if (defRegion.isEmpty) return null;

  var glosses = _extractNumberedSpanishGlosses(defRegion, maxCount: 2);
  if (glosses.isEmpty) {
    glosses = _extractNumberedSpanishGlosses(stripped, maxCount: 2);
  }
  if (glosses.isEmpty) {
    final fb = _fallbackMarkdownEtymology(stripped);
    if (fb == null) return null;
    return _WordData(word: word, definition: fb, partOfSpeech: partOfSpeech);
  }

  return _WordData(
    word: word,
    definition: glosses.join('\n\n'),
    partOfSpeech: partOfSpeech,
  );
}

String? _fallbackMarkdownEtymology(String section) {
  final m = RegExp(r'^### Etimolog[^\n]*\s*$', multiLine: true).firstMatch(section);
  if (m == null) return null;
  final tail = section.substring(m.end).trim();
  final nextH = RegExp(r'^(###|####)\s', multiLine: true).firstMatch(tail);
  final chunk = nextH != null ? tail.substring(0, nextH.start) : tail;
  final t = _wikitextToPlain(_stripMarkdownLinks(chunk));
  if (t.length < 22) return null;
  return t.length > 450 ? '${t.substring(0, 450)}…' : t;
}

List<String> _extractNumberedSpanishGlosses(String body, {required int maxCount}) {
  final out = <String>[];
  final reStart = RegExp(r'^\s*(\d+)\s*(.*)$');
  final lines = body.split('\n');
  var i = 0;
  while (i < lines.length && out.length < maxCount) {
    final m = reStart.firstMatch(lines[i]);
    if (m == null) {
      i++;
      continue;
    }
    final buf = StringBuffer(m.group(2)!.trim());
    i++;
    while (i < lines.length) {
      if (reStart.hasMatch(lines[i])) break;
      final t = lines[i].trim();
      if (t.startsWith('Sinónimos:') ||
          t.startsWith('Sin\u00f3nimos:') ||
          t.startsWith('- Sinónimos:') ||
          t.startsWith('- Sin\u00f3nimos:') ||
          t.startsWith('Hiperónimo:') ||
          t.startsWith('Hiper\u00f3nimo:') ||
          t.startsWith('Hipónimos:') ||
          t.startsWith('Hip\u00f3nimos:') ||
          t.startsWith('Relacionados:')) {
        break;
      }
      if (t.isNotEmpty) {
        buf.write(' ');
        buf.write(t);
      }
      i++;
    }
    final plain = _wikitextToPlain(buf.toString()).trim();
    if (plain.length >= 4) out.add(plain);
  }
  return out;
}

/// Wiktionary REST often returns HTML fragments (<span>, links, etc.).
String _wikitextToPlain(String raw) {
  final fragment = html_parser.parseFragment(raw);
  var t = fragment.text ?? '';
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t;
}

class _WordData {
  const _WordData({
    required this.word,
    required this.definition,
    this.partOfSpeech,
  });

  final String word;
  final String definition;
  final String? partOfSpeech;
}
