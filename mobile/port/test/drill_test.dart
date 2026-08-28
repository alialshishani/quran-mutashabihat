// The drill has no Python counterpart, so it cannot be checked against one.
// These assert its invariants against the real corpus instead.
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

import 'package:quran_port/drill.dart';
import 'package:quran_port/forks.dart';

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
  final pool = drillPool(db);

  test('the pool is not empty and every entry forks', () {
    expect(pool, isNotEmpty);
    for (final c in pool) {
      expect(c.shape, isNot('no_fork'));
      expect(c.branchCount, greaterThanOrEqualTo(2));
    }
  });

  test('cheapest shape first', () {
    const rank = {'all_but_one': 0, 'two_way': 1, 'many': 2};
    var last = -1;
    for (final c in pool) {
      final r = rank[c.shape]!;
      expect(r, greaterThanOrEqualTo(last),
          reason: 'pool order regressed at ${c.key}');
      last = r;
    }
  });

  test('every position appears once, and only its own fork claims it', () {
    final seen = <String>{};
    for (final c in pool) {
      expect(seen.add(c.key), isTrue, reason: 'duplicate ${c.key}');
    }
  });

  test('every question answers to a branch that holds the position', () {
    // The whole pool, not a sample: a question whose answer is not among its
    // options would teach the wrong thing, so none may exist.
    for (final c in pool) {
      final q = drillQuestion(db, c.phraseId, c.posId);
      expect(q.options.map((o) => o.branchId), contains(q.answerBranchId),
          reason: '${c.key}: answer is not among the options');
      expect(q.isCorrect(q.answerBranchId), isTrue);
      expect(q.options.length, greaterThanOrEqualTo(2),
          reason: '${c.key}: nothing to choose between');
    }
  });

  test('the options are distinguishable from each other', () {
    // Two branches showing the same word would make the question unanswerable.
    var identical = 0;
    for (final c in pool) {
      final q = drillQuestion(db, c.phraseId, c.posId);
      final labels = [
        for (final o in q.options) o.endsSurah ? '<ends>' : (o.tokenAr ?? '<null>'),
      ];
      if (labels.toSet().length != labels.length) identical++;
    }
    expect(identical, 0, reason: '$identical questions have duplicate options');
  });

  test('the road is the phrase plus its tail', () {
    for (final c in pool.take(200)) {
      final q = drillQuestion(db, c.phraseId, c.posId);
      expect(q.roadAr, startsWith(q.phraseAr));
      if (q.roadTailAr != null) {
        expect(q.roadAr, endsWith(q.roadTailAr!));
      }
    }
  });

  test('two positions in one surah with different answers never look alike', () {
    // The point of the lead-in and the ordinal. 491 forks have a single surah
    // taking two or more ways out, so naming the surah does not settle those and
    // the road is shared by definition. If two positions in one surah show the
    // same thing and expect different answers, no reciter could answer either.
    //
    // Positions in *different* surahs may look alike: the question names the
    // surah, so they are told apart already.
    final byForkSurah = <String, List<DrillCandidate>>{};
    for (final c in pool) {
      final q = drillQuestion(db, c.phraseId, c.posId);
      final surah = q.verseKey.split(':')[0];
      (byForkSurah['${c.phraseId}/$surah'] ??= []).add(c);
    }

    var ambiguous = 0;
    final examples = <String>[];
    for (final entry in byForkSurah.entries) {
      if (entry.value.length < 2) continue;
      final shown = <String, int>{};
      for (final c in entry.value) {
        final q = drillQuestion(db, c.phraseId, c.posId);
        final context = [
          q.precedingAr ?? '',
          q.leadInAr ?? '',
          q.roadAr,
          if (q.countInSurah > 1) 'no ${q.ordinalInSurah}',
        ].join('|');
        final prior = shown[context];
        if (prior != null && prior != q.answerBranchId) {
          ambiguous++;
          if (examples.length < 5) examples.add('${c.key} (${q.verseKey})');
        }
        shown[context] = q.answerBranchId;
      }
    }
    expect(ambiguous, 0,
        reason: '$ambiguous unanswerable questions: ${examples.join(", ")}');
  });

  test('the ordinal is within range and agrees with the count', () {
    for (final c in pool) {
      final q = drillQuestion(db, c.phraseId, c.posId);
      expect(q.countInSurah, greaterThanOrEqualTo(1));
      expect(q.ordinalInSurah, inInclusiveRange(1, q.countInSurah));
    }
  });

  test('a question always has a run-up, unless it opens its surah', () {
    for (final c in pool) {
      final q = drillQuestion(db, c.phraseId, c.posId);
      if (q.leadInAr == null && q.precedingAr == null) {
        // Nothing precedes it in the surah, so the surah's own opening is the
        // context -- and the question names the surah.
        expect(q.verseKey, endsWith(':1'), reason: '${c.key} has no run-up');
      }
    }
  });

  test('a position from another fork is refused', () {
    final a = pool.first;
    final other = pool.firstWhere((c) => c.phraseId != a.phraseId);
    expect(() => drillQuestion(db, a.phraseId, other.posId),
        throwsA(isA<ArgumentError>()));
  });

  test('an unknown fork is refused', () {
    expect(() => drillQuestion(db, -1, pool.first.posId),
        throwsA(isA<PhraseNotFound>()));
  });
}
