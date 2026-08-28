// Is the port's own output stable across query plans?
//
//   dart run bin/selfcheck.dart <db-a> <db-b>
//
// Runs every page against two databases holding the same corpus but planning
// queries differently (one indexed, one not) and compares the two outputs byte
// for byte. With `phrase_ids` ordered explicitly this must pass; without the
// ORDER BY it does not, which is the whole point.

import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:quran_port/mushaf.dart';

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
  final a = sqlite3.open(args[0], mode: OpenMode.readOnly);
  final b = sqlite3.open(args[1], mode: OpenMode.readOnly);

  final total = pageCount(a);
  var same = 0;
  final differ = <int>[];

  for (var page = 1; page <= total; page++) {
    final ja = jsonEncode(canonical(mushafPage(a, page)));
    final jb = jsonEncode(canonical(mushafPage(b, page)));
    if (ja == jb) {
      same++;
    } else {
      differ.add(page);
    }
  }

  stdout.writeln('pages     : $total');
  stdout.writeln('identical : $same');
  stdout.writeln('differing : ${differ.length}'
      '${differ.isEmpty ? "" : "  ${differ.take(10).join(", ")}"}');
  if (differ.isNotEmpty) exit(1);
}
