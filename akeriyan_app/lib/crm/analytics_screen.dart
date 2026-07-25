import 'package:flutter/material.dart';

import '../theme.dart';
import 'analytics_service.dart';
import 'crm_service.dart';

const _stageLabels = {
  'new': 'New',
  'contacted': 'Contacted',
  'qualified': 'Qualified',
  'proposal': 'Proposal',
  'won': 'Won',
  'lost': 'Lost',
};

/// Pipeline analytics over the CRM: KPIs, a funnel and lead sources.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Analytics? _a;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final a = await AnalyticsService.load();
      setState(() => _a = a);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Analytics error: $e')));
      }
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    return Scaffold(
      backgroundColor: Ak.bg0,
      appBar: AppBar(
        backgroundColor: Ak.bg0,
        elevation: 0,
        title: const Text('Analytics',
            style: TextStyle(fontFamily: Ak.dot, letterSpacing: 2)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: Ak.silver),
              onPressed: _load),
        ],
      ),
      body: _loading || a == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _kpi('Total leads', '${a.total}', Icons.groups_outlined),
                    _kpi('Conversion',
                        '${(a.conversion * 100).toStringAsFixed(0)}%',
                        Icons.trending_up),
                    _kpi('Pipeline', '₹${_k(a.pipelineValue)}',
                        Icons.savings_outlined),
                    _kpi('Won value', '₹${_k(a.wonValue)}',
                        Icons.emoji_events_outlined),
                    _kpi('Follow-ups due', '${a.followupsDue}',
                        Icons.notifications_active_outlined,
                        alert: a.followupsDue > 0),
                    _kpi('Activity · 7d', '${a.activityWeek}',
                        Icons.bolt_outlined),
                  ],
                ),
                const SizedBox(height: 24),
                _label('PIPELINE FUNNEL'),
                const SizedBox(height: 10),
                _funnel(a),
                const SizedBox(height: 24),
                if (a.bySource.isNotEmpty) ...[
                  _label('LEADS BY SOURCE'),
                  const SizedBox(height: 10),
                  _sources(a),
                ],
              ],
            ),
    );
  }

  static String _k(num v) => v >= 100000
      ? '${(v / 100000).toStringAsFixed(1)}L'
      : v >= 1000
          ? '${(v / 1000).toStringAsFixed(1)}k'
          : v.toStringAsFixed(0);

  Widget _kpi(String label, String value, IconData icon, {bool alert = false}) {
    final w = (MediaQuery.of(context).size.width - 32 - 24) / 3;
    return Container(
      width: w,
      padding: const EdgeInsets.all(13),
      decoration: Ak.bento(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: alert ? Ak.pink : Ak.purple),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                  color: alert ? Ak.pink : Ak.textHi,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(color: Ak.textLo, fontSize: 10.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _funnel(Analytics a) {
    final maxC = a.stageCounts.values.fold<int>(1, (m, v) => v > m ? v : m);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: Ak.bento(radius: 16),
      child: Column(
        children: [
          for (final s in CrmService.stages)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 78,
                    child: Text(_stageLabels[s]!,
                        style: TextStyle(color: Ak.textMid, fontSize: 12)),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Container(
                          height: 22,
                          decoration: BoxDecoration(
                              color: Ak.glassFill,
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        FractionallySizedBox(
                          widthFactor: (a.stageCounts[s] ?? 0) / maxC,
                          child: Container(
                            height: 22,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              gradient: LinearGradient(colors: [
                                s == 'won'
                                    ? Ak.up
                                    : s == 'lost'
                                        ? Ak.down
                                        : Ak.purple,
                                (s == 'won'
                                        ? Ak.up
                                        : s == 'lost'
                                            ? Ak.down
                                            : Ak.purple)
                                    .withValues(alpha: 0.6),
                              ]),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 26,
                    child: Text('${a.stageCounts[s] ?? 0}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: Ak.textHi, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sources(Analytics a) {
    final entries = a.bySource.entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: Ak.bento(radius: 16),
      child: Column(
        children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                      child: Text(e.key,
                          style: const TextStyle(color: Ak.textHi))),
                  Text('${e.value}',
                      style: TextStyle(
                          color: Ak.purple, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: TextStyle(
          color: Ak.textLo,
          fontSize: 11,
          letterSpacing: 2,
          fontWeight: FontWeight.w700));
}
