/// Platform selector for the openWakeWord engine.
///
/// On mobile (dart:io / dart:ffi available) this exports the real TFLite
/// pipeline from `oww_engine_io.dart`. On the web it falls back to a no-op
/// stub so the app still compiles and runs in Chrome (the wake word is a
/// native feature and simply stays inactive there — tap-to-talk still works).
library;

export 'oww_engine_stub.dart' if (dart.library.io) 'oww_engine_io.dart';
