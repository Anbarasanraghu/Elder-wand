import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Holds the Supabase connection for the cloud CRM. The user pastes their free
/// project URL + anon key once (Explore → CRM → Connect). Nothing runs on a PC.
class CrmConfig {
  static const _kUrl = 'sb_url';
  static const _kKey = 'sb_key';

  static String url = '';
  static String key = '';
  static bool _inited = false;

  static bool get isConfigured => url.isNotEmpty && key.isNotEmpty;
  static bool get isReady => _inited;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    url = p.getString(_kUrl) ?? '';
    key = p.getString(_kKey) ?? '';
  }

  static Future<void> save(String u, String k) async {
    final p = await SharedPreferences.getInstance();
    url = u.trim();
    key = k.trim();
    await p.setString(_kUrl, url);
    await p.setString(_kKey, key);
  }

  /// Initialise Supabase if configured. Safe to call once at startup and again
  /// after the user connects. Returns true when the client is ready.
  static Future<bool> init() async {
    if (_inited) return true;
    if (!isConfigured) await load();
    if (!isConfigured) return false;
    try {
      // ignore: deprecated_member_use — "anon key" is what the dashboard shows
      await Supabase.initialize(url: url, anonKey: key);
      _inited = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  static SupabaseClient get client => Supabase.instance.client;
}
