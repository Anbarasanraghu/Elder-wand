import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Tapping a notification whose payload is a URL (e.g. a wa.me link from the
  /// Message Agent) opens it — this is how "one-tap WhatsApp" works.
  static void _onTap(NotificationResponse r) {
    final p = r.payload;
    if (p != null && p.startsWith('http')) {
      launchUrl(Uri.parse(p), mode: LaunchMode.externalApplication);
    }
  }

  @pragma('vm:entry-point')
  static void _onTapBackground(NotificationResponse r) {
    // Background taps can't reliably launch; the tap re-opens the app and the
    // foreground handler above takes over.
  }

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onTap,
      onDidReceiveBackgroundNotificationResponse: _onTapBackground,
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
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'akeriyan_alerts',
          'Alerts & Briefings',
          channelDescription: 'Proactive price/RSI alerts and morning briefing',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          styleInformation: BigTextStyleInformation(body), // expand long text
        ),
      ),
    );
  }

  /// Like [show] but carries a [payload] URL that opens when the user taps it.
  static Future<void> showTap(String title, String body, String payload) async {
    await init();
    final id = DateTime.now().microsecondsSinceEpoch.remainder(1 << 31);
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      payload: payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'akeriyan_alerts',
          'Alerts & Briefings',
          channelDescription: 'Proactive alerts and message-agent taps',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          styleInformation: BigTextStyleInformation(body),
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