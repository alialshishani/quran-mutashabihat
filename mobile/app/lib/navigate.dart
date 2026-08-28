// Getting somewhere.
//
// Until now the only way through the muṣḥaf was a swipe, which is 250 of them
// to reach sūrah 36. Three ways in: by sūrah, by juz', and by page.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqlite3/common.dart' as sql show CommonDatabase, Row;

const Color _ink = Color(0xFF191C19);
const Color _inkMute = Color(0xFF767C74);
const Color _accent = Color(0xFF16584A);

class Surah {
  Surah(sql.Row r)
      : number = r['surah'] as int,
        nameAr = r['name_ar'] as String,
        ayahCount = r['ayah_count'] as int,
        place = r['revelation_place'] as String?,
        firstPage = r['first_page'] as int,
        lastPage = r['last_page'] as int;

  final int number;
  final String nameAr;
  final int ayahCount;
  final String? place;
  final int firstPage;
  final int lastPage;
}

List<Surah> allSurahs(sql.CommonDatabase db) => [
      for (final r in db.select(
        'SELECT surah, name_ar, ayah_count, revelation_place, first_page, last_page '
        'FROM surahs ORDER BY surah'))
        Surah(r),
    ];

/// First page of each juz', read off the āyah that opens it.
List<({int juz, int page})> allJuz(sql.CommonDatabase db) => [
      for (final r in db.select(
        'SELECT juz, MIN(page_start) AS page FROM ayahs '
        'GROUP BY juz ORDER BY juz'))
        (juz: r['juz'] as int, page: r['page'] as int),
    ];

class NavigateSheet extends StatefulWidget {
  const NavigateSheet({
    super.key,
    required this.db,
    required this.pages,
    required this.onGo,
  });

  final sql.CommonDatabase db;
  final int pages;
  final void Function(int page) onGo;

  @override
  State<NavigateSheet> createState() => _NavigateSheetState();
}

class _NavigateSheetState extends State<NavigateSheet> {
  late final List<Surah> _surahs = allSurahs(widget.db);
  late final List<({int juz, int page})> _juz = allJuz(widget.db);
  final TextEditingController _page = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _go(int page) {
    if (page < 1 || page > widget.pages) return;
    Navigator.of(context).pop();
    widget.onGo(page);
  }

  @override
  Widget build(BuildContext context) {
    final surahs = _filter.isEmpty
        ? _surahs
        : _surahs.where((s) {
            final q = _filter.trim();
            return s.nameAr.contains(q) || s.number.toString() == q;
          }).toList();

    return DefaultTabController(
      length: 2,
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) => DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFFFCFCFA),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFDFE2DC),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _page,
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
                      onPressed: () => _go(int.tryParse(_page.text) ?? 0),
                      child: const Text('Go'),
                    ),
                  ],
                ),
              ),
              const TabBar(
                labelColor: _accent,
                indicatorColor: _accent,
                tabs: [Tab(text: 'Sūrah'), Tab(text: "Juz'")],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: TextField(
                            onChanged: (v) => setState(() => _filter = v),
                            decoration: const InputDecoration(
                              isDense: true,
                              prefixIcon: Icon(Icons.search, size: 18),
                              hintText: 'name or number',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            controller: controller,
                            itemCount: surahs.length,
                            itemBuilder: (context, i) {
                              final s = surahs[i];
                              return ListTile(
                                dense: true,
                                leading: Text('${s.number}',
                                    style: const TextStyle(
                                        fontFamily: 'monospace',
                                        color: _inkMute)),
                                title: Text(s.nameAr,
                                    textDirection: TextDirection.rtl,
                                    style: const TextStyle(
                                        fontFamily: 'Amiri',
                                        fontSize: 19,
                                        color: _ink)),
                                subtitle: Text(
                                  '${s.ayahCount} āyāt  ·  '
                                  '${s.place ?? "?"}  ·  page ${s.firstPage}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onTap: () => _go(s.firstPage),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    ListView.builder(
                      itemCount: _juz.length,
                      itemBuilder: (context, i) {
                        final j = _juz[i];
                        return ListTile(
                          dense: true,
                          leading: Text('${j.juz}',
                              style: const TextStyle(
                                  fontFamily: 'monospace', color: _inkMute)),
                          title: Text("Juz' ${j.juz}"),
                          trailing: Text('page ${j.page}',
                              style: const TextStyle(
                                  fontSize: 11, color: _inkMute)),
                          onTap: () => _go(j.page),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
