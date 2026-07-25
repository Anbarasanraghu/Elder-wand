import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'crm_config.dart';
import 'crm_service.dart';
import 'demo_builder.dart';

/// Generates a demo site for a lead, hosts it free on Supabase Storage, and
/// saves the public link back on the lead. Returns the shareable URL.
class DemoService {
  static Future<String> generate(Lead l) async {
    final html = DemoBuilder.build(l);
    final path = 'lead-${l.id}.html';
    final bytes = Uint8List.fromList(utf8.encode(html));
    final storage = CrmConfig.client.storage.from('demos');
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(contentType: 'text/html', upsert: true),
    );
    // cache-bust so a re-generate shows the latest
    final url =
        '${storage.getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
    await CrmService.setDemoUrl(l.id, url);
    return url;
  }
}
