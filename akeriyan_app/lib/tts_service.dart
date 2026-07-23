import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_tts/flutter_tts.dart';

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
    if (!_deviceReady) {
      await _device.setLanguage('en-IN');
      await _device.setSpeechRate(0.5);
      await _device.awaitSpeakCompletion(true);
      _deviceReady = true;
    }
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
