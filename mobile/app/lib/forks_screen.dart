// The two kinds of mutashābihāt, side by side.
//
// This screen used to be the fork list alone. There are two confusions in the
// muṣḥaf, though, and only one of them was reachable from anywhere: a shared
// run of wording that several places part from at a fork, and a whole āyah
// with a near twin. The second had been in the corpus all along and could be
// met only by tapping the right word on the right page.
//
// So one destination, two tabs: الألفاظ for the forks below, الآيات for the
// twins in twins.dart.
//
// The official mutashābihāt, as forks.
//
// A fork is the road every position shares, the point where they part, and each
// way out with the positions taking it. `shape` says what it costs to hold:
// `all_but_one` is one exception to remember, `many` is a peg per position.
//
// This is the port of app/forks_page.py -- the page the web service serves at
// /official, and the one thing in the project the phone could not see.

import 'package:flutter/material.dart';
import 'package:quran_port/forks.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;

import 'strings.dart';
import 'theme.dart';
import 'twins.dart';
import 'type.dart';

// The palette in force, read by name; see theme.dart. These are getters
// rather than constants because the light can change while the app is up.
Color get _raised => palette.raised;
Color get _paper => palette.paper;
Color get _ink => palette.ink;
Color get _inkSoft => palette.inkSoft;
Color get _inkMute => palette.inkMute;
Color get _accent => palette.accent;
Color get _accentSoft => palette.accentSoft;
Color get _gold => palette.gold;
Color get _goldSoft => palette.goldSoft;
Color get _surface => palette.surface;
Color get _surfaceAlt => palette.surfaceAlt;
Color get _wrongSofter => palette.wrongSofter;

/// Cheapest to hold first, which is the order `sort: useful` puts them in.
final Map<String, ({String label, String gloss, Color tint})> kShapeInfo = {
  'all_but_one': (
    label: 'واحد يخالف',
    gloss: 'تأخذ المواضع كلها وجهًا واحدًا إلا موضعًا واحدًا',
    tint: _accentSoft,
  ),
  'two_way': (
    label: 'وجهان',
    gloss: 'تنقسم المواضع على وجهين',
    tint: _goldSoft,
  ),
  'many': (
    label: 'لكلٍّ وجه',
    gloss: 'يحتاج كل موضع إلى ضابط يخصه',
    tint: _wrongSofter,
  ),
  'no_fork': (
    label: 'لا افتراق',
    gloss: 'لا تفترق المواضع؛ وإنما يميزها ما قبلها',
    tint: _surface,
  ),
};

class ForksScreen extends StatefulWidget {
  const ForksScreen({
    super.key,
    required this.db,
    required this.onGo,
    required this.onOpenMenu,
  });

  final CommonDatabase db;

  /// Turn the muṣḥaf to this page and select this āyah.
  final void Function(int page, String verseKey) onGo;

  /// The same drawer the sheet opens, so the lists, the search and the
  /// settings reach every screen and not only the muṣḥaf.
  final VoidCallback onOpenMenu;

  @override
  State<ForksScreen> createState() => _ForksScreenState();
}

class _ForksScreenState extends State<ForksScreen> {
  static const int _pageSize = 20;

  String? _shape;
  String _sort = 'useful';
  int _offset = 0;
  Map<String, Object?>? _doc;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _doc = forkIndex(
        widget.db,
        shape: _shape,
        sort: _sort,
        limit: _pageSize,
        offset: _offset,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final counts = doc?['counts'] as Map<String, Object?>?;
    final total = (counts?['total'] as int?) ?? 0;
    final phrases =
        ((doc?['phrases'] as List?) ?? const []).cast<Map<String, Object?>>();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _paper,
        appBar: AppBar(
          leading: IconButton(
            tooltip: kMenu,
            onPressed: widget.onOpenMenu,
            icon: const Icon(Icons.menu),
          ),
          title: Text(kNavForks, style: tTitle()),
          bottom: TabBar(
            labelColor: _accent,
            unselectedLabelColor: _inkMute,
            indicatorColor: _accent,
            labelStyle: tBody(_accent),
            unselectedLabelStyle: tBody(_inkMute),
            tabs: const [
              Tab(text: kTabPhrases),
              Tab(text: kTabAyat),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _phrases(doc, total, phrases),
            TwinsTab(db: widget.db, onGo: widget.onGo),
          ],
        ),
      ),
    );
  }

  /// The fork list: what it used to be, moved under a tab.
  Widget _phrases(
    Map<String, Object?>? doc,
    int total,
    List<Map<String, Object?>> phrases,
  ) {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _chip(kAll, _shape == null, () {
                _shape = null;
                _offset = 0;
                _load();
              }),
              for (final s in kShapeInfo.keys)
                _chip(kShapeInfo[s]!.label, _shape == s, () {
                  _shape = s;
                  _offset = 0;
                  _load();
                }),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Text(places(total), style: tLabel()),
              const Spacer(),
              DropdownButton<String>(
                value: _sort,
                underline: const SizedBox.shrink(),
                style: tCaption(_ink),
                items: const [
                  DropdownMenuItem(value: 'useful', child: Text(kSortUseful)),
                  DropdownMenuItem(
                      value: 'positions', child: Text(kSortPositions)),
                  DropdownMenuItem(
                      value: 'branches', child: Text(kSortBranches)),
                  DropdownMenuItem(value: 'surahs', child: Text(kSortSurahs)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  _sort = v;
                  _offset = 0;
                  _load();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: doc == null
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: phrases.length + 1,
                  itemBuilder: (context, i) {
                    if (i == phrases.length) return _pager(total);
                    return _ForkCard(
                      fork: phrases[i],
                      db: widget.db,
                      onGo: widget.onGo,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _chip(String label, bool on, VoidCallback tap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
        child: ChoiceChip(
          label: Text(label, style: tCaption(_ink)),
          selected: on,
          onSelected: (_) => tap(),
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

class _ForkCard extends StatelessWidget {
  const _ForkCard({required this.fork, required this.db, required this.onGo});

  final Map<String, Object?> fork;
  final CommonDatabase db;
  final void Function(int page, String verseKey) onGo;

  @override
  Widget build(BuildContext context) {
    final shape = fork['shape'] as String;
    final info = kShapeInfo[shape];
    final branches = (fork['branches'] as List).cast<Map<String, Object?>>();
    final tail = fork['road_tail_ar'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _raised,
        border: Border.all(color: _surfaceAlt),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: info?.tint ?? _surface,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(info?.label ?? shape, style: tLabel(_gold)),
              ),
              const Spacer(),
              Text(
                '${places(fork['position_count'] as int)}  ·  '
                '${ways(fork['branch_count'] as int)}  ·  '
                '${surahsN(fork['surah_count'] as int)}',
                style: tLabel(),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // The road: the shared wording, then whatever the positions still say
          // together after it, dimmed to show where the agreement runs on.
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: fork['phrase_ar'] as String,
                style: tQuranBody(),
              ),
              if (tail != null)
                TextSpan(text: ' $tail', style: tQuranBody(_inkMute)),
            ]),
            textDirection: TextDirection.rtl,
          ),

          if (info != null) ...[
            const SizedBox(height: 6),
            Text(info.gloss, style: tCaption(_inkMute)),
          ],
          const Divider(height: 20),

          // Each way out of the fork.
          for (final b in branches) _Branch(branch: b, onGo: onGo),
        ],
      ),
    );
  }
}

class _Branch extends StatelessWidget {
  const _Branch({required this.branch, required this.onGo});

  final Map<String, Object?> branch;
  final void Function(int page, String verseKey) onGo;

  @override
  Widget build(BuildContext context) {
    final positions =
        (branch['positions'] as List).cast<Map<String, Object?>>();
    final largest = branch['is_largest'] == true;
    final token = branch['token_ar'] as String?;
    final endsSurah = branch['ends_surah'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(largest ? Icons.subdirectory_arrow_right : Icons.arrow_left,
                  size: 16, color: largest ? _inkMute : _accent),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  endsSurah ? kEndsSurah : (token ?? '—'),
                  textDirection: TextDirection.rtl,
                  // The way the crowd does not take is the one worth seeing,
                  // and it is carried by size and ink rather than by weight:
                  // only Amiri Regular is bundled, so a w600 here would be
                  // synthesised and the naskh joins would thicken into blots.
                  style: largest ? tQuranSmall(_inkSoft) : tQuranBody(),
                ),
              ),
              const SizedBox(width: 8),
              Text(ar(branch['position_count'] as int), style: tLabel()),
            ],
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              for (final p in positions)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: Text(
                    '${p['surah_name_ar']} '
                    '${arDigits(p['verse_key'] as String)}',
                    textDirection: TextDirection.rtl,
                    style: tLabel(_ink),
                  ),
                  onPressed: p['page'] == null
                      ? null
                      : () => onGo(p['page'] as int, p['verse_key'] as String),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
