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
import 'package:quran_port/drill.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;

import 'progress.dart';

const Color _ink = Color(0xFF191C19);
const Color _inkSoft = Color(0xFF4A5049);
const Color _inkMute = Color(0xFF767C74);
const Color _accent = Color(0xFF16584A);
const Color _accentSoft = Color(0xFFE4EFEA);
const Color _gold = Color(0xFF8A6C22);
const Color _goldSoft = Color(0xFFFBEFD2);
const Color _wrongTint = Color(0xFF8C3B2E);

class DrillScreen extends StatefulWidget {
  const DrillScreen({super.key, required this.db, required this.onGo});

  final CommonDatabase db;
  final void Function(int page, String verseKey) onGo;

  @override
  State<DrillScreen> createState() => _DrillScreenState();
}

class _DrillScreenState extends State<DrillScreen> {
  final Random _rng = Random();

  List<DrillCandidate> _pool = const [];
  Progress? _progress;
  DrillCandidate? _current;
  DrillQuestion? _question;
  List<DrillOption> _shuffled = const [];
  int? _picked;

  int _right = 0;
  int _wrong = 0;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final pool = drillPool(widget.db);
    final progress = await Progress.open();
    if (!mounted) return;
    setState(() {
      _pool = pool;
      _progress = progress;
    });
    _next();
  }

  /// Due questions first, in the pool's own order -- cheapest shape first, so a
  /// reciter meets `all_but_one` (one exception to hold) before `many` (a peg
  /// per position). Among the due, pick at random so a session is not the same
  /// session twice.
  void _next() {
    final progress = _progress;
    if (progress == null || _pool.isEmpty) return;
    final now = DateTime.now();

    var due = _pool.where((c) => progress.isDue(c.key, now)).toList();
    if (due.isEmpty) due = _pool;
    // The first 60 of the due list keeps the ordering meaningful while still
    // varying what comes up.
    final window = due.take(60).toList();
    final pick = window[_rng.nextInt(window.length)];

    final q = drillQuestion(widget.db, pick.phraseId, pick.posId);
    setState(() {
      _current = pick;
      _question = q;
      _shuffled = [...q.options]..shuffle(_rng);
      _picked = null;
    });
  }

  Future<void> _answer(DrillOption option) async {
    final q = _question;
    final c = _current;
    if (q == null || c == null || _picked != null) return;

    final correct = q.isCorrect(option.branchId);
    setState(() {
      _picked = option.branchId;
      correct ? _right++ : _wrong++;
    });
    await _progress?.record(c.key, correct: correct);
  }

  @override
  Widget build(BuildContext context) {
    final q = _question;
    final progress = _progress;

    return Scaffold(
      backgroundColor: const Color(0xFFFCFCFA),
      appBar: AppBar(
        title: const Text('Drill'),
        actions: [
          if (progress != null && _pool.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Text(
                  '$_right / ${_right + _wrong}',
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 13, color: _inkSoft),
                ),
              ),
            ),
        ],
      ),
      body: q == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _place(q),
                const SizedBox(height: 14),
                _road(q),
                const SizedBox(height: 18),
                const Text('which way does it go?',
                    style: TextStyle(fontSize: 12, color: _inkMute)),
                const SizedBox(height: 8),
                for (final o in _shuffled) _option(q, o),
                if (_picked != null) ...[
                  const SizedBox(height: 14),
                  _answerBlock(q),
                ],
              ],
            ),
      bottomNavigationBar: q == null
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Row(
                children: [
                  if (progress != null)
                    Expanded(
                      child: Builder(builder: (_) {
                        final s = progress.summary(
                            _pool.map((c) => c.key), DateTime.now());
                        return Text(
                          '${s.due} due  ·  ${s.seen} seen  ·  '
                          '${_pool.length} in all',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: _inkMute),
                        );
                      }),
                    ),
                  FilledButton(
                    onPressed: _picked == null ? null : _next,
                    child: const Text('Next'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _place(DrillQuestion q) => Row(
        children: [
          Text(q.surahNameAr,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                  fontFamily: 'Amiri', fontSize: 18, color: _ink)),
          const SizedBox(width: 8),
          Text(q.verseKey,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 12, color: _inkMute)),
          const Spacer(),
          if (q.countInSurah > 1)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _goldSoft,
                borderRadius: BorderRadius.circular(4),
              ),
              // For eighteen positions nothing in the wording tells them apart,
              // and which time it is in the sūrah is the reciter's only handle.
              child: Text('${q.ordinalInSurah} of ${q.countInSurah} here',
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 10, color: _gold)),
            ),
          Text('one of ${q.positionCount}',
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 11, color: _inkMute)),
        ],
      );

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
        color: Colors.white,
        border: Border.all(color: const Color(0xFFECEEE9)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fromPreviousAyah)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text('end of the āyah before',
                  style: TextStyle(fontSize: 10, color: _inkMute)),
            ),
          Text.rich(
            TextSpan(children: [
              if (runUp != null)
                TextSpan(
                  text: '$runUp ',
                  style: const TextStyle(
                      fontFamily: 'Amiri',
                      fontSize: 19,
                      height: 2.0,
                      color: _inkMute),
                ),
              TextSpan(
                text: q.roadAr,
                style: const TextStyle(
                    fontFamily: 'Amiri',
                    fontSize: 23,
                    height: 2.0,
                    color: _ink),
              ),
              const TextSpan(
                text: ' …',
                style: TextStyle(
                    fontFamily: 'Amiri',
                    fontSize: 23,
                    height: 2.0,
                    color: _gold),
              ),
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

    Color border = const Color(0xFFDFE2DC);
    Color fill = Colors.white;
    if (answered && isAnswer) {
      border = _accent;
      fill = _accentSoft;
    } else if (answered && isPicked) {
      border = _wrongTint;
      fill = const Color(0xFFF7E7E4);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: answered ? null : () => _answer(o),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: border, width: answered ? 1.4 : 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                if (answered)
                  Icon(
                    isAnswer
                        ? Icons.check
                        : (isPicked ? Icons.close : Icons.remove),
                    size: 16,
                    color: isAnswer
                        ? _accent
                        : (isPicked ? _wrongTint : const Color(0xFFDFE2DC)),
                  ),
                if (answered) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    o.endsSurah ? '— the sūrah ends here —' : (o.tokenAr ?? '—'),
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: 'Amiri',
                      fontSize: o.endsSurah ? 15 : 21,
                      color: o.endsSurah ? _inkSoft : _ink,
                    ),
                  ),
                ),
                // How many positions take this way -- only after answering, or
                // it gives the answer away.
                if (answered)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text('${o.positionCount}',
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: _inkMute)),
                  ),
              ],
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
            color: peg == null ? const Color(0xFFF3F4F0) : _goldSoft,
            borderRadius: BorderRadius.circular(8),
            border: peg == null
                ? null
                : Border.all(color: const Color(0xFFD8A93C), width: 0.8),
          ),
          child: peg == null
              ? const Text(
                  'No ḍābiṭ verified for this position — the confusion set does '
                  'not yield a cue that holds it apart on its own.',
                  style: TextStyle(fontSize: 12, color: _inkSoft, height: 1.5),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(peg['kind'] as String,
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 9.5,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.w700,
                                color: _gold)),
                        const Spacer(),
                        Text('strength ${peg['strength']}',
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 9.5,
                                color: _inkMute)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      peg['text_ar'] as String,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                          fontFamily: 'Amiri',
                          fontSize: 16,
                          height: 1.9,
                          color: Color(0xFF6B4708)),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        if (q.page != null)
          TextButton.icon(
            onPressed: () => widget.onGo(q.page!, q.verseKey),
            icon: const Icon(Icons.menu_book_outlined, size: 16),
            label: Text('see it on page ${q.page}'),
          ),
      ],
    );
  }
}
