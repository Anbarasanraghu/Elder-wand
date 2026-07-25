import 'crm_config.dart';

/// Drives the Lead Agent: creates a run, streams its live logs (Supabase
/// Realtime), and invokes the Edge Function that does the scraping/validation.
class LeadAgentService {
  static dynamic get _db => CrmConfig.client;

  /// Create a run row and return its id (so we can stream its logs).
  static Future<String> createRun(String search, String area, int target) async {
    final res = await _db
        .from('scrape_runs')
        .insert({
          'search': search,
          'area': area,
          'target': target,
          'status': 'queued',
        })
        .select('id')
        .single();
    return '${res['id']}';
  }

  /// Live log lines for a run (ordered). Streams via Realtime.
  static Stream<List<Map<String, dynamic>>> logStream(String runId) {
    return _db
        .from('scrape_logs')
        .stream(primaryKey: ['id'])
        .eq('run_id', runId)
        .order('id') as Stream<List<Map<String, dynamic>>>;
  }

  /// Live status/summary for a run.
  static Stream<List<Map<String, dynamic>>> runStream(String runId) {
    return _db
        .from('scrape_runs')
        .stream(primaryKey: ['id'])
        .eq('id', runId) as Stream<List<Map<String, dynamic>>>;
  }

  /// Kick off the agent. Resolves when it finishes (logs stream meanwhile).
  static Future<Map<String, dynamic>> run(
      String runId, String search, String area, int target) async {
    final res = await _db.functions.invoke('lead-agent', body: {
      'run_id': runId,
      'search': search,
      'area': area,
      'target': target,
    });
    final data = res.data;
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }
}
