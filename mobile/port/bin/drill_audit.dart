// How answerable is the drill, actually?
//
//   dart run bin/drill_audit.dart <db>
//
// Counts the questions whose displayed run-up does not distinguish them from a
// sibling expecting a different answer. Those are questions no reciter could
// get right, and they should not be asked.

import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:quran_port/drill.dart';

void main(List<String> args) {
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open('winsqlite3.dll'),
  );
  final db = sqlite3.open(args[0], mode: OpenMode.readOnly);
  final pool = drillPool(db);

  final byFork = <int, List<DrillCandidate>>{};
  for (final c in pool) {
    (byFork[c.phraseId] ??= []).add(c);
  }

  var noRunUp = 0;
  var opensSurah = 0;
  var sameSurah = 0;   // the reciter cannot tell: the real problem
  var crossSurah = 0;  // told apart by the surah name the question shows
  final examples = <String>[];

  for (final entry in byFork.entries) {
    // Keyed by surah, because a question shows which surah it is in and that
    // settles a collision between two surahs on its own. A collision inside one
    // surah is the one a reciter actually faces.
    final withinSurah = <String, int>{};
    final anywhere = <String, int>{};

    for (final c in entry.value) {
      final q = drillQuestion(db, c.phraseId, c.posId);
      if (q.leadInAr == null && q.precedingAr == null) {
        noRunUp++;
        if (q.verseKey.endsWith(':1')) opensSurah++;
      }
      final surah = q.verseKey.split(':')[0];
      final ctx = '${q.precedingAr ?? ""}|${q.leadInAr ?? ""}|${q.roadAr}'
          '|${q.countInSurah > 1 ? q.ordinalInSurah : 0}';

      final near = withinSurah['$surah|$ctx'];
      if (near != null && near != q.answerBranchId) {
        sameSurah++;
        if (examples.length < 8) {
          examples.add('${q.verseKey} (fork ${q.phraseId})');
        }
      }
      withinSurah['$surah|$ctx'] = q.answerBranchId;

      final far = anywhere[ctx];
      if (far != null && far != q.answerBranchId) crossSurah++;
      anywhere[ctx] = q.answerBranchId;
    }
  }

  stdout.writeln('questions               : ${pool.length}');
  stdout.writeln('no run-up at all        : $noRunUp  '
      '(of which open a sūrah: $opensSurah)');
  stdout.writeln('ambiguous within a sūrah: $sameSurah');
  stdout.writeln('ambiguous only across   : $crossSurah  '
      '(the question names the sūrah, so these are answerable)');
  if (examples.isNotEmpty) {
    stdout.writeln('  e.g. ${examples.join(", ")}');
  }
}
