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

const Color _ink = Color(0xFF191C19);
const Color _inkSoft = Color(0xFF4A5049);
const Color _inkMute = Color(0xFF767C74);
const Color _accent = Color(0xFF16584A);
const Color _wrong = Color(0xFF8C3B2E);

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
      for (final r in db.select('SELECT juz, MIN(page_start) AS page FROM ayahs '
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

  List<SearchHit> _hits = const [];
  bool _searching = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

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
        backgroundColor: const Color(0xFFFCFCFA),
        appBar: AppBar(
          title: TextField(
            controller: _query,
            onChanged: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: 'search the wording',
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
              : const TabBar(
                  labelColor: _accent,
                  indicatorColor: _accent,
                  tabs: [
                    Tab(text: 'Sūrah'),
                    Tab(text: "Juz'"),
                    Tab(text: 'Marked'),
                    Tab(text: 'Missed'),
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
    if (_hits.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Nothing found. The search matches the imlaei spelling — the one '
            'you type — not the Uthmānī rasm on the page.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _inkMute, height: 1.5),
          ),
        ),
      );
    }
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
            style: const TextStyle(
                fontFamily: 'Amiri', fontSize: 18, height: 1.9, color: _ink),
          ),
          subtitle: Text(
            '${h.surahNameAr}  ${h.verseKey}  ·  page ${h.page}',
            textDirection: TextDirection.rtl,
            style: const TextStyle(fontSize: 11, color: _inkMute),
          ),
        );
      },
    );
  }

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
                  width: 26,
                  child: Text('${s.number}',
                      style: const TextStyle(
                          fontFamily: 'monospace', color: _inkMute)),
                ),
                title: Text(s.nameAr,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                        fontFamily: 'Amiri', fontSize: 19, color: _ink)),
                subtitle: Text(
                  '${s.ayahCount} āyāt  ·  ${s.place ?? "?"}  ·  '
                  'page ${s.firstPage}',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () => _go(s.firstPage),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _pageJump() {
    final controller = TextEditingController();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.go,
              onSubmitted: (v) => _go(int.tryParse(v) ?? 0),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Page 1–${widget.pages}',
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => _go(int.tryParse(controller.text) ?? 0),
            child: const Text('Go'),
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
              width: 26,
              child: Text('${j.juz}',
                  style: const TextStyle(
                      fontFamily: 'monospace', color: _inkMute)),
            ),
            title: Text("Juz' ${j.juz}"),
            trailing: Text('page ${j.page}',
                style: const TextStyle(fontSize: 11, color: _inkMute)),
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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Nothing missed yet. In recall, hold the page when an āyah did '
            'not come to you, and it is kept here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _inkMute, height: 1.5),
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: missed.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final m = missed[i];
        return ListTile(
          leading: const Icon(Icons.error_outline, size: 18, color: _wrong),
          title: Text(m.surahNameAr,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                  fontFamily: 'Amiri', fontSize: 18, color: _ink)),
          subtitle: Text(
              '${m.verseKey}  ·  page ${m.page}  ·  '
              'missed ${m.count == 1 ? "once" : "${m.count} times"}',
              style: const TextStyle(fontSize: 11, color: _inkSoft)),
          trailing: IconButton(
            tooltip: 'Learnt it',
            icon: const Icon(Icons.check, size: 18),
            onPressed: () async {
              await widget.library.clearMiss(m.verseKey);
              if (mounted) setState(() {});
            },
          ),
          onTap: () => _go(m.page, m.verseKey),
        );
      },
    );
  }

  Widget _bookmarks() {
    final marks = widget.library.bookmarks;
    if (marks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Nothing marked yet. Open the controls on a page and use the '
            'bookmark button to mark the āyah you have selected.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _inkMute, height: 1.5),
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: marks.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final b = marks[i];
        return ListTile(
          leading: const Icon(Icons.bookmark, size: 18, color: _accent),
          title: Text(b.surahNameAr,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                  fontFamily: 'Amiri', fontSize: 18, color: _ink)),
          subtitle: Text('${b.verseKey}  ·  page ${b.page}',
              style: const TextStyle(fontSize: 11, color: _inkSoft)),
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
