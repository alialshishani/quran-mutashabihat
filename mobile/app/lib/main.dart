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
import 'package:quran_port/drill.dart' show DrillCandidate, drillPool;
import 'package:quran_port/forks.dart' show roadEnds;
import 'package:quran_port/lookup.dart' as ql;
import 'package:quran_port/mushaf.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;

import 'corpus.dart';
import 'drill_screen.dart';
import 'forks_screen.dart';
import 'index_screen.dart';
import 'library.dart';
import 'panel.dart';
import 'progress.dart';
import 'strings.dart';
import 'theme.dart';
import 'today_screen.dart';
import 'type.dart';

// The palette in force, read by name; see theme.dart. These are getters
// rather than constants because the light can change while the app is up.
Color get _paper => palette.paper;
Color get _card => palette.card;
Color get _ink => palette.ink;
Color get _inkMute => palette.inkMute;
Color get _gold => palette.gold;
Color get _goldBright => palette.goldBright;
Color get _shadow => palette.shadow;
Color get _selection => palette.selection;
Color get _covered => palette.covered;

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
  // Edge to edge by default, and immersive only on the sheet -- see
  // `_applySystemUi`. This used to be immersiveSticky for the whole app, so
  // the clock and the battery were taken from the Today screen, the index and
  // the drill as well, which gain nothing from the pixels and lose a phone's
  // ordinary furniture.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // The library is the small store -- where you were, what you marked, what you
  // missed, and which light you read by. The last of those is wanted before the
  // first frame, so it is opened here rather than with the corpus.
  final library = await Library.open();
  // Opened here rather than inside the drill. The Today screen and the drill
  // both read the boxes, and two copies of the store would let them disagree
  // about what is due -- the count on the button and the session behind it.
  final progress = await Progress.open();
  runApp(MushafApp(library: library, progress: progress));
}

class MushafApp extends StatefulWidget {
  const MushafApp({super.key, required this.library, required this.progress});

  final Library library;
  final Progress progress;

  @override
  State<MushafApp> createState() => _MushafAppState();
}

class _MushafAppState extends State<MushafApp> with WidgetsBindingObserver {
  late ThemeChoice _choice = widget.library.themeChoice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The platform's light changed under a reader who left it to follow.
  @override
  void didChangePlatformBrightness() {
    if (_choice == ThemeChoice.system) setState(() {});
  }

  Future<void> _setChoice(ThemeChoice choice) async {
    setState(() => _choice = choice);
    await widget.library.setThemeChoice(choice);
  }

  @override
  Widget build(BuildContext context) {
    final system =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final dark = switch (_choice) {
      ThemeChoice.light => false,
      ThemeChoice.dark => true,
      ThemeChoice.system => system == Brightness.dark,
    };
    // Set before the tree under it is built, so every `_ink` below reads the
    // light now in force rather than the one before it.
    palette = dark ? kDark : kLight;

    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: themeFor(kLight),
      darkTheme: themeFor(kDark),
      themeMode: switch (_choice) {
        ThemeChoice.light => ThemeMode.light,
        ThemeChoice.dark => ThemeMode.dark,
        ThemeChoice.system => ThemeMode.system,
      },
      // The chrome speaks Arabic, so the chrome runs right to left: the drawer
      // comes in from the right edge, a row reads from the right, and a list
      // row's leading sits where an Arabic reader's eye starts.
      //
      // Done with a Directionality rather than by declaring a locale, because
      // the locale route pulls in flutter_localizations for the sake of a
      // handful of Material strings the app has replaced anyway. The wrap is
      // inside MaterialApp, so the Navigator, its overlays -- the drawer, the
      // bottom sheets, the snack bars -- are all under it.
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: Loader(
        library: widget.library,
        progress: widget.progress,
        choice: _choice,
        onChoice: _setChoice,
      ),
    );
  }
}

class Loader extends StatefulWidget {
  const Loader({
    super.key,
    required this.library,
    required this.progress,
    required this.choice,
    required this.onChoice,
  });

  final Library library;
  final Progress progress;
  final ThemeChoice choice;
  final ValueChanged<ThemeChoice> onChoice;

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
        // The corpus is the longest wait the app ever makes anyone sit
        // through, and it is the only moment it has to itself. It used to
        // spend that moment on a bare spinner, and spend the failure on the
        // exception's toString -- a stack trace shown to a reciter.
        if (snap.hasError) {
          return Scaffold(
            backgroundColor: _paper,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.menu_book_outlined, size: 40, color: _inkMute),
                    const SizedBox(height: 16),
                    Text(kLoadFailedTitle,
                        textAlign: TextAlign.center, style: tTitle()),
                    const SizedBox(height: 8),
                    Text(kLoadFailedGloss,
                        textAlign: TextAlign.center,
                        style: tCaption(palette.inkMute)),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return Scaffold(
            backgroundColor: _paper,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(kAppName, style: tDisplay(_gold)),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 96,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: palette.line,
                      color: _gold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(kLoading, style: tLabel()),
                ],
              ),
            ),
          );
        }
        return HomeShell(
          db: snap.data!,
          library: widget.library,
          progress: widget.progress,
          choice: widget.choice,
          onChoice: widget.onChoice,
        );
      },
    );
  }
}

/// One place the reader has been.
///
/// [page] and [verseKey] are null for the destinations that are not a sheet --
/// Today, the forks, the drill -- where the place is the screen itself and its
/// own state is held for us by the IndexedStack.
class Place {
  const Place(this.tab, this.page, this.verseKey);

  final int tab;
  final int? page;
  final String? verseKey;

  bool sameAs(Place o) =>
      tab == o.tab && page == o.page && verseKey == o.verseKey;
}

/// Five destinations, with one of them home.
///
/// It used to be four peers and no home, so the app opened on whichever page
/// was last read -- or on the fallback, page 89 -- and left the reciter to
/// decide what to do. Today is first now: where you stopped, what is due, and
/// one button. The other four are still peers among themselves.
///
/// The muṣḥaf keeps the whole screen while reading -- the bar is swiped up
/// with the rest of the chrome -- but it is a destination beside recall, the
/// forks and the drill rather than the only way in. Vertical chrome is free
/// here: the type is set at `width / em`, so a bar at the bottom costs no
/// letter size, unlike a margin at the side.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.db,
    required this.library,
    required this.progress,
    required this.choice,
    required this.onChoice,
  });

  final CommonDatabase db;
  final Library library;
  final Progress progress;

  /// Which light the reader has asked for, and how to ask for another.
  final ThemeChoice choice;
  final ValueChanged<ThemeChoice> onChoice;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final GlobalKey<ScaffoldState> _scaffold = GlobalKey<ScaffoldState>();
  final GlobalKey<TodayScreenState> _today = GlobalKey<TodayScreenState>();
  final GlobalKey<MushafViewState> _mushaf = GlobalKey<MushafViewState>();
  final GlobalKey<MushafViewState> _recall = GlobalKey<MushafViewState>();
  final GlobalKey<DrillScreenState> _drill = GlobalKey<DrillScreenState>();

  /// Built once. It is a few thousand rows off the fork tables, and both the
  /// Today screen and the drill run on this same list.
  late final List<DrillCandidate> _pool = drillPool(widget.db);

  static const int kToday = 0;
  static const int kMushaf = 1;
  static const int kRecall = 2;
  static const int kDrill = 4;

  int _tab = kToday;
  bool _chrome = false;
  late bool _stopAtForks = widget.library.stopAtForks;

  /// Everywhere the reader has jumped from, oldest first.
  ///
  /// A jump is a tap that moves you somewhere discontinuous: a sibling in the
  /// mutashābihāt panel, a position in the fork list, `انظرها في صفحة` in the
  /// drill, a row in the index, a missed place on Today. Following one used to
  /// be a one-way trip -- you could check the āyah the panel sent you to and
  /// then had no way back to the page you had been reading except to remember
  /// its number.
  ///
  /// Turning the page by swiping is deliberately not recorded. It is not a
  /// jump, it is reading, and recording it would fill the stack with the act
  /// of reading and make `back` mean `previous page` -- which the swipe in the
  /// other direction already means. Tapping a destination in the bar is not
  /// recorded either, for the same reason: it is where you asked to be, not
  /// somewhere you were sent.
  ///
  /// Uncapped, as asked. An entry is a tab, a page and a key, and no one can
  /// press their way to a depth that costs anything.
  final List<Place> _history = [];

  /// Whether the sheet's gestures have been shown. Held here rather than in
  /// each sheet: both are built at once inside the IndexedStack, so each read
  /// the store in its own initState, both got `false`, and dismissing the
  /// overlay on the muṣḥaf left recall's copy of it standing. It is one flag,
  /// so it is kept in one place.
  late bool _coached = widget.library.sheetCoached;

  Future<void> _markCoached() async {
    setState(() => _coached = true);
    await widget.library.setSheetCoached();
  }

  @override
  void initState() {
    super.initState();
    _applySystemUi(_tab);
  }

  /// The sheet wants every pixel: its type size is derived from the width of
  /// the text block, so system chrome does not merely crowd the page, it
  /// shrinks the letters. Nothing else in the app is measured that way, so
  /// nothing else gives up the status bar for it.
  void _applySystemUi(int tab) {
    final sheet = tab == kMushaf || tab == kRecall;
    SystemChrome.setEnabledSystemUIMode(
      sheet ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  /// Where we are now, in the form the history keeps.
  Place _here() {
    final sheet = _sheet(_tab)?.currentState;
    return Place(_tab, sheet?.page, sheet?.selected);
  }

  bool get _canGoBack => _history.isNotEmpty;

  /// Turn the muṣḥaf to a page, from wherever the reader asked, and remember
  /// where they were standing when they asked.
  void _jump(int page, [String? verseKey]) {
    final here = _here();
    // A jump that lands where we already are should not stack an entry that
    // goes nowhere -- pressing back would then appear to do nothing.
    if (_history.isEmpty || !_history.last.sameAs(here)) _history.add(here);
    setState(() => _tab = kMushaf);
    _applySystemUi(kMushaf);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mushaf.currentState?.goTo(page, verseKey);
    });
  }

  /// Undo one jump.
  ///
  /// Reached two ways, because the system gesture is invisible and a control
  /// with no affordance is not a control: the platform's own back, and the
  /// arrow that appears in the page's head once there is somewhere to go.
  void _back() {
    // With the drawer open the platform's back is closing it, and every
    // PopScope in the route is told about that same press -- so without this
    // one press would both shut the drawer and undo a jump.
    if (_scaffold.currentState?.isDrawerOpen ?? false) return;
    if (_history.isEmpty) return;

    final to = _history.removeLast();
    setState(() => _tab = to.tab);
    _applySystemUi(to.tab);
    if (to.tab == kToday) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _today.currentState?.refresh());
    }
    final sheet = _sheet(to.tab);
    final page = to.page;
    if (sheet == null || page == null) return;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => sheet.currentState?.goTo(page, to.verseKey));
  }

  /// Deal a session and show it, which is what the Today screen's one button
  /// does.
  void _startDrill() {
    setState(() => _tab = kDrill);
    _applySystemUi(kDrill);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _drill.currentState?.startSession());
  }

  /// The muṣḥaf and recall are one page read two ways, so moving in either
  /// moves the other: you cover the page you were just reading, and you come
  /// back to the page you were just tested on. One place between them, and one
  /// record of where that place is.
  GlobalKey<MushafViewState>? _sheet(int tab) =>
      tab == kMushaf ? _mushaf : (tab == kRecall ? _recall : null);

  void _selectTab(int i) {
    final page = _sheet(_tab)?.currentState?.page;
    setState(() => _tab = i);
    _applySystemUi(i);
    // Everything on Today is a reading of stores the other screens write, so
    // coming back to it has to re-read them.
    if (i == kToday) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _today.currentState?.refresh());
    }
    final to = _sheet(i);
    if (to == null || page == null) return;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => to.currentState?.goTo(page));
  }

  void _openMenu() => _scaffold.currentState?.openDrawer();

  Future<void> _setStopAtForks(bool on) async {
    setState(() => _stopAtForks = on);
    await widget.library.setStopAtForks(on);
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
    // The platform's back undoes a jump for as long as there is one to undo.
    // `canPop` goes true once the stack is empty, so the last press leaves the
    // app as it always did rather than trapping the reader inside it.
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: _shell(),
    );
  }

  Widget _shell() {
    // On the muṣḥaf the bar comes and goes with the rest of the chrome; on the
    // other two it is always there, because those are ordinary screens.
    // The muṣḥaf and recall are the same sheet, read two ways, so both keep
    // the whole screen and both float their bar. The forks and the drill are
    // ordinary screens and take an ordinary bar under them.
    final onSheet = _tab == kMushaf || _tab == kRecall;

    return Scaffold(
      key: _scaffold,
      backgroundColor: _paper,
      drawer: _menu(),
      // Over the muṣḥaf the bar is laid on the page, not under it. Given a
      // strip of the Scaffold it would take that height from the block, and
      // the block sets the leading -- so the whole page would re-set itself
      // every time the chrome came and went. Floated, the sheet never moves.
      body: Stack(
        children: [
          IndexedStack(
            index: _tab,
            children: [
              TodayScreen(
                key: _today,
                db: widget.db,
                library: widget.library,
                progress: widget.progress,
                pool: _pool,
                onGo: _jump,
                onStartDrill: _startDrill,
                onOpenMenu: _openMenu,
              ),
              MushafView(
                key: _mushaf,
                db: widget.db,
                library: widget.library,
                chrome: _chrome,
                onToggleChrome: () => setState(() => _chrome = !_chrome),
                onOpenMenu: _openMenu,
                active: _tab == kMushaf,
                coached: _coached,
                onCoached: _markCoached,
                canGoBack: _canGoBack,
                onBack: _back,
                onNavigate: _jump,
              ),
              MushafView(
                key: _recall,
                db: widget.db,
                library: widget.library,
                chrome: _chrome,
                onToggleChrome: () => setState(() => _chrome = !_chrome),
                onOpenMenu: _openMenu,
                active: _tab == kRecall,
                coached: _coached,
                onCoached: _markCoached,
                canGoBack: _canGoBack,
                onBack: _back,
                onNavigate: _jump,
                stopAtForks: _stopAtForks,
                recall: true,
              ),
              ForksScreen(db: widget.db, onGo: _jump, onOpenMenu: _openMenu),
              DrillScreen(
                key: _drill,
                db: widget.db,
                progress: widget.progress,
                pool: _pool,
                onGo: _jump,
                onOpenMenu: _openMenu,
                onSessionEnd: () => _today.currentState?.refresh(),
              ),
            ],
          ),
          if (onSheet && _chrome)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _bar(floating: true),
            ),
        ],
      ),
      bottomNavigationBar: onSheet ? null : _bar(floating: false),
    );
  }

  /// Everything that is not a destination: the lists, the search, and what
  /// little there is to set. It lives behind one button so the page keeps the
  /// screen, and so a setting has somewhere to go that is not the page.
  Widget _menu() {
    final page = _sheet(_tab)?.currentState?.page;
    return Drawer(
      backgroundColor: _paper,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kAppName, style: tDisplay()),
                  const SizedBox(height: 2),
                  Text(
                    page == null ? kNavForks : '${pageN(page)} من ${ar(604)}',
                    style: tLabel(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.list),
              title: Text(kIndexAndSearch, style: tBody()),
              subtitle: Text(kIndexGloss, style: tCaption(_inkMute)),
              onTap: () {
                Navigator.of(context).pop();
                _openIndex();
              },
            ),
            const Divider(height: 1),
            _section(kSectionRecall),
            SwitchListTile(
              value: _stopAtForks,
              onChanged: _setStopAtForks,
              title: Text(kStopAtForks, style: tBody()),
              subtitle: Text(kStopAtForksGloss, style: tCaption(_inkMute)),
            ),
            const Divider(height: 1),
            _section(kSectionLight),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: SegmentedButton<ThemeChoice>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: ThemeChoice.light,
                      icon: const Icon(Icons.light_mode_outlined),
                      label: Text(kLightDay)),
                  ButtonSegment(
                      value: ThemeChoice.dark,
                      icon: const Icon(Icons.dark_mode_outlined),
                      label: Text(kLightNight)),
                  ButtonSegment(
                      value: ThemeChoice.system,
                      icon: const Icon(Icons.brightness_auto_outlined),
                      label: Text(kLightAuto)),
                ],
                selected: {widget.choice},
                onSelectionChanged: (s) => widget.onChoice(s.first),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The head of a group in the drawer. It used to be an English word in
  /// tracked-out monospace capitals; Arabic has neither capitals nor room for
  /// tracking, so the grouping is carried by the rule above it and by ink.
  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
        child: Text(label, style: tLabel()),
      );

  /// The four destinations. Floating over the muṣḥaf it is translucent and
  /// shadowed, like the controls at the head of the page, so the line beneath
  /// it is dimmed rather than lost; on the other two screens it is the
  /// ordinary opaque bar at the foot of the Scaffold.
  Widget _bar({required bool floating}) {
    final bar = NavigationBar(
      height: 62,
      backgroundColor: floating ? _card : null,
      selectedIndex: _tab,
      onDestinationSelected: _selectTab,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.wb_twilight_outlined),
          selectedIcon: Icon(Icons.wb_twilight),
          label: kNavToday,
        ),
        NavigationDestination(
          icon: Icon(Icons.menu_book_outlined),
          selectedIcon: Icon(Icons.menu_book),
          label: kNavMushaf,
        ),
        NavigationDestination(
          icon: Icon(Icons.visibility_off_outlined),
          selectedIcon: Icon(Icons.visibility_off),
          label: kNavRecall,
        ),
        // Not `call_split`, which is a version-control branch and reads as
        // one. Two roads leaving a shared one is what this screen is about.
        NavigationDestination(
          icon: Icon(Icons.alt_route_outlined),
          selectedIcon: Icon(Icons.alt_route),
          label: kNavForks,
        ),
        // Not `school`, a mortarboard: what the drill asks for is repetition,
        // not a qualification.
        NavigationDestination(
          icon: Icon(Icons.model_training_outlined),
          selectedIcon: Icon(Icons.model_training),
          label: kNavDrill,
        ),
      ],
    );

    if (!floating) return bar;
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [BoxShadow(color: _shadow, blurRadius: 12)],
      ),
      child: bar,
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
    required this.onOpenMenu,
    required this.active,
    required this.coached,
    required this.onCoached,
    required this.canGoBack,
    required this.onBack,
    required this.onNavigate,
    this.stopAtForks = true,
    this.recall = false,
  });

  final CommonDatabase db;
  final Library library;
  final bool chrome;
  final VoidCallback onToggleChrome;

  /// The way to everything that is not the page: the lists, the search and the
  /// settings. One button, one drawer, rather than a row of icons over the
  /// muṣḥaf -- vertical chrome is free here, but attention is not.
  final VoidCallback onOpenMenu;

  /// Whether recall also stops where a shared road turns. See [_cut].
  final bool stopAtForks;

  /// Whether the gestures have been shown once, and how to say they have.
  /// Held by the shell, since one telling covers both sheets.
  final bool coached;
  final VoidCallback onCoached;

  /// Whether there is a jump to undo, and how to undo it. The stack is the
  /// shell's -- a jump can cross destinations, and only the shell can put one
  /// back.
  final bool canGoBack;
  final VoidCallback onBack;

  /// A jump out of this sheet: a sibling position in the panel. Routed through
  /// the shell rather than turned to directly, so that it is recorded like
  /// every other jump and `back` can undo it.
  final void Function(int page, String verseKey) onNavigate;

  /// Whether this is the sheet on screen. Both sheets are built at once -- the
  /// shell keeps them in an IndexedStack so a tab change is not a page load --
  /// and only the one being looked at may hold the keyboard.
  final bool active;

  /// Recall: the same sheet with its ink held back. The page is set exactly as
  /// it is printed -- same measure, same size, same line breaks -- and then the
  /// words are withheld one ayah at a time. What a reciter is recalling is a
  /// place on a page, so the page has to keep its shape while it is covered.
  final bool recall;

  @override
  MushafViewState createState() => MushafViewState();
}

class MushafViewState extends State<MushafView> {
  final Map<String, TapGestureRecognizer> _recognizers = {};
  // A FontLoader registers its family with the engine, which is process-wide,
  // so two views of the same page share one registration.
  static final Set<int> _fontsLoaded = {};
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

  /// In recall, the word this page is revealed through, and the points at
  /// which revealing stops. Zero is a page still covered.
  int _frontier = 0;
  List<int> _stops = const [];
  Map<int, String> _keyOf = const {};

  @override
  void initState() {
    super.initState();
    // Where they left off, unless a #p= fragment asked for somewhere else.
    final last = widget.library.lastPage;
    if (last != null && initialPage == kFallbackPage) _page = last;
    _go(_page);
  }

  /// The page this sheet is on, so the shell can put the other sheet on it.
  int get page => _page;

  /// The āyah selected on it, so the shell's history can put the reader back
  /// where they were and not merely on the right page.
  String? get selected => _selected;

  /// Turn to a page and select an āyah there. Called by the shell, so the forks
  /// screen, the drill and the index can all send the reader to a place -- and
  /// so the two sheets can be kept on one page between them. Already being
  /// there is not a turn: reloading would cover recall again, and a reciter who
  /// glanced at the muṣḥaf has not asked for that.
  Future<void> goTo(int page, [String? verseKey]) async {
    if (page != _page) await _go(page);
    if (mounted && verseKey != null) {
      setState(() => _selected = verseKey);
    }
  }

  @override
  void didUpdateWidget(MushafView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The cut is made from the setting, so a page half-lit under the old one
    // is covered again under the new.
    if (widget.recall && widget.stopAtForks != oldWidget.stopAtForks) {
      setState(_cut);
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
    // A page arrives covered: turning to it is the point at which a reciter
    // has nothing yet.
    if (widget.recall) _cut();
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
    widget.onNavigate(page, verseKey);
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      backgroundColor: _paper,
      body: doc == null
          ? const Center(child: CircularProgressIndicator())
          : KeyboardListener(
              focusNode: widget.active ? (_focus..requestFocus()) : _focus,
              onKeyEvent: (e) {
                if (e is! KeyDownEvent) return;
                if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  _go(_page + 1);
                }
                if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
                  _go(_page - 1);
                }
                if (widget.recall && e.logicalKey == LogicalKeyboardKey.space) {
                  _revealNext();
                }
              },
              child: Stack(
                children: [
                  // The chrome rides the vertical axis, which nothing else
                  // on this screen claims: every word carries its own tap
                  // recognizer and the sheet is turned horizontally, so a tap
                  // here would have to win an arena it loses most of the time.
                  // A drag takes the pointer the moment it passes slop.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      // In recall a tap anywhere lets the next ayah through.
                      // On the muṣḥaf the tap belongs to the words, which open
                      // the panel, so the sheet does not take it.
                      onTap: widget.recall ? _revealNext : null,
                      // Held, not double-tapped: a double tap would put a
                      // wait on every reveal while the second tap was listened
                      // for, and the reveal is the thing done most.
                      onLongPress: widget.recall ? _markMissed : null,
                      // Swiped up like a blind: the bar comes from the foot of
                      // the screen, so it is drawn up and pushed back down.
                      onVerticalDragEnd: (d) {
                        final v = d.primaryVelocity ?? 0;
                        if (v.abs() < 120) return;
                        if ((v < 0) != widget.chrome) widget.onToggleChrome();
                      },
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
                  if (!widget.coached && widget.active) _coach(),
                ],
              ),
            ),
    );
  }

  /// Shown once, over the first sheet the reciter opens.
  ///
  /// Everything on this screen is a gesture and none of them is drawn: tap for
  /// the bar, tap to reveal, hold to mark a miss, swipe to turn the page. A
  /// gesture with no affordance is not a control, and the page was a wall on a
  /// first run. Kindle ships the same overlay for the same reason.
  Widget _coach() {
    return Positioned.fill(
      child: ColoredBox(
        // Near-solid. At 0.93 the page read straight through it on a dark
        // screen -- light ink at seven per cent over near-black paper is
        // plainly visible -- and the overlay looked like a fault rather
        // than a message. It is a hint of the page beneath, not a veil.
        color: palette.paper.withValues(alpha: 0.985),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app_outlined, size: 34, color: _inkMute),
                const SizedBox(height: 18),
                Text(
                  widget.recall ? kCoachReveal : kCoachChrome,
                  textAlign: TextAlign.center,
                  style: tBody(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(textStyle: tBody()),
                  onPressed: widget.onCoached,
                  child: const Text(kGotIt),
                ),
              ],
            ),
          ),
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
          // A page used to arrive by setState, which is to say instantly and
          // with no sign that anything had happened -- the only feedback a
          // turn gave was that the letters were different ones. It fades in
          // now. Keyed on the page, so the tween restarts on every turn; the
          // block itself is untouched, since the typesetting must not be
          // scaled, clipped or re-laid by anything.
          child: TweenAnimationBuilder<double>(
            key: ValueKey<int>(_page),
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            builder: (_, v, child) => Opacity(opacity: v, child: child),
            child: LayoutBuilder(builder: _buildBlock),
          ),
        ),
      ),
    );
  }

  /// The chrome: where you are, a way to the index, a bookmark, and a slider
  /// across all 604 pages. Everything that is not the page itself.
  Widget _controls() {
    final doc = _doc;
    final surahs =
        ((doc?['surahs'] as List?) ?? const []).cast<Map<String, Object?>>();
    final juz = doc?['juz'];
    final markKey = _markKey;
    final marked = markKey != null && widget.library.has(markKey);

    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      // Hung from the top edge rather than floated below it: the colour runs
      // to the physical top of the screen and only the foot of it is rounded,
      // so it reads as the head of the page and not as a card adrift on it.
      // The SafeArea is inside, so the inset holds the writing off the cutout
      // without leaving a strip of page above the bar.
      child: Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(14),
          ),
          boxShadow: [
            BoxShadow(color: _shadow, blurRadius: 12),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // Only once there is somewhere to go. `arrow_back` mirrors
                    // itself under an RTL Directionality, so it points the way
                    // back rather than the way the text runs.
                    if (widget.canGoBack)
                      IconButton(
                        tooltip: kBack,
                        onPressed: widget.onBack,
                        icon: const Icon(Icons.arrow_back),
                      ),
                    IconButton(
                      tooltip: kMenu,
                      onPressed: widget.onOpenMenu,
                      icon: const Icon(Icons.menu),
                    ),
                    // Where you are, which the page itself cannot say.
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            surahs.isEmpty
                                ? pageN(_page)
                                : surahs
                                    .map((x) => x['name_ar'] as String)
                                    .join('  ·  '),
                            textDirection: TextDirection.rtl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tTitle(),
                          ),
                          Text(
                            '${pageN(_page)}'
                            '${juz == null ? "" : "   ·   ${juzN(juz as int)}"}'
                            '${_selected == null ? "" : "   ·   ${arDigits(_selected!)}"}',
                            style: tLabel(),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      // Never disabled. It used to be, with a tooltip to say
                      // why -- and a tooltip wants a hover, which a phone has
                      // no way to give. With nothing selected it marks the
                      // first āyah of the page, which is what someone
                      // bookmarking a page means anyway.
                      tooltip: marked ? kBookmarkRemove : kBookmarkAdd,
                      onPressed: _toggleBookmark,
                      icon:
                          Icon(marked ? Icons.bookmark : Icons.bookmark_border),
                      color: marked ? _gold : null,
                    ),
                  ],
                ),
                // The slider that used to sit here is gone. It spanned 604
                // pages in a thumb's width -- a page either side of the one you
                // wanted, every time -- and the index has a page field that
                // lands on the page you asked for. Two ways to do one thing, and
                // this was the worse one.
                // In recall the card also says how much of the page is still
                // held back, and offers the two ways out of a run: give up and
                // read it, or cover it again and take the page from the top.
                if (widget.recall)
                  Row(
                    children: [
                      const SizedBox(width: 12),
                      // The count gives way, not the buttons. It is the part
                      // that grows -- the missed tally appears the first time a
                      // page goes badly -- and the part you can do without.
                      Expanded(
                        child: Text(
                          kGivenOf(_given, _stops.length) +
                              (widget.library.missCount == 0
                                  ? ''
                                  : '   ·   $kMissedTally ${ar(widget.library.missCount)}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tLabel(),
                        ),
                      ),
                      TextButton(
                        style: _rowButton,
                        onPressed: _given >= _stops.length ? null : _revealAll,
                        child: const Text(kShowAll),
                      ),
                      TextButton(
                        style: _rowButton,
                        onPressed: _frontier == 0 ? null : _hideAll,
                        child: const Text(kCoverAgain),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Two buttons and a count on one phone-width line: the ordinary button
  /// padding does not fit, and a button that has been squeezed out of the row
  /// is worse than a tight one.
  /// The style carries the type, not the child, so that the disabled colour
  /// the button computes for itself is the one that lands -- a colour set on
  /// the child would win over it and a dead button would look live.
  static ButtonStyle get _rowButton => TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: tCaption(),
        foregroundColor: palette.accent,
      );

  /// What the bookmark button acts on: the selected āyah, or -- when nothing
  /// is selected -- the first on the page, since someone reaching for the
  /// bookmark with no āyah chosen is marking the page.
  String? get _markKey {
    if (_selected != null) return _selected;
    final ayat = (_doc?['ayat'] as List?)?.cast<Map<String, Object?>>();
    if (ayat == null || ayat.isEmpty) return null;
    return ayat.first['verse_key'] as String;
  }

  Future<void> _toggleBookmark() async {
    final key = _markKey;
    final doc = _doc;
    if (key == null || doc == null) return;
    final ayat = (doc['ayat'] as List).cast<Map<String, Object?>>();
    final match = ayat.where((a) => a['verse_key'] == key);
    await widget.library.toggle(Bookmark(
      verseKey: key,
      page: _page,
      surahNameAr: match.isEmpty ? '' : match.first['surah_name_ar'] as String,
      addedMs: DateTime.now().millisecondsSinceEpoch,
    ));
    if (mounted) setState(() {});
  }

  /// Where the page is cut: the word every reveal stops at.
  ///
  /// Every ayah ends at one, so a page with nothing remarkable on it is given
  /// back an ayah at a time. But a shared road running through an ayah ends at
  /// one too, and that is the point of recall: the word after a road is the
  /// fork, the first word at which the places carrying that road stop agreeing,
  /// and the only word on the page nothing but memory supplies. Cut there and
  /// the reciter is stopped mid-ayah -- road in front of them, turning
  /// withheld -- which is where recitation actually breaks.
  void _cut() {
    _frontier = 0;
    _stops = const [];
    _keyOf = const {};
    final doc = _doc;
    if (doc == null) return;

    final keyOf = <int, String>{};
    final lastOfAyah = <String, int>{};
    for (final line in (doc['lines'] as List).cast<Map<String, Object?>>()) {
      for (final t in ((line['tokens'] as List?) ?? const [])
          .cast<Map<String, Object?>>()) {
        final id = t['word_id'] as int?;
        if (id == null) continue;
        final key = t['verse_key'] as String;
        keyOf[id] = key;
        lastOfAyah[key] = id;
      }
    }
    if (keyOf.isEmpty) return;

    final ids = keyOf.keys.toList()..sort();

    // One turning per ayah, and the hardest one. An ayah can sit on five shared
    // roads and be at risk on one of them; stopping at all five asks four
    // questions whose answer is the habit the reciter already has. `danger` is
    // how far this place stands from the crowd it shares the road with -- see
    // Stand in the port.
    final best = <String, ({int at, double danger})>{};
    if (widget.stopAtForks) {
      roadEnds(widget.db, ids.first, ids.last).forEach((end, danger) {
        final key = keyOf[end];
        // Only where the road ends inside this page and the ayah runs on past
        // it. A road ending where its ayah does asks nothing.
        if (key == null || lastOfAyah[key] == end) return;
        final held = best[key];
        if (held == null || danger > held.danger) {
          best[key] = (at: end, danger: danger);
        }
      });
    }

    final stops = <int>{
      ...lastOfAyah.values,
      for (final turn in best.values) turn.at,
    };
    _keyOf = keyOf;
    _stops = stops.toList()..sort();
  }

  /// How many of the page's cuts have been passed.
  int get _given => _stops.where((w) => w <= _frontier).length;

  /// Let the next piece through. Selecting the ayah it belongs to means the
  /// head of the card names where you are, the bookmark applies to it, and a
  /// long press knows what to mark missed.
  void _revealNext() {
    for (final stop in _stops) {
      if (stop <= _frontier) continue;
      // The lightest tap the platform has. Recall is done with the eyes shut
      // as often as not, and this is the only way the sheet can say that the
      // tap landed and there was more to give.
      HapticFeedback.selectionClick();
      setState(() {
        _frontier = stop;
        _selected = _keyOf[stop];
      });
      return;
    }
  }

  void _revealAll() => setState(() {
        if (_stops.isNotEmpty) _frontier = _stops.last;
        _selected = _keyOf[_frontier];
      });

  void _hideAll() => setState(() {
        _frontier = 0;
        _selected = null;
      });

  /// The ayah in front of you, missed. Held rather than tapped, so it cannot be
  /// hit by the tap that reveals -- and only failure is recorded: a page that
  /// went well leaves nothing behind.
  Future<void> _markMissed() async {
    final key = _selected;
    final doc = _doc;
    if (!widget.recall || key == null || doc == null) return;
    final ayat = (doc['ayat'] as List).cast<Map<String, Object?>>();
    final match = ayat.where((a) => a['verse_key'] == key);
    await widget.library.recordMiss(
      verseKey: key,
      page: _page,
      surahNameAr: match.isEmpty ? '' : match.first['surah_name_ar'] as String,
    );
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(kMarkedMissed(key)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
            border: Border.all(color: _goldBright, width: 1),
            borderRadius: BorderRadius.circular(2),
          ),
          child: FittedBox(
            child: Text(
              line['name_ar'] as String,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontFamily: kDrawnFace,
                fontSize: size * 0.40,
                color: _gold,
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
              color: _gold,
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
    // In recall the sheet is the tap target and no word carries a recognizer of
    // its own. That is not economy: on a page set edge to edge, a per-word tap
    // takes the arena from the sheet's nearly every time.
    final recognizer = widget.recall
        ? null
        : _recognizers.putIfAbsent(
            key,
            () => TapGestureRecognizer()..onTap = () => _openPanel(t.verseKey),
          );

    // Withheld, not removed. The glyphs are still set, still measured, still in
    // their place on the line; only the ink is kept back. Taking the words out
    // would re-set the page, and where a phrase falls on the page is half of
    // what a reciter holds. The ayah numbers stay lit, so the page keeps its
    // skeleton and you can see how much is still to come.
    final hidden = widget.recall &&
        !t.isMarker &&
        (t.wordId == null || t.wordId! > _frontier);

    return TextSpan(
      text: t.code,
      style: TextStyle(
        fontFamily: _family(_page),
        fontSize: size,
        // The stylesheet's .qline line-height. The glyphs ask for 1.531em, so
        // they overflow their line box by design and must not be clipped.
        height: kLineHeight,
        color: hidden ? Colors.transparent : (t.isMarker ? _gold : _ink),
        // The underline marks a mutashabih phrase. Drawn under covered words it
        // would point straight at the thing being recalled, so it waits.
        decoration: t.marked && !hidden
            ? TextDecoration.underline
            : TextDecoration.none,
        decorationColor: _goldBright,
        decorationThickness: 0.6,
        backgroundColor:
            hidden ? _covered : (_selected == t.verseKey ? _selection : null),
      ),
      recognizer: recognizer,
    );
  }
}
