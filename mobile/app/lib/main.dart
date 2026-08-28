// The mushaf, page by page, off the real corpus.
//
// Every page is built by `mushafPage` from package:quran_port -- the Dart port
// of app/lookup.py, checked page for page against the Python's own output -- and
// set in the font the King Fahd Complex cut for that page, loaded when the page
// is turned to.
//
// Nothing here composes Qur'anic text. Every token, the basmalah included,
// arrives from the database, as it does on the Python side.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quran_port/lookup.dart' as ql;
import 'package:quran_port/mushaf.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;

import 'corpus.dart';
import 'forks_screen.dart';
import 'navigate.dart';
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
  late final Future<CommonDatabase> _db = openCorpus();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CommonDatabase>(
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
        return MushafView(db: snap.data!);
      },
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
  const MushafView({super.key, required this.db});

  final CommonDatabase db;

  @override
  State<MushafView> createState() => _MushafViewState();
}

class _MushafViewState extends State<MushafView> {
  final Map<String, TapGestureRecognizer> _recognizers = {};
  final Set<int> _fontsLoaded = {};
  final FocusNode _focus = FocusNode();


  bool _chrome = false;
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
    _go(_page);
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

  void _openNavigate() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NavigateSheet(
        db: widget.db,
        pages: pageCount(widget.db),
        onGo: _go,
      ),
    );
  }

  void _openForks() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ForksScreen(db: widget.db, onGo: _jump),
    ));
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
                      onTap: () => setState(() => _chrome = !_chrome),
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
                  if (_chrome) _controls(),
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

  Widget _controls() {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(color: Color(0x22000000), blurRadius: 12),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Go to sūrah, juzʼ or page',
                onPressed: _openNavigate,
                icon: const Icon(Icons.menu_book_outlined),
              ),
              IconButton(
                tooltip: 'Forks',
                onPressed: _openForks,
                icon: const Icon(Icons.call_split),
              ),
              // The muṣḥaf reads right to left, so the arrows do too.
              IconButton(
                tooltip: 'Next page',
                onPressed: () => _go(_page + 1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  'Page $_page',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF4A5049)),
                ),
              ),
              IconButton(
                tooltip: 'Previous page',
                onPressed: () => _go(_page - 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlock(BuildContext context, BoxConstraints c) {
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
