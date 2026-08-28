// Opening the corpus in the browser.
//
// The database is the one `pipeline/` builds, plus the read-path indexes, shipped
// whole as an asset. SQLite itself is the package's WASM build, and the file is
// handed to it through an in-memory VFS -- so the page reads the real corpus with
// no server, no network after load, and no query rewritten for the web.
//
// On iOS and Android none of this is needed: `sqlite3_flutter_libs` bundles a
// native SQLite and `sqlite3.open` takes the file directly. This file is the
// web's share of the work, and it is all of it.

import 'package:flutter/services.dart';
import 'package:sqlite3/wasm.dart';
import 'package:typed_data/typed_buffers.dart';

const String kDbAsset = 'assets/app.db';
const String kWasmUrl = 'sqlite3.wasm';
const String _kDbPath = '/mushaf.db';

Future<CommonDatabase> openCorpus() async {
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse(kWasmUrl));

  final bytes = await rootBundle.load(kDbAsset);
  final fs = InMemoryFileSystem();
  fs.fileData[_kDbPath] = Uint8Buffer()..addAll(bytes.buffer.asUint8List());

  sqlite.registerVirtualFileSystem(fs, makeDefault: true);
  return sqlite.open(_kDbPath);
}
