import 'package:flutter/foundation.dart';

import 'crm_config.dart';

/// CRM data access against Supabase (Postgres). The app talks to the database
/// directly — no custom always-on server. See supabase/crm_schema.sql.
class Lead {
  final String id;
  final String name;
  final String company;
  final String phone;
  final String email;
  final String website;
  final String source;
  final String stage;
  final num value;
  final String notes;
  final String address;
  final String category;
  final String demoUrl;

  Lead({
    required this.id,
    required this.name,
    this.company = '',
    this.phone = '',
    this.email = '',
    this.website = '',
    this.source = '',
    this.stage = 'new',
    this.value = 0,
    this.notes = '',
    this.address = '',
    this.category = '',
    this.demoUrl = '',
  });

  factory Lead.fromMap(Map<String, dynamic> m) => Lead(
        id: '${m['id']}',
        name: '${m['name'] ?? ''}',
        company: '${m['company'] ?? ''}',
        phone: '${m['phone'] ?? ''}',
        email: '${m['email'] ?? ''}',
        website: '${m['website'] ?? ''}',
        source: '${m['source'] ?? ''}',
        stage: '${m['stage'] ?? 'new'}',
        value: (m['value'] as num?) ?? 0,
        notes: '${m['notes'] ?? ''}',
        address: '${m['address'] ?? ''}',
        category: '${m['category'] ?? ''}',
        demoUrl: '${m['demo_url'] ?? ''}',
      );
}

class CrmService {
  static const stages = [
    'new', 'contacted', 'qualified', 'proposal', 'won', 'lost'
  ];

  static dynamic get _db => CrmConfig.client;

  static Future<List<Lead>> leads({String? stage}) async {
    try {
      var q = _db.from('leads').select();
      if (stage != null) q = q.eq('stage', stage);
      final rows = await q.order('updated_at', ascending: false);
      debugPrint('[CRM] leads(stage=$stage) -> ${(rows as List).length} rows');
      return rows
          .map((e) => Lead.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[CRM] leads(stage=$stage) ERROR: $e');
      rethrow;
    }
  }

  static Future<Map<String, int>> stageCounts() async {
    final rows = await _db.from('leads').select('stage');
    final counts = {for (final s in stages) s: 0};
    for (final r in rows as List) {
      final s = '${r['stage']}';
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  static Future<void> addLead({
    required String name,
    String company = '',
    String phone = '',
    String email = '',
    String website = '',
    String source = '',
    num value = 0,
    String stage = 'new',
    String notes = '',
  }) async {
    await _db.from('leads').insert({
      'name': name,
      'company': company,
      'phone': phone,
      'email': email,
      'website': website,
      'source': source,
      'value': value,
      'stage': stage,
      'notes': notes,
    });
  }

  static Future<void> setStage(String id, String stage) async {
    await _db.from('leads').update({'stage': stage}).eq('id', id);
  }

  static Future<void> setDemoUrl(String id, String url) async {
    await _db.from('leads').update({'demo_url': url}).eq('id', id);
  }

  static Future<void> deleteLead(String id) async {
    await _db.from('leads').delete().eq('id', id);
  }

  // ---- activities ----
  static Future<List<Map<String, dynamic>>> activities(String leadId) async {
    final rows = await _db
        .from('activities')
        .select()
        .eq('lead_id', leadId)
        .order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  static Future<void> addActivity(
      String leadId, String kind, String body) async {
    await _db
        .from('activities')
        .insert({'lead_id': leadId, 'kind': kind, 'body': body});
  }

  // ---- follow-ups ----
  static Future<List<Map<String, dynamic>>> followups(String leadId) async {
    final rows = await _db
        .from('followups')
        .select()
        .eq('lead_id', leadId)
        .order('due_at', ascending: true);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  static Future<void> addFollowup(
      String leadId, DateTime dueAt, String note) async {
    await _db.from('followups').insert({
      'lead_id': leadId,
      'due_at': dueAt.toIso8601String(),
      'note': note,
    });
  }

  static Future<void> setFollowupDone(String id, bool done) async {
    await _db.from('followups').update({'done': done}).eq('id', id);
  }
}
