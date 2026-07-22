import 'dart:async';
import 'package:dio/dio.dart';
import 'notification_service.dart';

/// Polls the backend for triggered price/RSI alerts and the morning briefing,
/// then shows them as local notifications. Runs while the app process is alive
/// (the foreground service keeps it alive in the background).
class AlertsPoller {
  static Timer? _timer;
  static final _dio = Dio();

  static void start(String backendUrl, String token) {
    _timer?.cancel();
    _poll(backendUrl, token); // check immediately on open
    _timer = Timer.periodic(
        const Duration(minutes: 2), (_) => _poll(backendUrl, token));
  }

  static Future<void> _poll(String backendUrl, String token) async {
    try {
      final r = await _dio.get(
        '$backendUrl/v1/alerts/pending',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final list = (r.data['pending'] as List?) ?? [];
      for (final p in list) {
        await NotificationService.show(
            (p['title'] as String?) ?? 'Elder Wand', (p['body'] as String?) ?? '');
      }
    } catch (_) {
      // offline or backend down — try again next tick
    }
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
