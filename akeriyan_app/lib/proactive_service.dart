import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';
import 'location_service.dart';
import 'on_device_skills.dart';

/// Proactive assistant — checks in on you without being asked. While the
/// foreground service keeps the app alive (for the wake word), a light timer
/// delivers a daily morning briefing and warns you when the battery gets low.
/// All checks are throttled so you're never spammed.
class ProactiveService {
  static Timer? _timer;
  static bool _running = false;

  // ---- prefs keys / defaults ----
  static const kBriefOn = 'proact_brief_on';
  static const kBriefHour = 'proact_brief_hour';
  static const kBriefMin = 'proact_brief_min';
  static const kBattOn = 'proact_batt_on';
  static const _kBriefDone = 'proact_brief_done';
  static const _kBattAt = 'proact_batt_at';

  static Future<void> start() async {
    if (_running) return;
    _running = true;
    // A 3-minute cadence is plenty for a daily briefing + battery watch and is
    // gentle on power. It runs for as long as the app process is alive.
    _timer = Timer.periodic(const Duration(minutes: 3), (_) => _tick());
    await _tick();
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  static Future<void> _tick() async {
    try {
      final p = await SharedPreferences.getInstance();
      await _checkBattery(p);
      await _checkBriefing(p);
    } catch (_) {}
  }

  static Future<void> _checkBattery(SharedPreferences p) async {
    if (!(p.getBool(kBattOn) ?? true)) return;
    final battery = Battery();
    final level = await battery.batteryLevel;
    final state = await battery.batteryState;
    if (level > 15 || state == BatteryState.charging) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = p.getInt(_kBattAt) ?? 0;
    if (now - last < const Duration(hours: 2).inMilliseconds) return; // throttle
    await p.setInt(_kBattAt, now);
    await NotificationService.show(
      'Battery low — $level%',
      "You're down to $level% and not charging. Might be a good time to plug in.",
    );
  }

  static Future<void> _checkBriefing(SharedPreferences p) async {
    if (!(p.getBool(kBriefOn) ?? true)) return;
    final hour = p.getInt(kBriefHour) ?? 8;
    final min = p.getInt(kBriefMin) ?? 0;
    final now = DateTime.now();
    // Fire once per day, in the minute the briefing time arrives (the 3-min
    // cadence means we catch it within a few minutes if the exact minute is
    // missed — hence the small window).
    if (now.hour != hour || now.minute < min || now.minute > min + 4) return;
    final today = '${now.year}-${now.month}-${now.day}';
    if (p.getString(_kBriefDone) == today) return;
    await p.setString(_kBriefDone, today);
    await deliverBriefing();
  }

  /// Build and push the briefing now (also used by the "Test" button).
  static Future<void> deliverBriefing() async {
    String body;
    try {
      final pos = await LocationService.current();
      final weather = await OnDeviceSkills.weather(
          lat: pos?.latitude, lon: pos?.longitude);
      final news = await OnDeviceSkills.news(limit: 3);
      body = '$weather\n\n$news';
    } catch (_) {
      body = "Good morning! I couldn't reach weather or news right now.";
    }
    await NotificationService.show('Good morning ☀️', body);
  }
}
