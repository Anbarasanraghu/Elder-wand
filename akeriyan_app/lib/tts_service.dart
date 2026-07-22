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

  static Future<void> stop() async {
    await _player.stop();
    await _device.stop();
  }
}
