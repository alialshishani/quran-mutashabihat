// Compare the Dart `officialMatches` with the Python's, for every ayah that
// carries an official mutashabih phrase.
//
//   dart run bin/verify_official.dart <db> <golden-dir>

import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:quran_port/official.dart';

Object? canonical(Object? v) {
  if (v is Map) {
    final out = SplayTreeMap<String, Object?>();
    v.forEach((k, value) => out[k as String] = canonical(value));
    return out;
  }
  if (v is List) return [for (final e in v) canonical(e)];
  return v;
}

void main(List<String> args) {
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open('winsqlite3.dll'),
  );
  final db = sqlite3.open(args[0], mode: OpenMode.readOnly);
  final dir = args[1];

  final keys = (json.decode(File('$dir/index.json').readAsStringSync()) as List)
      .cast<String>();

  final names = surahNamesOf(db);
  final juz = juzOfAll(db);

  var ok = 0;
  final bad = <String>[];
  final sw = Stopwatch()..start();

  for (final key in keys) {
    final parts = key.split(':');
    final s = int.parse(parts[0]);
    final a = int.parse(parts[1]);

    final mine = utf8.encode(
      jsonEncode(canonical(officialMatches(db, s, a, Words(db), names, juz))),
    );
    final theirs = File('$dir/${s}_$a.json').readAsBytesSync();

    var same = mine.length == theirs.length;
    if (same) {
      for (var i = 0; i < mine.length; i++) {
        if (mine[i] != theirs[i]) {
          same = false;
          break;
        }
      }
    }
    if (same) {
      ok++;
    } else {
      bad.add(key);
    }
  }
  sw.stop();

  stdout.writeln('ayat      : ${keys.length}');
  stdout.writeln('identical : $ok');
  stdout.writeln('differing : ${bad.length}'
      '${bad.isEmpty ? "" : "  ${bad.take(10).join(", ")}"}');
  stdout.writeln('elapsed   : ${sw.elapsedMilliseconds} ms');
  if (bad.isNotEmpty) exit(1);
}
