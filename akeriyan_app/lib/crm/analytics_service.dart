import 'crm_config.dart';
import 'crm_service.dart';

class Analytics {
  final int total;
  final Map<String, int> stageCounts;
  final double conversion; // won / total
  final num pipelineValue; // open (not won/lost) value
  final num wonValue;
  final int followupsDue; // not done, due today or overdue
  final int activityWeek; // activities in last 7 days
  final Map<String, int> bySource;

  Analytics({
    required this.total,
    required this.stageCounts,
    required this.conversion,
    required this.pipelineValue,
    required this.wonValue,
    required this.followupsDue,
    required this.activityWeek,
    required this.bySource,
  });
}

class AnalyticsService {
  static dynamic get _db => CrmConfig.client;

  static Future<Analytics> load() async {
    final leads = (await _db.from('leads').select('stage,value,source')) as List;
    final counts = {for (final s in CrmService.stages) s: 0};
    num pipeline = 0, wonValue = 0;
    final bySource = <String, int>{};
    for (final r in leads) {
      final s = '${r['stage']}';
      counts[s] = (counts[s] ?? 0) + 1;
      final v = (r['value'] as num?) ?? 0;
      if (s == 'won') {
        wonValue += v;
      } else if (s != 'lost') {
        pipeline += v;
      }
      var src = '${r['source'] ?? ''}'.split('·').first.trim();
      if (src.isEmpty) src = 'Manual';
      bySource[src] = (bySource[src] ?? 0) + 1;
    }
    final total = leads.length;
    final won = counts['won'] ?? 0;
    final conversion = total > 0 ? won / total : 0.0;

    // follow-ups due (not done, due by end of today)
    final fups = (await _db
        .from('followups')
        .select('due_at,done')
        .eq('done', false)) as List;
    final endToday = DateTime.now().add(const Duration(days: 1));
    final due = fups.where((f) {
      final d = DateTime.tryParse('${f['due_at']}');
      return d != null && d.isBefore(endToday);
    }).length;

    // activities in the last 7 days
    final weekAgo =
        DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
    final acts =
        (await _db.from('activities').select('id').gte('created_at', weekAgo))
            as List;

    return Analytics(
      total: total,
      stageCounts: counts,
      conversion: conversion,
      pipelineValue: pipeline,
      wonValue: wonValue,
      followupsDue: due,
      activityWeek: acts.length,
      bySource: bySource,
    );
  }
}
