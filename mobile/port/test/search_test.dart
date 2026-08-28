// Search matches what a reader types against `search_ayat`, which
// stage_assets.py built with pipeline.normalize over the imlaei text.
//
//   dart test --define=db=../app/assets/app.db
//
// Needs the staged database, not data/quran.db: the search index is a build
// step, so the pipeline's own output does not carry it.

import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'package:quran_port/search.dart';

const String _dbPath =
    String.fromEnvironment('db', defaultValue: '../app/assets/app.db');

void main() {
  if (!File(_dbPath).existsSync()) {
    test('staged corpus not built', () {}, skip: 'no $_dbPath');
    return;
  }

  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open('winsqlite3.dll'),
  );
  final db = sqlite3.open(_dbPath, mode: OpenMode.readOnly);

  test('the normalizer strips what it should', () {
    // Harakat, tatweel and the annotation marks all go; the letters stay.
    expect(normalizeStandard('ٱلْحَمْدُ'), 'الحمد');
    expect(normalizeStandard('الرَّحْمَٰنِ'), 'الرحمن');
    // ة -> ه and ى -> ي, as the standard profile folds them.
    expect(normalizeStandard('الصلاة'), 'الصلاه');
    expect(normalizeStandard('موسى'), 'موسي');
    expect(normalizeStandard('  '), '');
  });

  test('a phrase typed plainly finds the ayah it is in', () {
    final hits = searchAyat(db, 'الحمد لله رب العالمين');
    expect(hits, isNotEmpty);
    expect(hits.map((h) => h.verseKey), contains('1:2'));
  });

  test('diacritics in the query do not change the result', () {
    final plain = searchAyat(db, 'مالك يوم الدين');
    final vowelled = searchAyat(db, 'مَالِكِ يَوْمِ الدِّينِ');
    expect(plain.map((h) => h.verseKey).toList(),
        vowelled.map((h) => h.verseKey).toList());
    expect(plain.map((h) => h.verseKey), contains('1:4'));
  });

  test('a phrase that repeats returns every ayah it is in', () {
    // فبأي آلاء ربكما تكذبان -- 31 times in ar-Rahman, and nowhere else.
    final hits = searchAyat(db, 'فبأي آلاء ربكما تكذبان', limit: 100);
    expect(hits.length, 31);
    expect(hits.every((h) => h.surah == 55), isTrue);
  });

  test('results carry the printed text, not the index key', () {
    final hits = searchAyat(db, 'الحمد لله رب العالمين');
    // text_uthmani, so it still has its harakat.
    expect(hits.first.textAr, isNot(equals(normalizeStandard(hits.first.textAr))));
    expect(hits.first.page, greaterThan(0));
  });

  test('nothing, and too little, return nothing', () {
    expect(searchAyat(db, ''), isEmpty);
    expect(searchAyat(db, '   '), isEmpty);
    expect(searchAyat(db, 'زقزقزقزقزق'), isEmpty);
  });

  test('the limit is honoured', () {
    final few = searchAyat(db, 'الله', limit: 5);
    expect(few.length, 5);
  });
}
