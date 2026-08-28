// A port of app/lookup.py's `lookup`.
//
// Everything the corpus has on one āyah: the phrases pass A detected repeating,
// each with every other position and any ḍābiṭ that verified for it, plus the
// curated official section from official.dart.

import 'dart:convert';

import 'package:sqlite3/common.dart';

import 'official.dart';

const String kDefaultScope = 'full';
const int kDefaultLimit = 25;

/// True when `match` adds nothing another match on this āyah does not.
///
/// Only fires when a longer span covers this one *and* lands in exactly the
/// same set of positions -- so it drops duplicates, never evidence.
bool _subsumed(Map<String, Object?> match, List<Map<String, Object?>> others) {
  final here = match['here'] as Map<String, Object?>;
  final hs = here['start_word_id'] as int;
  final he = here['end_word_id'] as int;
  final keys = {
    for (final p in (match['positions'] as List))
      (p as Map)['verse_key'] as String,
  };

  for (final other in others) {
    if (other['group_id'] == match['group_id']) continue;
    final oh = other['here'] as Map<String, Object?>;
    final os = oh['start_word_id'] as int;
    final oe = oh['end_word_id'] as int;
    if (os == hs && oe == he) continue;
    if (os <= hs && he <= oe) {
      final otherKeys = {
        for (final p in (other['positions'] as List))
          (p as Map)['verse_key'] as String,
      };
      if (keys.every(otherKeys.contains)) return true;
    }
  }
  return false;
}

/// Every repeated span touching `surah:ayah`, strongest peg first.
Map<String, Object?> lookup(
  CommonDatabase db,
  int surah,
  int ayah, {
  String scope = kDefaultScope,
  int minLen = 0,
  int minOccurrences = 2,
  int? limit = kDefaultLimit,
  bool collapse = true,
  bool official = true,
}) {
  final rows = db.select(
    'SELECT verse_key, surah, ayah, first_word_id, last_word_id, '
    '       page_start, page_end, juz, hizb, rub '
    'FROM ayahs WHERE surah = ? AND ayah = ?',
    [surah, ayah],
  );
  if (rows.isEmpty) {
    throw AyahNotFound('$surah:$ayah is not an ayah in the mushaf');
  }
  final row = rows.first;

  final words = Words(db);
  final names = surahNamesOf(db);
  final juz = juzOfAll(db);

  final first = row['first_word_id'] as int;
  final last = row['last_word_id'] as int;

  final hits = db.select(
    'SELECT o.group_id, o.start_word_id, o.end_word_id, '
    '       g.occurrence_count, g.span_len_min, g.span_len_max, g.kind, '
    '       g.cross_surah, g.needs_review '
    'FROM occurrences o JOIN groups g ON g.group_id = o.group_id '
    'WHERE g.scope = ? AND o.start_word_id <= ? AND o.end_word_id >= ? '
    'ORDER BY o.start_word_id',
    [scope, last, first],
  );

  var matches = <Map<String, Object?>>[];
  for (final hit in hits) {
    if ((hit['span_len_max'] as int) < minLen ||
        (hit['occurrence_count'] as int) < minOccurrences) {
      continue;
    }
    final gid = hit['group_id'] as int;

    final positions = <Map<String, Object?>>[];
    for (final occ in db.select(
      'SELECT occ_id, start_word_id, end_word_id, verse_key, page, line '
      'FROM occurrences WHERE group_id = ? ORDER BY start_word_id',
      [gid],
    )) {
      positions.add(position(
        db,
        words,
        start: occ['start_word_id'] as int,
        end: occ['end_word_id'] as int,
        verseKey: occ['verse_key'] as String,
        page: occ['page'] as int?,
        line: occ['line'] as int?,
        surahNames: names,
        juzOf: juz,
      ));
    }

    final hereStart = hit['start_word_id'] as int;
    final hereEnd = hit['end_word_id'] as int;
    for (final pos in positions) {
      pos['is_query'] =
          pos['start_word_id'] == hereStart && pos['end_word_id'] == hereEnd;
    }
    final here = positions.firstWhere((p) => p['is_query'] == true);

    final dawabit = <Map<String, Object?>>[];
    for (final d in db.select(
      'SELECT rule_code, strength, text_ar, verified, generated_by, payload '
      'FROM dawabit WHERE group_id = ? ORDER BY strength DESC',
      [gid],
    )) {
      final payload = d['payload'];
      dawabit.add({
        'rule_code': d['rule_code'],
        'strength': d['strength'],
        'text_ar': d['text_ar'],
        'verified': (d['verified'] as int? ?? 0) != 0,
        'generated_by': d['generated_by'],
        'evidence': (payload == null || (payload as String).isEmpty)
            ? null
            : json.decode(payload),
      });
    }

    matches.add({
      'group_id': gid,
      'kind': hit['kind'],
      'span_len': hereEnd - hereStart + 1,
      'occurrence_count': hit['occurrence_count'],
      'cross_surah': (hit['cross_surah'] as int? ?? 0) != 0,
      'needs_review': (hit['needs_review'] as int? ?? 0) != 0,
      'span_text': words.text(hereStart, hereEnd).join(' '),
      'span_tokens': words.text(hereStart, hereEnd),
      'here': here,
      'elsewhere': positions.where((p) => p['is_query'] != true).toList(),
      'positions': positions,
      'dawabit': dawabit,
    });
  }

  if (collapse) {
    final all = matches;
    matches = matches.where((m) => !_subsumed(m, all)).toList();
  }

  // A verified peg is the product; span length and breadth order the rest.
  num best(Map<String, Object?> m) {
    final d = m['dawabit'] as List;
    if (d.isEmpty) return 0;
    num top = 0;
    var firstOne = true;
    for (final x in d) {
      final s = (x as Map)['strength'] as num? ?? 0;
      if (firstOne || s > top) {
        top = s;
        firstOne = false;
      }
    }
    return top;
  }

  matches.sort((a, b) {
    final ha = (a['dawabit'] as List).isEmpty ? 1 : 0;
    final hb = (b['dawabit'] as List).isEmpty ? 1 : 0;
    if (ha != hb) return ha.compareTo(hb);
    final sa = (a['dawabit'] as List).isEmpty ? 0 : -best(a);
    final sb = (b['dawabit'] as List).isEmpty ? 0 : -best(b);
    if (sa != sb) return sa.compareTo(sb);
    final la = -(a['span_len'] as int);
    final lb = -(b['span_len'] as int);
    if (la != lb) return la.compareTo(lb);
    final oa = -(a['occurrence_count'] as int);
    final ob = -(b['occurrence_count'] as int);
    if (oa != ob) return oa.compareTo(ob);
    return (a['group_id'] as int).compareTo(b['group_id'] as int);
  });

  // Summary counts describe the āyah, so they are taken before the display
  // limit is applied; `returned` is the only number about the page size.
  final total = matches.length;
  final withDabit = matches.where((m) => (m['dawabit'] as List).isNotEmpty).length;
  var otherPositions = 0;
  final distinct = <String>{};
  for (final m in matches) {
    final e = m['elsewhere'] as List;
    otherPositions += e.length;
    for (final p in e) {
      distinct.add((p as Map)['verse_key'] as String);
    }
  }
  if (limit != null && matches.length > limit) {
    matches = matches.sublist(0, limit);
  }

  final hasOfficial = official && hasOfficialTables(db);
  final officialPhrases = hasOfficial
      ? officialMatches(db, surah, ayah, words, names, juz)
      : <Map<String, Object?>>[];

  final ayahWords = ayahWordsOf(db, row['verse_key'] as String, words);
  final covered = <int>{};
  for (final m in matches) {
    final h = m['here'] as Map<String, Object?>;
    for (var w = h['start_word_id'] as int; w <= (h['end_word_id'] as int); w++) {
      covered.add(w);
    }
  }

  var officialPositions = 0;
  for (final p in officialPhrases) {
    officialPositions += (p['elsewhere'] as List).length;
  }

  return {
    'query': {
      'verse_key': row['verse_key'],
      'surah': row['surah'],
      'ayah': row['ayah'],
      'surah_name_ar': names[row['surah'] as int],
      'page': row['page_start'],
      'juz': row['juz'],
      'hizb': row['hizb'],
      'rub': row['rub'],
      'text': ayahWords.map((w) => w['text_uthmani']).join(' '),
      'words': [
        for (final w in ayahWords)
          {
            'word_id': w['word_id'],
            'word_pos': w['word_pos'],
            'text': w['text_uthmani'],
            'repeated': covered.contains(w['word_id'] as int),
          },
      ],
    },
    'params': {
      'scope': scope,
      'min_len': minLen,
      'min_occurrences': minOccurrences,
      'limit': limit,
      'collapse': collapse,
      'official': hasOfficial,
    },
    'counts': {
      'matches': total,
      'returned': matches.length,
      'with_dabit': withDabit,
      'other_positions': otherPositions,
      'distinct_ayat': distinct.length,
      'official_phrases': officialPhrases.length,
      'official_positions': officialPositions,
    },
    'official': officialPhrases,
    'matches': matches,
  };
}
