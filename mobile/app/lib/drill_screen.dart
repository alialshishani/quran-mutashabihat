// The drill.
//
// You are at a place. Here is the wording that place shares with others, and
// here are the ways out of it. Which one does this place take?
//
// The question is the fork; the answer is which branch this position belongs
// to; and a miss is answered with the peg pipeline.pegs verified for it. None
// of it is composed here -- the road, the branches and the peg sentence all
// come out of the corpus.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quran_port/drill.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;

import 'progress.dart';
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
Color get _accentSoft => palette.accentSoft;
Color get _gold => palette.gold;
Color get _goldBright => palette.goldBright;
Color get _goldSoft => palette.goldSoft;
Color get _goldDeep => palette.goldDeep;
Color get _surface => palette.surface;
Color get _rule => palette.line;
Color get _wrongTint => palette.wrong;
Color get _wrongSoft => palette.wrongSoft;

class DrillScreen extends StatefulWidget {
  const DrillScreen({
    super.key,
    required this.db,
    required this.progress,
    required this.pool,
    required this.onGo,
    required this.onOpenMenu,
    required this.onSessionEnd,
  });

  final CommonDatabase db;

  /// Opened once by the shell. Both this screen and the Today screen read it,
  /// and a second copy would let them disagree about what is due.
  final Progress progress;
  final List<DrillCandidate> pool;

  final void Function(int page, String verseKey) onGo;

  /// The same drawer the sheet opens, so the lists, the search and the
  /// settings reach every screen and not only the muṣḥaf.
  final VoidCallback onOpenMenu;

  /// A session finished, so whatever else is showing a count is now stale.
  final VoidCallback onSessionEnd;

  @override
  State<DrillScreen> createState() => DrillScreenState();
}

class DrillScreenState extends State<DrillScreen> {
  final Random _rng = Random();

  /// The questions this session will ask, chosen when it is started and not
  /// added to. A session that can grow is a session that never ends, which is
  /// what the drill used to be.
  List<DrillCandidate> _session = const [];
  int _at = 0;

  DrillQuestion? _question;
  List<DrillOption> _shuffled = const [];
  int? _picked;

  int _right = 0;

  /// What went wrong this session, so the end card can offer them again.
  final List<DrillCandidate> _shaky = [];

  @override
  void initState() {
    super.initState();
    if (widget.pool.isNotEmpty) startSession();
  }

  /// Whether a session is under way, as against sitting on the end card.
  bool get _running => _at < _session.length;

  /// Deal a session.
  ///
  /// Due questions first, in the pool's own order -- cheapest shape first, so
  /// a reciter meets `all_but_one` (one exception to hold) before `many` (a
  /// peg per position). Among the due, shuffled, so a session is not the same
  /// session twice.
  void startSession({List<DrillCandidate>? from}) {
    if (widget.pool.isEmpty) return;
    final now = DateTime.now();

    List<DrillCandidate> take;
    if (from != null && from.isNotEmpty) {
      take = [...from];
    } else {
      var due =
          widget.pool.where((c) => widget.progress.isDue(c.key, now)).toList();
      // Nothing due is not nothing to do: a reciter who has come back the same
      // day gets the head of the pool rather than an empty screen.
      if (due.isEmpty) due = [...widget.pool];
      // The head of the due list keeps the ordering meaningful; the shuffle
      // inside it keeps the session from repeating.
      take = due.take(60).toList()..shuffle(_rng);
      take = take.take(kSessionLength).toList();
    }

    setState(() {
      _session = take;
      _at = 0;
      _right = 0;
      _shaky.clear();
    });
    _ask();
  }

  /// Build the question at the cursor.
  void _ask() {
    if (!_running) {
      setState(() => _question = null);
      return;
    }
    final pick = _session[_at];
    final q = drillQuestion(widget.db, pick.phraseId, pick.posId);
    setState(() {
      _question = q;
      _shuffled = [...q.options]..shuffle(_rng);
      _picked = null;
    });
  }

  void _next() {
    setState(() => _at += 1);
    if (_running) {
      _ask();
    } else {
      // The end of a session changes every count the app shows anywhere.
      setState(() => _question = null);
      HapticFeedback.mediumImpact();
      widget.onSessionEnd();
    }
  }

  Future<void> _answer(DrillOption option) async {
    final q = _question;
    if (q == null || _picked != null || !_running) return;
    final c = _session[_at];

    final correct = q.isCorrect(option.branchId);
    setState(() {
      _picked = option.branchId;
      if (correct) {
        _right++;
      } else {
        _shaky.add(c);
      }
    });
    // The app's one haptic used to be on failure, so the whole of what it
    // could say with the body it said to punish. Both are answers.
    if (correct) {
      HapticFeedback.selectionClick();
    } else {
      HapticFeedback.heavyImpact();
    }
    await widget.progress.record(c.key, correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final q = _question;

    return Scaffold(
      backgroundColor: _paper,
      appBar: AppBar(
        leading: IconButton(
          tooltip: kMenu,
          onPressed: widget.onOpenMenu,
          icon: const Icon(Icons.menu),
        ),
        title: Text(kNavDrill, style: tTitle()),
        // Where you are in the session, as a length rather than a fraction.
        // The score used to sit here instead, which told a reciter how he was
        // doing and never how much was left -- and how much is left is the
        // thing that makes a session finishable.
        bottom: _session.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  tween: Tween(end: _at / _session.length),
                  builder: (_, v, __) => LinearProgressIndicator(
                    value: v,
                    minHeight: 2,
                    backgroundColor: _rule,
                    color: _accent,
                  ),
                ),
              ),
      ),
      body: widget.pool.isEmpty
          ? _noPool()
          : (!_running ? _endCard() : (q == null ? _waiting() : _ask3(q))),
      bottomNavigationBar: (q == null || !_running)
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      kGivenOf(_at + 1, _session.length),
                      style: tLabel(),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(textStyle: tBody()),
                    onPressed: _picked == null ? null : _next,
                    child: Text(
                        _at + 1 >= _session.length ? kSessionFinish : kNext),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _waiting() => Center(
        child: SizedBox(
          width: 96,
          child: LinearProgressIndicator(
              minHeight: 2, backgroundColor: _rule, color: _gold),
        ),
      );

  Widget _noPool() => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.model_training_outlined, size: 34, color: _inkMute),
              const SizedBox(height: 16),
              Text(kNoPoolTitle, style: tTitle()),
              const SizedBox(height: 6),
              Text(kNoPoolGloss,
                  textAlign: TextAlign.center, style: tCaption(_inkMute)),
            ],
          ),
        ),
      );

  Widget _ask3(DrillQuestion q) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _place(q),
          const SizedBox(height: 14),
          _road(q),
          const SizedBox(height: 18),
          Text(kQuestion, style: tCaption(_inkMute)),
          const SizedBox(height: 8),
          for (final o in _shuffled) _option(q, o),
          if (_picked != null) ...[
            const SizedBox(height: 14),
            _answerBlock(q),
          ],
        ],
      );

  /// The end of a session, which the drill never had.
  ///
  /// A count of what was right, what went back to the first box, and the two
  /// things worth doing next. Anki's deck screen and Duolingo's end card are
  /// the same object: the session is a contract, and this is it discharged.
  Widget _endCard() {
    final all = _session.length;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(kSessionDone, textAlign: TextAlign.center, style: tLabel()),
            const SizedBox(height: 10),
            Text(kSessionScore(_right, all),
                textAlign: TextAlign.center,
                style: tDisplay(_shaky.isEmpty ? _accent : _ink)),
            const SizedBox(height: 12),
            Text(
              _shaky.isEmpty ? kSessionPerfect : kSessionShaky(_shaky.length),
              textAlign: TextAlign.center,
              style: tCaption(_inkMute),
            ),
            const SizedBox(height: 28),
            if (_shaky.isNotEmpty)
              FilledButton(
                style: FilledButton.styleFrom(
                  textStyle: tBody(),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => startSession(from: [..._shaky]),
                child: const Text(kSessionAgain),
              ),
            if (_shaky.isNotEmpty) const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                textStyle: tBody(),
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: _rule),
              ),
              onPressed: () => startSession(),
              child: const Text(kStartDrill),
            ),
          ],
        ),
      ),
    );
  }

  Widget _place(DrillQuestion q) => Row(
        children: [
          Text(q.surahNameAr,
              textDirection: TextDirection.rtl, style: tQuranSmall()),
          const SizedBox(width: 8),
          Text(arDigits(q.verseKey), style: tLabel()),
          const Spacer(),
          if (q.countInSurah > 1)
            Container(
              margin: const EdgeInsetsDirectional.only(end: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _goldSoft,
                borderRadius: BorderRadius.circular(4),
              ),
              // For eighteen positions nothing in the wording tells them apart,
              // and which time it is in the sūrah is the reciter's only handle.
              child: Text(kOrdinalHere(q.ordinalInSurah, q.countInSurah),
                  style: tLabel(_gold)),
            ),
          _strength(),
        ],
      );

  /// Which Leitner box this question sits in, as five pips.
  ///
  /// The schedule has been keeping this per question since it was written and
  /// showing it nowhere: a reciter could answer the same fork twenty times and
  /// never learn whether the app thought he had it. Boxes 3 and 4 rest a week
  /// and three weeks, so a filled pip is real ground held.
  Widget _strength() {
    if (!_running) return const SizedBox.shrink();
    final box = widget.progress.boxOf(_session[_at].key);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < kBoxRest.length; i++)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 3),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < box ? _accent : _rule,
              ),
            ),
          ),
      ],
    );
  }

  /// The run-up and the road.
  ///
  /// The āyah from its start up to the fork, dimmed, then the wording every
  /// position shares, then an ellipsis where they part. Without the run-up the
  /// question is often unanswerable: 491 forks have one sūrah taking two or
  /// more ways out, so the sūrah name settles nothing and the road is shared by
  /// definition.
  Widget _road(DrillQuestion q) {
    final runUp = q.leadInAr ?? q.precedingAr;
    final fromPreviousAyah = q.leadInAr == null && q.precedingAr != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fromPreviousAyah)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(kLeadInBefore, style: tLabel()),
            ),
          Text.rich(
            TextSpan(children: [
              if (runUp != null)
                TextSpan(text: '$runUp ', style: tQuranSmall(_inkMute)),
              TextSpan(text: q.roadAr, style: tQuranLead()),
              TextSpan(text: ' …', style: tQuranLead(_gold)),
            ]),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  Widget _option(DrillQuestion q, DrillOption o) {
    final answered = _picked != null;
    final isAnswer = o.branchId == q.answerBranchId;
    final isPicked = o.branchId == _picked;

    Color border = _rule;
    Color fill = _raised;
    if (answered && isAnswer) {
      border = _accent;
      fill = _accentSoft;
    } else if (answered && isPicked) {
      border = _wrongTint;
      fill = _wrongSoft;
    }

    // A right answer used to be a border colour changing, instantly, and
    // nothing else. The card now settles into its answered state over a beat,
    // which is the whole of the reward the drill offers and cost nothing.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: border, width: answered ? 1.4 : 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: answered ? null : () => _answer(o),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  if (answered)
                    Icon(
                      isAnswer
                          ? Icons.check
                          : (isPicked ? Icons.close : Icons.remove),
                      size: 16,
                      color:
                          isAnswer ? _accent : (isPicked ? _wrongTint : _rule),
                    ),
                  if (answered) const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      o.endsSurah ? kEndsSurah : (o.tokenAr ?? '—'),
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: o.endsSurah
                          ? tCaption(_inkSoft)
                          : tQuranLead(),
                    ),
                  ),
                  // How many positions take this way -- only after answering,
                  // or it gives the answer away.
                  if (answered)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: Text(ar(o.positionCount), style: tLabel()),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// After answering: the peg, which is the point. Knowing the way out is not
  /// the same as knowing what tells this place from the others.
  Widget _answerBlock(DrillQuestion q) {
    final peg = q.peg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: peg == null ? _surface : _goldSoft,
            borderRadius: BorderRadius.circular(8),
            border:
                peg == null ? null : Border.all(color: _goldBright, width: 0.8),
          ),
          child: peg == null
              ? Text(kNoPeg, style: tCaption(_inkSoft))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(pegKind(peg['kind'] as String),
                            style: tLabel(_gold)),
                        const Spacer(),
                        Text('$kPegStrength ${arPercent(peg['strength'] as num)}',
                            style: tLabel()),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      arDigits(peg['text_ar'] as String),
                      textDirection: TextDirection.rtl,
                      style: tQuranSmall(_goldDeep),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        if (q.page != null)
          TextButton.icon(
            style: TextButton.styleFrom(textStyle: tCaption()),
            onPressed: () => widget.onGo(q.page!, q.verseKey),
            icon: const Icon(Icons.menu_book_outlined, size: 16),
            label: Text(kSeeOnPage(q.page!)),
          ),
      ],
    );
  }
}
