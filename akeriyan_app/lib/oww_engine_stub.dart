import 'dart:async';

/// Web / no-FFI stub for [OpenWakeWordService].
///
/// tflite_flutter (and the openWakeWord pipeline) rely on `dart:ffi`, which is
/// not available on the web. This stub keeps the same public API so the app
/// compiles and runs in Chrome — the wake word simply does nothing there
/// (tap-to-talk still works). The real engine lives in `oww_engine_io.dart`
/// and is selected automatically on mobile via a conditional import.
class OpenWakeWordService {
  /// Detection threshold (0..1). Unused on web; kept for API parity.
  static double threshold = 0.5;

  bool get listening => false;

  Future<String?> start(Function() onWake) async => null;

  Future<void> stop() async {}

  Future<void> resume() async {}

  static Future<void> pauseGlobal() async {}

  static Future<void> resumeGlobal() async {}
}
