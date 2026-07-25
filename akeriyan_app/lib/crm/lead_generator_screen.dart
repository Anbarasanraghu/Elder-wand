import 'package:flutter/material.dart';

import '../theme.dart';
import 'lead_agent_service.dart';

/// Lead Agent — full-control lead generation with LIVE logs. You set the
/// niche + city, hit Run, and watch it scrape + validate in real time; new
/// leads land in the CRM.
class LeadGeneratorScreen extends StatefulWidget {
  const LeadGeneratorScreen({super.key});

  @override
  State<LeadGeneratorScreen> createState() => _LeadGeneratorScreenState();
}

class _LeadGeneratorScreenState extends State<LeadGeneratorScreen> {
  final _search = TextEditingController();
  final _area = TextEditingController(text: 'Chennai');
  double _target = 15;
  String? _runId;
  bool _running = false;
  String _summary = '';

  Color _levelColor(String level) {
    switch (level) {
      case 'ok':
        return Ak.green;
      case 'success':
        return Ak.purple;
      case 'error':
        return Ak.down;
      case 'warn':
        return Ak.amber;
      case 'dim':
        return Ak.textLo;
      default:
        return Ak.textMid;
    }
  }

  Future<void> _run() async {
    final s = _search.text.trim();
    final a = _area.text.trim();
    if (s.isEmpty || a.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a niche and a city.')));
      return;
    }
    setState(() {
      _running = true;
      _summary = '';
      _runId = null;
    });
    try {
      final runId = await LeadAgentService.createRun(s, a, _target.round());
      setState(() => _runId = runId); // starts the live log stream
      final res =
          await LeadAgentService.run(runId, s, a, _target.round());
      setState(() {
        _summary = res['ok'] == true
            ? 'Done — added ${res['added'] ?? 0} leads '
                '(${res['validated'] ?? 0} with valid email). Check the CRM.'
            : 'Error: ${res['error'] ?? 'unknown'}';
      });
    } catch (e) {
      setState(() => _summary = 'Error: $e');
    }
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ak.bg0,
      appBar: AppBar(
        backgroundColor: Ak.bg0,
        elevation: 0,
        title: const Text('Lead Agent',
            style: TextStyle(fontFamily: Ak.dot, letterSpacing: 2)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(flex: 3, child: _field(_search, 'Niche (dentist, gym…)')),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: _field(_area, 'City')),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('Target: ${_target.round()}',
                        style: TextStyle(color: Ak.textMid, fontSize: 13)),
                    Expanded(
                      child: Slider(
                        value: _target,
                        min: 5,
                        max: 50,
                        divisions: 9,
                        activeColor: Ak.purple,
                        onChanged: _running
                            ? null
                            : (v) => setState(() => _target = v),
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: Ak.purple,
                        padding: const EdgeInsets.symmetric(vertical: 13)),
                    onPressed: _running ? null : _run,
                    icon: _running
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Ak.bg0))
                        : const Icon(Icons.bolt, color: Ak.bg0),
                    label: Text(_running ? 'Running…' : 'Run agent',
                        style: const TextStyle(
                            color: Ak.bg0, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Ak.glassLine, height: 1),
          // ---- live log console ----
          Expanded(child: _console()),
          if (_summary.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              color: Ak.bg1,
              child: Text(_summary,
                  style: TextStyle(
                      color: _summary.startsWith('Error') ? Ak.down : Ak.green,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Widget _console() {
    if (_runId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            'Set a niche + city and hit Run.\nThe agent scrapes OpenStreetMap, '
            'validates contacts from their websites, skips duplicates, and '
            'streams every step here live. New leads land in your CRM.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Ak.textLo, height: 1.5),
          ),
        ),
      );
    }
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: LeadAgentService.logStream(_runId!),
      builder: (context, snap) {
        final logs = snap.data ?? const [];
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          itemCount: logs.length,
          itemBuilder: (context, i) {
            final l = logs[i];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${l['msg']}',
                style: TextStyle(
                  color: _levelColor('${l['level']}'),
                  fontSize: 12.5,
                  fontFamily: 'monospace',
                  height: 1.3,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _field(TextEditingController c, String hint) => TextField(
        controller: c,
        style: const TextStyle(color: Ak.textHi),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Ak.textLo, fontSize: 12),
          filled: true,
          fillColor: Ak.glassFill,
          isDense: true,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      );
}
