// The similar-āyah pairing has no Python counterpart either -- QUL ships the
// pairs, and the alignment over them is new here -- so these assert its
// invariants against the real corpus rather than against a golden.
//
//   dart test --define=db=../../data/quran.db
//
// Skipped, not failed, when the corpus is not built -- the same courtesy
// tests/ extends on the Python side.

import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'package:quran_port/similar.dart';

const String _dbPath =
    String.fromEnvironment('db', defaultValue: '../../data/quran.db');

void main() {
  if (!File(_dbPath).existsSync()) {
    test('corpus not built', () {}, skip: 'no $_dbPath');
    return;
  }

  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open('winsqlite3.dll'),
  );
  final db = sqlite3.open(_dbPath, mode: OpenMode.readOnly);

  if (!hasSimilar(db)) {
    test('no similar_ayahs in this corpus', () {},
        skip: 'table absent or empty');
    return;
  }

  /// Every verse_key the table has an opinion about.
  final keys = db
      .select('SELECT DISTINCT verse_key FROM similar_ayahs ORDER BY verse_key')
      .map((r) => r['verse_key'] as String)
      .toList();

  test('the corpus carries the pairing and the app can reach it', () {
    expect(keys, isNotEmpty);
    expect(similarAyat(db, keys.first), isNotEmpty);
  });

  test('an āyah with no twin asks for nothing', () {
    // 2:282 is the longest āyah in the muṣḥaf and has no near twin.
    expect(similarAyat(db, '2:282'), isEmpty);
    expect(similarAyat(db, '999:1'), isEmpty);
    expect(similarAyat(db, 'nonsense'), isEmpty);
  });

  test('the limit is honoured', () {
    // 2:1 is one of the muqaṭṭaʿāt openings, which have many twins.
    expect(similarAyat(db, '2:1', limit: 2).length, lessThanOrEqualTo(2));
    expect(similarAyat(db, '2:1', limit: 1).length, lessThanOrEqualTo(1));
  });

  test('closest first', () {
    for (final k in keys.take(300)) {
      var last = 1 << 30;
      for (final s in similarAyat(db, k)) {
        expect(s.score, lessThanOrEqualTo(last), reason: 'order regressed at $k');
        last = s.score;
      }
    }
  });

  // The alignment is the part with no upstream to check against, so it is
  // checked against the āyāt themselves: whatever it marks, it must not have
  // invented, dropped or reordered a single word.
  test('the alignment preserves both āyāt exactly', () {
    List<String> wordsOf(String key) {
      final at = key.indexOf(':');
      return db
          .select(
              'SELECT text_uthmani FROM words WHERE surah = ? AND ayah = ? '
              'ORDER BY word_pos',
              [
                int.parse(key.substring(0, at)),
                int.parse(key.substring(at + 1)),
              ])
          .map((r) => r['text_uthmani'] as String)
          .toList();
    }

    for (final k in keys.take(200)) {
      final mine = wordsOf(k);
      for (final s in similarAyat(db, k)) {
        expect(s.here.map((w) => w.text).toList(), mine,
            reason: '$k lost or reordered a word against ${s.verseKey}');
        expect(s.there.map((w) => w.text).toList(), wordsOf(s.verseKey),
            reason: '${s.verseKey} lost or reordered a word against $k');
      }
    }
  });

  test('the two sides agree about how much they agree', () {
    for (final k in keys.take(300)) {
      for (final s in similarAyat(db, k)) {
        // An alignment pairs words, so each side must report the same number
        // of paired ones -- if they disagree the walk has gone crooked.
        expect(s.here.where((w) => w.same).length,
            s.there.where((w) => w.same).length,
            reason: '$k vs ${s.verseKey}');
      }
    }
  });

  test('identical means identical, and differing means differing', () {
    var sawIdentical = false, sawDiffering = false;
    for (final k in keys.take(400)) {
      for (final s in similarAyat(db, k)) {
        if (s.identical) {
          sawIdentical = true;
          expect(s.differences, 0);
          expect(s.here.length, s.there.length);
        } else {
          sawDiffering = true;
          expect(s.differences, greaterThan(0));
        }
      }
    }
    // Both kinds exist in the corpus -- 1,546 pairs are word for word the
    // same once normalised -- so a run that meets only one has broken the
    // comparison rather than found a quiet stretch of muṣḥaf.
    expect(sawIdentical, isTrue, reason: 'no identical pair found');
    expect(sawDiffering, isTrue, reason: 'no differing pair found');
  });

  test('a known pair parts where it is known to part', () {
    // 2:136 against 3:84 is the classic of this kind: the same profession of
    // faith, opening قُولُوٓا۟ in one and قُلْ in the other, and turning on
    // إِلَيْنَا against عَلَيْنَا.
    final pair = similarAyat(db, '2:136').where((s) => s.verseKey == '3:84');
    expect(pair, isNotEmpty, reason: '2:136 should know 3:84');
    final s = pair.first;
    expect(s.identical, isFalse);

    final differingHere =
        s.here.where((w) => !w.same).map((w) => w.text).toList();
    final differingThere =
        s.there.where((w) => !w.same).map((w) => w.text).toList();
    expect(differingHere.first, contains('قُولُوا'.substring(0, 3)));
    expect(differingThere.first, contains('قُل'.substring(0, 2)));
    // And the words they share are not marked as differences.
    expect(s.here.where((w) => w.same), isNotEmpty);
  });

  // -------------------------------------------------------------- the index

  test('the index folds symmetric rows and still covers the pairing', () {
    final all = similarIndex(db, limit: 1);
    final same = similarIndex(db, scope: SimilarScope.sameSurah, limit: 1);
    final cross = similarIndex(db, scope: SimilarScope.crossSurah, limit: 1);
    // QUL stores most pairs from both ends; the index shows each once.
    final rows =
        db.select('SELECT COUNT(*) AS n FROM similar_ayahs').first['n'] as int;
    expect(all.total, lessThan(rows));
    expect(all.total, greaterThan(rows ~/ 2 - 1));
    // The two scopes partition the whole.
    expect(same.total + cross.total, all.total);
  });

  test('no pair is listed twice, in either direction', () {
    final seen = <String>{};
    for (var off = 0; off < 400; off += 50) {
      for (final p in similarIndex(db, limit: 50, offset: off).pairs) {
        final key = ([p.aKey, p.bKey]..sort()).join('|');
        expect(seen.add(key), isTrue, reason: '$key listed twice');
      }
    }
  });

  test('closest first, and the closest are the verbatim ones', () {
    var last = 1 << 30;
    for (var off = 0; off < 300; off += 50) {
      for (final p in similarIndex(db, limit: 50, offset: off).pairs) {
        expect(p.score, lessThanOrEqualTo(last));
        last = p.score;
      }
    }
    // The head of the list is where the word-for-word repeats live.
    expect(similarIndex(db, limit: 20).pairs.where((p) => p.identical),
        isNotEmpty);
  });

  test('the scopes hold to what they claim', () {
    int surahOf(String k) => int.parse(k.substring(0, k.indexOf(':')));
    for (final p in similarIndex(db, scope: SimilarScope.sameSurah, limit: 60).pairs) {
      expect(surahOf(p.aKey), surahOf(p.bKey));
    }
    for (final p in similarIndex(db, scope: SimilarScope.crossSurah, limit: 60).pairs) {
      expect(surahOf(p.aKey), isNot(surahOf(p.bKey)));
    }
  });

  test('paging walks the list without gap or repeat', () {
    final one = similarIndex(db, limit: 40).pairs;
    final first = similarIndex(db, limit: 20, offset: 0).pairs;
    final second = similarIndex(db, limit: 20, offset: 20).pairs;
    expect([...first, ...second].map((p) => '${p.aKey}|${p.bKey}').toList(),
        one.map((p) => '${p.aKey}|${p.bKey}').toList());
  });

  test('an index row carries both ayat whole', () {
    List<String> wordsOf(String key) {
      final at = key.indexOf(':');
      return db
          .select(
              'SELECT text_uthmani FROM words WHERE surah = ? AND ayah = ? '
              'ORDER BY word_pos',
              [
                int.parse(key.substring(0, at)),
                int.parse(key.substring(at + 1)),
              ])
          .map((r) => r['text_uthmani'] as String)
          .toList();
    }

    for (final p in similarIndex(db, limit: 60).pairs) {
      expect(p.a.map((w) => w.text).toList(), wordsOf(p.aKey));
      expect(p.b.map((w) => w.text).toList(), wordsOf(p.bKey));
      expect(p.identical, p.partings.isEmpty);
    }
  });

  test('every twin can be turned to', () {
    for (final k in keys.take(300)) {
      for (final s in similarAyat(db, k)) {
        expect(s.verseKey, isNot(k), reason: 'an āyah is not its own twin');
        expect(s.surahNameAr, isNotEmpty);
        expect(s.page, isNotNull, reason: '${s.verseKey} is on no page');
      }
    }
  });
}
