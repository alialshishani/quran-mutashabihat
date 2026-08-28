// A port of app/lookup.py's fork index and fork detail.
//
// A fork is an official mutashabih phrase seen as a road: the wording every
// position shares, the point where they part, and each way out with the
// positions taking it. `shape` says how expensive the fork is to hold -- one
// exception is cheap, a fork that costs a peg per position is not.

import 'package:sqlite3/common.dart';

import 'official.dart';

class PhraseNotFound implements Exception {
  PhraseNotFound(this.message);
  final String message;
  @override
  String toString() => 'PhraseNotFound: $message';
}

const List<String> kShapes = ['all_but_one', 'two_way', 'many', 'no_fork'];

// Cheapest to hold first: one exception beats a two-way split, which beats a
// fork that costs a peg per position.
const String _shapeRank = "CASE shape WHEN 'all_but_one' THEN 0 "
    "WHEN 'two_way' THEN 1 WHEN 'many' THEN 2 ELSE 3 END";

const Map<String, String> kSorts = {
  'useful': '$_shapeRank, position_count DESC, phrase_id',
  'positions': 'position_count DESC, phrase_id',
  'branches': 'branch_count DESC, position_count DESC, phrase_id',
  'surahs': 'surah_count DESC, position_count DESC, phrase_id',
};

bool hasForks(CommonDatabase db) {
  final present = db
      .select("SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name IN ('forks', 'fork_branches', 'fork_members')")
      .map((r) => r['name'] as String)
      .toSet();
  if (present.length != 3) return false;
  return db.select('SELECT 1 FROM forks LIMIT 1').isNotEmpty;
}

/// The road is the phrase plus whatever the positions still say together;
/// keeping the tail separate lets the page show where the agreement ends.
///
/// Sliced by runes, as Python slices by code point.
String? _tail(String road, String phrase) {
  final t = String.fromCharCodes(road.runes.skip(phrase.runes.length)).trim();
  return t.isEmpty ? null : t;
}

List<Map<String, Object?>> branchesOf(CommonDatabase db, int phraseId) {
  final out = <Map<String, Object?>>[];
  for (final branch in db.select(
    'SELECT * FROM fork_branches WHERE phrase_id = ? ORDER BY ordinal',
    [phraseId],
  )) {
    final members = db.select(
      'SELECT o.pos_id, o.verse_key, o.surah, o.ayah, o.page, o.juz, s.name_ar '
      'FROM fork_members m JOIN official_positions o ON o.pos_id = m.pos_id '
      'JOIN surahs s ON s.surah = o.surah '
      'WHERE m.branch_id = ? ORDER BY o.start_word_id',
      [branch['branch_id']],
    );
    out.add({
      'branch_id': branch['branch_id'],
      'ordinal': branch['ordinal'],
      'token_ar': branch['token_ar'],
      'ends_surah': (branch['ends_surah'] as int? ?? 0) != 0,
      'position_count': branch['position_count'],
      'is_largest': (branch['is_largest'] as int? ?? 0) != 0,
      'positions': [
        for (final m in members)
          {
            'pos_id': m['pos_id'],
            'verse_key': m['verse_key'],
            'surah': m['surah'],
            'ayah': m['ayah'],
            'surah_name_ar': m['name_ar'],
            'page': m['page'],
            'juz': m['juz'],
          },
      ],
    });
  }
  return out;
}

/// The official mutashābihāt as forks, filtered and paged.
Map<String, Object?> forkIndex(
  CommonDatabase db, {
  String? shape,
  int minPositions = 2,
  int? surah,
  String? q,
  String sort = 'useful',
  int limit = 25,
  int offset = 0,
}) {
  final where = <String>['f.position_count >= ?'];
  final args = <Object?>[minPositions];

  if (shape != null) {
    if (!kShapes.contains(shape)) {
      throw ArgumentError("unknown shape '$shape'; expected one of "
          "${kShapes.join(', ')}");
    }
    where.add('f.shape = ?');
    args.add(shape);
  }
  if (surah != null && surah != 0) {
    where.add('EXISTS (SELECT 1 FROM official_positions o '
        'WHERE o.phrase_id = f.phrase_id AND o.surah = ?)');
    args.add(surah);
  }
  if (q != null && q.isNotEmpty) {
    where.add('(f.road_ar LIKE ? OR p.text_norm LIKE ?)');
    args.addAll(['%$q%', '%$q%']);
  }

  final joined =
      'FROM forks f JOIN official_phrases p ON p.phrase_id = f.phrase_id '
      'WHERE ${where.join(" AND ")}';

  final total = db.select('SELECT COUNT(*) AS n $joined', args).first['n'] as int;
  final byShape = <String, int>{
    for (final r
        in db.select('SELECT f.shape AS s, COUNT(*) AS n $joined GROUP BY f.shape', args))
      r['s'] as String: r['n'] as int,
  };

  final order = kSorts[sort];
  if (order == null) {
    throw ArgumentError(
        "unknown sort '$sort'; expected one of ${kSorts.keys.join(', ')}");
  }

  final rows = db.select(
    'SELECT f.*, p.text_ar AS phrase_ar, p.span_len, p.official_count, '
    'p.exact_count $joined ORDER BY $order LIMIT ? OFFSET ?',
    [...args, limit, offset],
  );

  final phrases = <Map<String, Object?>>[];
  for (final row in rows) {
    phrases.add({
      'phrase_id': row['phrase_id'],
      'phrase_ar': row['phrase_ar'],
      'road_ar': row['road_ar'],
      'road_tail_ar': _tail(row['road_ar'] as String, row['phrase_ar'] as String),
      'shared_after': row['shared_after'],
      'shape': row['shape'],
      'position_count': row['position_count'],
      'branch_count': row['branch_count'],
      'largest_branch': row['largest_branch'],
      'singleton_branches': row['singleton_branches'],
      'surah_count': row['surah_count'],
      'span_len': row['span_len'],
      'official_count': row['official_count'],
      'exact_count': row['exact_count'],
      'branches': branchesOf(db, row['phrase_id'] as int),
    });
  }

  return {
    'params': {
      'shape': shape,
      'min_positions': minPositions,
      'surah': surah,
      'q': q,
      'sort': sort,
      'limit': limit,
      'offset': offset,
    },
    'counts': {'total': total, 'returned': phrases.length, 'by_shape': byShape},
    'phrases': phrases,
  };
}

/// One fork in full: every position with its āyah and its signpost.
Map<String, Object?> forkDetail(CommonDatabase db, int phraseId) {
  final rows = db.select(
    'SELECT f.*, p.text_ar AS phrase_ar, p.span_len, p.official_count, '
    'p.exact_count, p.source_verse_key FROM forks f '
    'JOIN official_phrases p ON p.phrase_id = f.phrase_id WHERE f.phrase_id = ?',
    [phraseId],
  );
  if (rows.isEmpty) throw PhraseNotFound('no official phrase $phraseId');
  final row = rows.first;

  final words = Words(db);
  final names = surahNamesOf(db);
  final juz = juzOfAll(db);

  final branches = branchesOf(db, phraseId);
  for (final branch in branches) {
    final detailed = <Map<String, Object?>>[];
    for (final member in (branch['positions'] as List).cast<Map<String, Object?>>()) {
      final source = db.select(
        'SELECT o.start_word_id, o.end_word_id, o.verse_key, o.page, '
        '       o.in_official, o.in_exact, o.group_id, o.link, '
        '       g.kind, g.cue_ar, g.cue_window, g.continuation_ar, '
        '       g.continuation_unique, g.strength, g.text_ar, g.evidence '
        'FROM official_positions o LEFT JOIN pegs g ON g.pos_id = o.pos_id '
        'WHERE o.pos_id = ?',
        [member['pos_id']],
      ).first;

      final p = position(
        db,
        words,
        start: source['start_word_id'] as int,
        end: source['end_word_id'] as int,
        verseKey: source['verse_key'] as String,
        page: source['page'] as int?,
        line: null,
        surahNames: names,
        juzOf: juz,
      );
      p['pos_id'] = member['pos_id'];
      p['in_official'] = (source['in_official'] as int? ?? 0) != 0;
      p['in_exact'] = (source['in_exact'] as int? ?? 0) != 0;
      p['group_id'] = source['group_id'];
      p['link'] = source['link'];
      p['peg'] = peg(source);
      detailed.add(p);
    }
    branch['positions'] = detailed;
  }

  return {
    'phrase_id': row['phrase_id'],
    'phrase_ar': row['phrase_ar'],
    'road_ar': row['road_ar'],
    'road_tail_ar': _tail(row['road_ar'] as String, row['phrase_ar'] as String),
    'shared_after': row['shared_after'],
    'shape': row['shape'],
    'position_count': row['position_count'],
    'branch_count': row['branch_count'],
    'largest_branch': row['largest_branch'],
    'singleton_branches': row['singleton_branches'],
    'surah_count': row['surah_count'],
    'span_len': row['span_len'],
    'official_count': row['official_count'],
    'exact_count': row['exact_count'],
    'source_verse_key': row['source_verse_key'],
    'branches': branches,
  };
}
