import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

/// Offline wake-word listener powered by Vosk.
///
/// Vosk allows only ONE native SpeechService per process, so the engine is held
/// in STATIC fields and created exactly once — re-entering the assistant screen
/// reuses it instead of trying to init a second one (which throws
/// "SpeechService instance already exist"). Other screens that need the mic
/// (e.g. the meeting recorder) call [pauseGlobal] / [resumeGlobal].
class WakeWordService {
  static const String _modelAsset =
      'assets/models/vosk-model-small-en-us-0.15.zip';
  static const int _sampleRate = 16000;

  static final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  static Model? _model;
  static Recognizer? _recognizer;
  static SpeechService? _speech;
  static bool _initialized = false;
  static bool _woken = false;
  static bool _running = false; // true while the mic stream is active
  static Function()? _onWake;

  bool get listening => _running;

  /// Grammar restricts Vosk to ONLY the wake phrase (+ "[unk]" for everything
  /// else). This makes wake detection much faster, far lighter on CPU, and far
  /// less prone to false triggers than open transcription.
  static const List<String> _wakeGrammar = [
    'hey elder wand', 'elder wand', 'elder', 'wand', '[unk]',
  ];

  /// Fire as soon as any of these appears — 'elder' lets it trigger on the
  /// first word for a fast, "Hey Google"-like response.
  static const List<String> _variants = [
    'elder wand', 'hey elder wand', 'elder', 'alder wand', 'held a wand',
  ];

  Future<String?> start(Function() onWake) async {
    _onWake = onWake;
    _woken = false;
    try {
      if (!_initialized) {
        // First launch unzips the ~40MB model into app storage (a few seconds).
        final modelPath = await ModelLoader().loadFromAssets(_modelAsset);
        _model = await _vosk.createModel(modelPath);
        _recognizer = await _vosk.createRecognizer(
            model: _model!, sampleRate: _sampleRate, grammar: _wakeGrammar);
        _speech = await _vosk.initSpeechService(_recognizer!);
        _speech!.onPartial().listen(_onText);
        _speech!.onResult().listen(_onText);
        _initialized = true;
      }
      await _speech!.start();
      _running = true;
      return null;
    } catch (e) {
      // If the engine already exists (hot restart / re-entry) just (re)start it.
      if (_speech != null) {
        try {
          await _speech!.start();
          _running = true;
          return null;
        } catch (_) {}
      }
      debugPrint('[WAKE] init error: $e');
      // Non-fatal: the orb (tap-to-talk) still works without the wake word.
      return null;
    }
  }

  static void _onText(String json) {
    if (_woken) return;
    String heard;
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      heard = ((m['partial'] ?? m['text'] ?? '') as String).toLowerCase();
    } catch (_) {
      heard = json.toLowerCase();
    }
    if (heard.isEmpty) return;
    debugPrint('[WAKE] heard: $heard');
    for (final v in _variants) {
      if (heard.contains(v)) {
        debugPrint('[WAKE] WAKE WORD DETECTED via "$v"');
        _woken = true;
        _fireWake();
        return;
      }
    }
  }

  static Future<void> _fireWake() async {
    await _stopStream();
    _onWake?.call();
  }

  static Future<void> _stopStream() async {
    try {
      if (_speech != null && _running) await _speech!.stop();
    } catch (e) {
      debugPrint('[WAKE] stop error: $e');
    }
    _running = false;
  }

  Future<void> stop() => _stopStream();

  Future<void> resume() async {
    _woken = false;
    if (_speech == null) {
      await start(_onWake ?? () {});
      return;
    }
    if (_running) return;
    try {
      await _recognizer?.reset(); // clear stale partial from last utterance
      await _speech!.start();
      _running = true;
    } catch (e) {
      debugPrint('[WAKE] resume error: $e');
    }
  }

  /// Free the mic for another recorder (meeting notes). Call [resumeGlobal] after.
  static Future<void> pauseGlobal() => _stopStream();

  static Future<void> resumeGlobal() async {
    _woken = false;
    if (_speech == null || _running) return;
    try {
      await _recognizer?.reset();
      await _speech!.start();
      _running = true;
    } catch (e) {
      debugPrint('[WAKE] resume error: $e');
    }
  }
}
