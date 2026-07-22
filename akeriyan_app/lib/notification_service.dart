import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings: settings,
    );

    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();

    _ready = true;
  }

  /// Show an immediate notification (used for proactive price/RSI alerts and
  /// the morning briefing pushed by the backend).
  static Future<void> show(String title, String body) async {
    await init();
    final id = DateTime.now().microsecondsSinceEpoch.remainder(1 << 31);
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'akeriyan_alerts',
          'Alerts & Briefings',
          channelDescription: 'Proactive price/RSI alerts and morning briefing',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
      ),
    );
  }

  static Future<void> scheduleReminder({
    required String task,
    required DateTime time,
    bool daily = false,
  }) async {
    await init();
    final id = DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);

    await _plugin.zonedSchedule(
      id: id,
      title: 'Elder Wand Reminder',
      body: task,
      scheduledDate: tz.TZDateTime.from(time, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'akeriyan_reminders',
          'Reminders',
          channelDescription: 'Elder Wand voice reminders',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: daily ? DateTimeComponents.time : null,
    );
  }
}