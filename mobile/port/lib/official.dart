// A port of app/lookup.py's `official_matches` and the helpers it leans on.
//
// This is the section the muṣḥaf panel is for: the official mutashābih phrases
// touching an āyah, every other place each one occurs, and for each of those
// positions the peg that tells it from its siblings.
//
// Literal, like mushaf.dart, and for the same reason -- it is checked against
// the Python's own output rather than merely reviewed.

import 'dart:convert';

import 'package:sqlite3/common.dart';

import 'forks.dart' show Stand, forkStands;

class AyahNotFound implements Exception {
  AyahNotFound(this.message);
  final String message;
  @override
  String toString() => 'AyahNotFound: $message';
}

/// Per-request word cache. One query per contiguous range asked for.
class Words {
  Words(this._db);

  final CommonDatabase _db;
  final Map<int, Row> _rows = {};

  void loadRange(int first, int last) {
    var missing = false;
    for (var w = first; w <= last; w++) {
      if (!_rows.containsKey(w)) {
        missing = true;
        break;
      }
    }
    if (!missing) return;

    for (final row in _db.select(
      'SELECT word_id, surah, ayah, word_pos, text_uthmani, text_norm '
      'FROM words WHERE word_id BETWEEN ? AND ?',
      [first, last],
    )) {
      _rows[row['word_id'] as int] = row;
    }
  }

  Row? get(int wordId) {
    if (!_rows.containsKey(wordId)) loadRange(wordId, wordId);
    return _rows[wordId];
  }

  List<String> text(int first, int last) {
    loadRange(first, last);
    return [
      for (var w = first; w <= last; w++) _rows[w]!['text_uthmani'] as String,
    ];
  }

  /// The token at `wordId`, but only if it lies inside the same sūrah. A token
  /// on the far side of a sūrah seam is not part of the phrase.
  String? neighbour(int wordId, int surah) {
    final row = get(wordId);
    if (row == null || row['surah'] != surah) return null;
    return row['text_uthmani'] as String;
  }

  /// The `count` tokens the muṣḥaf prints after `wordId`, stopping at the end
  /// of the sūrah.
  ///
  /// What a place says next does not stop at its āyah, and neither can the
  /// answer to which place you are in. Five places share `وَٱتَّقُوا۟ ٱللَّهَ
  /// لَعَلَّكُمْ` and three of them go on `تُفْلِحُونَ`, so a tail cut at the āyah
  /// tells those three apart from nothing at all.
  List<Map<String, Object?>> following(int wordId, int surah, int count) {
    loadRange(wordId, wordId + count - 1);
    final out = <Map<String, Object?>>[];
    for (var w = wordId; w < wordId + count; w++) {
      final row = get(w);
      if (row == null || row['surah'] != surah) break;
      out.add({
        'word_id': row['word_id'],
        'text': row['text_uthmani'],
        'norm': row['text_norm'],
      });
    }
    return out;
  }
}

/// Whether `pipeline.official` and `pipeline.pegs` have run on this corpus.
///
/// All three tables, and `pegs` actually populated -- the same test the Python
/// makes. Checking only the two phrase tables would say yes on a corpus where
/// `pipeline.pegs` had not run, and every position would come back peg-less.
bool hasOfficialTables(CommonDatabase db) {
  final present = db
      .select("SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name IN ('official_phrases', 'official_positions', 'pegs')")
      .map((r) => r['name'] as String)
      .toSet();
  if (present.length < 3) return false;
  return db.select('SELECT 1 FROM pegs LIMIT 1').isNotEmpty;
}

List<Row> ayahWordsOf(CommonDatabase db, String verseKey, Words words) =>
    _ayahWords(db, verseKey, words);

List<Row> _ayahWords(CommonDatabase db, String verseKey, Words words) {
  final b = db.select(
    'SELECT first_word_id, last_word_id FROM ayahs WHERE verse_key = ?',
    [verseKey],
  ).first;
  final first = b['first_word_id'] as int;
  final last = b['last_word_id'] as int;
  words.loadRange(first, last);
  return [for (var w = first; w <= last; w++) words.get(w)!];
}

/// One position of a group: the āyah(s) it sits in, with the span marked.
Map<String, Object?> position(
  CommonDatabase db,
  Words words, {
  required int start,
  required int end,
  required String verseKey,
  required int? page,
  required int? line,
  required Map<int, String> surahNames,
  required Map<String, int> juzOf,
}) {
  words.loadRange(start, end);
  final surah = int.parse(verseKey.split(':')[0]);

  final covered = <String>[];
  for (var w = start; w <= end; w++) {
    final row = words.get(w)!;
    final key = '${row['surah']}:${row['ayah']}';
    if (!covered.contains(key)) covered.add(key);
  }

  final ayat = <Map<String, Object?>>[];
  for (final key in covered) {
    final parts = key.split(':');
    final s = int.parse(parts[0]);
    final a = int.parse(parts[1]);
    ayat.add({
      'verse_key': key,
      'surah': s,
      'surah_name_ar': surahNames[s],
      'ayah': a,
      'juz': juzOf[key],
      'words': [
        for (final row in _ayahWords(db, key, words))
          {
            'word_id': row['word_id'],
            'word_pos': row['word_pos'],
            'text': row['text_uthmani'],
            // What two spellings of one word are compared on. The curated
            // list groups by root, so a caller that wants to know whether two
            // places really say the same word has to be able to ask.
            'norm': row['text_norm'],
            'in_span': start <= (row['word_id'] as int) &&
                (row['word_id'] as int) <= end,
          },
      ],
    });
  }

  // The last word of the last āyah this position sits in. What follows it is
  // the next āyah, and that is where a short tail has to keep reading.
  final ayahEnd = ((ayat.last['words'] as List)
      .cast<Map<String, Object?>>()
      .last['word_id'] as int);

  return {
    'verse_key': verseKey,
    'surah': surah,
    'surah_name_ar': surahNames[surah],
    'ayah': int.parse(verseKey.split(':')[1]),
    'page': page,
    'line': line,
    'juz': juzOf[verseKey],
    'start_word_id': start,
    'end_word_id': end,
    'span_text': words.text(start, end).join(' '),
    // In recitation order: `before` precedes the span, `after` follows it.
    'before': words.neighbour(start - 1, surah),
    'after': words.neighbour(end + 1, surah),
    // And what the muṣḥaf prints after the last āyah this position sits in, so
    // a tail can read on past its own āyah. Taken from the āyah's end rather
    // than the span's, so it never repeats what `ayat` already carries and can
    // simply be added to it.
    'after_words': words.following(ayahEnd + 1, surah, 8),
    'crosses_ayah': covered.length > 1,
    'ayat': ayat,
  };
}

Map<String, Object?>? peg(Row row) {
  if (row['kind'] == null) return null;
  final ev = row['evidence'];
  return {
    'kind': row['kind'],
    'cue_ar': row['cue_ar'],
    'cue_window': row['cue_window'],
    'continuation_ar': row['continuation_ar'],
    'continuation_unique': (row['continuation_unique'] as int? ?? 0) != 0,
    'strength': row['strength'],
    'text_ar': row['text_ar'],
    'evidence': (ev == null || (ev as String).isEmpty) ? null : json.decode(ev),
  };
}

Map<int, String> surahNamesOf(CommonDatabase db) => {
      for (final r in db.select('SELECT surah, name_ar FROM surahs'))
        r['surah'] as int: r['name_ar'] as String,
    };

Map<String, int> juzOfAll(CommonDatabase db) => {
      for (final r in db.select('SELECT verse_key, juz FROM ayahs'))
        r['verse_key'] as String: r['juz'] as int,
    };

/// Official mutashābih phrases touching this āyah, each position with its peg.
/// What the panel and the drill both need to say about a fork, as plain data.
Map<String, Object?> _forkOf(Stand s) => {
      'shape': s.shape,
      'places': s.places,
      'mine': s.mine,
      'others': s.others,
      'turn': s.turn,
      'ends_surah': s.endsSurah,
      // The last word every place on this road still says alike. The curated
      // span can stop short of it, so a panel that wants to print what each
      // place says *after* the road cannot get the split from the span alone.
      'road_end': s.roadEnd,
      'danger': s.danger,
      'rivals': [
        for (final r in s.rivals)
          {'token': r.token, 'places': r.places, 'ends_surah': r.endsSurah},
      ],
    };

List<Map<String, Object?>> officialMatches(
  CommonDatabase db,
  int surah,
  int ayah,
  Words words,
  Map<int, String> surahNames,
  Map<String, int> juzOf,
) {
  final bounds = db.select(
    'SELECT first_word_id, last_word_id FROM ayahs WHERE surah = ? AND ayah = ?',
    [surah, ayah],
  );
  if (bounds.isEmpty) {
    throw AyahNotFound('$surah:$ayah is not an ayah in the mushaf');
  }
  final first = bounds.first['first_word_id'] as int;
  final last = bounds.first['last_word_id'] as int;

  final hits = db.select(
    'SELECT DISTINCT phrase_id FROM official_positions '
    'WHERE start_word_id <= ? AND end_word_id >= ?',
    [last, first],
  );

  final out = <Map<String, Object?>>[];
  for (final hit in hits) {
    final phraseId = hit['phrase_id'] as int;
    final phrase = db.select(
      'SELECT * FROM official_phrases WHERE phrase_id = ?',
      [phraseId],
    ).first;

    final positions = <Map<String, Object?>>[];
    for (final row in db.select(
      'SELECT o.*, p.kind, p.cue_ar, p.cue_window, p.continuation_ar, '
      '       p.continuation_unique, p.strength, p.text_ar, p.evidence '
      'FROM official_positions o LEFT JOIN pegs p ON p.pos_id = o.pos_id '
      'WHERE o.phrase_id = ? ORDER BY o.start_word_id',
      [phraseId],
    )) {
      final start = row['start_word_id'] as int;
      final end = row['end_word_id'] as int;
      final p = position(
        db,
        words,
        start: start,
        end: end,
        verseKey: row['verse_key'] as String,
        page: row['page'] as int?,
        line: null,
        surahNames: surahNames,
        juzOf: juzOf,
      );
      p['pos_id'] = row['pos_id'];
      p['in_official'] = (row['in_official'] as int? ?? 0) != 0;
      p['in_exact'] = (row['in_exact'] as int? ?? 0) != 0;
      p['group_id'] = row['group_id'];
      p['link'] = row['link'];
      p['is_query'] = start <= last && end >= first;
      p['peg'] = peg(row);
      positions.add(p);
    }

    // Where each of these places stands at the fork it shares: what it turns
    // on, what the others turn on, and how far it is from the crowd. This is
    // what makes one of an ayah's phrases the one that trips a reciter and the
    // rest a reference list.
    final stands = forkStands(
      db,
      posIds: [for (final p in positions) p['pos_id'] as int],
    );
    for (final p in positions) {
      final s = stands[p['pos_id'] as int];
      p['fork'] = s == null ? null : _forkOf(s);
    }

    final here = positions.where((p) => p['is_query'] == true).toList();
    out.add({
      'phrase_id': phrase['phrase_id'],
      'source': phrase['source'],
      'text_ar': phrase['text_ar'],
      'span_len': phrase['span_len'],
      'set_count': phrase['set_count'],
      'official_count': phrase['official_count'],
      'exact_count': phrase['exact_count'],
      'surah_count': phrase['surah_count'],
      'here': here,
      'elsewhere': positions.where((p) => p['is_query'] != true).toList(),
      'positions': positions,
      'danger': here.isEmpty
          ? 0.0
          : here
              .map((p) => ((p['fork'] as Map?)?['danger'] as num? ?? 0).toDouble())
              .reduce((a, b) => a > b ? a : b),
    });
  }

  // Strongest peg for the position in this āyah first; a wider confusion set is
  // the more urgent one to hold apart.
  num strongest(Map<String, Object?> p) {
    final here = p['here'] as List;
    if (here.isEmpty) return 0;
    num best = 0;
    var first = true;
    for (final h in here) {
      final pg = (h as Map)['peg'] as Map?;
      final s = pg == null ? 0 : (pg['strength'] as num? ?? 0);
      if (first || s > best) {
        best = s;
        first = false;
      }
    }
    return best;
  }

  out.sort((a, b) {
    // How far this ayah's place stands from the crowd, first. An ayah can carry
    // five curated phrases and be at risk from one of them; that one leads, and
    // the rest are reference. Below it the Python's order is kept: strongest
    // peg, then the wider confusion set, then phrase_id.
    final da = -(a['danger'] as double);
    final dbg = -(b['danger'] as double);
    if (da != dbg) return da.compareTo(dbg);
    final ka = -strongest(a);
    final kb = -strongest(b);
    if (ka != kb) return ka.compareTo(kb);
    final sa = -(a['set_count'] as int);
    final sb = -(b['set_count'] as int);
    if (sa != sb) return sa.compareTo(sb);
    return (a['phrase_id'] as int).compareTo(b['phrase_id'] as int);
  });
  return out;
}
