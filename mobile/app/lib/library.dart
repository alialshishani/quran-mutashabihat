// Where you were, what you marked, and what you missed.
//
// All three live on the device and nowhere else, in the same store the drill's
// Leitner boxes use.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class Bookmark {
  Bookmark({
    required this.verseKey,
    required this.page,
    required this.surahNameAr,
    required this.addedMs,
  });

  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
        verseKey: j['k'] as String,
        page: j['p'] as int,
        surahNameAr: j['s'] as String,
        addedMs: j['t'] as int,
      );

  final String verseKey;
  final int page;
  final String surahNameAr;
  final int addedMs;

  Map<String, Object?> toJson() =>
      {'k': verseKey, 'p': page, 's': surahNameAr, 't': addedMs};
}

/// An ayah recall asked for and did not get.
///
/// Only failures are kept. A recall session that went well leaves nothing
/// behind -- there is no use in a list of what you already know -- so the
/// missed list is short by construction and is the whole of what it says.
class Miss {
  Miss({
    required this.verseKey,
    required this.page,
    required this.surahNameAr,
    required this.count,
    required this.lastMs,
  });

  factory Miss.fromJson(Map<String, dynamic> j) => Miss(
        verseKey: j['k'] as String,
        page: j['p'] as int,
        surahNameAr: j['s'] as String,
        count: j['n'] as int,
        lastMs: j['t'] as int,
      );

  final String verseKey;
  final int page;
  final String surahNameAr;

  /// How many times it has been missed. A place missed four times is not the
  /// same as one missed once, and the list says so rather than averaging it.
  final int count;
  final int lastMs;

  Map<String, Object?> toJson() =>
      {'k': verseKey, 'p': page, 's': surahNameAr, 'n': count, 't': lastMs};
}

class Library {
  Library._(this._prefs, this._bookmarks, this._missed);

  static const String _lastPageKey = 'read.lastPage.v1';
  static const String _bookmarksKey = 'read.bookmarks.v1';
  static const String _missedKey = 'recall.missed.v1';
  static const String _forkStopsKey = 'recall.stopAtForks.v1';

  final SharedPreferences _prefs;
  final List<Bookmark> _bookmarks;
  final List<Miss> _missed;

  static Future<Library> open() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_bookmarksKey);
    final marks = <Bookmark>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final e in json.decode(raw) as List) {
          marks.add(Bookmark.fromJson(e as Map<String, dynamic>));
        }
      } on FormatException {
        // A store that cannot be read is one we start again. Losing bookmarks
        // is not worth refusing to open the muṣḥaf over.
      }
    }
    final missed = <Miss>[];
    final rawMissed = prefs.getString(_missedKey);
    if (rawMissed != null && rawMissed.isNotEmpty) {
      try {
        for (final e in json.decode(rawMissed) as List) {
          missed.add(Miss.fromJson(e as Map<String, dynamic>));
        }
      } on FormatException {
        // As above: a store that cannot be read is one we start again.
      }
    }
    return Library._(prefs, marks, missed);
  }

  /// Whether recall stops where a shared road turns, as well as at the end of
  /// every ayah. On by default: the turning is the thing worth being asked,
  /// and a reciter who wants the plain cover can say so once.
  bool get stopAtForks => _prefs.getBool(_forkStopsKey) ?? true;

  Future<void> setStopAtForks(bool on) => _prefs.setBool(_forkStopsKey, on);

  /// The page last read, or null the first time the app is opened.
  int? get lastPage => _prefs.getInt(_lastPageKey);

  Future<void> setLastPage(int page) => _prefs.setInt(_lastPageKey, page);

  List<Bookmark> get bookmarks =>
      [..._bookmarks]..sort((a, b) => b.addedMs.compareTo(a.addedMs));

  bool has(String verseKey) =>
      _bookmarks.any((b) => b.verseKey == verseKey);

  Future<void> toggle(Bookmark mark) async {
    final at = _bookmarks.indexWhere((b) => b.verseKey == mark.verseKey);
    if (at >= 0) {
      _bookmarks.removeAt(at);
    } else {
      _bookmarks.add(mark);
    }
    await _prefs.setString(
      _bookmarksKey,
      json.encode([for (final b in _bookmarks) b.toJson()]),
    );
  }

  /// The missed, worst first: most often missed, and among equals the most
  /// recent. What to go back to is the top of this list.
  List<Miss> get missed => [..._missed]..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : b.lastMs.compareTo(a.lastMs);
      });

  int get missCount => _missed.length;

  bool missedHas(String verseKey) =>
      _missed.any((m) => m.verseKey == verseKey);

  /// Mark an ayah missed, or mark it missed again.
  Future<void> recordMiss({
    required String verseKey,
    required int page,
    required String surahNameAr,
  }) async {
    final at = _missed.indexWhere((m) => m.verseKey == verseKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    final miss = Miss(
      verseKey: verseKey,
      page: page,
      surahNameAr: surahNameAr,
      count: at >= 0 ? _missed[at].count + 1 : 1,
      lastMs: now,
    );
    if (at >= 0) {
      _missed[at] = miss;
    } else {
      _missed.add(miss);
    }
    await _saveMissed();
  }

  /// Struck off the list, because it has been learnt.
  Future<void> clearMiss(String verseKey) async {
    _missed.removeWhere((m) => m.verseKey == verseKey);
    await _saveMissed();
  }

  Future<void> _saveMissed() => _prefs.setString(
        _missedKey,
        json.encode([for (final m in _missed) m.toJson()]),
      );
}
