import 'crm_config.dart';
import 'crm_service.dart';
import 'demo_builder.dart';

/// Generates a demo site for a lead, stores the HTML in the `demos` table, and
/// points the shareable link at the public `demo` Edge Function (which returns
/// text/html so it renders — Supabase Storage force-serves HTML as text/plain).
class DemoService {
  static Future<String> generate(Lead l) async {
    final html = DemoBuilder.build(l);
    await CrmConfig.client.from('demos').upsert({
      'id': l.id,
      'html': html,
      'updated_at': DateTime.now().toIso8601String(),
    });
    final base = CrmConfig.url.replaceAll(RegExp(r'/+$'), '');
    final url = '$base/functions/v1/demo?id=${l.id}';
    await CrmService.setDemoUrl(l.id, url);
    return url;
  }
}
