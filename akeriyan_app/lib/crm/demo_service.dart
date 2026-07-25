import 'package:shared_preferences/shared_preferences.dart';

import 'crm_config.dart';
import 'crm_service.dart';
import 'demo_builder.dart';

/// Thrown when no demo host (Cloudflare worker URL) is configured yet.
class DemoHostNotSet implements Exception {}

/// Generates a demo site, stores the HTML in the `demos` table, and builds a
/// shareable link that RENDERS. Supabase force-serves HTML as text/plain, so
/// the link points at a Cloudflare worker (see cloudflare/demo-worker.js) that
/// re-serves it as text/html.
class DemoService {
  static const _kHost = 'demo_host';

  static Future<String?> host() async {
    final p = await SharedPreferences.getInstance();
    final h = (p.getString(_kHost) ?? '').trim();
    return h.isEmpty ? null : h;
  }

  static Future<void> setHost(String h) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kHost, h.trim());
  }

  static Future<String> generate(Lead l) async {
    final html = DemoBuilder.build(l);
    await CrmConfig.client.from('demos').upsert({
      'id': l.id,
      'html': html,
      'updated_at': DateTime.now().toIso8601String(),
    });
    final h = await host();
    if (h == null) throw DemoHostNotSet();
    final base = h.replaceAll(RegExp(r'[?].*$'), '').replaceAll(RegExp(r'/+$'), '');
    final url = '$base?id=${l.id}';
    await CrmService.setDemoUrl(l.id, url);
    return url;
  }
}
