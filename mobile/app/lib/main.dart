// The mushaf, page by page, off the real corpus.
//
// Every page is built by `mushafPage` from package:quran_port -- the Dart port
// of app/lookup.py, checked page for page against the Python's own output -- and
// set in the font the King Fahd Complex cut for that page, loaded when the page
// is turned to.
//
// Nothing here composes Qur'anic text. Every token, the basmalah included,
// arrives from the database, as it does on the Python side.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quran_port/lookup.dart' as ql;
import 'package:quran_port/mushaf.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;

import 'corpus.dart';
import 'drill_screen.dart';
import 'forks_screen.dart';
import 'index_screen.dart';
import 'library.dart';
import 'panel.dart';

const int kFallbackPage = 89;

/// The face for the lines the page fonts cannot set -- surah headings, the
/// basmalah, and the Uthmani fallback. Bundled, not fallen back to: the engine
/// fetches its own Arabic fallback over the network, which offline never gets.
const String kDrawnFace = 'Amiri';

/// The margin the sheet is given on each side. Every pixel here comes off the
/// measure, and so off the size of the letters -- 14 is about the least that
/// still reads as a margin rather than a crop.
const double kEdgeMargin = 14;

const Color _ink = Color(0xFF191C19);
const Color _inkMute = Color(0xFF767C74);
const Color _gold = Color(0xFF8A6C22);

/// The stylesheet's .qline line-height. The glyphs ask for 1.531em, so they
/// overflow their line box by design and must not be clipped.
const double kLineHeight = 1.35;

/// The view deep-links as `#p=89`, as the stylesheet's page does.
///
/// Read before anything else in `main`. Flutter web's default URL strategy
/// keeps its route in the fragment too, and it has rewritten `#p=89` to its own
/// form by the time the first widget is built -- so reading it later gets the
/// router's fragment, not the one the reader typed.
int initialPage = kFallbackPage;

int _pageFromFragment() {
  final m = RegExp(r'(?:^|&)p=(\d+)').firstMatch(Uri.base.fragment);
  return m == null ? kFallbackPage : int.parse(m.group(1)!);
}

Future<void> main() async {
  initialPage = _pageFromFragment();
  WidgetsFlutterBinding.ensureInitialized();
  // The sheet wants every pixel: the type size is derived from the width of the
  // text block, so chrome does not merely crowd the page, it shrinks the type.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MushafApp());
}

class MushafApp extends StatelessWidget {
  const MushafApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mushaf',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF16584A)),
          scaffoldBackgroundColor: const Color(0xFFFCFCFA),
        ),
        home: const Loader(),
      );
}

class Loader extends StatefulWidget {
  const Loader({super.key});

  @override
  State<Loader> createState() => _LoaderState();
}

class _LoaderState extends State<Loader> {
  late final Future<({CommonDatabase db, Library library})> _db = _open();

  Future<({CommonDatabase db, Library library})> _open() async {
    final db = await openCorpus();
    final library = await Library.open();
    return (db: db, library: library);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({CommonDatabase db, Library library})>(
      future: _db,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('${snap.error}'),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return HomeShell(db: snap.data!.db, library: snap.data!.library);
      },
    );
  }
}


/// Three peers, not one screen with the rest hidden behind an icon.
///
/// The muṣḥaf keeps the whole screen while reading -- the bar goes with the
/// rest of the chrome on a tap -- but it is a destination beside the forks and
/// the drill rather than the only way in. Vertical chrome is free here: the
/// type is set at `width / em`, so a bar at the bottom costs no letter size,
/// unlike a margin at the side.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.db, required this.library});

  final CommonDatabase db;
  final Library library;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final GlobalKey<MushafViewState> _mushaf = GlobalKey<MushafViewState>();
  int _tab = 0;
  bool _chrome = false;

  /// Turn the muṣḥaf to a page, from wherever the reader asked.
  void _jump(int page, [String? verseKey]) {
    setState(() => _tab = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mushaf.currentState?.goTo(page, verseKey);
    });
  }

  void _openIndex() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => IndexScreen(
        db: widget.db,
        pages: pageCount(widget.db),
        library: widget.library,
        onGo: (page, [verseKey]) {
          Navigator.of(context).pop();
          _jump(page, verseKey);
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // On the muṣḥaf the bar comes and goes with the rest of the chrome; on the
    // other two it is always there, because those are ordinary screens.
    final showBar = _tab != 0 || _chrome;

    return Scaffold(
      backgroundColor: const Color(0xFFFCFCFA),
      body: IndexedStack(
        index: _tab,
        children: [
          MushafView(
            key: _mushaf,
            db: widget.db,
            library: widget.library,
            chrome: _chrome,
            onToggleChrome: () => setState(() => _chrome = !_chrome),
            onOpenIndex: _openIndex,
          ),
          ForksScreen(db: widget.db, onGo: _jump),
          DrillScreen(db: widget.db, onGo: _jump),
        ],
      ),
      bottomNavigationBar: showBar
          ? NavigationBar(
              height: 62,
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  selectedIcon: Icon(Icons.menu_book),
                  label: 'Muṣḥaf',
                ),
                NavigationDestination(
                  icon: Icon(Icons.call_split_outlined),
                  selectedIcon: Icon(Icons.call_split),
                  label: 'Forks',
                ),
                NavigationDestination(
                  icon: Icon(Icons.school_outlined),
                  selectedIcon: Icon(Icons.school),
                  label: 'Drill',
                ),
              ],
            )
          : null,
    );
  }
}

/// One token on a line: a word, or the marker that closes an ayah.
class Tok {
  Tok(Map<String, Object?> j)
      : kind = j['kind'] as String,
        code = j['code'] as String?,
        wordId = j['word_id'] as int?,
        verseKey = j['verse_key'] as String,
        text = j['text'] as String?,
        marked = ((j['phrase_ids'] as List?) ?? const []).isNotEmpty;

  final String kind;
  final String? code;
  final String verseKey;
  final int? wordId;
  final String? text;
  final bool marked;

  bool get isMarker => kind != 'word';
}

class MushafView extends StatefulWidget {
  const MushafView({
    super.key,
    required this.db,
    required this.library,
    required this.chrome,
    required this.onToggleChrome,
    required this.onOpenIndex,
  });

  final CommonDatabase db;
  final Library library;
  final bool chrome;
  final VoidCallback onToggleChrome;
  final VoidCallback onOpenIndex;

  @override
  MushafViewState createState() => MushafViewState();
}

class MushafViewState extends State<MushafView> {
  final Map<String, TapGestureRecognizer> _recognizers = {};
  final Set<int> _fontsLoaded = {};
  final FocusNode _focus = FocusNode();


  // A page turn is async -- it awaits the page's font -- so `_page` still holds
  // the old value while one is in flight. Without this guard a second turn
  // starting in that window computes its target from the stale page, and one
  // flick walks several pages at once.
  bool _turning = false;
  late int _page = initialPage;
  Map<String, Object?>? _doc;
  double? _em;
  String? _selected;

  @override
  void initState() {
    super.initState();
    // Where they left off, unless a #p= fragment asked for somewhere else.
    final last = widget.library.lastPage;
    if (last != null && initialPage == kFallbackPage) _page = last;
    _go(_page);
  }

  /// Turn to a page and select an āyah there. Called by the shell, so the forks
  /// screen, the drill and the index can all send the reader to a place.
  Future<void> goTo(int page, [String? verseKey]) async {
    await _go(page);
    if (mounted && verseKey != null) {
      setState(() => _selected = verseKey);
    }
  }

  @override
  void dispose() {
    for (final r in _recognizers.values) {
      r.dispose();
    }
    _focus.dispose();
    super.dispose();
  }

  String _family(int page) => 'QCF_P$page';

  /// The font KFGQPC cut for this page, loaded the first time the page is
  /// turned to and kept after. Turning back is free.
  Future<void> _loadFont(int page) async {
    if (_fontsLoaded.contains(page)) return;
    final bytes = await rootBundle.load('assets/fonts/p$page.ttf');
    await (FontLoader(_family(page))..addFont(Future.value(bytes))).load();
    _fontsLoaded.add(page);
  }

  Future<void> _go(int page) async {
    final total = pageCount(widget.db);
    if (page < 1 || page > total || _turning) return;
    _turning = true;

    try {
      await _turn(page);
    } finally {
      _turning = false;
    }
  }

  Future<void> _turn(int page) async {
    final sw = Stopwatch()..start();
    final doc = mushafPage(widget.db, page);
    sw.stop();

    await _loadFont(page);
    if (!mounted) return;

    setState(() {
      _page = page;
      _doc = doc;
      _em = null;
      _selected = null;
      _recognizers.clear();
    });
    unawaited(widget.library.setLastPage(page));
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  /// One size per page, from the measure: `em` is the widest line set at 1px.
  void _measure() {
    final doc = _doc;
    if (doc == null) return;
    const probe = 100.0;
    var widest = 0.0;

    for (final line in (doc['lines'] as List).cast<Map<String, Object?>>()) {
      final toks = (line['tokens'] as List?)?.cast<Map<String, Object?>>();
      if (toks == null || toks.isEmpty) continue;
      final codes = toks.map((t) => t['code'] as String? ?? '').join();
      if (codes.isEmpty) continue;

      final tp = TextPainter(
        text: TextSpan(
          text: codes,
          style: TextStyle(fontFamily: _family(_page), fontSize: probe),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      if (tp.width > widest) widest = tp.width;
    }
    if (widest > 0 && mounted) setState(() => _em = widest / probe);
  }

  /// Everything the corpus has on this ayah.
  ///
  /// `lookup` is the Dart port of app/lookup.py's function of the same name --
  /// the curated official phrases with their pegs, and pass A's own detected
  /// repeats with their dawabit. Checked against the Python's output.
  void _openPanel(String verseKey) {
    setState(() => _selected = verseKey);
    final parts = verseKey.split(':');
    final doc = ql.lookup(
      widget.db,
      int.parse(parts[0]),
      int.parse(parts[1]),
      minLen: 3,
      limit: 12,
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MutashabihatPanel(
        verseKey: verseKey,
        matches: (doc['official'] as List).cast<Map<String, Object?>>(),
        detected: (doc['matches'] as List).cast<Map<String, Object?>>(),
        onJump: _jump,
      ),
    );
  }

  /// Turn to a page and select an ayah there -- what every position button in
  /// the panel and on the forks screen does.
  void _jump(int page, String verseKey) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    _go(page).then((_) {
      if (mounted) setState(() => _selected = verseKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      backgroundColor: const Color(0xFFFCFCFA),
      body: doc == null
          ? const Center(child: CircularProgressIndicator())
          : KeyboardListener(
              focusNode: _focus..requestFocus(),
              onKeyEvent: (e) {
                if (e is! KeyDownEvent) return;
                if (e.logicalKey == LogicalKeyboardKey.arrowLeft) _go(_page + 1);
                if (e.logicalKey == LogicalKeyboardKey.arrowRight) _go(_page - 1);
              },
              child: Stack(
                children: [
                  // Tapping anywhere that is not a word shows or hides the
                  // controls, so the muṣḥaf can hold the whole screen.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: widget.onToggleChrome,
                      // Dragged like a paper page: pulling the sheet to the
                      // right brings the next page over, as it does in the
                      // muṣḥaf, so a rightward swipe advances.
                      onHorizontalDragEnd: (d) {
                        final v = d.primaryVelocity ?? 0;
                        if (v.abs() < 120) return;
                        _go(v > 0 ? _page + 1 : _page - 1);
                      },
                      child: SafeArea(
                        minimum: const EdgeInsets.symmetric(vertical: 6),
                        child: Padding(
                          // Horizontal padding costs type size directly: the
                          // glyphs are set at width/em, so a pixel taken from
                          // the measure is taken from the letters. This is the
                          // margin the sheet is given, and it is all it gets.
                          padding: const EdgeInsets.symmetric(
                              horizontal: kEdgeMargin, vertical: 4),
                          child: _em == null
                              ? const SizedBox.shrink()
                              : LayoutBuilder(builder: _buildSheet),
                        ),
                      ),
                    ),
                  ),
                  if (widget.chrome) _controls(),
                ],
              ),
            ),
    );
  }

  /// The sheet. On a phone the screen is far taller than the muṣḥaf's 1:1.55, so
  /// holding that proportion would letterbox the page and shrink nothing but the
  /// margins -- the type size comes from the width either way. So the block
  /// takes the full height on a tall screen, and the extra goes into leading;
  /// on a wide one the proportion is kept, since there the height is what binds.
  Widget _buildSheet(BuildContext context, BoxConstraints c) {
    const sheetRatio = 1.55;
    const maxLeadingStretch = 2.25;

    double w = c.maxWidth;
    double h = c.maxHeight;
    if (h > w * maxLeadingStretch) {
      h = w * maxLeadingStretch;
    } else if (h < w * sheetRatio) {
      w = h / sheetRatio;
    }

    return Center(
      child: SizedBox(
        width: w,
        height: h,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: LayoutBuilder(builder: _buildBlock),
        ),
      ),
    );
  }

  /// The chrome: where you are, a way to the index, a bookmark, and a slider
  /// across all 604 pages. Everything that is not the page itself.
  Widget _controls() {
    final doc = _doc;
    final surahs = ((doc?['surahs'] as List?) ?? const [])
        .cast<Map<String, Object?>>();
    final juz = doc?['juz'];
    final marked = _selected != null && widget.library.has(_selected!);

    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(color: Color(0x22000000), blurRadius: 12),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Index, bookmarks and search',
                    onPressed: widget.onOpenIndex,
                    icon: const Icon(Icons.list),
                  ),
                  // Where you are, which the page itself cannot say.
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          surahs.isEmpty
                              ? 'Page $_page'
                              : surahs
                                  .map((x) => x['name_ar'] as String)
                                  .join('  ·  '),
                          textDirection: TextDirection.rtl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: 'Amiri', fontSize: 17, color: _ink),
                        ),
                        Text(
                          'page $_page'
                          '${juz == null ? "" : "   ·   juz $juz"}'
                          '${_selected == null ? "" : "   ·   $_selected"}',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: _inkMute),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _selected == null
                        ? 'Select an āyah to bookmark it'
                        : (marked ? 'Remove bookmark' : 'Bookmark this āyah'),
                    onPressed: _selected == null ? null : _toggleBookmark,
                    icon: Icon(marked ? Icons.bookmark : Icons.bookmark_border),
                    color: marked ? _gold : null,
                  ),
                ],
              ),
              // The whole muṣḥaf under a thumb. The reference apps all have
              // this, and 604 pages is far too many to reach by swiping.
              Row(
                children: [
                  const SizedBox(width: 10),
                  Text('1',
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9,
                          color: _inkMute)),
                  Expanded(
                    child: Slider(
                      min: 1,
                      max: pageCount(widget.db).toDouble(),
                      value: _page
                          .clamp(1, pageCount(widget.db))
                          .toDouble(),
                      // Only on release: turning a page loads its font, and
                      // dragging would load one per pixel.
                      onChanged: (v) => setState(() => _page = v.round()),
                      onChangeEnd: (v) => _go(v.round()),
                    ),
                  ),
                  Text('${pageCount(widget.db)}',
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9,
                          color: _inkMute)),
                  const SizedBox(width: 10),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleBookmark() async {
    final key = _selected;
    final doc = _doc;
    if (key == null || doc == null) return;
    final ayat = (doc['ayat'] as List).cast<Map<String, Object?>>();
    final match = ayat.where((a) => a['verse_key'] == key);
    await widget.library.toggle(Bookmark(
      verseKey: key,
      page: _page,
      surahNameAr: match.isEmpty
          ? ''
          : match.first['surah_name_ar'] as String,
      addedMs: DateTime.now().millisecondsSinceEpoch,
    ));
    if (mounted) setState(() {});
  }

  Widget _buildBlock(BuildContext context, BoxConstraints c) {
    // The whole of the typesetting: one size, from the measure, per page.
    final size = c.maxWidth / _em!;
    final lines = (_doc!['lines'] as List).cast<Map<String, Object?>>();
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final line in lines) _line(line, size)],
    );
  }

  Widget _line(Map<String, Object?> line, double size) {
    final type = line['type'] as String;

    // Heading and basmalah lines carry no glyph codes -- the font holds this
    // page's verses and nothing else -- so they are drawn, not set. This is the
    // one part of the page that is not the print; see docs/MUSHAF.md.
    if (type == 'surah_name') {
      // The mushaf sets a heading in a cartouche the full width of the text
      // block: a ruled frame with the name centred in it. Drawn, because the
      // page's font holds this page's verses and no heading glyphs.
      // Bounded to one line box. A heading takes one of the page's lines in
      // print, and an unbounded FittedBox would scale the name up to the full
      // width of the text block and push the ayat off the sheet.
      return SizedBox(
        height: size * kLineHeight,
        child: Container(
          width: double.infinity,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: size * 0.3),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFD8A93C), width: 1),
            borderRadius: BorderRadius.circular(2),
          ),
          child: FittedBox(
            child: Text(
              line['name_ar'] as String,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontFamily: kDrawnFace,
                fontSize: size * 0.40,
                color: const Color(0xFF8A6C22),
              ),
            ),
          ),
        ),
      );
    }
    if (type == 'basmallah') {
      final words = (line['words'] as List).cast<Map<String, Object?>>();
      return SizedBox(
        height: size * kLineHeight,
        child: FittedBox(
          child: Text(
            words.map((w) => w['text']).join(' '),
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontFamily: kDrawnFace,
              fontSize: size * 0.5,
              color: const Color(0xFF8A6C22),
            ),
          ),
        ),
      );
    }

    final toks = ((line['tokens'] as List?) ?? const [])
        .cast<Map<String, Object?>>()
        .map(Tok.new)
        .toList();
    if (toks.isEmpty) return const SizedBox.shrink();

    // A page whose glyphs are not bound falls back to the Uthmani text.
    if (toks.first.code == null) {
      return Center(
        child: FittedBox(
          child: Text(
            toks.map((t) => t.text ?? '').join(' '),
            textDirection: TextDirection.rtl,
            style: TextStyle(fontFamily: kDrawnFace, fontSize: size * 0.6),
          ),
        ),
      );
    }

    final lineNo = line['line'] as int;
    return Text.rich(
      TextSpan(children: [
        for (var i = 0; i < toks.length; i++)
          _span(toks[i], '$_page/$lineNo/$i', size),
      ]),
      textDirection: TextDirection.rtl,
      textAlign: line['centered'] == true ? TextAlign.center : TextAlign.right,
      maxLines: 1,
      // The glyphs are cut to fill the line; nothing may re-wrap or re-fit them.
      softWrap: false,
      overflow: TextOverflow.visible,
    );
  }

  /// One span per token, so the hairline and the tap target are both per word.
  InlineSpan _span(Tok t, String key, double size) {
    final recognizer = _recognizers.putIfAbsent(
      key,
      () => TapGestureRecognizer()..onTap = () => _openPanel(t.verseKey),
    );

    return TextSpan(
      text: t.code,
      style: TextStyle(
        fontFamily: _family(_page),
        fontSize: size,
        // The stylesheet's .qline line-height. The glyphs ask for 1.531em, so
        // they overflow their line box by design and must not be clipped.
        height: kLineHeight,
        color: t.isMarker ? const Color(0xFF8A6C22) : const Color(0xFF191C19),
        decoration: t.marked ? TextDecoration.underline : TextDecoration.none,
        decorationColor: const Color(0xFFD8A93C),
        decorationThickness: 0.6,
        backgroundColor:
            _selected == t.verseKey ? const Color(0x33D8A93C) : null,
      ),
      recognizer: recognizer,
    );
  }
}
