import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'local_cache.dart';
import 'theme.dart';
import 'widgets/nothing_loader.dart';

/// Project tracker — the build phase after a lead is won: milestones, status,
/// deadlines. Complements the CRM (lead -> client -> project -> delivered).
class ProjectsScreen extends StatefulWidget {
  final String backendUrl;
  final String token;
  const ProjectsScreen(
      {super.key, required this.backendUrl, required this.token});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

const _statuses = ['planning', 'in_progress', 'review', 'delivered', 'on_hold'];

Color _statusColor(String s) {
  switch (s) {
    case 'delivered':
      return Ak.up;
    case 'on_hold':
      return Ak.down;
    case 'in_progress':
    case 'review':
      return Ak.purple;
    default:
      return Ak.textMid;
  }
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  late final Dio _dio = Dio(BaseOptions(
    baseUrl: '${widget.backendUrl}/v1/projects',
    headers: {'Authorization': 'Bearer ${widget.token}'},
  ));

  List<dynamic> _projects = [];
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
      final r = await _dio.get('');
      final projects = r.data['projects'] as List;
      setState(() {
        _projects = projects;
        _offline = false;
      });
      LocalCache.save('projects', projects);
    } catch (_) {
      final cached = await LocalCache.load('projects');
      if (cached is List) {
        setState(() {
          _projects = cached;
          _offline = true;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _done(List ms) => ms.where((m) => m['done'] == true).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Row(children: [
        const Text('PROJECTS'),
        if (_offline) ...[
          const SizedBox(width: 8),
          const Icon(Icons.cloud_off, color: Ak.textLo, size: 16),
          const SizedBox(width: 4),
          const Text('offline',
              style: TextStyle(color: Ak.textLo, fontSize: 11)),
        ],
      ])),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Ak.purple,
        icon: const Icon(Icons.add, color: Ak.bg0),
        label: const Text('Project', style: TextStyle(color: Ak.bg0)),
        onPressed: _addSheet,
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: Ak.bgGradient),
        child: SafeArea(
          child: _loading
              ? const NothingLoader(label: 'Loading projects…')
              : _projects.isEmpty
                  ? const Center(
                      child: Text('No projects yet.\nWin a lead or tap +.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Ak.textLo)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                      itemCount: _projects.length,
                      itemBuilder: (_, i) => _card(_projects[i]),
                    ),
        ),
      ),
    );
  }

  Widget _card(Map p) {
    final ms = (p['milestones'] as List?) ?? [];
    final done = _done(ms);
    final frac = ms.isEmpty ? 0.0 : done / ms.length;
    return GestureDetector(
      onTap: () => _detail(p),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: Ak.glass(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(p['company']?.isNotEmpty == true ? p['company'] : (p['name'] ?? 'Project'),
                  style: const TextStyle(
                      color: Ak.textHi, fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                  color: _statusColor(p['status'] ?? '').withAlpha(38),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _statusColor(p['status'] ?? '').withAlpha(120))),
              child: Text((p['status'] ?? '').replaceAll('_', ' '),
                  style: TextStyle(
                      color: _statusColor(p['status'] ?? ''), fontSize: 11)),
            ),
          ]),
          const SizedBox(height: 4),
          Text('${p['service'] ?? ''}${(p['deadline'] ?? '').isNotEmpty ? ' · due ${p['deadline']}' : ''}',
              style: const TextStyle(color: Ak.textLo, fontSize: 12)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 8,
                  backgroundColor: Ak.glassFillStrong,
                  color: Ak.purple,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text('$done/${ms.length}',
                style: const TextStyle(color: Ak.textMid, fontSize: 12)),
          ]),
        ]),
      ),
    );
  }

  void _detail(Map p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Ak.bg1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final ms = List<Map<String, dynamic>>.from(
            (p['milestones'] as List).map((e) => Map<String, dynamic>.from(e)));

        Future<void> save() async {
          final r = await _dio.patch('/${p['id']}',
              data: {'milestones': ms, 'status': p['status']});
          setSheet(() => p.addAll(Map<String, dynamic>.from(r.data)));
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
              Text(p['company'] ?? p['name'] ?? 'Project',
                  style: Ak.display(size: 18)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: _statuses
                    .map((s) => ChoiceChip(
                          label: Text(s.replaceAll('_', ' '),
                              style: const TextStyle(fontSize: 11)),
                          selected: p['status'] == s,
                          onSelected: (_) {
                            p['status'] = s;
                            save();
                          },
                          selectedColor: _statusColor(s),
                          backgroundColor: Ak.glassFill,
                          labelStyle: TextStyle(
                              color: p['status'] == s ? Ak.bg0 : Ak.textMid),
                        ))
                    .toList(),
              ),
              const Divider(color: Ak.glassLine, height: 26),
              ...ms.asMap().entries.map((e) {
                final m = e.value;
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: Ak.purple,
                  checkColor: Ak.bg0,
                  title: Text(m['title'] ?? '',
                      style: TextStyle(
                          color: Ak.textHi,
                          decoration: m['done'] == true
                              ? TextDecoration.lineThrough
                              : null)),
                  value: m['done'] == true,
                  onChanged: (v) {
                    ms[e.key]['done'] = v ?? false;
                    save();
                  },
                );
              }),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  await _dio.delete('/${p['id']}');
                  if (ctx.mounted) Navigator.pop(ctx);
                  _refresh();
                },
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Ak.down)),
                  child: const Text('Delete project',
                      style: TextStyle(color: Ak.down)),
                ),
              ),
              const SizedBox(height: 12),
            ]),
          ),
        );
      }),
    );
  }

  void _addSheet() {
    final company = TextEditingController();
    final service = TextEditingController();
    final deadline = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Ak.bg1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('New project', style: Ak.display(size: 18)),
          const SizedBox(height: 14),
          _tf(company, 'Client / company'),
          _tf(service, 'Service (website/app/automation)'),
          _tf(deadline, 'Deadline (optional, e.g. 2026-08-15)'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              if (company.text.trim().isEmpty) return;
              await _dio.post('', data: {
                'company': company.text.trim(),
                'service': service.text.trim(),
                'deadline': deadline.text.trim(),
              });
              if (ctx.mounted) Navigator.pop(ctx);
              _refresh();
            },
            child: Container(
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  gradient: Ak.goldGradient,
                  borderRadius: BorderRadius.circular(12)),
              child: const Text('Create project',
                  style:
                      TextStyle(color: Ak.bg0, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Widget _tf(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
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
