import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:another_telephony/telephony.dart';
import 'package:http/http.dart' as http;
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server/gmail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

/// A scheduled reminder that messages a person on the day-before and/or on the
/// day — automatically over SMS / Email / Telegram, and one-tap for WhatsApp.
class MessageTask {
  final String id;
  final String name;
  final String phone; // country code + number, digits only (for SMS/WhatsApp)
  final String email;
  final String telegramChatId;
  final String message;
  final DateTime due;
  final Set<String> channels; // sms, whatsapp, email, telegram
  final bool dayBefore;
  final bool onDay;
  final int fireHour; // hour of day (0-23) to fire
  List<int> alarmIds;

  MessageTask({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.telegramChatId,
    required this.message,
    required this.due,
    required this.channels,
    required this.dayBefore,
    required this.onDay,
    required this.fireHour,
    this.alarmIds = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'email': email,
        'telegram': telegramChatId,
        'message': message,
        'due': due.toIso8601String(),
        'channels': channels.toList(),
        'dayBefore': dayBefore,
        'onDay': onDay,
        'fireHour': fireHour,
        'alarmIds': alarmIds,
      };

  factory MessageTask.fromJson(Map<String, dynamic> j) => MessageTask(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        phone: j['phone'] ?? '',
        email: j['email'] ?? '',
        telegramChatId: j['telegram'] ?? '',
        message: j['message'] ?? '',
        due: DateTime.tryParse(j['due'] ?? '') ?? DateTime.now(),
        channels: ((j['channels'] as List?) ?? []).map((e) => '$e').toSet(),
        dayBefore: j['dayBefore'] ?? true,
        onDay: j['onDay'] ?? true,
        fireHour: j['fireHour'] ?? 9,
        alarmIds:
            ((j['alarmIds'] as List?) ?? []).map((e) => e as int).toList(),
      );
}

/// Storage + scheduling for the Message Agent. Fires exact background alarms
/// (survive app-close and reboot) that run [messageAlarmCallback].
class MessageStore {
  static final ValueNotifier<List<MessageTask>> tasks =
      ValueNotifier<List<MessageTask>>([]);

  // prefs keys for the shared agent settings
  static const kGmailUser = 'agent_gmail_user';
  static const kGmailPass = 'agent_gmail_pass';
  static const kTgToken = 'agent_tg_token';

  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('msg_tasks');
    if (raw != null) {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      tasks.value = list.map(MessageTask.fromJson).toList();
    }
  }

  static Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        'msg_tasks', jsonEncode(tasks.value.map((t) => t.toJson()).toList()));
  }

  static int _nextAlarmId(SharedPreferences p) {
    final n = (p.getInt('agent_alarm_seq') ?? 900000) + 1;
    p.setInt('agent_alarm_seq', n);
    return n;
  }

  /// Add a task and schedule its fires. Returns how many fires were scheduled.
  static Future<int> add(MessageTask t) async {
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final fires = <(int, DateTime)>[]; // (kind: 0 on-day / 1 day-before, when)
    if (t.onDay) {
      fires.add((0, DateTime(t.due.year, t.due.month, t.due.day, t.fireHour)));
    }
    if (t.dayBefore) {
      final d = t.due.subtract(const Duration(days: 1));
      fires.add((1, DateTime(d.year, d.month, d.day, t.fireHour)));
    }
    final ids = <int>[];
    for (final f in fires) {
      if (f.$2.isBefore(now)) continue; // don't schedule past fires
      final aid = _nextAlarmId(p);
      await p.setString('fire_$aid', jsonEncode({
        'name': t.name,
        'phone': t.phone,
        'email': t.email,
        'telegram': t.telegramChatId,
        'message': t.message,
        'channels': t.channels.toList(),
        'kind': f.$1,
        'gmailUser': p.getString(kGmailUser) ?? '',
        'gmailPass': p.getString(kGmailPass) ?? '',
        'tgToken': p.getString(kTgToken) ?? '',
      }));
      await AndroidAlarmManager.oneShotAt(
        f.$2,
        aid,
        messageAlarmCallback,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
        alarmClock: true,
      );
      ids.add(aid);
    }
    t.alarmIds = ids;
    tasks.value = [t, ...tasks.value];
    await _persist();
    return ids.length;
  }

  static Future<void> remove(String id) async {
    final p = await SharedPreferences.getInstance();
    final t = tasks.value.where((x) => x.id == id).firstOrNull;
    if (t != null) {
      for (final aid in t.alarmIds) {
        await AndroidAlarmManager.cancel(aid);
        await p.remove('fire_$aid');
      }
    }
    tasks.value = tasks.value.where((x) => x.id != id).toList();
    await _persist();
  }

  /// Fire everything for a task right now (the "Send test" button).
  static Future<void> sendNow(MessageTask t) async {
    await _dispatch({
      'name': t.name,
      'phone': t.phone,
      'email': t.email,
      'telegram': t.telegramChatId,
      'message': t.message,
      'channels': t.channels.toList(),
      'kind': 0,
      'gmailUser': (await SharedPreferences.getInstance()).getString(kGmailUser) ?? '',
      'gmailPass': (await SharedPreferences.getInstance()).getString(kGmailPass) ?? '',
      'tgToken': (await SharedPreferences.getInstance()).getString(kTgToken) ?? '',
    });
  }

  /// The actual multi-channel send. Shared by the alarm callback and test send.
  static Future<List<String>> _dispatch(Map<String, dynamic> m) async {
    final channels = ((m['channels'] as List?) ?? []).map((e) => '$e').toList();
    final name = '${m['name']}';
    final phone = '${m['phone']}';
    final message = '${m['message']}';
    final done = <String>[];

    // ---- SMS (fully automatic) ----
    if (channels.contains('sms') && phone.isNotEmpty) {
      try {
        await Telephony.backgroundInstance.sendSms(to: phone, message: message);
        done.add('SMS');
      } catch (_) {}
    }

    // ---- Email (fully automatic, on-device SMTP) ----
    final email = '${m['email']}';
    final gu = '${m['gmailUser']}';
    final gp = '${m['gmailPass']}';
    if (channels.contains('email') &&
        email.isNotEmpty &&
        gu.isNotEmpty &&
        gp.isNotEmpty) {
      try {
        final msg = Message()
          ..from = Address(gu, 'Elder Wand')
          ..recipients.add(email)
          ..subject = 'A reminder from Elder Wand'
          ..text = message;
        await send(msg, gmail(gu, gp));
        done.add('Email');
      } catch (_) {}
    }

    // ---- Telegram (fully automatic, free Bot API) ----
    final tg = '${m['telegram']}';
    final tk = '${m['tgToken']}';
    if (channels.contains('telegram') && tg.isNotEmpty && tk.isNotEmpty) {
      try {
        await http.get(Uri.parse(
            'https://api.telegram.org/bot$tk/sendMessage?chat_id=$tg&text=${Uri.encodeComponent(message)}'));
        done.add('Telegram');
      } catch (_) {}
    }

    // ---- WhatsApp (one-tap: a notification that opens the chat pre-filled) ----
    if (channels.contains('whatsapp') && phone.isNotEmpty) {
      await NotificationService.showTap(
        'Message $name on WhatsApp',
        message,
        'https://wa.me/$phone?text=${Uri.encodeComponent(message)}',
      );
      done.add('WhatsApp (tap)');
    }

    // ---- reminder to the user ----
    final kind = m['kind'] == 1 ? 'Tomorrow' : 'Today';
    await NotificationService.show(
      'Reminder · $name',
      '$kind: $message'
          '${done.isEmpty ? '' : '\n\nSent via ${done.join(', ')}.'}',
    );
    return done;
  }
}

/// Background alarm entry point — runs in its own isolate at the scheduled time,
/// even if the app is closed. Reads the self-contained fire record and sends.
@pragma('vm:entry-point')
Future<void> messageAlarmCallback(int alarmId) async {
  WidgetsFlutterBinding.ensureInitialized();
  final p = await SharedPreferences.getInstance();
  final raw = p.getString('fire_$alarmId');
  if (raw == null) return;
  try {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    await MessageStore._dispatch(m);
  } catch (_) {}
  await p.remove('fire_$alarmId');
}
