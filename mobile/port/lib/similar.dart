// The āyah that reads like this one.
//
// The official phrases in official.dart are *phrase*-level: several places
// share a run of wording, and the fork is the word they stop agreeing at.
// This is the other confusion, and the one a reciter is more frightened of --
// a whole āyah with a near twin somewhere else in the muṣḥaf. QUL ships the
// pairing as its similar-ayah resource, which pipeline.official copies into
// `similar_ayahs` verbatim; 1,162 āyāt carry at least one, and 636 of those
// carry no official phrase at all, so until now the panel told their reader
// there was nothing to know about them.
//
// Two halves, from two sources, and the split is deliberate.
//
// WHICH āyāt are alike is QUL's judgement: `score`, `coverage` and
// `matched_words` are theirs and are used only to choose the pairs and rank
// them. WHAT differs is computed here, because QUL's `match_words_range`
// cannot answer it. Those ranges are one-sided -- they mark the source āyah
// and say nothing about the twin -- and they are loose: 16:115 -> 2:173 ends
// at word 25 of a 22-word āyah, and the ranges of 2:136 cover 25 positions
// while its own `matched_words` says 29. Aligning the two word streams here
// is exact, symmetric, and answers the question the reciter actually has,
// which is not "how alike are these" but "where do they part".
//
// Nothing composes Qur'anic text. Both sides are the stored `text_uthmani`,
// in their stored order; alignment only marks which of them agree.

import 'package:sqlite3/common.dart';

/// One word of an āyah, and whether the twin has it in the same place.
class DiffWord {
  const DiffWord(this.text, this.same);

  /// `words.text_uthmani`, as stored.
  final String text;

  /// Whether the alignment paired this word with an equal one on the other
  /// side. False is the interesting value: it is what the reciter has to hold.
  final bool same;
}

/// A stretch of the two āyāt that the alignment treats as one unit: either a
/// run both say alike, or the two runs they say instead of each other.
///
/// The chunks are what makes the parting sayable. Marking single words apart
/// would leave a reciter to pair them up by eye across two lines of naskh;
/// held as runs, the panel can set قُولُوٓا۟ against قُلْ and إِلَيْنَا against
/// عَلَيْنَا, which is how a teacher would put it and how a ḍābiṭ is
/// remembered.
class DiffChunk {
  const DiffChunk({required this.here, required this.there, required this.same});

  /// Words on the side asked about, and on the twin's.
  ///
  /// When [same] the two run word for word together, but each keeps its own
  /// spelling: the runs are equal once normalised, and the muṣḥaf still
  /// prints رَّحِيمٌۭ in one place and رَّحِيمٌ in the other. Showing an āyah in
  /// its neighbour's orthography would be the app editing the print.
  ///
  /// When not [same], either side may be empty -- one āyah simply carrying
  /// words the other has nowhere.
  final List<String> here;
  final List<String> there;
  final bool same;
}

/// An āyah that reads like the one asked about, and where the two part.
class SimilarAyah {
  SimilarAyah({
    required this.verseKey,
    required this.surah,
    required this.ayah,
    required this.surahNameAr,
    required this.page,
    required this.matchedWords,
    required this.coverage,
    required this.score,
    required this.chunks,
  });

  /// The twin.
  final String verseKey;
  final int surah;
  final int ayah;
  final String surahNameAr;

  /// Where to turn to read it. Null only if the āyah is not on a bound page.
  final int? page;

  /// QUL's own measures, kept for ranking and shown as the strength of the
  /// resemblance. Not used to compute the diff -- see the file's head.
  final int matchedWords;
  final int coverage;
  final int score;

  /// The two āyāt aligned, in order: runs they say alike and runs they say
  /// instead of each other.
  final List<DiffChunk> chunks;

  /// The āyah asked about, and the twin, word by word, each word carrying
  /// whether the other side has it. For setting the whole āyah with its
  /// partings lit.
  List<DiffWord> get here => [
        for (final c in chunks)
          for (final w in c.here) DiffWord(w, c.same),
      ];

  List<DiffWord> get there => [
        for (final c in chunks)
          for (final w in c.there) DiffWord(w, c.same),
      ];

  /// Only the places the two part, in order. This is the ḍābiṭ, and for a
  /// pair that differs in one word it is the whole of what has to be held.
  List<DiffChunk> get partings =>
      [for (final c in chunks) if (!c.same) c];

  /// Word for word the same, once the orthography is normalised. 1,546 of the
  /// pairs are, and saying so is the whole of what that reader needs: the
  /// āyah is not merely alike, it is repeated, and only its surroundings tell
  /// the two apart.
  bool get identical => partings.isEmpty;

  /// How many words, across both sides, the alignment could not pair. The
  /// smaller this is the more dangerous the pair, which is why it is worth
  /// showing next to the āyah rather than leaving to the eye.
  int get differences => partings.fold(
      0, (n, c) => n + c.here.length + c.there.length);
}

/// Whether this corpus carries the similar-āyah pairing at all.
///
/// The table is optional the way the fork tables are: a corpus built without
/// the QUL resource simply has no rows, and a screen asks rather than assumes.
bool hasSimilar(CommonDatabase db) {
  final present = db.select("SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name = 'similar_ayahs'");
  if (present.isEmpty) return false;
  return db.select('SELECT 1 FROM similar_ayahs LIMIT 1').isNotEmpty;
}

/// The āyāt that read like [verseKey], closest first.
///
/// Ordered by QUL's score, since that is what their measure is for, and then
/// by the length of the agreement: between two equally scored twins the one
/// that agrees for longer is the one a reciter is likelier to slide into.
List<SimilarAyah> similarAyat(
  CommonDatabase db,
  String verseKey, {
  int limit = 8,
}) {
  if (!hasSimilar(db)) return const [];

  final rows = db.select(
    'SELECT s.matched_verse_key, s.matched_words, s.coverage, s.score, '
    '       a.surah, a.ayah, a.page_start, sr.name_ar '
    'FROM similar_ayahs s '
    'JOIN ayahs a ON a.verse_key = s.matched_verse_key '
    'JOIN surahs sr ON sr.surah = a.surah '
    'WHERE s.verse_key = ? '
    'ORDER BY s.score DESC, s.matched_words DESC, a.surah, a.ayah '
    'LIMIT ?',
    [verseKey, limit],
  );
  if (rows.isEmpty) return const [];

  final here = _wordsOf(db, verseKey);
  if (here.isEmpty) return const [];

  final out = <SimilarAyah>[];
  for (final r in rows) {
    final key = r['matched_verse_key'] as String;
    final twin = _wordsOf(db, key);
    if (twin.isEmpty) continue;
    final aligned = _align(here, twin);
    out.add(SimilarAyah(
      verseKey: key,
      surah: r['surah'] as int,
      ayah: r['ayah'] as int,
      surahNameAr: r['name_ar'] as String,
      page: r['page_start'] as int?,
      matchedWords: r['matched_words'] as int,
      coverage: r['coverage'] as int,
      score: r['score'] as int,
      chunks: aligned,
    ));
  }
  return out;
}

/// One āyah's words: what to show, and what to compare.
///
/// Compared on `text_norm` rather than `text_uthmani` so that the small marks
/// the muṣḥaf carries do not read as differences -- رَّحِيمٌۭ against رَّحِيمٌ
/// is one word, not two. What a real difference of spelling looks like,
/// إِبْرَٰهِـۧمَ against إِبْرَٰهِيمَ, survives normalisation and is still marked,
/// which is right: a reciter setting those two āyāt side by side wants it.
List<({String show, String norm})> _wordsOf(CommonDatabase db, String key) {
  final at = key.indexOf(':');
  if (at <= 0) return const [];
  final surah = int.tryParse(key.substring(0, at));
  final ayah = int.tryParse(key.substring(at + 1));
  if (surah == null || ayah == null) return const [];

  return [
    for (final r in db.select(
      'SELECT text_uthmani, text_norm FROM words '
      'WHERE surah = ? AND ayah = ? ORDER BY word_pos',
      [surah, ayah],
    ))
      (show: r['text_uthmani'] as String, norm: r['text_norm'] as String? ?? ''),
  ];
}

/// Mark, on each side, which words the other side has in the same order.
///
/// A longest-common-subsequence alignment, which is the right shape for this:
/// it keeps order, so a word that has merely moved -- بِهِۦ لِغَيْرِ ٱللَّهِ against
/// لِغَيْرِ ٱللَّهِ بِهِۦ -- comes out as a difference, and moving a word is exactly
/// the kind of slip this is meant to catch.
///
/// The table is |a| x |b| cells. The longest āyah in the muṣḥaf is 2:282 at
/// 128 words, so the worst pair anyone can ask for is about sixteen thousand
/// cells, computed once when a panel opens.
List<DiffChunk> _align(
  List<({String show, String norm})> a,
  List<({String show, String norm})> b,
) {
  final n = a.length, m = b.length;
  // lcs[i][j] is the length of the longest common subsequence of a[i:] and
  // b[j:]; filled from the end so the walk forward below can follow it.
  final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = a[i].norm == b[j].norm
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }

  final out = <DiffChunk>[];
  final hereRun = <String>[], thereRun = <String>[];
  final sameHere = <String>[], sameThere = <String>[];

  void flushParting() {
    if (hereRun.isEmpty && thereRun.isEmpty) return;
    out.add(DiffChunk(
      here: List.of(hereRun),
      there: List.of(thereRun),
      same: false,
    ));
    hereRun.clear();
    thereRun.clear();
  }

  void flushSame() {
    if (sameHere.isEmpty) return;
    out.add(DiffChunk(
      here: List.of(sameHere),
      there: List.of(sameThere),
      same: true,
    ));
    sameHere.clear();
    sameThere.clear();
  }

  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i].norm == b[j].norm) {
      // A parting ends where the two meet again, so it is closed here rather
      // than word by word -- that is what makes it a run and not a scatter.
      flushParting();
      // Each side keeps its own printed form. They agree once normalised,
      // which is what makes this a shared run, but they are not always
      // spelled alike and the app does not get to choose between two muṣḥaf
      // spellings.
      sameHere.add(a[i].show);
      sameThere.add(b[j].show);
      i++;
      j++;
    } else {
      flushSame();
      if (lcs[i + 1][j] >= lcs[i][j + 1]) {
        hereRun.add(a[i].show);
        i++;
      } else {
        thereRun.add(b[j].show);
        j++;
      }
    }
  }
  flushSame();
  for (; i < n; i++) {
    hereRun.add(a[i].show);
  }
  for (; j < m; j++) {
    thereRun.add(b[j].show);
  }
  flushParting();
  return out;
}
