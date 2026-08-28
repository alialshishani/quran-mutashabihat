// Opening the corpus on iOS and Android.
//
// `sqlite3_flutter_libs` bundles the native library, so there is no WASM to load
// and no VFS to register. The one wrinkle is that an asset inside an APK is not
// a file with a path, so the database is copied out once on first launch and
// opened read-only from there afterwards.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

const String kDbAsset = 'assets/app.db';

Future<CommonDatabase> openCorpus() async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/mushaf.db');

  final asset = await rootBundle.load(kDbAsset);
  final expected = asset.lengthInBytes;

  // Copied once. The length check also re-copies after an update ships a new
  // corpus, without needing a version to track.
  if (!file.existsSync() || file.lengthSync() != expected) {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(asset.buffer.asUint8List(), flush: true);
  }

  return sqlite3.open(file.path, mode: OpenMode.readOnly);
}
