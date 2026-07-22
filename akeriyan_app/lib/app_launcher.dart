import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';

class AppLauncher {
  static List<AppInfo>? _cache;

  // Direct package names for popular apps — instant and reliable.
  static const Map<String, String> _knownApps = {
    'youtube': 'com.google.android.youtube',
    'chrome': 'com.android.chrome',
    'gmail': 'com.google.android.gm',
    'maps': 'com.google.android.apps.maps',
    'googlemaps': 'com.google.android.apps.maps',
    'photos': 'com.google.android.apps.photos',
    'playstore': 'com.android.vending',
    'whatsapp': 'com.whatsapp',
    'telegram': 'org.telegram.messenger',
    'instagram': 'com.instagram.android',
    'facebook': 'com.facebook.katana',
    'binance': 'com.binance.dev',
    'tradingview': 'com.tradingview.tradingviewapp',
    'settings': 'com.android.settings',
    'calculator': 'com.google.android.calculator',
    'camera': 'com.android.camera',
    'calendar': 'com.google.android.calendar',
    'calender': 'com.google.android.calendar', // common Whisper misspelling
    'clock': 'com.google.android.deskclock',
    'files': 'com.google.android.documentsui',
    'contacts': 'com.google.android.contacts',
    'messages': 'com.google.android.apps.messaging',
    'phone': 'com.google.android.dialer',
    'drive': 'com.google.android.apps.docs',
    'meet': 'com.google.android.apps.tachyon',
    'mx player': 'com.mxtech.videoplayer.ad',
  };

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static Future<String?> openByName(String spokenName) async {
    final q = _norm(spokenName);
    if (q.isEmpty) return null;

    // 1. Known apps: launch directly by package name.
    final knownPkg = _knownApps[q];
    if (knownPkg != null) {
      try {
        await InstalledApps.startApp(knownPkg);
        return spokenName;
      } catch (_) {
        // not installed or launch failed -> fall through to search
      }
    }

    // 2. Search the installed-app list (including system apps).
    try {
      _cache ??= await InstalledApps.getInstalledApps();
    } catch (_) {
      return null;
    }

    AppInfo? exact;
    AppInfo? partial;
    for (final app in _cache!) {
      final name = _norm(app.name);
      if (name == q) {
        exact = app;
        break;
      }
      if (partial == null && (name.contains(q) || q.contains(name))) {
        partial = app;
      }
    }

    final best = exact ?? partial;
    if (best == null) return null;
    await InstalledApps.startApp(best.packageName);
    return best.name;
  }
}