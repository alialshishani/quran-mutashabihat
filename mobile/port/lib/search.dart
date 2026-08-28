// Finding an āyah by its wording.
//
// `words.text_norm` is the index key `pipeline/normalize.py` wrote, so a search
// has to turn what the reader types into the same key. This is a port of that
// module's `standard` profile, with one deliberate gap: Dart has no Unicode
// normalisation in its SDK, so the two NFC passes are missing.
//
// That matters less than it sounds, and `bin/verify_normalize.dart` measures
// exactly how much: the NFC passes exist to recompose the Uthmānī rasm's
// decomposed spellings, which a reader typing on an Arabic keyboard does not
// produce. What they type composes already.
//
// The corpus side is unaffected either way -- `text_norm` is read, never
// recomputed here.

import 'package:sqlite3/common.dart';

// Phonetic diacritics, stripped at `standard`.
final RegExp _harakat = RegExp(
  '[ً-ْٗ-ٟ]',
);

// Waqf signs, sajdah marks, rub' marks, end-of-āyah: reciter's instructions,
// not letters.
final RegExp _annotation = RegExp(
  '[ؐ-ؚۖ-ۜ۝۞۟-ۤ'
  'ۧۨ۩۪-ࣰۭ-ࣳ]',
);

// Superscript alif and the small wāw/yā', plus maddah.
final RegExp _superscript = RegExp('[ٰۥۦٖٓ]');

// Zero-width marks and the tatweel elongation. Purely presentational.
final RegExp _invisible = RegExp('[​-‏⁠﻿ـ]');

// Hamza above/below left stranded once their seat letter is stripped.
final RegExp _orphanHamza = RegExp('[ٕٔ]');

final RegExp _alif = RegExp('[آأإٱٲٳٵ]');
final RegExp _space = RegExp(r'\s+');

/// The `standard` profile of pipeline/normalize.py, less its NFC passes.
String normalizeStandard(String token) {
  var out = token;
  out = out.replaceAll(_annotation, '');
  out = out.replaceAll(_invisible, '');
  out = out.replaceAll(_harakat, '');
  out = out.replaceAll(_superscript, '');
  out = out.replaceAll(_orphanHamza, '');
  out = out.replaceAll(_alif, 'ا');
  out = out.replaceAll('ة', 'ه'); // ة -> ه
  out = out.replaceAll('ى', 'ي'); // ى -> ي
  out = out.replaceAll(_space, ' ').trim();
  return out.replaceAll(' ', '');
}

/// One āyah matching a search.
class SearchHit {
  SearchHit({
    required this.verseKey,
    required this.surah,
    required this.ayah,
    required this.surahNameAr,
    required this.page,
    required this.textAr,
  });

  final String verseKey;
  final int surah;
  final int ayah;
  final String surahNameAr;
  final int page;

  /// The āyah as it is printed -- `text_uthmani`, never the index key.
  final String textAr;
}

/// Āyāt whose wording contains [query], in muṣḥaf order.
///
/// Matched against `search_ayat`, which `mobile/tools/stage_assets.py` builds
/// from `text_imlaei` using `pipeline.normalize` itself. So the stored key and
/// the query key are made by the same rules, and the reader is matched against
/// the spelling they type rather than against the Uthmānī rasm.
List<SearchHit> searchAyat(
  CommonDatabase db,
  String query, {
  int limit = 50,
}) {
  final key = normalizeStandard(query);
  if (key.isEmpty) return const [];
  if (db
      .select("SELECT name FROM sqlite_master WHERE type='table' "
          "AND name='search_ayat'")
      .isEmpty) {
    return const [];
  }

  final rows = db.select(
    'SELECT a.verse_key, a.surah, a.ayah, a.page_start, s.name_ar, '
    '       group_concat(w.text_uthmani, " ") AS text_ar '
    'FROM search_ayat x '
    'JOIN ayahs a ON a.verse_key = x.verse_key '
    'JOIN surahs s ON s.surah = a.surah '
    'JOIN words w ON w.word_id BETWEEN a.first_word_id AND a.last_word_id '
    'WHERE x.norm LIKE ? '
    'GROUP BY a.verse_key ORDER BY a.first_word_id LIMIT ?',
    ['%$key%', limit],
  );

  return [
    for (final r in rows)
      SearchHit(
        verseKey: r['verse_key'] as String,
        surah: r['surah'] as int,
        ayah: r['ayah'] as int,
        surahNameAr: r['name_ar'] as String,
        page: r['page_start'] as int,
        textAr: r['text_ar'] as String,
      ),
  ];
}
