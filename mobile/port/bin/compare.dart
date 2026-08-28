// Compare the port with the Python goldens, structurally rather than by bytes,
// with `phrase_ids` treated as a set.
//
//   dart run bin/compare.dart <db> <golden-dir>
//
// Byte comparison on the pipeline's own database already passes 604/604. This
// answers the narrower question the indexed database raises: when the query
// plan changes, is the difference confined to the order of `phrase_ids`, or is
// there a real disagreement hiding behind it?

import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:quran_port/mushaf.dart';

/// Sort keys, and sort any `phrase_ids` list, so ordering cannot register as a
/// difference. Every other list keeps its order -- lines, tokens and ayat are
/// sequences whose order is meaning, and a difference there must still fail.
Object? canonical(Object? v, {String? key}) {
  if (v is Map) {
    final out = SplayTreeMap<String, Object?>();
    v.forEach((k, value) => out[k as String] = canonical(value, key: k));
    return out;
  }
  if (v is List) {
    final items = [for (final e in v) canonical(e)];
    if (key == 'phrase_ids') {
      items.sort((a, b) => (a as int).compareTo(b as int));
    }
    return items;
  }
  return v;
}

void main(List<String> args) {
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open('winsqlite3.dll'),
  );
  final db = sqlite3.open(args[0], mode: OpenMode.readOnly);
  final total = pageCount(db);

  var identical = 0;
  var orderOnly = 0;
  final real = <int>[];

  for (var page = 1; page <= total; page++) {
    final doc = mushafPage(db, page);
    final golden =
        json.decode(File('${args[1]}/p$page.json').readAsStringSync());

    final strictMine = jsonEncode(_plain(doc));
    final strictTheirs = jsonEncode(_plain(golden));
    if (strictMine == strictTheirs) {
      identical++;
      continue;
    }

    final looseMine = jsonEncode(canonical(doc));
    final looseTheirs = jsonEncode(canonical(golden));
    if (looseMine == looseTheirs) {
      orderOnly++;
    } else {
      real.add(page);
    }
  }

  stdout.writeln('pages                     : $total');
  stdout.writeln('byte-identical            : $identical');
  stdout.writeln('differ only in phrase_ids : $orderOnly');
  stdout.writeln('differ in content         : ${real.length}');
  if (real.isNotEmpty) {
    stdout.writeln('  pages: ${real.take(20).join(", ")}');
    exit(1);
  }
}

/// Key-sorted only -- the strict form, matching bin/verify.dart.
Object? _plain(Object? v) {
  if (v is Map) {
    final out = SplayTreeMap<String, Object?>();
    v.forEach((k, value) => out[k as String] = _plain(value));
    return out;
  }
  if (v is List) return [for (final e in v) _plain(e)];
  return v;
}
