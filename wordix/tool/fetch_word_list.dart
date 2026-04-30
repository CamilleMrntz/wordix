// Regenerates assets/words_en.txt or assets/words_es.txt from LibreOffice Hunspell.
//
// Free Dictionary API does not provide full word lists; we mirror the English
// approach using LibreOffice dictionaries (spell-check oriented).
//
// Usage (from project root):
//   dart run tool/fetch_word_list.dart        # English -> assets/words_en.txt
//   dart run tool/fetch_word_list.dart es     # Spanish -> assets/words_es.txt
//
// License: https://github.com/LibreOffice/dictionaries

import 'dart:io';

import 'package:http/http.dart' as http;

const _enUrl =
    'https://raw.githubusercontent.com/LibreOffice/dictionaries/master/en/en_US.dic';
const _esUrl =
    'https://raw.githubusercontent.com/LibreOffice/dictionaries/master/es/es_ES.dic';

/// Lowercase letters only (Unicode), optional apostrophe + lowercase chunk (contractions).
final _headwordLower = RegExp(r"^\p{Ll}+(?:'\p{Ll}+)?$", unicode: true);

bool _isRepeatedSingleLetter(String w) {
  final letters = w.replaceAll("'", '');
  if (letters.length < 3) return false;
  final it = letters.runes.iterator;
  if (!it.moveNext()) return false;
  final first = it.current;
  while (it.moveNext()) {
    if (it.current != first) return false;
  }
  return true;
}

bool _looksLikeEnglishPossessive(String w) {
  final i = w.indexOf("'");
  if (i <= 0) return false;
  if (!w.endsWith('s')) return false;
  final after = w.substring(i + 1);
  if (after != 's') return false;
  return i >= 3;
}

Future<void> _writeFromDic({
  required String url,
  required String outPath,
  required String label,
}) async {
  stderr.writeln('Downloading $label ...');
  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) {
    stderr.writeln('HTTP ${response.statusCode}');
    exit(1);
  }

  final words = <String>{};
  final lines = response.body.split(RegExp(r'\r?\n'));

  for (var idx = 0; idx < lines.length; idx++) {
    final raw = lines[idx].trim();
    if (raw.isEmpty) continue;
    if (idx == 0 && int.tryParse(raw) != null) continue;

    final slash = raw.indexOf('/');
    final head = (slash == -1 ? raw : raw.substring(0, slash)).toLowerCase();

    if (head.length <= 2) continue;
    if (!_headwordLower.hasMatch(head)) continue;
    if (_isRepeatedSingleLetter(head)) continue;
    if (_looksLikeEnglishPossessive(head)) continue;

    words.add(head);
  }

  final sorted = words.toList()..sort();
  final outFile = File(outPath);
  await outFile.writeAsString('${sorted.join('\n')}\n');
  stderr.writeln('Wrote ${sorted.length} words to ${outFile.path}');
}

Future<void> main(List<String> args) async {
  final lang = args.isNotEmpty ? args.first.toLowerCase() : 'en';
  if (lang == 'es') {
    await _writeFromDic(
      url: _esUrl,
      outPath: 'assets/words_es.txt',
      label: 'LibreOffice es_ES.dic',
    );
  } else {
    await _writeFromDic(
      url: _enUrl,
      outPath: 'assets/words_en.txt',
      label: 'LibreOffice en_US.dic',
    );
  }
}
