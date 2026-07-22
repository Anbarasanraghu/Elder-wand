import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Tiny JSON cache in shared_preferences so screens can show their last-known
/// data with no backend / Wi-Fi. Each screen caches on a successful fetch and
/// falls back to the cache when the network fails.
class LocalCache {
  static Future<void> save(String key, Object data) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('cache_$key', jsonEncode(data));
  }

  static Future<dynamic> load(String key) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('cache_$key');
    if (s == null) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }
}
