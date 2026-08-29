// A port of app/lookup.py's mushaf_page and its helpers.
//
// Deliberately literal. Where the Python builds a dict in a particular order,
// walks a source id range, or lets a query's natural order decide, this does
// the same thing the same way -- because the point is not to write idiomatic
// Dart, it is to produce byte-identical output and so prove the port.
//
// No Qur'anic text is composed here either: every token arrives from the
// database, as it does on the Python side.

import 'package:sqlite3/common.dart';

/// The basmalah is read out of the corpus at this key rather than written here.
const String kBasmalahKey = '1:1';
const String kDefaultScope = 'full';

class PageNotFound implements Exception {
  PageNotFound(this.message);
  final String message;
  @override
  String toString() => 'PageNotFound: $message';
}

class LayoutMissing implements Exception {
  LayoutMissing(this.message);
  final String message;
  @override
  String toString() => 'LayoutMissing: $message';
}

// Answered once per database. The Python asks `SELECT COUNT(*) FROM x LIMIT 1`,
// which the LIMIT does not shorten -- the aggregate still counts every row, so
// asking whether `glyphs` is populated walks all 83,665 of them, on every page
// turn. `SELECT 1 ... LIMIT 1` stops at the first row and answers the same
// question; caching it means later page turns do not ask at all.
final _tableHasRowsCache = <CommonDatabase, Map<String, bool>>{};

bool _tableHasRows(CommonDatabase db, String name) =>
    (_tableHasRowsCache[db] ??= {}).putIfAbsent(name, () {
      final present = db.select(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        [name],
      );
      if (present.isEmpty) return false;
      return db.select('SELECT 1 FROM "$name" LIMIT 1').isNotEmpty;
    });

bool hasLayout(CommonDatabase db) => _tableHasRows(db, 'lines');
bool hasGlyphs(CommonDatabase db) => _tableHasRows(db, 'glyphs');

// The Python's `_has_official` also requires `pegs` to be populated. Checking
// only the two phrase tables would answer yes on a corpus where pipeline.pegs
// had not run, and mark the page for phrases whose positions carry no peg.
bool hasOfficial(CommonDatabase db) =>
    _tableHasRows(db, 'official_phrases') &&
    _tableHasRows(db, 'official_positions') &&
    _tableHasRows(db, 'pegs');

int pageCount(CommonDatabase db) {
  if (!hasLayout(db)) return 0;
  final v = db.select('SELECT MAX(page) AS m FROM lines').first['m'];
  return (v as int?) ?? 0;
}

// The widest span in each table, read once per database.
//
// The Python asks for every occurrence with `start_word_id <= last_word_id`,
// which on a late page is nearly the whole table, and only then discards the
// ones that end too early. Since no span is wider than this, an occurrence that
// overlaps the ayah must START within `maxSpan` words of it, and the open-ended
// scan becomes a bounded one on the index that already exists. The result set is
// identical -- the bound is derived from the data, not assumed.
final _spans = <CommonDatabase, ({int occ, int official})>{};

({int occ, int official}) _maxSpans(CommonDatabase db) => _spans.putIfAbsent(db, () {
      int widest(String table) {
        if (!_tableHasRows(db, table)) return 0;
        final v = db
            .select('SELECT MAX(end_word_id - start_word_id) AS m FROM "$table"')
            .first['m'];
        return (v as int?) ?? 0;
      }

      return (occ: widest('occurrences'), official: widest('official_positions'));
    });

/// Per ayah on the page: how much there is to confuse it with.
Map<String, Map<String, int>> _pageMarks(
  CommonDatabase db,
  List<String> keys,
  String scope,
) {
  final marks = <String, Map<String, int>>{
    for (final k in keys) k: {'official': 0, 'phrases': 0},
  };
  if (keys.isEmpty) return marks;
  final holes = List.filled(keys.length, '?').join(',');
  final span = _maxSpans(db);

  if (hasOfficial(db)) {
    final rows = db.select(
      'SELECT a.verse_key AS k, COUNT(DISTINCT o.phrase_id) AS c '
      'FROM ayahs a JOIN official_positions o '
      '  ON o.start_word_id BETWEEN a.first_word_id - ${span.official} AND a.last_word_id '
      '  AND o.end_word_id >= a.first_word_id '
      'WHERE a.verse_key IN ($holes) GROUP BY a.verse_key',
      keys,
    );
    for (final r in rows) {
      marks[r['k'] as String]!['official'] = r['c'] as int;
    }
  }

  final rows = db.select(
    'SELECT a.verse_key AS k, COUNT(DISTINCT o.group_id) AS c '
    'FROM ayahs a JOIN occurrences o '
    '  ON o.start_word_id BETWEEN a.first_word_id - ${span.occ} AND a.last_word_id '
    '  AND o.end_word_id >= a.first_word_id '
    'JOIN groups g ON g.group_id = o.group_id AND g.scope = ? '
    'WHERE a.verse_key IN ($holes) GROUP BY a.verse_key',
    [scope, ...keys],
  );
  for (final r in rows) {
    marks[r['k'] as String]!['phrases'] = r['c'] as int;
  }
  return marks;
}

// The read path also wants three indexes `pipeline/` does not create, on
// ayahs(juz), ayahs(hizb) and ayahs(rub). They live in
// mobile/tools/read_path_indexes.sql, applied by tools/stage_assets.py when the
// shipped database is built. They change no result, only what a page turn costs.


List<Map<String, Object?>> _basmalah(CommonDatabase db) {
  final rows = db.select(
    'SELECT w.word_id, w.text_uthmani FROM words w, ayahs a '
    'WHERE a.verse_key = ? AND w.word_id BETWEEN a.first_word_id AND a.last_word_id '
    'ORDER BY w.word_id',
    [kBasmalahKey],
  );
  return [
    for (final r in rows)
      {'word_id': r['word_id'], 'text': r['text_uthmani']},
  ];
}

/// One printed page: its lines, the tokens on each, and what repeats there.
/// The glyph codes of one token, with nothing between them.
///
/// A word the font sets as two glyphs is stored as its two codes separated by
/// a space -- `pipeline.glyphs` writes them that way, and 198 tokens are like
/// it. That space is a separator in the record, not a glyph on the line: the
/// KFGQPC faces carry their own side bearings, which is why every other token
/// is set against its neighbour with nothing added between them. Left in, it
/// sets one line of the page a word-space too wide, and since the page takes
/// its type size from its widest line, that one space shrinks the whole page
/// -- on 177 by 8%, with every other line then falling short of the measure.
String? _code(String? code) => code?.replaceAll(' ', '');

Map<String, Object?> mushafPage(
  CommonDatabase db,
  int page, {
  String scope = kDefaultScope,
}) {
  if (!hasLayout(db)) {
    throw LayoutMissing('no page layout; run: python -m pipeline.layout --rebuild');
  }
  final total = pageCount(db);
  if (page < 1 || page > total) {
    throw PageNotFound('page $page is outside the mushaf (1-$total)');
  }

  final rows = db.select(
    'SELECT line, line_type, is_centered, surah, src_first, src_last '
    'FROM lines WHERE page = ? ORDER BY line',
    [page],
  );

  // Keyed by src_word_id, in word_id order -- the Python relies on that order
  // for min/max below, so the insertion order is load-bearing.
  final words = <int, Row>{};
  for (final r in db.select(
    'SELECT word_id, src_word_id, surah, ayah, word_pos, text_uthmani '
    'FROM words WHERE page = ? ORDER BY word_id',
    [page],
  )) {
    words[r['src_word_id'] as int] = r;
  }

  final ids = [for (final r in words.values) r['word_id'] as int];
  final firstWord = ids.isEmpty ? 0 : ids.reduce((a, b) => a < b ? a : b);
  final lastWord = ids.isEmpty ? -1 : ids.reduce((a, b) => a > b ? a : b);

  final srcFirsts = [
    for (final r in rows)
      if (r['src_first'] != null) r['src_first'] as int,
  ];
  final srcLasts = [
    for (final r in rows)
      if (r['src_last'] != null) r['src_last'] as int,
  ];
  final srcLo = srcFirsts.isEmpty ? 1 : srcFirsts.reduce((a, b) => a < b ? a : b);
  final srcHi = srcLasts.isEmpty ? 0 : srcLasts.reduce((a, b) => a > b ? a : b);

  // A marker carries no row in `words`; its source id is one past the last word
  // of the ayah it closes, which is enough to place it.
  final markers = <int, List<int>>{};
  for (final r in db.select(
    'SELECT a.surah, a.ayah, w.src_word_id + 1 AS src FROM ayahs a '
    'JOIN words w ON w.word_id = a.last_word_id '
    'WHERE w.src_word_id + 1 BETWEEN ? AND ?',
    [srcLo, srcHi],
  )) {
    markers[r['src'] as int] = [r['surah'] as int, r['ayah'] as int];
  }

  // Which words on this page sit inside an official mutashabih phrase.
  final phrasesAt = <int, List<int>>{};
  if (ids.isNotEmpty && hasOfficial(db)) {
    // ORDER BY is not in the Python, and its absence is a live bug there: the
    // order rows come back in decides the order of `phrase_ids` in the response,
    // so the API's output changes if the query plan changes -- which adding an
    // index, running ANALYZE, or shipping a different SQLite version all do. It
    // was reproduced here: 66 pages reorder under the read-path indexes, with no
    // difference in content. Ordering explicitly costs nothing and fixes it.
    for (final hit in db.select(
      'SELECT phrase_id, start_word_id, end_word_id FROM official_positions '
      'WHERE start_word_id <= ? AND end_word_id >= ? '
      'ORDER BY start_word_id, phrase_id',
      [lastWord, firstWord],
    )) {
      final lo = [hit['start_word_id'] as int, firstWord].reduce((a, b) => a > b ? a : b);
      final hi = [hit['end_word_id'] as int, lastWord].reduce((a, b) => a < b ? a : b);
      for (var wordId = lo; wordId <= hi; wordId++) {
        (phrasesAt[wordId] ??= <int>[]).add(hit['phrase_id'] as int);
      }
    }
  }

  // Where the KFGQPC glyphs are bound they are what the line is made of, and
  // the font's own record of which line a token sits on is what orders them.
  final glyphLines = <int, List<Map<String, Object?>>>{};
  if (hasGlyphs(db)) {
    for (final row in db.select(
      'SELECT g.line, g.kind, g.word_id, g.verse_key, g.code_v1, '
      '       w.surah, w.ayah, w.word_pos, w.text_uthmani '
      'FROM glyphs g LEFT JOIN words w ON w.word_id = g.word_id '
      'WHERE g.page = ? ORDER BY g.line, g.ordinal',
      [page],
    )) {
      final key = row['verse_key'] as String;
      final parts = key.split(':');
      final surah = int.parse(parts[0]);
      final ayah = int.parse(parts[1]);

      final Map<String, Object?> token;
      if (row['kind'] == 'word') {
        token = {
          'kind': 'word',
          'word_id': row['word_id'],
          'verse_key': key,
          'surah': surah,
          'ayah': ayah,
          'word_pos': row['word_pos'],
          'text': row['text_uthmani'],
          'code': _code(row['code_v1'] as String?),
          'phrase_ids': <int>[],
        };
      } else {
        token = {
          // `end` is an āyah marker; `sign` is a mark the font sets at the head
          // of a line although it trails the word that closed the one before —
          // the sajdah on page 454. Neither is a word, and neither is a tap
          // target, but only one of them is a marker.
          'kind': row['kind'] == 'end' ? 'marker' : 'sign',
          'verse_key': key,
          'surah': surah,
          'ayah': ayah,
          'code': _code(row['code_v1'] as String?),
        };
      }
      (glyphLines[row['line'] as int] ??= []).add(token);
    }
  }

  final surahRows = <int, Row>{};
  for (final r in db.select('SELECT * FROM surahs ORDER BY surah')) {
    surahRows[r['surah'] as int] = r;
  }

  final keys = <String>[];
  final lines = <Map<String, Object?>>[];

  for (final row in rows) {
    final lineNo = row['line'] as int;
    final lineType = row['line_type'] as String;
    final line = <String, Object?>{
      'line': lineNo,
      'type': lineType,
      'centered': (row['is_centered'] as int) != 0,
    };

    if (lineType == 'surah_name') {
      final surah = surahRows[row['surah'] as int]!;
      line['surah'] = surah['surah'];
      line['name_ar'] = surah['name_ar'];
      line['ayah_count'] = surah['ayah_count'];
      line['revelation_place'] = surah['revelation_place'];
    } else if (lineType == 'basmallah') {
      line['words'] = _basmalah(db);
    } else if (glyphLines.containsKey(lineNo)) {
      final tokens = glyphLines[lineNo]!;
      for (final token in tokens) {
        if (token['kind'] != 'word') continue;
        final key = token['verse_key'] as String;
        if (!keys.contains(key)) keys.add(key);
        token['phrase_ids'] = phrasesAt[token['word_id'] as int] ?? <int>[];
      }
      line['tokens'] = tokens;
    } else {
      final tokens = <Map<String, Object?>>[];
      for (var src = row['src_first'] as int; src <= (row['src_last'] as int); src++) {
        final word = words[src];
        if (word != null) {
          final key = '${word['surah']}:${word['ayah']}';
          if (!keys.contains(key)) keys.add(key);
          tokens.add({
            'kind': 'word',
            'word_id': word['word_id'],
            'verse_key': key,
            'surah': word['surah'],
            'ayah': word['ayah'],
            'word_pos': word['word_pos'],
            'text': word['text_uthmani'],
            'phrase_ids': phrasesAt[word['word_id'] as int] ?? <int>[],
          });
        } else if (markers.containsKey(src)) {
          final m = markers[src]!;
          tokens.add({
            'kind': 'marker',
            'verse_key': '${m[0]}:${m[1]}',
            'surah': m[0],
            'ayah': m[1],
          });
        }
      }
      line['tokens'] = tokens;
    }
    lines.add(line);
  }

  // Where a juz', hizb or rub' opens -- at whichever of its ayat comes first.
  final meta = <String, Row>{};
  if (keys.isNotEmpty) {
    final holes = List.filled(keys.length, '?').join(',');
    for (final r in db.select(
      'SELECT verse_key, juz, hizb, rub, '
      '  first_word_id = (SELECT MIN(x.first_word_id) FROM ayahs x '
      '                   WHERE x.juz = a.juz) AS starts_juz, '
      '  first_word_id = (SELECT MIN(x.first_word_id) FROM ayahs x '
      '                   WHERE x.hizb = a.hizb) AS starts_hizb, '
      '  first_word_id = (SELECT MIN(x.first_word_id) FROM ayahs x '
      '                   WHERE x.rub = a.rub) AS starts_rub '
      'FROM ayahs a WHERE verse_key IN ($holes)',
      keys,
    )) {
      meta[r['verse_key'] as String] = r;
    }
  }
  final marks = _pageMarks(db, keys, scope);

  final ayat = <Map<String, Object?>>[];
  for (final key in keys) {
    final parts = key.split(':');
    final surah = int.parse(parts[0]);
    final ayah = int.parse(parts[1]);
    final m = meta[key]!;
    ayat.add({
      'verse_key': key,
      'surah': surah,
      'ayah': ayah,
      'surah_name_ar': surahRows[surah]!['name_ar'],
      'juz': m['juz'],
      'hizb': m['hizb'],
      'rub': m['rub'],
      'starts_juz': (m['starts_juz'] as int) != 0,
      'starts_hizb': (m['starts_hizb'] as int) != 0,
      'starts_rub': (m['starts_rub'] as int) != 0,
      'official': marks[key]!['official'],
      'phrases': marks[key]!['phrases'],
    });
  }

  final onPage = <int>{
    for (final a in ayat) a['surah'] as int,
    for (final line in lines)
      if (line['type'] == 'surah_name') line['surah'] as int,
  }.toList()
    ..sort();

  return {
    'page': page,
    'pages': total,
    'prev': page > 1 ? page - 1 : null,
    'next': page < total ? page + 1 : null,
    'lines_printed': lines.length,
    'glyph_font': glyphLines.isNotEmpty ? '/fonts/qcf-v1/p$page.woff2' : null,
    'juz': ayat.isNotEmpty ? ayat[0]['juz'] : null,
    'hizb': ayat.isNotEmpty ? ayat[0]['hizb'] : null,
    'surahs': [
      for (final s in onPage)
        {
          'surah': s,
          'name_ar': surahRows[s]!['name_ar'],
          'ayah_count': surahRows[s]!['ayah_count'],
          'revelation_place': surahRows[s]!['revelation_place'],
        },
    ],
    'counts': {
      'ayat': ayat.length,
      'with_official': ayat.where((a) => (a['official'] as int) != 0).length,
      'with_phrases': ayat.where((a) => (a['phrases'] as int) != 0).length,
    },
    'ayat': ayat,
    'lines': lines,
  };
}
