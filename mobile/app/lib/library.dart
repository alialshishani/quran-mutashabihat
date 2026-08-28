// Where you were, and what you marked.
//
// Both live on the device and nowhere else, in the same store the drill's
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

class Library {
  Library._(this._prefs, this._bookmarks);

  static const String _lastPageKey = 'read.lastPage.v1';
  static const String _bookmarksKey = 'read.bookmarks.v1';

  final SharedPreferences _prefs;
  final List<Bookmark> _bookmarks;

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
    return Library._(prefs, marks);
  }

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
}
