// How long does building one page actually take? Page-turn latency is the
// number that decides whether the mushaf view feels like a book.

import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:quran_port/mushaf.dart';

void main(List<String> args) {
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open('winsqlite3.dll'),
  );
  final db = sqlite3.open(args[0], mode: OpenMode.readOnly);
  final total = pageCount(db);

  // Warm the cache the way real use does, then time every page once.
  for (var p = 1; p <= 20; p++) {
    mushafPage(db, p);
  }

  final times = <int>[];
  for (var page = 1; page <= total; page++) {
    final sw = Stopwatch()..start();
    mushafPage(db, page);
    sw.stop();
    times.add(sw.elapsedMicroseconds);
  }
  times.sort();

  String ms(int us) => (us / 1000).toStringAsFixed(1);
  final sum = times.reduce((a, b) => a + b);

  stdout.writeln('pages   : $total');
  stdout.writeln('mean    : ${ms(sum ~/ total)} ms');
  stdout.writeln('median  : ${ms(times[total ~/ 2])} ms');
  stdout.writeln('p95     : ${ms(times[(total * 0.95).floor()])} ms');
  stdout.writeln('max     : ${ms(times.last)} ms');
}
