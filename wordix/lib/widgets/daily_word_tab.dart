import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/user_stats_service.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'lexicon_blocks.dart';

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
  static const int _spanishDefinitionCacheVersion = 7;

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

  String? _lastStatsDailyRecorded;
  String? _lastStatsRandomRecorded;

  void _recordDailyWordStats(String word) {
    final w = word.trim();
    if (w.isEmpty || w == _lastStatsDailyRecorded) return;
    _lastStatsDailyRecorded = w;
    UserStatsService.recordWordViewed(widget.langCode, w);
  }

  void _recordRandomWordStats(String word) {
    final w = word.trim();
    if (w.isEmpty || w == _lastStatsRandomRecorded) return;
    _lastStatsRandomRecorded = w;
    UserStatsService.recordWordViewed(widget.langCode, w);
  }

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
          _recordDailyWordStats(cachedWord);
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
        _recordDailyWordStats(wordData.word);
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
        _recordRandomWordStats(wordData.word);
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

  /// FNV-1a (32-bit) on UTF-8 — the old `hash * 31 + codeUnit` mix mapped consecutive
  /// [dayKey] strings to consecutive indices in the alphabetically sorted word lists,
  /// so each day looked like “the next line in the .txt file”.
  int _stableHash(String input) {
    var hash = 0x811c9dc5;
    for (final b in utf8.encode(input)) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final defStyle = theme.textTheme.bodyLarge?.copyWith(
      height: 1.55,
      color: scheme.onSurfaceVariant,
    );

    return SafeArea(
      top: false,
      left: false,
      right: false,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LexiconSection(
              icon: Icons.wb_sunny_outlined,
              title: widget.titleDaily,
              child: _buildDailyBody(theme, scheme, defStyle),
            ),
            const SizedBox(height: 14),
            _LexiconSection(
              icon: Icons.shuffle,
              title: widget.titleRandom,
              child: _buildRandomBody(theme, scheme, defStyle),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: isLoadingDaily || isLoadingRandom ? null : _loadRandomWord,
              icon: const Icon(Icons.casino_outlined),
              label: const Text('Nouveau mot'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyBody(ThemeData theme, ColorScheme scheme, TextStyle? defStyle) {
    if (isLoadingDaily) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    if (error != null) {
      return _InlineError(message: error!);
    }
    if (dailyWord == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                dailyWord!,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: scheme.onSurface,
                ),
              ),
            ),
            _GoogleWordSearchButton(word: dailyWord!),
          ],
        ),
        if (dailyPartOfSpeech != null) ...[
          const SizedBox(height: 10),
          LexiconPosBadge(text: dailyPartOfSpeech!),
        ],
        const SizedBox(height: 12),
        LexiconDefinitionPanel(
          child: SelectableText(dailyDefinition ?? '', style: defStyle ?? theme.textTheme.bodyLarge),
        ),
      ],
    );
  }

  Widget _buildRandomBody(ThemeData theme, ColorScheme scheme, TextStyle? defStyle) {
    if (isLoadingRandom) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    if (randomWord == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome_outlined, size: 20, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Choisis « Nouveau mot » pour en tirer un au hasard.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                randomWord!,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            _GoogleWordSearchButton(word: randomWord!),
          ],
        ),
        if (randomPartOfSpeech != null) ...[
          const SizedBox(height: 8),
          LexiconPosBadge(text: randomPartOfSpeech!),
        ],
        const SizedBox(height: 12),
        LexiconDefinitionPanel(
          child: SelectableText(randomDefinition ?? '', style: defStyle ?? theme.textTheme.bodyLarge),
        ),
      ],
    );
  }
}

class _LexiconSection extends StatelessWidget {
  const _LexiconSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.primaryContainer.withValues(alpha: 0.65),
                  child: Icon(icon, size: 20, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.45)),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.error.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onErrorContainer,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens [Google web search](https://www.google.com/search) for [word] in the system browser or Google app.
class _GoogleWordSearchButton extends StatelessWidget {
  const _GoogleWordSearchButton({required this.word});

  final String word;

  static const _gLogoUrl = 'https://www.gstatic.com/images/branding/product/2x/googleg_48dp.png';

  Future<void> _open(BuildContext context) async {
    final uri = Uri.https('www.google.com', 'search', {'q': word});
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!context.mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d\'ouvrir Google.')),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'ouvrir Google.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(12),
        child: Tooltip(
          message: 'Rechercher sur Google',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    _gLogoUrl,
                    width: 28,
                    height: 28,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        'G',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: scheme.primary,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.arrow_forward_rounded, size: 21, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
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
    var text = _wikimediaSnippetToPlain(ddEl.innerHtml);
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
    final t = _wikimediaSnippetToPlain(el.innerHtml);
    if (t.isNotEmpty) {
      buf.write(t);
      buf.write(' ');
    }
  }
  var s = _wikimediaSnippetToPlain(buf.toString());
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

/// Parsoid injects `<style>` (TemplateStyles) inside senses; [Node.text] includes that CSS — skip those subtrees.
String _visiblePlainTextFromHtmlNode(dom.Node node) {
  if (node is dom.Text) return node.text;
  if (node is! dom.Element) return '';
  final el = node;
  final name = el.localName?.toLowerCase();
  if (name == 'style' || name == 'script' || name == 'template' || name == 'noscript' || name == 'link') {
    return '';
  }
  final buf = StringBuffer();
  for (final child in el.nodes) {
    buf.write(_visiblePlainTextFromHtmlNode(child));
  }
  return buf.toString();
}

String _visiblePlainTextFromHtmlNodes(Iterable<dom.Node> nodes) {
  final buf = StringBuffer();
  for (final n in nodes) {
    buf.write(_visiblePlainTextFromHtmlNode(n));
  }
  return buf.toString();
}

/// Wiktionary / Parsoid snippets: structured HTML → visible text; strip any leftover tags.
String _wikimediaSnippetToPlain(String raw) {
  final fragment = html_parser.parseFragment(raw);
  var t = _visiblePlainTextFromHtmlNodes(fragment.nodes).replaceAll(RegExp(r'\s+'), ' ').trim();
  if (!t.contains('<')) return t;
  final fragment2 = html_parser.parseFragment(t);
  t = _visiblePlainTextFromHtmlNodes(fragment2.nodes).replaceAll(RegExp(r'\s+'), ' ').trim();
  if (!t.contains('<')) return t;
  return t.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Wiktionary REST often returns HTML fragments (<span>, links, etc.).
String _wikitextToPlain(String raw) {
  return _wikimediaSnippetToPlain(raw);
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
