import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'theme.dart';

/// Proactive alerts — price/RSI rules that push a notification when they fire,
/// plus a daily auto morning-briefing time.
class AlertsScreen extends StatefulWidget {
  final String backendUrl;
  final String token;
  const AlertsScreen(
      {super.key, required this.backendUrl, required this.token});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  late final Dio _dio = Dio(BaseOptions(
    baseUrl: '${widget.backendUrl}/v1/alerts',
    headers: {'Authorization': 'Bearer ${widget.token}'},
  ));

  List<dynamic> _rules = [];
  String _briefingTime = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final r = await _dio.get('');
      setState(() {
        _rules = r.data['rules'] as List;
        _briefingTime = (r.data['briefing_time'] as String?) ?? '';
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ALERTS')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Ak.purple,
        icon: const Icon(Icons.add_alert, color: Ak.bg0),
        label: const Text('Alert', style: TextStyle(color: Ak.bg0)),
        onPressed: _addRuleSheet,
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: Ak.bgGradient),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Ak.purple))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  children: [
                    _briefingCard(),
                    const SizedBox(height: 20),
                    Text('Price / RSI alerts',
                        style: Ak.display(size: 14, color: Ak.textMid)),
                    const SizedBox(height: 12),
                    if (_rules.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                            child: Text('No alerts yet. Tap + to add one.',
                                style: TextStyle(color: Ak.textLo))),
                      ),
                    ..._rules.map(_ruleCard),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _briefingCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: Ak.glass(),
      child: Row(children: [
        const Icon(Icons.wb_twilight, color: Ak.purple),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Morning briefing',
                style: TextStyle(color: Ak.textHi, fontWeight: FontWeight.w700)),
            Text(_briefingTime.isEmpty ? 'Off' : 'Every day at $_briefingTime',
                style: const TextStyle(color: Ak.textLo, fontSize: 12)),
          ]),
        ),
        if (_briefingTime.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close, color: Ak.textLo, size: 18),
            onPressed: () => _setBriefing(''),
          ),
        TextButton(
          onPressed: _pickBriefing,
          child: Text(_briefingTime.isEmpty ? 'Set' : 'Change',
              style: const TextStyle(color: Ak.purple)),
        ),
      ]),
    );
  }

  Future<void> _pickBriefing() async {
    final t = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 7, minute: 0),
    );
    if (t == null) return;
    final hhmm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    _setBriefing(hhmm);
  }

  Future<void> _setBriefing(String time) async {
    await _dio.post('/briefing_time', data: {'time': time});
    _refresh();
  }

  Widget _ruleCard(dynamic rule) {
    final sym = (rule['symbol'] as String).toUpperCase();
    final kind = rule['kind'] as String;
    final op = rule['op'] as String;
    final thr = rule['threshold'];
    final arrow = op == 'above' ? '▲' : '▼';
    final color = op == 'above' ? Ak.up : Ak.down;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: Ak.glass(),
      child: Row(children: [
        Text(arrow, style: TextStyle(color: color, fontSize: 18)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(sym,
                style: const TextStyle(
                    color: Ak.textHi, fontSize: 16, fontWeight: FontWeight.w700)),
            Text(
                '${kind == 'rsi' ? 'RSI' : 'Price'} $op ${thr is num ? (thr % 1 == 0 ? thr.toInt() : thr) : thr}'
                '${(rule['note'] ?? '').isNotEmpty ? ' · ${rule['note']}' : ''}',
                style: const TextStyle(color: Ak.textLo, fontSize: 12)),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Ak.down),
          onPressed: () async {
            await _dio.delete('/${rule['id']}');
            _refresh();
          },
        ),
      ]),
    );
  }

  void _addRuleSheet() {
    final symbol = TextEditingController();
    final threshold = TextEditingController();
    final note = TextEditingController();
    String kind = 'price';
    String op = 'above';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Ak.bg1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              left: 16,
              right: 16,
              top: 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('New alert', style: Ak.display(size: 18)),
            const SizedBox(height: 14),
            _tf(symbol, 'Symbol (bitcoin, gold, apple…)'),
            Row(children: [
              Expanded(
                  child: _seg(['price', 'rsi'], kind,
                      (v) => setSheet(() => kind = v))),
              const SizedBox(width: 10),
              Expanded(
                  child: _seg(['above', 'below'], op,
                      (v) => setSheet(() => op = v))),
            ]),
            const SizedBox(height: 10),
            _tf(threshold, kind == 'rsi' ? 'RSI level (e.g. 70)' : 'Price level',
                number: true),
            _tf(note, 'Note (optional)'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                if (symbol.text.trim().isEmpty ||
                    threshold.text.trim().isEmpty) {
                  return;
                }
                await _dio.post('', data: {
                  'symbol': symbol.text.trim(),
                  'kind': kind,
                  'op': op,
                  'threshold': double.tryParse(threshold.text) ?? 0,
                  'note': note.text.trim(),
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
                child: const Text('Create alert',
                    style: TextStyle(
                        color: Ak.bg0, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 12),
          ]),
        ),
      ),
    );
  }

  Widget _seg(List<String> opts, String value, ValueChanged<String> onPick) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
          color: Ak.glassFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Ak.glassLine)),
      child: Row(
        children: opts.map((o) {
          final on = o == value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onPick(o),
              child: Container(
                alignment: Alignment.center,
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                    color: on ? Ak.purple : Colors.transparent,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(o,
                    style: TextStyle(
                        color: on ? Ak.bg0 : Ak.textMid,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _tf(TextEditingController c, String label, {bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
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
}
