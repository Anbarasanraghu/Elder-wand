import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Speaks replies with the natural offline Piper voice served by the backend
/// (`POST /v1/tts` -> WAV), and falls back to the phone's built-in TTS when the
/// backend is unreachable or Piper isn't available.
///
/// `speak()` completes only when playback finishes, so callers can safely start
/// listening again afterwards (used by continuous conversation).
class TtsService {
  static final FlutterTts _device = FlutterTts();
  static final AudioPlayer _player = AudioPlayer();
  static final Dio _dio = Dio();
  static String? _backendUrl;
  static String? _token;
  static bool _deviceReady = false;

  static Future<void> init(String backendUrl, String token) async {
    _backendUrl = backendUrl;
    _token = token;
    // Fail fast to the phone voice when the PC/Piper isn't reachable.
    _dio.options.connectTimeout = const Duration(seconds: 2);
    if (!_deviceReady) {
      try {
        // Prefer Google's neural TTS engine — far more human than the defaults.
        final engines = await _device.getEngines;
        if (engines is List &&
            engines.map((e) => '$e').contains('com.google.android.tts')) {
          await _device.setEngine('com.google.android.tts');
        }
      } catch (_) {}
      await _device.setLanguage('en-US');
      // Apply the user's saved voice if they picked one; else best-quality.
      final saved = await _savedVoice();
      if (saved != null) {
        try {
          await _device.setVoice(saved);
        } catch (_) {}
      } else {
        await _pickNaturalVoice();
      }
      await _device.setSpeechRate(0.52); // natural pace
      await _device.setPitch(1.0);
      await _device.awaitSpeakCompletion(true);
      _deviceReady = true;
    }
  }

  static const _kVoiceName = 'tts_voice_name';
  static const _kVoiceLocale = 'tts_voice_locale';

  static Future<Map<String, String>?> _savedVoice() async {
    final p = await SharedPreferences.getInstance();
    final n = p.getString(_kVoiceName), l = p.getString(_kVoiceLocale);
    return (n != null && l != null) ? {'name': n, 'locale': l} : null;
  }

  /// All English voices on the phone, best quality first — for the picker.
  static Future<List<Map<String, String>>> englishVoices() async {
    try {
      final raw = await _device.getVoices;
      if (raw is! List) return [];
      final en = <Map<String, String>>[];
      for (final v in raw) {
        if (v is Map) {
          final locale = '${v['locale'] ?? ''}';
          if (locale.toLowerCase().startsWith('en')) {
            en.add({
              'name': '${v['name'] ?? ''}',
              'locale': locale,
              'quality': '${v['quality'] ?? ''}',
            });
          }
        }
      }
      en.sort((a, b) => _q(b['quality']!).compareTo(_q(a['quality']!)));
      return en;
    } catch (_) {
      return [];
    }
  }

  static int _q(String quality) => switch (quality) {
        'very high' => 4,
        'high' => 3,
        'normal' => 2,
        _ => 1,
      };

  /// Preview a voice without saving it.
  static Future<void> previewVoice(Map<String, String> v) async {
    try {
      await _player.stop();
      await _device.setVoice({'name': v['name']!, 'locale': v['locale']!});
      await _device.speak("Hi, I'm Elder Wand. This is how I sound.");
    } catch (_) {}
  }

  /// Save + apply a voice as the assistant's permanent voice.
  static Future<void> selectVoice(Map<String, String> v) async {
    try {
      await _device.setVoice({'name': v['name']!, 'locale': v['locale']!});
      final p = await SharedPreferences.getInstance();
      await p.setString(_kVoiceName, v['name']!);
      await p.setString(_kVoiceLocale, v['locale']!);
    } catch (_) {}
  }

  static Future<Map<String, String>?> currentVoice() => _savedVoice();

  static Future<void> _pickNaturalVoice() async {
    final en = await englishVoices();
    if (en.isEmpty) return;
    try {
      await _device
          .setVoice({'name': en.first['name']!, 'locale': en.first['locale']!});
    } catch (_) {}
  }

  /// Speak with the phone's neural voice directly — no PC/Piper round-trip.
  /// Used for on-device replies so there's zero backend latency.
  static Future<void> speakLocal(String text, {String lang = 'en'}) async {
    text = text.trim();
    if (text.isEmpty) return;
    try {
      await _player.stop();
      if (lang != 'en') {
        await _device.setLanguage('$lang-IN');
        await _device.speak(text);
        await _device.setLanguage('en-US');
      } else {
        await _device.speak(text);
      }
    } catch (_) {}
  }

  static Future<void> speak(String text, {String lang = 'en'}) async {
    text = text.trim();
    if (text.isEmpty) return;

    // Non-English (e.g. Tamil): Piper only has an English voice, so use the
    // phone's built-in TTS voice for that language.
    if (lang != 'en') {
      try {
        await _player.stop();
        await _device.setLanguage('$lang-IN');
        await _device.speak(text);
        await _device.setLanguage('en-IN'); // reset for next English reply
        return;
      } catch (_) {
        // fall through to the normal path
      }
    }

    if (_backendUrl != null) {
      try {
        final resp = await _dio.post(
          '$_backendUrl/v1/tts',
          data: {'text': text},
          options: Options(
            headers: {'Authorization': 'Bearer $_token'},
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 30),
          ),
        );
        final data = resp.data;
        if (resp.statusCode == 200 && data is List<int> && data.isNotEmpty) {
          await _playBytes(Uint8List.fromList(data));
          return;
        }
      } catch (_) {
        // fall through to device TTS
      }
    }
    await _device.speak(text);
  }

  static Future<void> _playBytes(Uint8List bytes) async {
    await _player.stop();
    final completer = Completer<void>();
    late StreamSubscription<void> sub;
    sub = _player.onPlayerComplete.listen((_) {
      sub.cancel();
      if (!completer.isCompleted) completer.complete();
    });
    await _player.play(BytesSource(bytes, mimeType: 'audio/wav'));
    await completer.future.timeout(const Duration(seconds: 45),
        onTimeout: () => sub.cancel());
  }

  // ---- Phase 2: streaming playback queue ----
  // The backend's /v1/converse/stream emits WAV chunks (one per sentence) as the
  // LLM generates. We play them back-to-back so the reply starts within ~1-2s
  // instead of waiting for the whole answer + full synthesis.
  static final List<Uint8List> _queue = <Uint8List>[];
  static bool _pumping = false;

  /// Begin a fresh streamed reply (clears any leftover chunks).
  static void beginStream() {
    _queue.clear();
  }

  /// Add a WAV chunk; playback starts immediately if idle, else it queues.
  static void enqueueWav(Uint8List bytes) {
    if (bytes.isEmpty) return;
    _queue.add(bytes);
    _pump();
  }

  static Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_queue.isNotEmpty) {
        await _playBytes(_queue.removeAt(0));
      }
    } finally {
      _pumping = false;
    }
  }

  /// Wait until every queued chunk has finished playing.
  static Future<void> endStream() async {
    while (_queue.isNotEmpty || _pumping) {
      await Future.delayed(const Duration(milliseconds: 40));
    }
  }

  static Future<void> stop() async {
    _queue.clear();
    await _player.stop();
    await _device.stop();
  }
}
