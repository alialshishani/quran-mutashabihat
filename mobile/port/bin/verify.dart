// Run the Dart port over every printed page and compare it, byte for byte,
// with what app/lookup.py produced for the same page.
//
//   dart run bin/verify.dart <db> <golden-dir>
//
// Both sides emit the same canonical form -- keys sorted, UTF-8, compact -- so
// a difference in key order cannot hide a difference in content, and a match
// means the two implementations agree on every field of every page.

import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:quran_port/mushaf.dart';

/// Recursively sort every map key, so encoding is deterministic on both sides.
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
  if (args.length < 2) {
    stderr.writeln('usage: dart run bin/verify.dart <db> <golden-dir>');
    exit(2);
  }
  final dbPath = args[0];
  final goldenDir = Directory(args[1]);

  // Windows ships a SQLite the Dart package can drive; nothing to vendor.
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open('winsqlite3.dll'),
  );

  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  stdout.writeln('sqlite ${sqlite3.version.libVersion}  (dart side)');

  final total = pageCount(db);
  stdout.writeln('$total pages');

  var ok = 0;
  final failures = <int, String>{};
  final sw = Stopwatch()..start();

  for (var page = 1; page <= total; page++) {
    final doc = mushafPage(db, page);
    final mine = utf8.encode(jsonEncode(canonical(doc)));

    final file = File('${goldenDir.path}/p$page.json');
    if (!file.existsSync()) {
      failures[page] = 'no golden file';
      continue;
    }
    final theirs = file.readAsBytesSync();

    if (mine.length == theirs.length) {
      var same = true;
      for (var i = 0; i < mine.length; i++) {
        if (mine[i] != theirs[i]) {
          same = false;
          failures[page] = _context(mine, theirs, i);
          break;
        }
      }
      if (same) {
        ok++;
        continue;
      }
    } else {
      var i = 0;
      while (i < mine.length && i < theirs.length && mine[i] == theirs[i]) {
        i++;
      }
      failures[page] =
          'length ${mine.length} vs golden ${theirs.length}; ${_context(mine, theirs, i)}';
    }
  }

  sw.stop();
  stdout.writeln('');
  stdout.writeln('identical : $ok / $total');
  stdout.writeln('differing : ${failures.length}');
  stdout.writeln('elapsed   : ${sw.elapsedMilliseconds} ms '
      '(${(sw.elapsedMicroseconds / total / 1000).toStringAsFixed(2)} ms/page)');

  if (failures.isNotEmpty) {
    stdout.writeln('');
    final shown = failures.keys.take(5);
    for (final p in shown) {
      stdout.writeln('page $p: ${failures[p]}');
    }
    if (failures.length > shown.length) {
      stdout.writeln('... and ${failures.length - shown.length} more');
    }
    exit(1);
  }
}

String _context(List<int> mine, List<int> theirs, int at) {
  String slice(List<int> b) {
    final lo = (at - 60).clamp(0, b.length);
    final hi = (at + 60).clamp(0, b.length);
    return utf8.decode(b.sublist(lo, hi), allowMalformed: true);
  }

  return 'first difference at byte $at\n'
      '      dart: ...${slice(mine)}...\n'
      '    python: ...${slice(theirs)}...';
}
