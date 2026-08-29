// What the print cannot say.
//
// For the tapped ayah: every official mutashabih phrase touching it, and for
// each, the peg that tells this position from the others -- then every sibling
// position, each with its own peg, as a way to turn there.
//
// Every string here comes from the database. The peg sentences are `pegs.text_ar`
// as `pipeline.pegs` wrote them; nothing is composed in the app.

import 'package:flutter/material.dart';
import 'package:quran_port/similar.dart';

import 'strings.dart';
import 'theme.dart';
import 'type.dart';

// The palette in force, read by name; see theme.dart. These are getters
// rather than constants because the light can change while the app is up.
Color get _raised => palette.raised;
Color get _paper => palette.paper;
Color get _ink => palette.ink;
Color get _inkSoft => palette.inkSoft;
Color get _inkMute => palette.inkMute;
Color get _accent => palette.accent;
Color get _gold => palette.gold;
Color get _goldBright => palette.goldBright;
Color get _goldSoft => palette.goldSoft;
Color get _goldDeep => palette.goldDeep;
Color get _surface => palette.surface;
Color get _surfaceAlt => palette.surfaceAlt;
Color get _rule => palette.line;

class MutashabihatPanel extends StatelessWidget {
  const MutashabihatPanel({
    super.key,
    required this.verseKey,
    required this.matches,
    required this.detected,
    required this.similar,
    required this.onJump,
  });

  final String verseKey;

  /// The curated QUL list, each position with its peg.
  final List<Map<String, Object?>> matches;

  /// Pass A's own detection: spans this ayah repeats elsewhere, with any dabit
  /// that verified for them. Behind a disclosure, as the web page has it -- the
  /// curated phrases are the answer, these are the evidence behind it.
  final List<Map<String, Object?>> detected;

  /// Whole ayat that read like this one, with the places they part. A
  /// different confusion from the phrases above: not a shared run of wording
  /// between several places, but one ayah with a near twin. 636 ayat carry one
  /// of these and no curated phrase at all, and for their reader this panel
  /// used to have nothing to say.
  final List<SimilarAyah> similar;

  /// (page, verseKey) of the sibling to turn to.
  final void Function(int page, String verseKey) onJump;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, controller) => DecoratedBox(
        decoration: BoxDecoration(
          color: _paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Text(arDigits(verseKey), style: tLabel()),
                const SizedBox(width: 10),
                Text(
                  matches.isEmpty ? kNoOfficial : kOfficialCount(matches.length),
                  style: tBody(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (matches.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  detected.isEmpty && similar.isEmpty
                      ? kNothingHere
                      : kNothingCurated,
                  style: tCaption(),
                ),
              ),
            // One leads. An ayah can carry five curated phrases and be at
            // risk from one of them -- the one where this place stands apart
            // from the crowd it shares a road with. The rest are reference, and
            // reference belongs behind a disclosure, not in front of a reciter
            // who wants to know what they are about to get wrong.
            if (matches.isNotEmpty)
              _Phrase(match: matches.first, onJump: onJump, lead: true),
            if (matches.length > 1)
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(kMorePhrases(matches.length - 1),
                      style: tBody(_accent)),
                  subtitle: Text(kMorePhrasesGloss, style: tLabel()),
                  children: [
                    for (final m in matches.skip(1))
                      _Phrase(match: m, onJump: onJump),
                  ],
                ),
              ),
            // The twins sit between the curated phrases and pass A's own
            // detection, which is where they belong on the evidence: QUL
            // pairs them, as it lists the phrases above, but what parts them
            // is computed here -- see the head of port/lib/similar.dart.
            if (similar.isNotEmpty) ...[
              const Divider(height: 26),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(kSimilarCount(similar.length), style: tBody()),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(kSimilarGloss, style: tLabel()),
              ),
              // The closest twin leads, open, as the lead phrase does above
              // it: it is the one the reciter is actually at risk from, and
              // the rest are reference.
              _Twin(twin: similar.first, onJump: onJump),
              if (similar.length > 1)
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    title: Text(kMoreSimilar(similar.length - 1),
                        style: tBody(_accent)),
                    children: [
                      for (final t in similar.skip(1))
                        _Twin(twin: t, onJump: onJump),
                    ],
                  ),
                ),
            ],
            if (detected.isNotEmpty)
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(kDetectedCount(detected.length),
                      style: tBody(_accent)),
                  subtitle: Text(kDetectedGloss, style: tLabel()),
                  children: [
                    for (final d in detected)
                      _Detected(match: d, onJump: onJump),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- the column
//
// A curated phrase set the way a teacher sets it on a board: the road once,
// then every place that takes it, each with what it says after the road runs
// out. The tails all begin at the same measure, so the differences read down a
// column -- which is the thing a reciter came for -- instead of having to be
// assembled out of counts and prose.
//
// The one thing a column of tails cannot survive is tails that hang off
// different words, and the curated list is full of them: QUL groups by the
// root of a word rather than its lettering, so أَطِيعُوا۟ ٱللَّهَ وَٱلرَّسُولَ,
// يُطِعِ ٱللَّهَ وَرَسُولَهُۥ and أَطَعْنَا ٱللَّهَ وَأَطَعْنَا are one entry of
// it, twenty places wide. Setting يُدْخِلْهُ جَنَّٰتٍ beside فَإِن تَوَلَّوْا۟
// says they are two ways out of one road. They are not: they are two roads.
//
// So the column is cut to the places whose road ends on the same word this one
// does -- see `_agreement` -- and the rest are named for what they are, behind
// a disclosure, in their own wording.
//
// Nothing here is composed. Every word is `words.text_uthmani` as `position()`
// in port/lib/official.dart handed it over, compared on its `text_norm` and
// printed in its own orthography.

/// The words of a position's āyah(s), in order. `position()` returns the whole
/// āyah around the span, which is what makes a tail available at all.
List<Map<String, Object?>> _wordsOf(Map<String, Object?> position) => [
      for (final a in (position['ayat'] as List).cast<Map<String, Object?>>())
        ...(a['words'] as List).cast<Map<String, Object?>>(),
    ];

/// `words.text_norm`, which is what two spellings of one word are compared on.
/// The muṣḥaf's own lettering is what gets printed; this is only ever read.
String _norm(Map<String, Object?> word) =>
    (word['norm'] as String?) ?? word['text'] as String;

/// The last word this place still says together with its siblings.
///
/// The curated span can stop short of that -- 83 of the 809 phrases keep
/// agreeing past their own end -- so the span's end is the fallback, for a
/// position with no fork, and not the answer.
int _roadEndOf(Map<String, Object?> position) =>
    ((position['fork'] as Map<String, Object?>?)?['road_end'] as int?) ??
    position['end_word_id'] as int;

/// The words of this place's road: its own span, and whatever it goes on
/// saying past the end of it.
List<Map<String, Object?>> _roadOf(Map<String, Object?> position) {
  final start = position['start_word_id'] as int;
  final end = _roadEndOf(position);
  return [
    for (final w in _wordsOf(position))
      if ((w['word_id'] as int) >= start && (w['word_id'] as int) <= end) w,
  ];
}

/// How many words two roads say alike, counted back from the fork.
///
/// Backwards is the only direction that means anything. A tail hangs off the
/// last word of its road, so two places whose roads end on different words
/// have nothing to compare: what they say next answers a different question.
/// Zero is the whole test -- a place that shares not even the last word is on
/// another road, however the curated list grouped it.
int _agreement(List<Map<String, Object?>> a, List<Map<String, Object?>> b) {
  var n = 0;
  while (n < a.length &&
      n < b.length &&
      _norm(a[a.length - 1 - n]) == _norm(b[b.length - 1 - n])) {
    n++;
  }
  return n;
}

/// What this place says once the road has run out: the fork word first, then
/// the rest of its āyah.
///
/// Empty where the road runs to the end of the āyah. There the muṣḥaf's next
/// word is the parting and `after` carries it -- but only when the road ends
/// where the span does, since otherwise `after` is a word still inside the
/// road. `after` is null at a sūrah seam, and then the place has no next word.
List<Map<String, Object?>> _tailOf(Map<String, Object?> position) {
  final end = _roadEndOf(position);
  final tail = [
    for (final w in _wordsOf(position))
      if ((w['word_id'] as int) > end) w,
  ];
  if (tail.isNotEmpty) return tail;
  final after = position['after'] as String?;
  if (after != null && end == position['end_word_id']) {
    return [
      {'text': after},
    ];
  }
  return const [];
}

/// One curated phrase: the road, and every place actually on it.
class _Phrase extends StatelessWidget {
  const _Phrase({required this.match, required this.onJump, this.lead = false});

  final Map<String, Object?> match;
  final void Function(int page, String verseKey) onJump;

  /// The one this āyah is actually at risk from, shown open and first.
  final bool lead;

  @override
  Widget build(BuildContext context) {
    final positions = (match['positions'] as List).cast<Map<String, Object?>>();
    final here = (match['here'] as List).cast<Map<String, Object?>>();
    if (here.isEmpty) return const SizedBox.shrink();

    final road = _roadOf(here.first);

    // Cut the list to the places whose road ends where this one's does, and
    // keep how far back the agreement runs: it is where the road being read
    // actually begins, and the words before it are this place's own.
    final onRoad = <Map<String, Object?>>[];
    final elsewhere = <Map<String, Object?>>[];
    var agreed = road.length;
    for (final p in positions) {
      if (p['is_query'] == true) {
        onRoad.add(p);
        continue;
      }
      final n = _agreement(road, _roadOf(p));
      if (n == 0) {
        elsewhere.add(p);
      } else {
        onRoad.add(p);
        if (n < agreed) agreed = n;
      }
    }
    if (onRoad.length == 1) agreed = road.length;

    // Standing in the minority at the fork is what makes a road dangerous, and
    // it is the one count worth printing. Counted over the places actually on
    // this road, not over the curated entry: `forks` was built on the entry, so
    // its own tally counts places that never say this wording at all.
    final mineWord = _firstTail(here.first);
    final mine = onRoad.where((p) => _firstTail(p) == mineWord).length;
    final odd = onRoad.length > 1 && mine < onRoad.length - mine;

    final otherPegs = [
      for (final p in onRoad)
        if (p['is_query'] != true && p['peg'] != null) p,
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: _raised,
        border: Border.all(color: _surfaceAlt),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The road, in this place's own lettering -- the curated entry's
          // text_ar is a representative and can be wording this place never
          // says. Muted at the head, where the others do not follow it in.
          Text.rich(
            TextSpan(children: [
              for (var i = 0; i < road.length; i++)
                TextSpan(
                  text: i == 0 ? '${road[i]['text']}' : ' ${road[i]['text']}',
                  style: i < road.length - agreed
                      ? tQuranLead(_inkMute)
                      : tQuranLead(),
                ),
            ]),
            textDirection: TextDirection.rtl,
          ),
          if (odd)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                kGoesAgainst(onRoad.length - mine),
                style: tCaption(lead ? _goldDeep : _inkMute),
              ),
            ),
          const Divider(height: 22),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(kWhatFollows, style: tLabel()),
          ),

          // Every place on the road, in the muṣḥaf's own order, and all of
          // them. A column is a thing read down; a column with a disclosure in
          // the middle of it is a list again, which is what this card used to
          // be.
          for (final p in onRoad) _Place(position: p, onJump: onJump),

          // The ḍābiṭ for this place, under the column rather than in front of
          // it: the column shows what parts the places, the ḍābiṭ says how to
          // hold it, and in that order.
          if (here.first['peg'] != null) ...[
            const SizedBox(height: 8),
            _Peg(position: here.first, isHere: true),
          ],
          if (otherPegs.isNotEmpty)
            Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                title: Text(kOtherPegs, style: tLabel()),
                children: [
                  for (final p in otherPegs) _OtherPeg(position: p),
                ],
              ),
            ),

          // The places the curated entry gathered that do not say this wording.
          // They are kept, because the list is the source and dropping rows of
          // it silently would be the app overruling it -- but they are named
          // for what they are and set in their own words, not as tails.
          if (elsewhere.isNotEmpty)
            Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                title: Text(kOtherRoads(elsewhere.length), style: tBody(_accent)),
                subtitle: Text(kOtherRoadsGloss, style: tLabel()),
                children: [
                  for (final p in elsewhere)
                    _OtherRoad(position: p, onJump: onJump),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The normalised first word of a place's tail: what it says at the fork.
String? _firstTail(Map<String, Object?> position) {
  final tail = _tailOf(position);
  return tail.isEmpty ? null : _norm(tail.first);
}

/// One place on the road, as a row of the column.
///
/// Gutter, then tail, then the way there. The gutter is a fixed measure and
/// every row carries the same padding -- including the one washed gold -- so
/// the tails all begin at the same x and the eye can run down them.
class _Place extends StatelessWidget {
  const _Place({required this.position, required this.onJump});

  final Map<String, Object?> position;
  final void Function(int page, String verseKey) onJump;

  /// How much of the road to set before the fork.
  ///
  /// A fork word alone is a word out of the air. Three carries the run-up a
  /// reciter actually has in the mouth when the parting arrives, and where the
  /// places do not agree that far back it is the third word that shows it --
  /// أَطِيعُوا۟ against يُطِعِ against وَأَطِعْنَ, each above its own tail.
  static const int _leadIn = 3;

  @override
  Widget build(BuildContext context) {
    final here = position['is_query'] == true;
    final page = position['page'] as int?;
    final key = position['verse_key'] as String;
    final tail = _tailOf(position);
    final road = _roadOf(position);
    final lead = road.length <= _leadIn
        ? road
        : road.sublist(road.length - _leadIn);

    return InkWell(
      onTap: page == null ? null : () => onJump(page, key),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: here ? _goldSoft : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${position['surah_name_ar']} ${arDigits(key)}',
                  textDirection: TextDirection.rtl,
                  style: tLabel(here ? _accent : _inkMute),
                ),
                const Spacer(),
                if (page != null)
                  Text('${pageN(page)}  ‹', style: tLabel(_accent)),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                // The run-up, in a measure of its own so that every fork word
                // below begins at the same x. Aligned to the end of the slot,
                // which in a right-to-left line is its left edge, so what
                // falls off when the run-up is long is the word furthest from
                // the fork -- the one that matters least.
                SizedBox(
                  width: 132,
                  child: Text(
                    lead.map((w) => w['text']).join(' '),
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: tQuranSmall(_inkMute),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: tail.isEmpty
                      ? Text(
                          position['after'] == null
                              ? kEndsSurah
                              : kNothingDropped,
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                          style: tCaption(_inkMute),
                        )
                      : Text.rich(
                          TextSpan(children: [
                            // The fork word: the first thing this place says
                            // that its siblings may not. On the row that is
                            // already washed gold the ink alone carries it --
                            // a wash on a wash marks nothing.
                            TextSpan(
                              text: '${tail.first['text']}',
                              style: here
                                  ? tQuranSmall(_goldDeep)
                                  : tQuranSmall(_goldDeep)
                                      .copyWith(backgroundColor: _goldSoft),
                            ),
                            for (final w in tail.skip(1))
                              TextSpan(
                                text: ' ${w['text']}',
                                style: tQuranSmall(here ? _ink : _inkSoft),
                              ),
                          ]),
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A place the curated entry gathered whose road ends on another word.
///
/// Set in its own wording rather than as a tail, because a tail of it would be
/// answering a question nobody asked: what follows a road this place is not on.
class _OtherRoad extends StatelessWidget {
  const _OtherRoad({required this.position, required this.onJump});

  final Map<String, Object?> position;
  final void Function(int page, String verseKey) onJump;

  @override
  Widget build(BuildContext context) {
    final page = position['page'] as int?;
    final key = position['verse_key'] as String;

    return InkWell(
      onTap: page == null ? null : () => onJump(page, key),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SizedBox(
              width: 104,
              child: Text(
                '${position['surah_name_ar']} ${arDigits(key)}',
                textDirection: TextDirection.rtl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tLabel(),
              ),
            ),
            Expanded(
              child: Text(
                position['span_text'] as String,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tQuranSmall(_inkSoft),
              ),
            ),
            const SizedBox(width: 6),
            if (page != null) Text('‹', style: tCaption(_accent)),
          ],
        ),
      ),
    );
  }
}

class _Peg extends StatelessWidget {
  const _Peg({required this.position, required this.isHere});

  final Map<String, Object?> position;
  final bool isHere;

  @override
  Widget build(BuildContext context) {
    final peg = position['peg'] as Map<String, Object?>?;
    if (peg == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(kNoPegShort, style: tCaption(_inkMute)),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isHere ? _goldSoft : _surface,
        borderRadius: BorderRadius.circular(6),
        border: isHere ? Border.all(color: _goldBright, width: 0.8) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(pegKind(peg['kind'] as String), style: tLabel(_gold)),
          const SizedBox(height: 6),
          // pegs.text_ar, exactly as pipeline.pegs wrote it.
          Text(
            arDigits(peg['text_ar'] as String),
            textDirection: TextDirection.rtl,
            style: tQuranSmall(isHere ? _goldDeep : _inkSoft),
          ),
        ],
      ),
    );
  }
}

/// A sibling's ḍābiṭ, behind a disclosure. Reference, not the answer -- the
/// answer is the column.
class _OtherPeg extends StatelessWidget {
  const _OtherPeg({required this.position});

  final Map<String, Object?> position;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(position['surah_name_ar'] as String,
                  textDirection: TextDirection.rtl, style: tQuranSmall()),
              const SizedBox(width: 8),
              Text(arDigits(position['verse_key'] as String), style: tLabel()),
            ],
          ),
          _Peg(position: position, isHere: false),
        ],
      ),
    );
  }
}

/// One ayah that reads like the one tapped, and where the two part.
///
/// The twin is set whole, with the words it shares dimmed and the words it
/// does not lit -- so the eye lands on the parting rather than reading two
/// near-identical ayat and hoping to spot it. Under that, the partings are
/// paired and named: here this, there that, which is how a teacher says it
/// and how a dabit is held.
class _Twin extends StatelessWidget {
  const _Twin({required this.twin, required this.onJump});

  final SimilarAyah twin;
  final void Function(int page, String verseKey) onJump;

  /// A parting can be one-sided -- one ayah simply carrying words the other
  /// has nowhere -- and an empty half is worth showing as empty rather than
  /// leaving the row to collapse.
  Widget _side(String label, List<String> words, bool here) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SizedBox(
              width: 52,
              child: Text(label, style: tLabel(here ? _accent : _inkMute)),
            ),
            Expanded(
              child: Text(
                words.isEmpty ? kNothingDropped : words.join(' '),
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: words.isEmpty
                    ? tCaption(_inkMute)
                    : tQuranSmall(here ? _ink : _goldDeep),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final page = twin.page;
    // Four is enough to be a dabit. Past that the two ayat are not a pair to
    // hold apart by their differences, they are simply two ayat, and printing
    // a dozen rows says so less clearly than one line does.
    final partings = twin.partings.take(4).toList();
    final rest = twin.partings.length - partings.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _raised,
        border: Border.all(
            color: twin.identical ? _goldBright : _surfaceAlt,
            width: twin.identical ? 0.8 : 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: page == null ? null : () => onJump(page, twin.verseKey),
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                Text(twin.surahNameAr,
                    textDirection: TextDirection.rtl, style: tQuranSmall()),
                const SizedBox(width: 8),
                Text(arDigits(twin.verseKey), style: tLabel()),
                const Spacer(),
                if (page != null)
                  Text('${pageN(page)}  \u2039', style: tCaption(_accent)),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // The twin itself. One size throughout -- a larger face for the
          // differing words would ripple the baseline of a line of naskh --
          // so the parting is carried by ink and by a wash behind it.
          Text.rich(
            TextSpan(children: [
              for (final w in twin.there)
                TextSpan(
                  text: '${w.text} ',
                  style: w.same
                      ? tQuranSmall(_inkSoft)
                      : tQuranSmall(_goldDeep)
                          .copyWith(backgroundColor: _goldSoft),
                ),
            ]),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 10),

          Text(
            twin.identical ? kIdentical : kPartsIn(twin.partings.length),
            style: tCaption(twin.identical ? _goldDeep : _inkMute),
          ),
          if (twin.identical)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(kIdenticalGloss, style: tLabel()),
            ),
          for (final c in partings) ...[
            const SizedBox(height: 4),
            _side(kHere, c.here, true),
            _side(kThere, c.there, false),
          ],
          if (rest > 0)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 6, start: 52),
              child: Text(kMorePartings(rest), style: tLabel()),
            ),
        ],
      ),
    );
  }
}

/// One span pass A found repeating, with its dawabit.
class _Detected extends StatelessWidget {
  const _Detected({required this.match, required this.onJump});

  final Map<String, Object?> match;
  final void Function(int page, String verseKey) onJump;

  @override
  Widget build(BuildContext context) {
    final elsewhere = (match['elsewhere'] as List).cast<Map<String, Object?>>();
    final dawabit = (match['dawabit'] as List).cast<Map<String, Object?>>();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            match['span_text'] as String,
            textDirection: TextDirection.rtl,
            style: tQuranSmall(),
          ),
          const SizedBox(height: 6),
          Text(
            '${repeatsN(match['occurrence_count'] as int)}  \u00b7  '
            '${wordsN(match['span_len'] as int)}'
            '${match['cross_surah'] == true ? "  \u00b7  $kCrossesSurah" : ""}',
            style: tLabel(),
          ),
          for (final d in dawabit)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(pegKind(d['rule_code'] as String),
                          style: tLabel(_gold)),
                      const SizedBox(width: 8),
                      if (d['verified'] == true)
                        Icon(Icons.check, size: 12, color: _accent),
                      const Spacer(),
                      Text('$kPegStrength ${arPercent(d['strength'] as num)}',
                          style: tLabel()),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // dawabit.text_ar, as pipeline.apply_rules wrote it.
                  Text(
                    arDigits(d['text_ar'] as String),
                    textDirection: TextDirection.rtl,
                    style: tQuranSmall(_inkSoft),
                  ),
                ],
              ),
            ),
          if (elsewhere.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 2,
              children: [
                for (final p in elsewhere)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text(
                        '${p['surah_name_ar']} '
                        '${arDigits(p['verse_key'] as String)}',
                        textDirection: TextDirection.rtl,
                        style: tLabel(_ink)),
                    onPressed: p['page'] == null
                        ? null
                        : () =>
                            onJump(p['page'] as int, p['verse_key'] as String),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
