// What the reciter has and has not held onto.
//
// A Leitner box per question, kept on the device and nowhere else. A hit moves
// the question up a box and so further away; a miss sends it back to the first,
// because a wording you have just confused is one to see again soon.
//
// Deliberately small. The corpus is the hard part of this project; the schedule
// is not, and a schedule nobody can explain is worse than one that is obvious.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// How long a question rests in each box. Five boxes; the last is effectively
/// "known", and still comes back eventually.
const List<Duration> kBoxRest = [
  Duration.zero,
  Duration(days: 1),
  Duration(days: 3),
  Duration(days: 7),
  Duration(days: 21),
];

class Record {
  Record({this.box = 0, this.seen = 0, this.missed = 0, this.lastMs = 0});

  factory Record.fromJson(List<dynamic> j) => Record(
        box: j[0] as int,
        seen: j[1] as int,
        missed: j[2] as int,
        lastMs: j[3] as int,
      );

  int box;
  int seen;
  int missed;
  int lastMs;

  List<int> toJson() => [box, seen, missed, lastMs];

  bool dueAt(DateTime now) {
    if (seen == 0) return true;
    final rest = kBoxRest[box.clamp(0, kBoxRest.length - 1)];
    return DateTime.fromMillisecondsSinceEpoch(lastMs).add(rest).isBefore(now);
  }
}

/// How many questions a session is.
///
/// The drill used to have no answer to this: `_next` picked another question
/// and went on picking, so the only way to finish was to put the phone down,
/// and nothing was ever completed. A session that ends is a session that can
/// be started -- twelve is about four minutes, which is short enough to do
/// between two other things and long enough to move a box.
const int kSessionLength = 12;

/// The box at which a question stops being work and starts being kept.
///
/// Boxes 3 and 4 rest a week and three weeks. A question that has survived
/// that long is not something the reciter is learning any more, and saying so
/// is the whole point of showing the boxes at all.
const int kMasteredFrom = 3;

/// How the pool stands: what has never been asked, what is still being got
/// wrong, and what has settled.
typedef Mastery = ({int unseen, int learning, int mastered, int all});

class Progress {
  Progress._(this._prefs, this._records, this._streak, this._lastDay);

  static const String _key = 'drill.records.v1';
  static const String _streakKey = 'drill.streak.v1';

  final SharedPreferences _prefs;
  final Map<String, Record> _records;

  /// How many days running the drill has been opened and answered. Kept
  /// beside the boxes because it answers a different question: the boxes say
  /// what is known, the streak says whether anyone is still turning up.
  int _streak;
  int _lastDay;

  static Future<Progress> open() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final records = <String, Record>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        (json.decode(raw) as Map<String, dynamic>).forEach((k, v) {
          records[k] = Record.fromJson(v as List<dynamic>);
        });
      } on FormatException {
        // A store we cannot read is a store we start again; losing a schedule
        // is not worth failing to open the drill over.
      }
    }
    final streak = prefs.getStringList(_streakKey);
    return Progress._(
      prefs,
      records,
      streak == null ? 0 : (int.tryParse(streak.first) ?? 0),
      streak == null || streak.length < 2 ? 0 : (int.tryParse(streak[1]) ?? 0),
    );
  }

  /// The local day a moment falls in, counted in days. Local rather than UTC
  /// on purpose: a reciter who drills at ten at night and again at seven the
  /// next morning has turned up on two days, whatever UTC thinks.
  static int _dayOf(DateTime t) =>
      DateTime(t.year, t.month, t.day).millisecondsSinceEpoch ~/ 86400000;

  /// Days running, or zero once a day has been missed. Computed rather than
  /// stored, so a streak lapses on its own without the app being opened to
  /// notice.
  int streakAt(DateTime now) {
    if (_streak == 0) return 0;
    final today = _dayOf(now);
    return (_lastDay == today || _lastDay == today - 1) ? _streak : 0;
  }

  /// Whether today has been counted yet, which is what a Today screen needs
  /// to know to say `ابدأ اليوم` rather than a number.
  bool answeredToday(DateTime now) => _lastDay == _dayOf(now);

  Future<void> _touchStreak(DateTime now) async {
    final today = _dayOf(now);
    if (_lastDay == today) return;
    _streak = _lastDay == today - 1 ? _streak + 1 : 1;
    _lastDay = today;
    await _prefs.setStringList(_streakKey, ['$_streak', '$_lastDay']);
  }

  /// Where the pool stands, for the strip on the Today screen.
  ///
  /// The Leitner boxes were being kept and never shown: five levels of "how
  /// well is this held" recorded per question and reported to the reciter as
  /// nothing at all. This is the whole of what the schedule knows, in three
  /// numbers.
  Mastery mastery(Iterable<String> keys) {
    var unseen = 0, learning = 0, mastered = 0, all = 0;
    for (final k in keys) {
      all += 1;
      final r = _records[k];
      if (r == null || r.seen == 0) {
        unseen += 1;
      } else if (r.box >= kMasteredFrom) {
        mastered += 1;
      } else {
        learning += 1;
      }
    }
    return (unseen: unseen, learning: learning, mastered: mastered, all: all);
  }

  /// Which box a question sits in, for the strength shown beside it.
  int boxOf(String key) => of(key).box;

  Record of(String key) => _records[key] ?? Record();

  bool isDue(String key, DateTime now) => of(key).dueAt(now);

  Future<void> record(String key, {required bool correct}) async {
    final now = DateTime.now();
    await _touchStreak(now);
    final r = _records.putIfAbsent(key, Record.new);
    r.seen += 1;
    r.lastMs = now.millisecondsSinceEpoch;
    if (correct) {
      if (r.box < kBoxRest.length - 1) r.box += 1;
    } else {
      r.missed += 1;
      r.box = 0;
    }
    await _flush();
  }

  Future<void> reset() async {
    _records.clear();
    _streak = 0;
    _lastDay = 0;
    await _prefs.remove(_key);
    await _prefs.remove(_streakKey);
  }

  Future<void> _flush() => _prefs.setString(
        _key,
        json.encode({for (final e in _records.entries) e.key: e.value.toJson()}),
      );

  ({int seen, int due, int missed}) summary(
    Iterable<String> keys,
    DateTime now,
  ) {
    var seen = 0;
    var due = 0;
    var missed = 0;
    for (final k in keys) {
      final r = _records[k];
      if (r != null && r.seen > 0) {
        seen += 1;
        missed += r.missed;
      }
      if (r == null || r.dueAt(now)) due += 1;
    }
    return (seen: seen, due: due, missed: missed);
  }
}
