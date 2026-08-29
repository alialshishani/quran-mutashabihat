// Where the app opens.
//
// It used to open on the muṣḥaf at page 89 -- the fallback -- with four peer
// destinations in a bar and nothing anywhere saying what to do. Every screen
// asked the reciter to decide: which page, which fork, how many questions,
// when to stop. The drill in particular ran forever, because `_next` simply
// picked another one.
//
// The apps people actually keep using do the opposite. They open on a screen
// that has already decided: here is where you stopped, here is what is due,
// here is how long it will take. So this screen is four answers and one
// button, and everything on it is read off stores the app was already
// keeping and never showed -- the last page, the Leitner boxes, the missed
// list.
//
// Nothing here is composed. The counts are the pool's, the boxes are the
// schedule's, and the surah names come from the corpus.

import 'package:flutter/material.dart';
import 'package:quran_port/drill.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;

import 'library.dart';
import 'progress.dart';
import 'strings.dart';
import 'theme.dart';
import 'type.dart';

// The palette in force, read by name; see theme.dart. These are getters
// rather than constants because the light can change while the app is up.
Color get _paper => palette.paper;
Color get _raised => palette.raised;
Color get _ink => palette.ink;
Color get _inkMute => palette.inkMute;
Color get _accent => palette.accent;
Color get _accentSoft => palette.accentSoft;
Color get _gold => palette.gold;
Color get _goldBright => palette.goldBright;
Color get _surface => palette.surface;
Color get _surfaceAlt => palette.surfaceAlt;
Color get _line => palette.line;
Color get _wrong => palette.wrong;

class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.db,
    required this.library,
    required this.progress,
    required this.pool,
    required this.onGo,
    required this.onStartDrill,
    required this.onOpenMenu,
  });

  final CommonDatabase db;
  final Library library;
  final Progress progress;

  /// The drill's pool, passed in rather than queried again: it is the same
  /// list the drill screen runs on, and building it twice would let the two
  /// screens disagree about what is due.
  final List<DrillCandidate> pool;

  final void Function(int page, [String? verseKey]) onGo;

  /// Start a session and show it. The Today screen decides that a session is
  /// wanted; the drill decides what is in it.
  final VoidCallback onStartDrill;

  final VoidCallback onOpenMenu;

  @override
  State<TodayScreen> createState() => TodayScreenState();
}

class TodayScreenState extends State<TodayScreen> {
  /// Called by the shell when this screen is returned to, since everything on
  /// it is a reading of stores that other screens write.
  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final keys = widget.pool.map((c) => c.key);
    final summary = widget.progress.summary(keys, now);
    final mastery = widget.progress.mastery(keys);
    final streak = widget.progress.streakAt(now);
    final missed = widget.library.missed;

    return Scaffold(
      backgroundColor: _paper,
      appBar: AppBar(
        leading: IconButton(
          tooltip: kMenu,
          onPressed: widget.onOpenMenu,
          icon: const Icon(Icons.menu),
        ),
        title: Text(kNavToday, style: tTitle()),
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Center(child: _streak(streak)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _resume(),
          const SizedBox(height: 12),
          _due(summary.due),
          if (missed.isNotEmpty) ...[
            const SizedBox(height: 24),
            _heading(kSectionNeedsWork),
            const SizedBox(height: 6),
            for (final m in missed.take(3)) _missedRow(m),
          ],
          if (mastery.all > 0) ...[
            const SizedBox(height: 24),
            _heading(kSectionMastery),
            const SizedBox(height: 10),
            _masteryStrip(mastery),
          ],
        ],
      ),
    );
  }

  Widget _heading(String label) => Text(label, style: tLabel());

  /// Days running. A flame would be the obvious mark and the wrong one --
  /// this is a book, and the streak is a lamp kept lit rather than a fire.
  Widget _streak(int days) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(days == 0 ? Icons.light_outlined : Icons.light,
              size: 16, color: days == 0 ? _inkMute : _gold),
          const SizedBox(width: 5),
          Text(kStreak(days), style: tLabel(days == 0 ? _inkMute : _gold)),
        ],
      );

  /// Where you stopped. The app knew this all along -- `library.lastPage` is
  /// what the muṣḥaf restores itself from -- and never said it anywhere the
  /// reciter could see before the page had already been turned to.
  Widget _resume() {
    final page = widget.library.lastPage;
    final where = page == null ? null : _surahAt(page);

    return _Card(
      onTap: () => widget.onGo(page ?? 1),
      fill: _raised,
      border: _surfaceAlt,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kSectionContinue, style: tLabel()),
                const SizedBox(height: 6),
                Text(where ?? kAppName,
                    textDirection: TextDirection.rtl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tQuranBody()),
                const SizedBox(height: 2),
                Text(pageN(page ?? 1), style: tLabel()),
              ],
            ),
          ),
          Icon(Icons.chevron_left, color: _inkMute),
        ],
      ),
    );
  }

  /// The sūrah a page opens in, for the resume card. One row, and only when
  /// the card is built.
  String? _surahAt(int page) {
    final rows = widget.db.select(
      'SELECT s.name_ar FROM ayahs a JOIN surahs s ON s.surah = a.surah '
      'WHERE a.page_start = ? ORDER BY a.surah, a.ayah LIMIT 1',
      [page],
    );
    return rows.isEmpty ? null : rows.first['name_ar'] as String;
  }

  /// What is due, and the one button on the screen.
  ///
  /// A session is bounded, and the card says by how much before it is
  /// started. An open-ended "practise" is the thing nobody opens.
  Widget _due(int due) {
    if (widget.pool.isEmpty) {
      return _Card(
        fill: _surface,
        border: _surfaceAlt,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(kNoPoolTitle, style: tBody()),
            const SizedBox(height: 4),
            Text(kNoPoolGloss, style: tCaption(_inkMute)),
          ],
        ),
      );
    }

    final nothing = due == 0;
    final take = due == 0 ? kSessionLength : (due < kSessionLength ? due : kSessionLength);

    return _Card(
      fill: nothing ? _surface : _accentSoft,
      border: nothing ? _surfaceAlt : _accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(nothing ? kNothingDue : kDueNow(due),
              style: tTitle(nothing ? _inkMute : _ink)),
          const SizedBox(height: 4),
          Text(
            nothing ? kNothingDueGloss : kSessionOf(take),
            style: tCaption(_inkMute),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                textStyle: tBody(),
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: nothing ? _surfaceAlt : _accent,
                foregroundColor: nothing ? _ink : palette.paper,
              ),
              onPressed: widget.onStartDrill,
              child: Text(nothing ? kDrillAnyway : kStartDrill),
            ),
          ),
        ],
      ),
    );
  }

  /// The three worst places from the missed list. Not the whole list -- that
  /// is what the index's tab is for -- but enough that the screen names
  /// somewhere to go rather than only a count.
  Widget _missedRow(Miss m) => InkWell(
        onTap: () => widget.onGo(m.page, m.verseKey),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              Icon(Icons.error_outline, size: 16, color: _wrong),
              const SizedBox(width: 10),
              Expanded(
                child: Text(m.surahNameAr,
                    textDirection: TextDirection.rtl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tQuranSmall()),
              ),
              const SizedBox(width: 8),
              Text('${arDigits(m.verseKey)}  ·  $kMissedTally ${ar(m.count)}',
                  style: tLabel()),
            ],
          ),
        ),
      );

  /// The Leitner boxes, at last visible.
  ///
  /// One bar in three bands rather than three numbers in a row: what the
  /// reciter wants off this is the proportion, and a proportion is a length.
  Widget _masteryStrip(Mastery m) {
    Widget band(int n, Color fill) => n == 0
        ? const SizedBox.shrink()
        : Expanded(flex: n, child: ColoredBox(color: fill));

    Widget key(String label, int n, Color fill) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, color: fill),
            const SizedBox(width: 6),
            Text('$label ${ar(n)}', style: tLabel()),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                band(m.mastered, _accent),
                band(m.learning, _goldBright),
                band(m.unseen, _line),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            key(kMastered, m.mastered, _accent),
            key(kLearning, m.learning, _goldBright),
            key(kUnseen, m.unseen, _line),
          ],
        ),
      ],
    );
  }
}

/// One block on the screen. The app had grown a habit of stacking a fill, a
/// border and a radius by hand at every level; this is the one shape, so the
/// screen has a single elevation rather than five.
class _Card extends StatelessWidget {
  const _Card({
    required this.child,
    required this.fill,
    required this.border,
    this.onTap,
  });

  final Widget child;
  final Color fill;
  final Color border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: child,
        ),
      ),
    );
  }
}
