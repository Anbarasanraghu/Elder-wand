import 'package:flutter_notification_listener/flutter_notification_listener.dart';

class NotificationReader {
  static final List<Map<String, String>> _log = [];
  static bool _started = false;

  /// Apps we don't want read aloud (our own service, system noise).
  static const _ignore = {
    'com.anbarasan.akeriyan_app',
    'android',
    'com.android.systemui',
  };

  static Future<bool> hasPermission() async {
    return await NotificationsListener.hasPermission ?? false;
  }

  static Future<void> requestPermission() async {
    await NotificationsListener.openPermissionSettings();
  }

  static Future<void> start() async {
    if (_started) return;
    await NotificationsListener.initialize(callbackHandle: _onNotification);
    NotificationsListener.receivePort?.listen((evt) => _store(evt));
    await NotificationsListener.startService();
    _started = true;
  }

  static void _store(NotificationEvent evt) {
    final pkg = evt.packageName ?? '';
    if (_ignore.contains(pkg)) return;
    final title = evt.title ?? '';
    final text = evt.text ?? '';
    if (title.isEmpty && text.isEmpty) return;
    _log.insert(0, {'app': pkg, 'title': title, 'text': text});
    if (_log.length > 100) _log.removeLast();
  }

  /// Returns a spoken summary of the latest notification.
  static String latestSpoken() {
    if (_log.isEmpty) return "You have no recent notifications.";
    final n = _log.first;
    final app = _appLabel(n['app'] ?? '');
    return "Your latest notification from $app: ${n['title']}. ${n['text']}";
  }

  static String allSpoken({int count = 3}) {
    if (_log.isEmpty) return "You have no recent notifications.";
    final items = _log.take(count).map((n) {
      final app = _appLabel(n['app'] ?? '');
      return "From $app: ${n['title']}. ${n['text']}";
    }).join('  ');
    return items;
  }

  static const _msgApps = {
    'whatsapp', 'telegram', 'messaging', 'messenger', 'signal',
    'instagram', 'sms', 'mms', 'gm', 'gmail',
  };

  /// Spoken summary of recent MESSAGE notifications only.
  static String messagesSpoken({int count = 5}) {
    final msgs = _log.where((n) {
      final a = (n['app'] ?? '').toLowerCase();
      return _msgApps.any((m) => a.contains(m));
    }).take(count).toList();
    if (msgs.isEmpty) return 'You have no new messages.';
    final body = msgs
        .map((n) => '${_appLabel(n['app'] ?? '')} from ${n['title']}: ${n['text']}')
        .join('. ');
    return 'You have ${msgs.length} message${msgs.length != 1 ? 's' : ''}. $body';
  }

  static String _appLabel(String pkg) {
    if (pkg.contains('whatsapp')) return 'WhatsApp';
    if (pkg.contains('gm') || pkg.contains('gmail')) return 'Gmail';
    if (pkg.contains('telegram')) return 'Telegram';
    if (pkg.contains('instagram')) return 'Instagram';
    if (pkg.contains('binance')) return 'Binance';
    final parts = pkg.split('.');
    return parts.isNotEmpty ? parts.last : pkg;
  }
}

@pragma('vm:entry-point')
void _onNotification(NotificationEvent evt) {
  // Required entry point; storage happens in the receivePort listener above.
}