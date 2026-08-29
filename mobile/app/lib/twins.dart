// The āyāt that read alike, as a list to walk.
//
// The panel already answers "what reads like the āyah I tapped", but that is
// the only way in: you have to be standing on the right page and tap the
// right word. The forks have had a destination of their own since they were
// built, and this is the other confusion -- 2,336 pairs of āyāt, 1,546 of
// them word for word the same -- with nowhere to go and see them.
//
// So: the same screen, a second tab. Closest first, which puts the verbatim
// repeats at the head, and both āyāt set whole with their partings lit rather
// than one named and the other left to the eye.

import 'package:flutter/material.dart';
import 'package:quran_port/similar.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;

import 'strings.dart';
import 'theme.dart';
import 'type.dart';

// The palette in force, read by name; see theme.dart. These are getters
// rather than constants because the light can change while the app is up.
Color get _raised => palette.raised;
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

class TwinsTab extends StatefulWidget {
  const TwinsTab({super.key, required this.db, required this.onGo});

  final CommonDatabase db;

  /// Turn the muṣḥaf to this page and select this āyah.
  final void Function(int page, String verseKey) onGo;

  @override
  State<TwinsTab> createState() => _TwinsTabState();
}

class _TwinsTabState extends State<TwinsTab> {
  static const int _pageSize = 20;

  SimilarScope _scope = SimilarScope.all;
  int _offset = 0;
  SimilarPage? _page;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The alignment runs over the rows this page shows and no others, which is
  /// what makes 2,336 pairs pageable on a phone: the ranking is QUL's score,
  /// which is a column, so the database does the sorting and the diff is
  /// computed twenty times.
  void _load() {
    setState(() {
      _page = similarIndex(
        widget.db,
        scope: _scope,
        limit: _pageSize,
        offset: _offset,
      );
    });
  }

  void _pick(SimilarScope scope) {
    _scope = scope;
    _offset = 0;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    if (page == null) {
      return Center(
        child: SizedBox(
          width: 96,
          child: LinearProgressIndicator(
              minHeight: 2, backgroundColor: palette.line, color: _gold),
        ),
      );
    }
    if (page.total == 0 && _scope == SimilarScope.all) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Text(kTwinsEmpty,
              textAlign: TextAlign.center, style: tCaption(_inkMute)),
        ),
      );
    }

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _chip(kAll, SimilarScope.all),
              _chip(kScopeSameSurah, SimilarScope.sameSurah),
              _chip(kScopeCrossSurah, SimilarScope.crossSurah),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Text(pairsN(page.total), style: tLabel()),
              const Spacer(),
              Text(kTwinsGloss, style: tLabel()),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: page.pairs.length + 1,
            itemBuilder: (context, i) => i == page.pairs.length
                ? _pager(page.total)
                : _PairCard(pair: page.pairs[i], onGo: widget.onGo),
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, SimilarScope scope) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
        child: ChoiceChip(
          label: Text(label, style: tCaption(_ink)),
          selected: _scope == scope,
          onSelected: (_) => _pick(scope),
        ),
      );

  Widget _pager(int total) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              style: TextButton.styleFrom(textStyle: tCaption()),
              onPressed: _offset <= 0
                  ? null
                  : () {
                      _offset = (_offset - _pageSize).clamp(0, 1 << 30);
                      _load();
                    },
              child: const Text(kPrevious),
            ),
            Text(
                '${ar(_offset + 1)}–'
                '${ar((_offset + _pageSize).clamp(0, total))}',
                style: tLabel()),
            TextButton(
              style: TextButton.styleFrom(textStyle: tCaption()),
              onPressed: _offset + _pageSize >= total
                  ? null
                  : () {
                      _offset += _pageSize;
                      _load();
                    },
              child: const Text(kNext),
            ),
          ],
        ),
      );
}

/// Two āyāt, one above the other, each set whole with its partings lit.
///
/// Neither is "the" āyah here -- unlike the panel, which is answering about
/// one the reader has tapped, this is the pair itself, so the two are given
/// the same weight and either can be turned to.
class _PairCard extends StatelessWidget {
  const _PairCard({required this.pair, required this.onGo});

  final SimilarPair pair;
  final void Function(int page, String verseKey) onGo;

  Widget _side(String nameAr, String key, int? page, List<DiffWord> words) =>
      Builder(builder: (context) {
        return InkWell(
          onTap: page == null ? null : () => onGo(page, key),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(nameAr,
                        textDirection: TextDirection.rtl,
                        style: tQuranSmall()),
                    const SizedBox(width: 8),
                    Text(arDigits(key), style: tLabel()),
                    const Spacer(),
                    if (page != null)
                      Text('${pageN(page)}  ‹', style: tCaption(_accent)),
                  ],
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(children: [
                    for (final w in words)
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
              ],
            ),
          ),
        );
      });

  @override
  Widget build(BuildContext context) {
    final identical = pair.identical;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _raised,
        border: Border.all(color: identical ? _goldBright : _surfaceAlt),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: identical ? _goldSoft : _surface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              identical ? kIdenticalPair : kPartsIn(pair.partings.length),
              style: tLabel(identical ? _gold : _inkMute),
            ),
          ),
          const SizedBox(height: 8),
          _side(pair.aSurahNameAr, pair.aKey, pair.aPage, pair.a),
          const Divider(height: 18),
          _side(pair.bSurahNameAr, pair.bKey, pair.bPage, pair.b),
        ],
      ),
    );
  }
}
