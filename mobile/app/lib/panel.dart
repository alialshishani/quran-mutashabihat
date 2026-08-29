// What the print cannot say.
//
// For the tapped ayah: every official mutashabih phrase touching it, and for
// each, the peg that tells this position from the others -- then every sibling
// position, each with its own peg, as a way to turn there.
//
// Every string here comes from the database. The peg sentences are `pegs.text_ar`
// as `pipeline.pegs` wrote them; nothing is composed in the app.

import 'package:flutter/material.dart';

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
    required this.onJump,
  });

  final String verseKey;

  /// The curated QUL list, each position with its peg.
  final List<Map<String, Object?>> matches;

  /// Pass A's own detection: spans this ayah repeats elsewhere, with any dabit
  /// that verified for them. Behind a disclosure, as the web page has it -- the
  /// curated phrases are the answer, these are the evidence behind it.
  final List<Map<String, Object?>> detected;

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
                  detected.isEmpty ? kNothingHere : kNothingCurated,
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

class _Phrase extends StatelessWidget {
  const _Phrase({required this.match, required this.onJump, this.lead = false});

  final Map<String, Object?> match;
  final void Function(int page, String verseKey) onJump;

  /// The one this āyah is actually at risk from, shown open and first.
  final bool lead;

  @override
  Widget build(BuildContext context) {
    final here = (match['here'] as List).cast<Map<String, Object?>>();
    final elsewhere = (match['elsewhere'] as List).cast<Map<String, Object?>>();
    final fork =
        here.isEmpty ? null : here.first['fork'] as Map<String, Object?>?;

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
          // The shared wording itself.
          Text(
            match['text_ar'] as String,
            textDirection: TextDirection.rtl,
            style: tQuranLead(),
          ),
          const SizedBox(height: 8),
          Text(
            '${places(match['set_count'] as int)}  ·  '
            '${surahsN(match['surah_count'] as int)}  ·  '
            '${wordsN(match['span_len'] as int)}',
            style: tLabel(),
          ),
          if (fork != null) _Turning(fork: fork, lead: lead),
          const Divider(height: 22),

          // The peg for the position sitting in the āyah that was tapped.
          for (final h in here) _Peg(position: h, isHere: true),

          // Where else the road runs. It is the evidence behind the counts
          // above, not the thing to be read: a reciter who wants to know why
          // this place is hard has been told already, in one line.
          if (elsewhere.isNotEmpty)
            Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                title:
                    Text(kOtherPlaces(elsewhere.length), style: tLabel()),
                children: [
                  for (final e in elsewhere)
                    _Sibling(position: e, onJump: onJump),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Where the road this place is on parts, and which way this place goes.
///
/// The road is what several places say alike; the fork is the first word at
/// which they stop agreeing. Nothing in the road says which way to go, so this
/// is the whole of what a reciter has to hold -- and the count beside each way
/// is why: the mouth takes the way the most places take.
class _Turning extends StatelessWidget {
  const _Turning({required this.fork, required this.lead});

  final Map<String, Object?> fork;
  final bool lead;

  String _word(Map<String, Object?> way) => (way['ends_surah'] == true)
      ? kEndsSurah
      : (way['token'] as String? ?? '—');

  @override
  Widget build(BuildContext context) {
    final rivals = (fork['rivals'] as List).cast<Map<String, Object?>>();
    final placeCount = fork['places'] as int;
    final mine = fork['mine'] as int;
    final odd = mine < placeCount - mine;
    final shown = rivals.take(3).toList();
    final rest = rivals.skip(3).toList();
    final restPlaces = rest.fold<int>(0, (n, r) => n + (r['places'] as int));

    Widget way(String label, String word, int count, bool here) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(
                width: 76,
                child: Text(label, style: tLabel(here ? _accent : _inkMute)),
              ),
              Expanded(
                child: Text(word,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.right,
                    style: here ? tQuranBody() : tQuranSmall(_inkSoft)),
              ),
              const SizedBox(width: 8),
              Text(ar(count), style: tLabel(here ? _accent : _inkMute)),
            ],
          ),
        );

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: odd && lead ? _goldSoft : _surface,
        border: Border.all(color: odd && lead ? _goldBright : _surfaceAlt),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            odd ? kGoesAgainst(placeCount - mine) : kShareRoad(placeCount),
            style: tCaption(odd ? _goldDeep : _inkMute),
          ),
          way(
              kHere,
              _word({'token': fork['turn'], 'ends_surah': fork['ends_surah']}),
              mine,
              true),
          // The ways the crowd takes, biggest first, and only the first few.
          // A road that parts eight ways is not eight things to hold: it is
          // one -- what this place says -- against a scatter, and printing the
          // scatter puts the reference list back inside the card.
          for (var i = 0; i < shown.length; i++)
            way(i == 0 ? kElsewhere : '', _word(shown[i]),
                shown[i]['places'] as int, false),
          if (rest.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 6, start: 76),
              child:
                  Text(kOtherWays(rest.length, restPlaces), style: tLabel()),
            ),
        ],
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
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text(kNoPegShort, style: tCaption(_inkMute)),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isHere ? _goldSoft : _surface,
        borderRadius: BorderRadius.circular(6),
        border: isHere ? Border.all(color: _goldBright, width: 0.8) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(peg['kind'] as String, style: tLabel(_gold)),
              const Spacer(),
              Text('$kPegStrength ${ar(peg['strength'] as int)}',
                  style: tLabel()),
            ],
          ),
          const SizedBox(height: 6),
          // pegs.text_ar, exactly as pipeline.pegs wrote it.
          Text(
            peg['text_ar'] as String,
            textDirection: TextDirection.rtl,
            style: tQuranSmall(isHere ? _goldDeep : _inkSoft),
          ),
        ],
      ),
    );
  }
}

class _Sibling extends StatelessWidget {
  const _Sibling({required this.position, required this.onJump});

  final Map<String, Object?> position;
  final void Function(int page, String verseKey) onJump;

  @override
  Widget build(BuildContext context) {
    final page = position['page'] as int?;
    final key = position['verse_key'] as String;

    return InkWell(
      onTap: page == null ? null : () => onJump(page, key),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(position['surah_name_ar'] as String,
                    textDirection: TextDirection.rtl, style: tQuranSmall()),
                const SizedBox(width: 8),
                Text(arDigits(key), style: tLabel()),
                const Spacer(),
                if (page != null)
                  Text('${pageN(page)}  ‹', style: tCaption(_accent)),
              ],
            ),
            const SizedBox(height: 4),
            _Peg(position: position, isHere: false),
          ],
        ),
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
                      Text(d['rule_code'] as String, style: tLabel(_gold)),
                      const SizedBox(width: 8),
                      if (d['verified'] == true)
                        Icon(Icons.check, size: 12, color: _accent),
                      const Spacer(),
                      Text('$kPegStrength ${ar(d['strength'] as int)}',
                          style: tLabel()),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // dawabit.text_ar, as pipeline.apply_rules wrote it.
                  Text(
                    d['text_ar'] as String,
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
