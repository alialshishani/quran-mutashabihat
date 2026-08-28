// Does the Dart query normalizer agree with the Python that built the index?
//
//   dart run bin/verify_normalize.dart <app.db>
//
// Search matches a normalized query against `search_ayat.norm`, which
// `mobile/tools/stage_assets.py` built by running `pipeline.normalize` over the
// imlaei text. So the invariant search depends on is exactly this: normalizing
// the same words in Dart must give the same key.
//
// Comparing against `words.text_norm` instead would prove nothing -- that
// column was normalized from the Uthmānī rasm, and the imlaei spelling of the
// same word is legitimately different (الْعَالَمِينَ against العلمين).

import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:quran_port/search.dart';

void main(List<String> args) {
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open('winsqlite3.dll'),
  );
  final db = sqlite3.open(args[0], mode: OpenMode.readOnly);

  if (db
      .select("SELECT name FROM sqlite_master WHERE type='table' "
          "AND name='search_ayat'")
      .isEmpty) {
    stderr.writeln('no search_ayat table; run: '
        'python -m mobile.tools.stage_assets --force');
    exit(2);
  }

  var total = 0;
  var same = 0;
  final examples = <String>[];

  for (final r in db.select(
    'SELECT a.verse_key, x.norm, '
    '       group_concat(COALESCE(w.text_imlaei, w.text_uthmani), " ") AS src '
    'FROM ayahs a '
    'JOIN search_ayat x ON x.verse_key = a.verse_key '
    'JOIN words w ON w.word_id BETWEEN a.first_word_id AND a.last_word_id '
    'GROUP BY a.verse_key ORDER BY a.first_word_id',
  )) {
    total++;
    final expected = r['norm'] as String;
    final mine =
        (r['src'] as String).split(' ').map(normalizeStandard).join();
    if (mine == expected) {
      same++;
    } else if (examples.length < 6) {
      examples.add(
          '${r['verse_key']}\n     dart  : $mine\n     python: $expected');
    }
  }

  final pct = same / total * 100;
  stdout.writeln('ayat       : $total');
  stdout.writeln('identical  : $same  (${pct.toStringAsFixed(2)}%)');
  stdout.writeln('differing  : ${total - same}');
  for (final e in examples) {
    stdout.writeln('  $e');
  }
  if (same != total) exit(1);
}
