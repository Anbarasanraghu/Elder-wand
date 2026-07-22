import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'tts_service.dart';
import 'documents.dart';
import 'local_cache.dart';
import 'theme.dart';
import 'widgets/nothing_loader.dart';

/// Business CRM — leads & clients for the IT agency: pipeline, follow-ups,
/// analytics dashboard and AI assistance (extract, score, outreach, insights).
class CrmScreen extends StatefulWidget {
  final String backendUrl;
  final String token;
  const CrmScreen({super.key, required this.backendUrl, required this.token});

  @override
  State<CrmScreen> createState() => _CrmScreenState();
}

const _stages = ['new', 'contacted', 'proposal', 'negotiation', 'won', 'lost'];

String _money(num v) {
  if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(v % 100000 == 0 ? 0 : 1)}L';
  if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(0)}K';
  return '₹${v.toStringAsFixed(0)}';
}

Color _stageColor(String s) {
  switch (s) {
    case 'won':
      return Ak.up;
    case 'lost':
      return Ak.down;
    case 'negotiation':
    case 'proposal':
      return Ak.purple;
    default:
      return Ak.textMid;
  }
}

Color _scoreColor(String s) =>
    s == 'hot' ? Ak.down : (s == 'cold' ? Ak.textMid : Ak.purple);

class _CrmScreenState extends State<CrmScreen> {
  late final Dio _dio = Dio(BaseOptions(
    baseUrl: '${widget.backendUrl}/v1/crm',
    headers: {'Authorization': 'Bearer ${widget.token}'},
    receiveTimeout: const Duration(minutes: 3),
  ));

  int _tab = 0;
  Map<String, dynamic>? _stats;
  List<dynamic> _leads = [];
  String _filter = 'all';
  bool _loading = true;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final a = await _dio.get('/analytics');
      final l = await _dio.get('/leads');
      final stats = Map<String, dynamic>.from(a.data);
      final leads = l.data['leads'] as List;
      setState(() {
        _stats = stats;
        _leads = leads;
        _offline = false;
      });
      LocalCache.save('crm', {'stats': stats, 'leads': leads});
    } catch (_) {
      final cached = await LocalCache.load('crm');
      if (cached is Map) {
        setState(() {
          _stats = cached['stats'] is Map
              ? Map<String, dynamic>.from(cached['stats'])
              : null;
          _leads = (cached['leads'] as List?) ?? [];
          _offline = true;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<dynamic> get _shown =>
      _filter == 'all' ? _leads : _leads.where((l) => l['stage'] == _filter).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('CRM'),
          if (_offline) ...[
            const SizedBox(width: 8),
            const Icon(Icons.cloud_off, color: Ak.textLo, size: 16),
            const SizedBox(width: 4),
            const Text('offline',
                style: TextStyle(color: Ak.textLo, fontSize: 11)),
          ],
        ]),
        actions: [
          IconButton(
            tooltip: 'AI insights',
            icon: const Icon(Icons.auto_awesome, color: Ak.purple),
            onPressed: _insights,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Ak.textMid),
            onPressed: _refresh,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Ak.purple,
        icon: const Icon(Icons.add, color: Ak.bg0),
        label: const Text('Lead', style: TextStyle(color: Ak.bg0)),
        onPressed: _addLeadSheet,
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: Ak.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              _tabBar(),
              Expanded(
                child: _loading
                    ? const NothingLoader(label: 'Loading pipeline…')
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        color: Ak.purple,
                        backgroundColor: Ak.bg2,
                        child: _tab == 0 ? _dashboard() : _pipeline(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          _tabBtn('Dashboard', 0),
          const SizedBox(width: 10),
          _tabBtn('Pipeline', 1),
        ],
      ),
    );
  }

  Widget _tabBtn(String label, int i) {
    final on = _tab == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = i),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: on ? Ak.goldGradient : null,
            color: on ? null : Ak.glassFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? Colors.transparent : Ak.glassLine),
          ),
          child: Text(label,
              style: TextStyle(
                  color: on ? Ak.bg0 : Ak.textMid,
                  fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  // ---------- DASHBOARD ----------
  Widget _dashboard() {
    final s = _stats;
    if (s == null) return const SizedBox();
    final byStage = Map<String, dynamic>.from(s['by_stage'] ?? {});
    final bySource = Map<String, dynamic>.from(s['by_source'] ?? {});
    final overdue = (s['overdue_followups'] as List?) ?? [];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      children: [
        Row(children: [
          _stat('Leads', '${s['total']}', Ak.purple),
          const SizedBox(width: 12),
          _stat('Pipeline', _money(s['pipeline_value'] ?? 0), Ak.textHi),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _stat('Won', _money(s['won_revenue'] ?? 0), Ak.up),
          const SizedBox(width: 12),
          _stat('Conversion', '${s['conversion_pct']}%', Ak.purpleSoft),
        ]),
        const SizedBox(height: 20),
        _sectionTitle('By stage'),
        ..._stages.map((st) => _stageBar(st, (byStage[st] ?? 0) as int, s['total'] ?? 0)),
        const SizedBox(height: 20),
        if (bySource.isNotEmpty) ...[
          _sectionTitle('By source'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: bySource.entries
                .map((e) => Chip(
                      label: Text('${e.key}: ${e.value}',
                          style: const TextStyle(color: Ak.textHi, fontSize: 12)),
                      backgroundColor: Ak.glassFill,
                      side: const BorderSide(color: Ak.glassLine),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),
        ],
        if (overdue.isNotEmpty) ...[
          _sectionTitle('⚠ Overdue follow-ups'),
          ...overdue.map((o) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: Ak.glass(),
                child: Row(children: [
                  const Icon(Icons.schedule, color: Ak.down, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text('${o['company']} — ${o['name']}',
                          style: const TextStyle(color: Ak.textHi))),
                ]),
              )),
        ],
      ],
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: Ak.glass(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Ak.textLo, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 24, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  Widget _stageBar(String stage, int count, int total) {
    final frac = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        SizedBox(
            width: 92,
            child: Text(stage,
                style: const TextStyle(color: Ak.textMid, fontSize: 13))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 10,
              backgroundColor: Ak.glassFillStrong,
              color: _stageColor(stage),
            ),
          ),
        ),
        SizedBox(
            width: 28,
            child: Text('  $count',
                style: const TextStyle(color: Ak.textHi, fontSize: 13))),
      ]),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(t, style: Ak.display(size: 14, color: Ak.textMid)),
      );

  // ---------- PIPELINE ----------
  Widget _pipeline() {
    return Column(children: [
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: ['all', ..._stages].map((f) {
            final on = _filter == f;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(f),
                selected: on,
                onSelected: (_) => setState(() => _filter = f),
                labelStyle:
                    TextStyle(color: on ? Ak.bg0 : Ak.textMid, fontSize: 12),
                selectedColor: Ak.purple,
                backgroundColor: Ak.glassFill,
                side: const BorderSide(color: Ak.glassLine),
              ),
            );
          }).toList(),
        ),
      ),
      Expanded(
        child: _shown.isEmpty
            ? Center(
                child: Text('No leads here.\nTap + to add one.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Ak.textLo)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: _shown.length,
                itemBuilder: (_, i) => _leadCard(_shown[i]),
              ),
      ),
    ]);
  }

  Widget _leadCard(Map lead) {
    return GestureDetector(
      onTap: () => _leadDetail(lead),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: Ak.glass(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                  (lead['company'] as String?)?.isNotEmpty == true
                      ? lead['company']
                      : (lead['name'] ?? 'Lead'),
                  style: const TextStyle(
                      color: Ak.textHi,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: _scoreColor(lead['score'] ?? 'warm'),
                  shape: BoxShape.circle),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
              '${lead['name'] ?? ''}${(lead['service'] ?? '').isNotEmpty ? ' · ${lead['service']}' : ''}',
              style: const TextStyle(color: Ak.textLo, fontSize: 12)),
          const SizedBox(height: 8),
          Row(children: [
            _pill(lead['stage'] ?? 'new', _stageColor(lead['stage'] ?? 'new')),
            const Spacer(),
            if ((lead['value'] ?? 0) > 0)
              Text(_money(lead['value'] ?? 0),
                  style: const TextStyle(
                      color: Ak.textHi, fontWeight: FontWeight.w700)),
          ]),
        ]),
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
            color: color.withAlpha(38),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withAlpha(120))),
        child: Text(text, style: TextStyle(color: color, fontSize: 11)),
      );

  // ---------- ADD LEAD ----------
  void _addLeadSheet() {
    final name = TextEditingController();
    final company = TextEditingController();
    final phone = TextEditingController();
    final service = TextEditingController();
    final value = TextEditingController();
    final source = TextEditingController();
    final paste = TextEditingController();
    final bulk = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Ak.bg1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Add lead', style: Ak.display(size: 18)),
            const SizedBox(height: 14),
            _tf(company, 'Company'),
            _tf(name, 'Contact name'),
            _tf(phone, 'Phone'),
            Row(children: [
              Expanded(child: _tf(service, 'Service (website/app/automation)')),
              const SizedBox(width: 10),
              Expanded(child: _tf(value, 'Value ₹', number: true)),
            ]),
            _tf(source, 'Source (referral/linkedin/website…)'),
            const SizedBox(height: 8),
            _sheetBtn('Save lead', () async {
              await _dio.post('/leads', data: {
                'name': name.text,
                'company': company.text,
                'phone': phone.text,
                'service': service.text,
                'value': double.tryParse(value.text) ?? 0,
                'source': source.text,
              });
              if (ctx.mounted) Navigator.pop(ctx);
              _refresh();
            }),
            const Divider(color: Ak.glassLine, height: 28),
            _tf(paste, 'Paste an inquiry/email → AI fills the lead',
                lines: 3),
            _sheetBtn('AI extract & save', () async {
              if (paste.text.trim().isEmpty) return;
              final ex = await _dio.post('/extract', data: {'text': paste.text});
              await _dio.post('/leads', data: ex.data);
              if (ctx.mounted) Navigator.pop(ctx);
              _refresh();
            }, filled: false),
            const Divider(color: Ak.glassLine, height: 28),
            _tf(bulk, 'Bulk paste: company, service, value, source (one per line)',
                lines: 3),
            _sheetBtn('Import all', () async {
              if (bulk.text.trim().isEmpty) return;
              await _dio.post('/import', data: {'text': bulk.text});
              if (ctx.mounted) Navigator.pop(ctx);
              _refresh();
            }, filled: false),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  // ---------- LEAD DETAIL ----------
  void _leadDetail(Map lead) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Ak.bg1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> patch(Map<String, dynamic> body) async {
            final r = await _dio.patch('/leads/${lead['id']}', data: body);
            setSheet(() => lead.addAll(Map<String, dynamic>.from(r.data)));
            _refresh();
          }

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                left: 16,
                right: 16,
                top: 16),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(
                      child: Text(lead['company'] ?? lead['name'] ?? 'Lead',
                          style: Ak.display(size: 18))),
                  _pill(lead['score'] ?? 'warm',
                      _scoreColor(lead['score'] ?? 'warm')),
                ]),
                const SizedBox(height: 4),
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        '${lead['name'] ?? ''} · ${lead['phone'] ?? ''}',
                        style: const TextStyle(color: Ak.textLo))),
                const SizedBox(height: 14),
                // Stage selector
                Wrap(
                  spacing: 6,
                  children: _stages
                      .map((st) => ChoiceChip(
                            label: Text(st, style: const TextStyle(fontSize: 11)),
                            selected: lead['stage'] == st,
                            onSelected: (_) => patch({'stage': st}),
                            selectedColor: _stageColor(st),
                            backgroundColor: Ak.glassFill,
                            labelStyle: TextStyle(
                                color: lead['stage'] == st
                                    ? Ak.bg0
                                    : Ak.textMid),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                      child: _sheetBtn('AI score', () async {
                    final r =
                        await _dio.post('/leads/${lead['id']}/score');
                    setSheet(() => lead['score'] = r.data['score']);
                    _refresh();
                  }, filled: false)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _sheetBtn('AI outreach', () async {
                    final r = await _dio.post(
                        '/leads/${lead['id']}/outreach',
                        queryParameters: {'channel': 'whatsapp'});
                    _showOutreach(r.data['message'] ?? '');
                  })),
                ]),
                const SizedBox(height: 10),
                _sheetBtn('📄 Proposal PDF', () async {
                  final r = await _dio.post('/leads/${lead['id']}/proposal');
                  await Documents.shareProposal(
                      Map<String, dynamic>.from(r.data));
                }, filled: false),
                const SizedBox(height: 10),
                _sheetBtn('🚀 Start project (mark won)', () async {
                  await _dio.post(
                      '${widget.backendUrl}/v1/projects/from_lead/${lead['id']}');
                  setSheet(() => lead['stage'] = 'won');
                  _refresh();
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content: Text('Project created from lead'),
                        backgroundColor: Ak.bg2));
                  }
                }),
                const SizedBox(height: 10),
                _sheetBtn('Delete lead', () async {
                  await _dio.delete('/leads/${lead['id']}');
                  if (ctx.mounted) Navigator.pop(ctx);
                  _refresh();
                }, filled: false, danger: true),
                const SizedBox(height: 12),
              ]),
            ),
          );
        },
      ),
    );
  }

  void _showOutreach(String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Ak.bg2,
        title: Text('Outreach draft', style: Ak.display(size: 16)),
        content: Text(msg, style: const TextStyle(color: Ak.textHi)),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: msg));
              Navigator.pop(context);
            },
            child: const Text('Copy', style: TextStyle(color: Ak.purple)),
          ),
        ],
      ),
    );
  }

  Future<void> _insights() async {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const NothingLoader(label: 'Analyzing pipeline…'));
    try {
      final r = await _dio.get('/insights');
      final text = r.data['speak'] as String? ?? '';
      if (mounted) Navigator.pop(context);
      TtsService.speak(text);
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: Ak.bg2,
            title: Text('Pipeline insights', style: Ak.display(size: 16)),
            content: Text(text, style: const TextStyle(color: Ak.textHi)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close',
                      style: TextStyle(color: Ak.purple)))
            ],
          ),
        );
      }
    } catch (_) {
      if (mounted) Navigator.pop(context);
    }
  }

  Widget _tf(TextEditingController c, String label,
      {bool number = false, int lines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: lines,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        style: const TextStyle(color: Ak.textHi),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Ak.textLo, fontSize: 13),
          filled: true,
          fillColor: Ak.glassFill,
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Ak.glassLine)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Ak.purple)),
        ),
      ),
    );
  }

  Widget _sheetBtn(String label, Future<void> Function() onTap,
      {bool filled = true, bool danger = false}) {
    return GestureDetector(
      onTap: () async {
        try {
          await onTap();
        } catch (_) {}
      },
      child: Container(
        height: 48,
        margin: const EdgeInsets.only(top: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: filled ? Ak.goldGradient : null,
          color: filled ? null : Ak.glassFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: danger ? Ak.down : (filled ? Colors.transparent : Ak.glassLine)),
        ),
        child: Text(label,
            style: TextStyle(
                color: danger ? Ak.down : (filled ? Ak.bg0 : Ak.textHi),
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}
