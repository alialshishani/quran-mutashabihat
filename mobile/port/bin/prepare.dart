// Build the database the app ships: the pipeline's output plus the indexes the
// read path needs.
//
//   dart run bin/prepare.dart <src.db> <out.db>
//
// A build step, not a migration -- the source is left exactly as pipeline/ wrote
// it. Indexes change no query result, only what a page turn costs.

import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('usage: dart run bin/prepare.dart <src.db> <out.db> '
        '[read_path_indexes.sql]');
    exit(2);
  }
  // One source for the DDL, shared with tools/stage_assets.py.
  final ddlPath = args.length > 2 ? args[2] : '../tools/read_path_indexes.sql';
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open('winsqlite3.dll'),
  );

  final out = File(args[1]);
  if (out.existsSync()) out.deleteSync();
  File(args[0]).copySync(out.path);

  final before = out.lengthSync();
  final db = sqlite3.open(out.path);
  db.execute(File(ddlPath).readAsStringSync());
  db.execute('ANALYZE');
  db.execute('VACUUM');
  db.dispose();

  final after = File(out.path).lengthSync();
  stdout.writeln('indexes from $ddlPath + ANALYZE + VACUUM');
  stdout.writeln('${(before / 1e6).toStringAsFixed(1)} MB -> '
      '${(after / 1e6).toStringAsFixed(1)} MB');
}
