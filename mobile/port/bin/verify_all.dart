// Compare the Dart ports of fork_index, fork_detail and lookup with the
// Python's own output.
//
//   dart run bin/verify_all.dart <db> <golden-root>

import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:quran_port/forks.dart';
import 'package:quran_port/lookup.dart';

Object? canonical(Object? v) {
  if (v is Map) {
    final out = SplayTreeMap<String, Object?>();
    v.forEach((k, value) => out[k as String] = canonical(value));
    return out;
  }
  if (v is List) return [for (final e in v) canonical(e)];
  return v;
}

bool same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

int report(String name, int ok, List<String> bad) {
  stdout.writeln('${name.padRight(12)} identical ${ok.toString().padLeft(5)}'
      '   differing ${bad.length}'
      '${bad.isEmpty ? "" : "  ${bad.take(6).join(", ")}"}');
  return bad.length;
}

void main(List<String> args) {
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open('winsqlite3.dll'),
  );
  final db = sqlite3.open(args[0], mode: OpenMode.readOnly);
  final root = args[1];
  var failures = 0;

  // --- fork_index -----------------------------------------------------------
  {
    final cases = (json.decode(
            File('$root/forks/cases.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    var ok = 0;
    final bad = <String>[];
    for (var i = 0; i < cases.length; i++) {
      final c = cases[i];
      final doc = forkIndex(
        db,
        shape: c['shape'] as String?,
        minPositions: (c['min_positions'] as int?) ?? 2,
        surah: c['surah'] as int?,
        q: c['q'] as String?,
        sort: (c['sort'] as String?) ?? 'useful',
        limit: (c['limit'] as int?) ?? 25,
        offset: (c['offset'] as int?) ?? 0,
      );
      final mine = utf8.encode(jsonEncode(canonical(doc)));
      final theirs = File('$root/forks/index_$i.json').readAsBytesSync();
      same(mine, theirs) ? ok++ : bad.add('case $i $c');
    }
    failures += report('fork_index', ok, bad);
  }

  // --- fork_detail ----------------------------------------------------------
  {
    final ids = (json.decode(File('$root/forks/ids.json').readAsStringSync())
            as List)
        .cast<int>();
    var ok = 0;
    final bad = <String>[];
    for (final id in ids) {
      final mine = utf8.encode(jsonEncode(canonical(forkDetail(db, id))));
      final theirs = File('$root/forks/detail_$id.json').readAsBytesSync();
      same(mine, theirs) ? ok++ : bad.add('$id');
    }
    failures += report('fork_detail', ok, bad);
  }

  // --- lookup ---------------------------------------------------------------
  {
    final keys = (json.decode(
            File('$root/lookup/keys.json').readAsStringSync()) as List)
        .cast<String>();
    var ok = 0;
    final bad = <String>[];
    for (final key in keys) {
      final p = key.split(':');
      final s = int.parse(p[0]);
      final a = int.parse(p[1]);
      final mine = utf8.encode(jsonEncode(canonical(lookup(db, s, a))));
      final theirs = File('$root/lookup/${s}_$a.json').readAsBytesSync();
      same(mine, theirs) ? ok++ : bad.add(key);
    }
    failures += report('lookup', ok, bad);
  }

  if (failures > 0) exit(1);
}
