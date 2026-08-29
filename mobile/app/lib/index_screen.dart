// The index: a way in that is not a swipe.
//
// The reference muṣḥaf apps all put this first -- sūrah, juz', bookmarks, a
// page field, and a resume -- and reach the page from it. This app keeps the
// page as home, since reading is what it is for, but the index is a screen of
// its own rather than a sheet with a list crammed into it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quran_port/search.dart';
import 'package:sqlite3/common.dart' as sql show CommonDatabase, Row;

import 'library.dart';
import 'strings.dart';
import 'theme.dart';
import 'type.dart';

// The palette in force, read by name; see theme.dart. These are getters
// rather than constants because the light can change while the app is up.
Color get _paper => palette.paper;
Color get _inkSoft => palette.inkSoft;
Color get _inkMute => palette.inkMute;
Color get _accent => palette.accent;
Color get _wrong => palette.wrong;

class Surah {
  Surah(sql.Row r)
      : number = r['surah'] as int,
        nameAr = r['name_ar'] as String,
        ayahCount = r['ayah_count'] as int,
        place = r['revelation_place'] as String?,
        firstPage = r['first_page'] as int;

  final int number;
  final String nameAr;
  final int ayahCount;
  final String? place;
  final int firstPage;
}

List<Surah> allSurahs(sql.CommonDatabase db) => [
      for (final r in db.select(
          'SELECT surah, name_ar, ayah_count, revelation_place, first_page '
          'FROM surahs ORDER BY surah'))
        Surah(r),
    ];

List<({int juz, int page})> allJuz(sql.CommonDatabase db) => [
      for (final r
          in db.select('SELECT juz, MIN(page_start) AS page FROM ayahs '
              'GROUP BY juz ORDER BY juz'))
        (juz: r['juz'] as int, page: r['page'] as int),
    ];

class IndexScreen extends StatefulWidget {
  const IndexScreen({
    super.key,
    required this.db,
    required this.pages,
    required this.library,
    required this.onGo,
  });

  final sql.CommonDatabase db;
  final int pages;
  final Library library;

  /// Turn to a page, and select an āyah there when one is named.
  final void Function(int page, [String? verseKey]) onGo;

  @override
  State<IndexScreen> createState() => _IndexScreenState();
}

class _IndexScreenState extends State<IndexScreen> {
  late final List<Surah> _surahs = allSurahs(widget.db);
  late final List<({int juz, int page})> _juz = allJuz(widget.db);
  final TextEditingController _query = TextEditingController();
  final TextEditingController _jump = TextEditingController();

  List<SearchHit> _hits = const [];
  bool _searching = false;

  @override
  void dispose() {
    _query.dispose();
    _jump.dispose();
    super.dispose();
  }

  /// Where a sūrah came down, in the word a muṣḥaf's own heading uses.
  String _place(String? place) => switch (place) {
        'makkah' => kMakki,
        'madinah' => kMadani,
        _ => '—',
      };

  void _go(int page, [String? verseKey]) {
    if (page < 1 || page > widget.pages) return;
    widget.onGo(page, verseKey);
  }

  void _search(String q) {
    // Short queries match most of the muṣḥaf and say nothing.
    if (q.trim().length < 2) {
      setState(() {
        _hits = const [];
        _searching = false;
      });
      return;
    }
    setState(() {
      _hits = searchAyat(widget.db, q, limit: 80);
      _searching = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: _paper,
        appBar: AppBar(
          title: TextField(
            controller: _query,
            onChanged: _search,
            textInputAction: TextInputAction.search,
            style: tBody(),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: kSearchHint,
              hintStyle: tBody(_inkMute),
              suffixIcon: _searching
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _query.clear();
                        _search('');
                      },
                    )
                  : const Icon(Icons.search, size: 18),
            ),
          ),
          bottom: _searching
              ? null
              : TabBar(
                  labelColor: _accent,
                  unselectedLabelColor: _inkMute,
                  indicatorColor: _accent,
                  labelStyle: tBody(_accent),
                  unselectedLabelStyle: tBody(_inkMute),
                  tabs: const [
                    Tab(text: kTabSurahs),
                    Tab(text: kTabJuz),
                    Tab(text: kTabMarked),
                    Tab(text: kTabMissed),
                  ],
                ),
        ),
        body: _searching
            ? _results()
            : TabBarView(
                children: [
                  _surahList(),
                  _juzList(),
                  _bookmarks(),
                  _missed(),
                ],
              ),
      ),
    );
  }

  Widget _results() {
    if (_hits.isEmpty) return _empty(Icons.search_off_outlined, kNothingFound);
    return ListView.separated(
      itemCount: _hits.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final h = _hits[i];
        return ListTile(
          onTap: () => _go(h.page, h.verseKey),
          title: Text(
            h.textAr,
            textDirection: TextDirection.rtl,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: tQuranSmall(),
          ),
          subtitle: Text(
            '${h.surahNameAr}  ${arDigits(h.verseKey)}  ·  ${pageN(h.page)}',
            textDirection: TextDirection.rtl,
            style: tLabel(),
          ),
        );
      },
    );
  }

  /// A list with nothing in it yet. All four of these used to be a wall of
  /// grey sentence with no shape to it; a mark and a rule give the eye
  /// somewhere to land and say that the emptiness is expected rather than a
  /// failure to load.
  Widget _empty(IconData mark, String says) => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(mark, size: 34, color: _inkMute.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(says, textAlign: TextAlign.center, style: tCaption(_inkMute)),
            ],
          ),
        ),
      );

  Widget _surahList() {
    return Column(
      children: [
        _pageJump(),
        Expanded(
          child: ListView.builder(
            itemCount: _surahs.length,
            itemBuilder: (context, i) {
              final s = _surahs[i];
              return ListTile(
                dense: true,
                leading: SizedBox(
                  width: 28,
                  child: Text(ar(s.number),
                      textAlign: TextAlign.center, style: tLabel()),
                ),
                title: Text(s.nameAr,
                    textDirection: TextDirection.rtl, style: tQuranSmall()),
                subtitle: Text(
                  '${ayatN(s.ayahCount)}  ·  ${_place(s.place)}  ·  '
                  '${pageN(s.firstPage)}',
                  style: tLabel(),
                ),
                onTap: () => _go(s.firstPage),
              );
            },
          ),
        ),
      ],
    );
  }

  /// The way to a page by its number, which is how anyone who knows the
  /// muṣḥaf reaches a page.
  ///
  /// The controller is a field, not a local. It used to be built inside this
  /// method, so every rebuild of the tab -- a keystroke in the search box, a
  /// theme change, a returning keyboard -- threw away the one holding what had
  /// been typed and made a fresh empty one. The number vanished as you typed
  /// it, and the controller leaked on each pass.
  Widget _pageJump() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _jump,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.go,
              style: tBody(),
              onSubmitted: (v) => _go(int.tryParse(v) ?? 0),
              decoration: InputDecoration(
                isDense: true,
                labelText: kPageField(widget.pages),
                labelStyle: tCaption(_inkMute),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(textStyle: tBody()),
            onPressed: () => _go(int.tryParse(_jump.text) ?? 0),
            child: const Text(kGo),
          ),
        ],
      ),
    );
  }

  Widget _juzList() => ListView.builder(
        itemCount: _juz.length,
        itemBuilder: (context, i) {
          final j = _juz[i];
          return ListTile(
            dense: true,
            leading: SizedBox(
              width: 28,
              child: Text(ar(j.juz),
                  textAlign: TextAlign.center, style: tLabel()),
            ),
            title: Text(juzN(j.juz), style: tBody()),
            trailing: Text(pageN(j.page), style: tLabel()),
            onTap: () => _go(j.page),
          );
        },
      );

  /// What recall asked for and did not get, worst first.
  ///
  /// Only failures are here. A page that went well leaves no trace, so this is
  /// a list of work rather than a log -- and an ayah leaves it when you say it
  /// has been learnt, not on a timer.
  Widget _missed() {
    final missed = widget.library.missed;
    if (missed.isEmpty) {
      return _empty(Icons.spa_outlined, kNothingMissed);
    }
    return ListView.separated(
      itemCount: missed.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final m = missed[i];
        return ListTile(
          leading: Icon(Icons.error_outline, size: 18, color: _wrong),
          title: Text(m.surahNameAr,
              textDirection: TextDirection.rtl, style: tQuranSmall()),
          subtitle: Text(
              '${arDigits(m.verseKey)}  ·  ${pageN(m.page)}  ·  '
              '$kMissedTally ${timesN(m.count)}',
              style: tLabel(_inkSoft)),
          trailing: TextButton(
            style: TextButton.styleFrom(textStyle: tCaption()),
            onPressed: () async {
              await widget.library.clearMiss(m.verseKey);
              if (mounted) setState(() {});
            },
            child: const Text(kLearnt),
          ),
          onTap: () => _go(m.page, m.verseKey),
        );
      },
    );
  }

  Widget _bookmarks() {
    final marks = widget.library.bookmarks;
    if (marks.isEmpty) {
      return _empty(Icons.bookmark_border, kNothingMarked);
    }
    return ListView.separated(
      itemCount: marks.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final b = marks[i];
        return ListTile(
          leading: Icon(Icons.bookmark, size: 18, color: _accent),
          title: Text(b.surahNameAr,
              textDirection: TextDirection.rtl, style: tQuranSmall()),
          subtitle: Text('${arDigits(b.verseKey)}  ·  ${pageN(b.page)}',
              style: tLabel(_inkSoft)),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () async {
              await widget.library.toggle(b);
              if (mounted) setState(() {});
            },
          ),
          onTap: () => _go(b.page, b.verseKey),
        );
      },
    );
  }
}
