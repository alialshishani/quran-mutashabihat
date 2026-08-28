// A port of app/lookup.py's fork index and fork detail.
//
// A fork is an official mutashabih phrase seen as a road: the wording every
// position shares, the point where they part, and each way out with the
// positions taking it. `shape` says how expensive the fork is to hold -- one
// exception is cheap, a fork that costs a peg per position is not.

import 'package:sqlite3/common.dart';

import 'official.dart';

/// One way out of a fork, and how many places take it.
class Rival {
  const Rival({required this.token, required this.places, required this.endsSurah});

  final String? token;
  final int places;
  final bool endsSurah;
}

/// How far one place stands from the crowd it shares a road with.
///
/// A road is wording several places say alike, and the fork is the first word
/// at which they part. What trips a reciter is not that the road exists but
/// standing in the minority at its end: if this place goes the way the other
/// eleven go, the habit is right and nothing is at risk. One of two against
/// ten, and the mouth will take the ten.
class Stand {
  const Stand({
    required this.posId,
    required this.phraseId,
    required this.shape,
    required this.places,
    required this.mine,
    required this.turn,
    required this.endsSurah,
    required this.roadEnd,
    required this.rivals,
  });

  final int posId;
  final int phraseId;
  final String shape;

  /// Places on this road, and of those, places taking the same way out as this
  /// one does.
  final int places;
  final int mine;

  /// The word this place turns on, or null where the road runs into the end of
  /// its sūrah and there is no next word.
  final String? turn;
  final bool endsSurah;

  /// The last word of the road: the fork is the word after it.
  final int roadEnd;

  /// The other ways out, largest first.
  final List<Rival> rivals;

  int get others => places - mine;

  /// The places pulling the other way, weighted by what share of the road they
  /// are: `others x others / places`. A place in the majority scores near
  /// nothing -- the habit is right there. The single exception among nine
  /// scores 7.1, and that is the one worth being stopped at.
  double get danger => places == 0 ? 0 : others * others / places;
}

/// The stand of every position in a stretch of the corpus, or of named
/// positions. Only forks worth asking about: a phrase whose places all continue
/// the same way has no turning to miss.
Map<int, Stand> forkStands(
  CommonDatabase db, {
  Iterable<int>? posIds,
  int? firstWord,
  int? lastWord,
}) {
  final where = posIds != null
      ? 'o.pos_id IN (${List.filled(posIds.length, '?').join(',')})'
      : 'o.start_word_id BETWEEN ? AND ?';
  final args = posIds != null ? posIds.toList() : [firstWord, lastWord];
  if (posIds != null && posIds.isEmpty) return const {};

  final rows = db.select(
    'SELECT o.pos_id, o.phrase_id, o.end_word_id, f.shape, f.shared_after, '
    '       f.position_count AS places, b.branch_id, b.token_ar, '
    '       b.ends_surah, b.position_count AS mine '
    'FROM official_positions o '
    'JOIN forks f ON f.phrase_id = o.phrase_id '
    'JOIN fork_members m ON m.pos_id = o.pos_id '
    'JOIN fork_branches b ON b.branch_id = m.branch_id '
    "WHERE f.shape != 'no_fork' AND f.branch_count >= 2 AND $where",
    args,
  );
  if (rows.isEmpty) return const {};

  final phraseIds = {for (final r in rows) r['phrase_id'] as int}.toList();
  final branches = <int, List<Row>>{};
  for (final b in db.select(
    'SELECT phrase_id, branch_id, token_ar, ends_surah, position_count '
    'FROM fork_branches '
    'WHERE phrase_id IN (${List.filled(phraseIds.length, '?').join(',')}) '
    'ORDER BY position_count DESC',
    phraseIds,
  )) {
    (branches[b['phrase_id'] as int] ??= []).add(b);
  }

  final out = <int, Stand>{};
  for (final r in rows) {
    final phraseId = r['phrase_id'] as int;
    final mineId = r['branch_id'] as int;
    out[r['pos_id'] as int] = Stand(
      posId: r['pos_id'] as int,
      phraseId: phraseId,
      shape: r['shape'] as String,
      places: r['places'] as int,
      mine: r['mine'] as int,
      turn: r['token_ar'] as String?,
      endsSurah: (r['ends_surah'] as int? ?? 0) != 0,
      roadEnd: (r['end_word_id'] as int) + (r['shared_after'] as int),
      rivals: [
        for (final b in branches[phraseId] ?? const <Row>[])
          if (b['branch_id'] != mineId)
            Rival(
              token: b['token_ar'] as String?,
              places: b['position_count'] as int,
              endsSurah: (b['ends_surah'] as int? ?? 0) != 0,
            ),
      ],
    );
  }
  return out;
}

/// Where a shared road ends, inside a stretch of the corpus.
///
/// The word after one of these is the fork: the first word at which the places
/// carrying that road stop agreeing, and so the word a reciter has to know
/// rather than infer. Recall cuts a page at these points, so what it asks for
/// is the turning and not the whole ayah.
///
/// Only forks worth asking about: a phrase whose positions all continue the
/// same way has no turning to miss.
Map<int, double> roadEnds(CommonDatabase db, int firstWord, int lastWord) {
  final out = <int, double>{};
  for (final stand
      in forkStands(db, firstWord: firstWord, lastWord: lastWord).values) {
    final at = stand.roadEnd;
    // Two phrases can end their road on the same word. The stronger claim wins:
    // it is the same stop either way, and it is the harder of the two.
    if (stand.danger > (out[at] ?? -1)) out[at] = stand.danger;
  }
  return out;
}

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
