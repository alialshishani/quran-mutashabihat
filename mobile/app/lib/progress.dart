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

class Progress {
  Progress._(this._prefs, this._records);

  static const String _key = 'drill.records.v1';

  final SharedPreferences _prefs;
  final Map<String, Record> _records;

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
    return Progress._(prefs, records);
  }

  Record of(String key) => _records[key] ?? Record();

  bool isDue(String key, DateTime now) => of(key).dueAt(now);

  Future<void> record(String key, {required bool correct}) async {
    final r = _records.putIfAbsent(key, Record.new);
    r.seen += 1;
    r.lastMs = DateTime.now().millisecondsSinceEpoch;
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
    await _prefs.remove(_key);
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
