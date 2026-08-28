// The drill.
//
// Unlike everything else in this package, this is not a port -- there is no
// Python counterpart to check it against. It is new, so it is covered by tests
// rather than by goldens (see test/drill_test.dart).
//
// The question comes straight out of the fork tables, because a fork already
// has the shape of one. The road is the wording every position shares; the
// branches are the ways out; and each position takes exactly one of them. So
// asking "you are at this place, reciting this road -- which way does it go?"
// needs no new data, and the answer is known.
//
// A miss is answered with the peg `pipeline.pegs` verified for that position:
// not merely which way it goes, but what tells it from the others.

import 'package:sqlite3/common.dart';

import 'forks.dart';
import 'official.dart';

/// One way out of the fork, as an answer to choose between.
class DrillOption {
  DrillOption({
    required this.branchId,
    required this.tokenAr,
    required this.endsSurah,
    required this.positionCount,
  });

  final int branchId;

  /// The word the recitation continues with. Null when this branch ends the
  /// sūrah, which is an answer too -- and the one a reciter most often misses.
  final String? tokenAr;
  final bool endsSurah;
  final int positionCount;
}

/// One question: a place, the road up to the fork, and the ways out.
class DrillQuestion {
  DrillQuestion({
    required this.phraseId,
    required this.posId,
    required this.verseKey,
    required this.surahNameAr,
    required this.page,
    required this.roadAr,
    required this.phraseAr,
    required this.roadTailAr,
    required this.shape,
    required this.positionCount,
    required this.options,
    required this.answerBranchId,
    required this.peg,
    required this.before,
    required this.leadInAr,
    required this.precedingAr,
    required this.ordinalInSurah,
    required this.countInSurah,
  });

  final int phraseId;

  /// The position being asked about -- the row in `official_positions`.
  final int posId;
  final String verseKey;
  final String surahNameAr;
  final int? page;

  /// The wording shared up to the fork, and its two halves: the curated phrase
  /// and whatever the positions still say together after it.
  final String roadAr;
  final String phraseAr;
  final String? roadTailAr;

  final String shape;
  final int positionCount;

  /// Every way out, in the order the fork records them. Shuffle for display.
  final List<DrillOption> options;
  final int answerBranchId;

  /// What tells this position from its siblings, revealed after answering.
  final Map<String, Object?>? peg;

  /// The token before the road at this position -- the cue a CUE_BEFORE peg
  /// leans on.
  final String? before;

  /// The āyah from its first word up to the fork.
  ///
  /// Without this the question can be unanswerable, and often is: 491 forks
  /// have a single sūrah taking two or more different ways out, covering 1,313
  /// of the positions. For those, "which sūrah" does not settle it and the road
  /// alone does not either -- only the wording leading into the fork does.
  ///
  /// Null when the road opens the āyah, in which case [precedingAr] carries the
  /// context instead.
  final String? leadInAr;

  /// The tail of the āyah before, for when the road opens this one. A reciter
  /// arriving here has just said it, so it is the context they actually hold.
  final String? precedingAr;

  /// Which occurrence this is inside its own sūrah, and how many there are.
  ///
  /// For eighteen positions the run-up is not enough: the same sūrah says the
  /// same words into the same fork twice and then parts. Nothing in the wording
  /// tells those apart, and the reciter's only handle is which time it is --
  /// which is what an ORDINAL_IN_SURAH peg is (docs/PEGS.md). Shown only when
  /// [countInSurah] is more than one, since otherwise it says nothing.
  final int ordinalInSurah;
  final int countInSurah;

  bool isCorrect(int branchId) => branchId == answerBranchId;
}

/// A place worth drilling: one position of one fork.
class DrillCandidate {
  DrillCandidate({
    required this.phraseId,
    required this.posId,
    required this.shape,
    required this.positionCount,
    required this.branchCount,
  });

  final int phraseId;
  final int posId;
  final String shape;
  final int positionCount;
  final int branchCount;

  /// Stable identity for progress that survives a rebuild of the corpus only if
  /// the ids do; good enough for a local Leitner box.
  String get key => '$phraseId/$posId';
}

/// Every position of every fork that actually forks, cheapest shape first.
///
/// `no_fork` is excluded: those positions never part, so there is no question
/// to ask -- they are told apart by what precedes them, not by what follows.
/// A single-branch fork is excluded for the same reason.
List<DrillCandidate> drillPool(CommonDatabase db, {int? limit}) {
  if (!hasForks(db)) return const [];

  final rows = db.select(
    'SELECT f.phrase_id, f.shape, f.position_count, f.branch_count, m.pos_id '
    'FROM forks f '
    'JOIN fork_branches b ON b.phrase_id = f.phrase_id '
    'JOIN fork_members m ON m.branch_id = b.branch_id '
    'JOIN official_positions o ON o.pos_id = m.pos_id '
    "WHERE f.shape != 'no_fork' AND f.branch_count >= 2 "
    // Cheapest to hold first, as SORTS['useful'] orders the fork index.
    'ORDER BY CASE f.shape WHEN \'all_but_one\' THEN 0 '
    "  WHEN 'two_way' THEN 1 WHEN 'many' THEN 2 ELSE 3 END, "
    'f.position_count DESC, f.phrase_id, o.start_word_id'
    '${limit == null ? "" : " LIMIT $limit"}',
  );

  return [
    for (final r in rows)
      DrillCandidate(
        phraseId: r['phrase_id'] as int,
        posId: r['pos_id'] as int,
        shape: r['shape'] as String,
        positionCount: r['position_count'] as int,
        branchCount: r['branch_count'] as int,
      ),
  ];
}

/// Build the question for one position of one fork.
///
/// Throws [PhraseNotFound] if the fork is gone, [ArgumentError] if the position
/// is not one of its own -- neither should happen for a candidate from
/// [drillPool], and both are worth failing loudly on rather than guessing.
DrillQuestion drillQuestion(CommonDatabase db, int phraseId, int posId) {
  final forkRows = db.select(
    'SELECT f.shape, f.position_count, f.road_ar, p.text_ar AS phrase_ar '
    'FROM forks f JOIN official_phrases p ON p.phrase_id = f.phrase_id '
    'WHERE f.phrase_id = ?',
    [phraseId],
  );
  if (forkRows.isEmpty) throw PhraseNotFound('no fork for phrase $phraseId');
  final fork = forkRows.first;

  final branches = branchesOf(db, phraseId);
  int? answer;
  for (final b in branches) {
    for (final p in (b['positions'] as List).cast<Map<String, Object?>>()) {
      if (p['pos_id'] == posId) answer = b['branch_id'] as int;
    }
  }
  if (answer == null) {
    throw ArgumentError('position $posId is not in fork $phraseId');
  }

  final posRows = db.select(
    'SELECT o.pos_id, o.verse_key, o.surah, o.page, o.start_word_id, '
    '       s.name_ar, '
    '       g.kind, g.cue_ar, g.cue_window, g.continuation_ar, '
    '       g.continuation_unique, g.strength, g.text_ar, g.evidence '
    'FROM official_positions o '
    'JOIN surahs s ON s.surah = o.surah '
    'LEFT JOIN pegs g ON g.pos_id = o.pos_id '
    'WHERE o.pos_id = ?',
    [posId],
  );
  if (posRows.isEmpty) throw ArgumentError('no position $posId');
  final pos = posRows.first;

  // The token before the road, and only if it is in the same sūrah -- the same
  // rule the peg builder applies, since a token across a sūrah seam is not a
  // cue a reciter has.
  final words = Words(db);
  final before = words.neighbour(
    (pos['start_word_id'] as int) - 1,
    pos['surah'] as int,
  );

  // The āyah this position sits in, so the question can show the run-up to the
  // fork rather than the shared wording alone.
  final start = pos['start_word_id'] as int;
  final bounds = db.select(
    'SELECT first_word_id, last_word_id FROM ayahs WHERE verse_key = ?',
    [pos['verse_key']],
  ).first;
  final ayahFirst = bounds['first_word_id'] as int;

  String? leadIn;
  if (start > ayahFirst) {
    leadIn = words.text(ayahFirst, start - 1).join(' ');
  }

  String? preceding;
  if (leadIn == null) {
    // The road opens the āyah, so the run-up is the end of the one before --
    // and only if it is in the same sūrah, since a reciter crossing a sūrah
    // seam has not just said it.
    final prev = db.select(
      'SELECT first_word_id, last_word_id FROM ayahs '
      'WHERE surah = ? AND last_word_id < ? ORDER BY last_word_id DESC LIMIT 1',
      [pos['surah'], ayahFirst],
    );
    if (prev.isNotEmpty) {
      final pf = prev.first['first_word_id'] as int;
      final pl = prev.first['last_word_id'] as int;
      // At most the last six words: enough to place the reciter, not so much
      // that the question becomes a reading exercise.
      preceding = words.text(pl - 5 < pf ? pf : pl - 5, pl).join(' ');
    }
  }

  // Where this position falls among the fork's positions in its own sūrah.
  final siblings = db.select(
    'SELECT pos_id FROM official_positions '
    'WHERE phrase_id = ? AND surah = ? ORDER BY start_word_id',
    [phraseId, pos['surah']],
  ).map((r) => r['pos_id'] as int).toList();
  final ordinal = siblings.indexOf(posId) + 1;

  final road = fork['road_ar'] as String;
  final phrase = fork['phrase_ar'] as String;
  final tail = String.fromCharCodes(road.runes.skip(phrase.runes.length)).trim();

  return DrillQuestion(
    phraseId: phraseId,
    posId: posId,
    verseKey: pos['verse_key'] as String,
    surahNameAr: pos['name_ar'] as String,
    page: pos['page'] as int?,
    roadAr: road,
    phraseAr: phrase,
    roadTailAr: tail.isEmpty ? null : tail,
    shape: fork['shape'] as String,
    positionCount: fork['position_count'] as int,
    options: [
      for (final b in branches)
        DrillOption(
          branchId: b['branch_id'] as int,
          tokenAr: b['token_ar'] as String?,
          endsSurah: b['ends_surah'] == true,
          positionCount: b['position_count'] as int,
        ),
    ],
    answerBranchId: answer,
    peg: peg(pos),
    before: before,
    leadInAr: leadIn,
    precedingAr: preceding,
    ordinalInSurah: ordinal,
    countInSurah: siblings.length,
  );
}
