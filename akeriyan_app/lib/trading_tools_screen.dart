import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'local_cache.dart';
import 'trading_screen.dart';
import 'theme.dart';
import 'widgets/nothing_loader.dart';

/// Trading tools: Watchlist (live prices), Portfolio (holdings + value), and a
/// Trade Journal (entries + P&L). All stored locally (offline-friendly);
/// live prices come from the backend /v1/market/price endpoint.
class TradingToolsScreen extends StatefulWidget {
  final String backendUrl;
  final String token;
  const TradingToolsScreen(
      {super.key, required this.backendUrl, required this.token});

  @override
  State<TradingToolsScreen> createState() => _TradingToolsScreenState();
}

class _TradingToolsScreenState extends State<TradingToolsScreen> {
  late final Dio _dio = Dio(BaseOptions(
    baseUrl: '${widget.backendUrl}/v1/market',
    headers: {'Authorization': 'Bearer ${widget.token}'},
    receiveTimeout: const Duration(seconds: 20),
  ));

  int _tab = 0;
  List<String> _watch = [];
  List<Map<String, dynamic>> _holdings = [];
  List<Map<String, dynamic>> _trades = [];
  final Map<String, Map<String, dynamic>> _prices = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _watch = ((await LocalCache.load('watchlist') as List?) ?? [])
        .map((e) => '$e')
        .toList();
    _holdings = ((await LocalCache.load('portfolio') as List?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    _trades = ((await LocalCache.load('journal') as List?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    setState(() => _loading = false);
    _loadPrices();
  }

  Future<void> _loadPrices() async {
    final syms = {..._watch, ..._holdings.map((h) => '${h['symbol']}')};
    for (final s in syms) {
      try {
        final r = await _dio.get('/price', queryParameters: {'symbol': s});
        if (r.data['ok'] == true) {
          _prices[s] = Map<String, dynamic>.from(r.data);
          if (mounted) setState(() {});
        }
      } catch (_) {}
    }
  }

  Future<void> _saveWatch() => LocalCache.save('watchlist', _watch);
  Future<void> _saveHoldings() => LocalCache.save('portfolio', _holdings);
  Future<void> _saveTrades() => LocalCache.save('journal', _trades);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TRADING TOOLS')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Ak.purple,
        child: const Icon(Icons.add, color: Ak.bg0),
        onPressed: () => [_addWatch, _addHolding, _addTrade][_tab](),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: Ak.bgGradient),
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                _tabBtn('Watchlist', 0),
                const SizedBox(width: 8),
                _tabBtn('Portfolio', 1),
                const SizedBox(width: 8),
                _tabBtn('Journal', 2),
              ]),
            ),
            Expanded(
              child: _loading
                  ? const NothingLoader(label: 'Loading…')
                  : [_watchlist(), _portfolio(), _journal()][_tab],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tabBtn(String label, int i) {
    final on = _tab == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = i),
        child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: on ? Ak.goldGradient : null,
            color: on ? null : Ak.glassFill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? Colors.transparent : Ak.glassLine),
          ),
          child: Text(label,
              style: TextStyle(
                  color: on ? Ak.bg0 : Ak.textMid, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  // ---------- WATCHLIST ----------
  Widget _watchlist() {
    if (_watch.isEmpty) return _empty('No symbols.\nTap + to add one.');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
      children: _watch.map((s) {
        final p = _prices[s];
        final up = ((p?['change_pc'] ?? 0) as num) >= 0;
        return GestureDetector(
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => TradingScreen(
                      backendUrl: widget.backendUrl,
                      token: widget.token,
                      initialSymbol: s))),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: Ak.glass(),
            child: Row(children: [
              Expanded(
                  child: Text((p?['base'] ?? s).toString().toUpperCase(),
                      style: const TextStyle(
                          color: Ak.textHi,
                          fontSize: 16,
                          fontWeight: FontWeight.w700))),
              if (p != null) ...[
                Text('\$${p['price']}',
                    style: const TextStyle(color: Ak.textHi)),
                const SizedBox(width: 10),
                Text('${up ? '▲' : '▼'} ${(p['change_pc'] as num).abs()}%',
                    style: TextStyle(color: up ? Ak.up : Ak.down, fontSize: 12)),
              ] else
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Ak.textLo)),
              IconButton(
                icon: const Icon(Icons.close, color: Ak.textLo, size: 18),
                onPressed: () {
                  setState(() => _watch.remove(s));
                  _saveWatch();
                },
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }

  void _addWatch() => _prompt('Add symbol (bitcoin, ethereum…)', (v) {
        if (v.isEmpty || _watch.contains(v)) return;
        setState(() => _watch.add(v));
        _saveWatch();
        _loadPrices();
      });

  // ---------- PORTFOLIO ----------
  Widget _portfolio() {
    if (_holdings.isEmpty) return _empty('No holdings.\nTap + to add one.');
    double total = 0;
    for (final h in _holdings) {
      final p = _prices['${h['symbol']}'];
      if (p != null) total += ((h['qty'] as num) * (p['price'] as num));
    }
    return Column(children: [
      Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.all(16),
        decoration: Ak.glass(),
        child: Column(children: [
          const Text('Portfolio value',
              style: TextStyle(color: Ak.textLo, fontSize: 12)),
          const SizedBox(height: 4),
          Text('\$${total.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: Ak.purple, fontSize: 26, fontWeight: FontWeight.w800)),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
          children: _holdings.asMap().entries.map((e) {
            final h = e.value;
            final p = _prices['${h['symbol']}'];
            final val = p != null ? (h['qty'] as num) * (p['price'] as num) : null;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: Ak.glass(),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${h['symbol']}'.toUpperCase(),
                            style: const TextStyle(
                                color: Ak.textHi,
                                fontWeight: FontWeight.w700)),
                        Text('${h['qty']} units',
                            style: const TextStyle(
                                color: Ak.textLo, fontSize: 12)),
                      ]),
                ),
                if (val != null)
                  Text('\$${val.toStringAsFixed(2)}',
                      style: const TextStyle(color: Ak.textHi)),
                IconButton(
                  icon: const Icon(Icons.close, color: Ak.textLo, size: 18),
                  onPressed: () {
                    setState(() => _holdings.removeAt(e.key));
                    _saveHoldings();
                  },
                ),
              ]),
            );
          }).toList(),
        ),
      ),
    ]);
  }

  void _addHolding() {
    final sym = TextEditingController();
    final qty = TextEditingController();
    _dialog('Add holding', [
      _field(sym, 'Symbol (bitcoin…)'),
      _field(qty, 'Quantity', number: true),
    ], () {
      if (sym.text.trim().isEmpty) return;
      setState(() => _holdings.add({
            'symbol': sym.text.trim().toLowerCase(),
            'qty': double.tryParse(qty.text) ?? 0,
          }));
      _saveHoldings();
      _loadPrices();
    });
  }

  // ---------- JOURNAL ----------
  double _pnl(Map t) {
    final entry = (t['entry'] as num?)?.toDouble() ?? 0;
    final exit = (t['exit'] as num?)?.toDouble() ?? 0;
    if (entry == 0) return 0;
    return t['side'] == 'short'
        ? (entry - exit) / entry * 100
        : (exit - entry) / entry * 100;
  }

  Widget _journal() {
    if (_trades.isEmpty) return _empty('No trades logged.\nTap + to add one.');
    final wins = _trades.where((t) => _pnl(t) > 0).length;
    final avg = _trades.map(_pnl).fold<double>(0, (a, b) => a + b);
    return Column(children: [
      Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.all(14),
        decoration: Ak.glass(),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _stat('Trades', '${_trades.length}', Ak.textHi),
          _stat('Win rate',
              '${(_trades.isEmpty ? 0 : wins / _trades.length * 100).round()}%',
              Ak.purple),
          _stat('Total P&L', '${avg >= 0 ? '+' : ''}${avg.toStringAsFixed(1)}%',
              avg >= 0 ? Ak.up : Ak.down),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
          children: _trades.asMap().entries.map((e) {
            final t = e.value;
            final pnl = _pnl(t);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: Ak.glass(),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${'${t['symbol']}'.toUpperCase()}  ${(t['side'] ?? 'long').toString().toUpperCase()}',
                            style: const TextStyle(
                                color: Ak.textHi,
                                fontWeight: FontWeight.w700)),
                        Text('${t['entry']} → ${t['exit']}',
                            style: const TextStyle(
                                color: Ak.textLo, fontSize: 12)),
                      ]),
                ),
                Text('${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(1)}%',
                    style: TextStyle(
                        color: pnl >= 0 ? Ak.up : Ak.down,
                        fontWeight: FontWeight.w700)),
                IconButton(
                  icon: const Icon(Icons.close, color: Ak.textLo, size: 18),
                  onPressed: () {
                    setState(() => _trades.removeAt(e.key));
                    _saveTrades();
                  },
                ),
              ]),
            );
          }).toList(),
        ),
      ),
    ]);
  }

  void _addTrade() {
    final sym = TextEditingController();
    final entry = TextEditingController();
    final exit = TextEditingController();
    String side = 'long';
    _dialog('Log trade', [
      _field(sym, 'Symbol'),
      StatefulBuilder(
        builder: (ctx, set) => Row(children: [
          for (final s in ['long', 'short'])
            Expanded(
              child: GestureDetector(
                onTap: () => set(() => side = s),
                child: Container(
                  margin: const EdgeInsets.all(3),
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: side == s ? Ak.purple : Ak.glassFill,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Ak.glassLine)),
                  child: Text(s,
                      style: TextStyle(
                          color: side == s ? Ak.bg0 : Ak.textMid)),
                ),
              ),
            ),
        ]),
      ),
      Row(children: [
        Expanded(child: _field(entry, 'Entry', number: true)),
        const SizedBox(width: 8),
        Expanded(child: _field(exit, 'Exit', number: true)),
      ]),
    ], () {
      if (sym.text.trim().isEmpty) return;
      setState(() => _trades.insert(0, {
            'symbol': sym.text.trim().toLowerCase(),
            'side': side,
            'entry': double.tryParse(entry.text) ?? 0,
            'exit': double.tryParse(exit.text) ?? 0,
            'at': DateTime.now().toIso8601String(),
          }));
      _saveTrades();
    });
  }

  // ---------- shared ----------
  Widget _empty(String t) => Center(
      child: Text(t,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Ak.textLo)));

  Widget _stat(String k, String v, Color c) => Column(children: [
        Text(k, style: const TextStyle(color: Ak.textLo, fontSize: 11)),
        const SizedBox(height: 4),
        Text(v,
            style:
                TextStyle(color: c, fontSize: 18, fontWeight: FontWeight.w800)),
      ]);

  Widget _field(TextEditingController c, String label, {bool number = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          style: const TextStyle(color: Ak.textHi),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Ak.textLo, fontSize: 12),
            filled: true,
            fillColor: Ak.glassFill,
            isDense: true,
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Ak.glassLine)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Ak.purple)),
          ),
        ),
      );

  void _prompt(String label, void Function(String) onOk) {
    final c = TextEditingController();
    _dialog(label, [_field(c, label)], () => onOk(c.text.trim().toLowerCase()));
  }

  void _dialog(String title, List<Widget> children, VoidCallback onOk) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Ak.bg2,
        title: Text(title, style: Ak.display(size: 16)),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: children)),
        actions: [
          TextButton(
            onPressed: () {
              onOk();
              Navigator.pop(ctx);
            },
            child: const Text('Add', style: TextStyle(color: Ak.purple)),
          ),
        ],
      ),
    );
  }
}
