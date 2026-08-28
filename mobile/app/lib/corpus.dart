// Opening the corpus, whichever platform this is.
//
// The two paths differ completely and the rest of the app sees neither: on the
// web SQLite is a WASM build reading the file from an in-memory VFS, and on
// iOS/Android it is the native library reading a real file. `openCorpus` is the
// only thing either one exposes.

export 'corpus_native.dart' if (dart.library.js_interop) 'corpus_web.dart';
