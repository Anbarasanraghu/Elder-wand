import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';

import 'api_registry.dart';

/// Batch 4 — real device actions via Android system intents: set an alarm or
/// timer in the Clock app, add an event to the Calendar, and play music by
/// voice. These are fire-and-forget (no mic contention with the wake word).
class DeviceActions {
  static String _clock(int h, int m) {
    final ampm = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    final mm = m.toString().padLeft(2, '0');
    return m == 0 ? '$h12 $ampm' : '$h12:$mm $ampm';
  }

  /// Sets a real alarm in the phone's Clock app for [hour]:[minute] (24h).
  static Future<String> setAlarm(
      {required int hour, required int minute, String? label}) async {
    ApiUsage.record('intents');
    final intent = AndroidIntent(
      action: 'android.intent.action.SET_ALARM',
      arguments: <String, dynamic>{
        'android.intent.extra.alarm.HOUR': hour,
        'android.intent.extra.alarm.MINUTES': minute,
        'android.intent.extra.alarm.SKIP_UI': true,
        if (label != null && label.isNotEmpty)
          'android.intent.extra.alarm.MESSAGE': label,
      },
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
    );
    try {
      await intent.launch();
      return 'Alarm set for ${_clock(hour, minute)}'
          '${label != null && label.isNotEmpty ? ' — $label' : ''}.';
    } catch (_) {
      return "I couldn't reach the clock app to set that alarm.";
    }
  }

  /// Starts a countdown timer in the phone's Clock app for [seconds].
  static Future<String> setSystemTimer(int seconds, {String? label}) async {
    ApiUsage.record('intents');
    final intent = AndroidIntent(
      action: 'android.intent.action.SET_TIMER',
      arguments: <String, dynamic>{
        'android.intent.extra.alarm.LENGTH': seconds,
        'android.intent.extra.alarm.SKIP_UI': true,
        if (label != null && label.isNotEmpty)
          'android.intent.extra.alarm.MESSAGE': label,
      },
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
    );
    final mins = seconds ~/ 60;
    final human =
        mins > 0 ? '$mins minute${mins != 1 ? 's' : ''}' : '$seconds seconds';
    try {
      await intent.launch();
      return 'Timer started for $human.';
    } catch (_) {
      return "I couldn't reach the clock app to start that timer.";
    }
  }

  /// Opens the Calendar app pre-filled with a new event so the user can confirm.
  static Future<String> addCalendarEvent({
    required String title,
    required DateTime begin,
    DateTime? end,
  }) async {
    ApiUsage.record('intents');
    final endT = end ?? begin.add(const Duration(hours: 1));
    final intent = AndroidIntent(
      action: 'android.intent.action.INSERT',
      data: 'content://com.android.calendar/events',
      arguments: <String, dynamic>{
        'title': title,
        'beginTime': begin.millisecondsSinceEpoch,
        'endTime': endT.millisecondsSinceEpoch,
      },
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
    );
    try {
      await intent.launch();
      return 'Opening your calendar to add "$title".';
    } catch (_) {
      return "I couldn't open the calendar app.";
    }
  }

  /// Tells the default music app to play [query] (a song, artist, or "music").
  static Future<String> playMusic(String query) async {
    ApiUsage.record('intents');
    final q = query.trim();
    final intent = AndroidIntent(
      action: 'android.media.action.MEDIA_PLAY_FROM_SEARCH',
      arguments: <String, dynamic>{'query': q},
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
    );
    try {
      await intent.launch();
      return q.isEmpty ? 'Playing music.' : 'Playing $q.';
    } catch (_) {
      return "I couldn't find a music app to play that.";
    }
  }
}
