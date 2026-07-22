import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'theme.dart';
import 'widgets/nothing_loader.dart';
import 'trading_screen.dart' show Candle;
import 'pro_screen.dart';

/// Multi-timeframe scalping analysis — bias, order blocks, support/resistance
/// and a 1-minute entry setup, drawn on a 15-minute candle chart.
class ScalpScreen extends StatefulWidget {
  final String backendUrl;
  final String token;
  final String initialSymbol;

  const ScalpScreen({
    super.key,
    required this.backendUrl,
    required this.token,
    this.initialSymbol = 'bitcoin',
  });

  @override
  State<ScalpScreen> createState() => _ScalpScreenState();
}

class _ScalpScreenState extends State<ScalpScreen> {
  final _dio = Dio();
  final _ctrl = TextEditingController();
  String _symbol = 'bitcoin';
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _d;

  static const _quick = ['BTC', 'ETH', 'SOL', 'GOLD', 'EURUSD', 'USDINR'];

  @override
  void initState() {
    super.initState();
    _symbol = widget.initialSymbol;
    _ctrl.text = _symbol;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _dio.get('${widget.backendUrl}/v1/market/scalp',
          queryParameters: {'symbol': _symbol},
          options:
              Options(headers: {'Authorization': 'Bearer ${widget.token}'}));
      final d = Map<String, dynamic>.from(res.data);
      if (d['ok'] != true) {
        setState(() {
          _error = (d['speak'] as String?) ?? 'No setup for "$_symbol".';
          _loading = false;
        });
        return;
      }
      setState(() {
        _d = d;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not reach the scalp service.\n$e';
        _loading = false;
      });
    }
  }

  Color _biasColor(String b) => b == 'bullish'
      ? Ak.up
      : (b == 'bearish' ? Ak.down : Ak.textLo);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(_d == null ? 'SCALP' : 'SCALP · ${_d!['base']}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.insights, color: Ak.gold),
            tooltip: 'Pro terminal',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProScreen(
                  backendUrl: widget.backendUrl,
                  token: widget.token,
                  initialSymbol: _symbol,
                ),
              ),
            ),
          ),
          IconButton(
              icon: const Icon(Icons.refresh, color: Ak.textMid),
              onPressed: _load),
          const SizedBox(width: 6),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: Ak.bgGradient),
        child: SafeArea(
          child: _loading
              ? const NothingLoader(label: 'Reading the setup…')
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Ak.textMid)),
                      ),
                    )
                  : _content(),
        ),
      ),
    );
  }

  Widget _content() {
    final d = _d!;
    final tfs = Map<String, dynamic>.from(d['timeframes'] ?? {});
    final bias = (d['bias'] as String?) ?? 'neutral';
    final candles = (d['candles'] as List)
        .map((c) => Candle((c['o'] as num).toDouble(), (c['h'] as num).toDouble(),
            (c['l'] as num).toDouble(), (c['c'] as num).toDouble()))
        .toList();
    final supports =
        (d['supports'] as List).map((e) => (e as num).toDouble()).toList();
    final resistances =
        (d['resistances'] as List).map((e) => (e as num).toDouble()).toList();
    final obs = Map<String, dynamic>.from(d['order_blocks'] ?? {});
    final setup = d['setup'] as Map?;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _symbolBar(),
          const SizedBox(height: 14),
          // Bias banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _biasColor(bias)),
              color: Ak.glassFill,
            ),
            child: Column(
              children: [
                const Text('OVERALL BIAS',
                    style: TextStyle(
                        color: Ak.textLo, fontSize: 11, letterSpacing: 3)),
                const SizedBox(height: 4),
                Text(bias.toUpperCase(),
                    style: TextStyle(
                        color: _biasColor(bias),
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Timeframe row
          Row(
            children: [
              for (final tf in ['4h', '1h', '15m', '1m'])
                Expanded(child: _tfChip(tf, (tfs[tf] as String?) ?? '—')),
            ],
          ),
          const SizedBox(height: 16),
          // Chart with overlays
          Container(
            padding: const EdgeInsets.all(10),
            decoration: Ak.glass(),
            child: AspectRatio(
              aspectRatio: 1.25,
              child: CustomPaint(
                painter: ScalpChartPainter(
                  candles: candles,
                  supports: supports,
                  resistances: resistances,
                  bullOB: obs['bullish'] as Map?,
                  bearOB: obs['bearish'] as Map?,
                  setup: setup,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _legend(),
          const SizedBox(height: 16),
          if (setup != null) _setupCard(setup) else _noSetupCard(),
          const SizedBox(height: 14),
          _levelsCard(supports, resistances),
          const SizedBox(height: 14),
          // Spoken analysis
          Container(
            padding: const EdgeInsets.all(14),
            decoration: Ak.glass(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome, color: Ak.gold, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text((d['speak'] as String?) ?? '',
                      style: const TextStyle(
                          color: Ak.textHi, fontSize: 14, height: 1.45)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text('Educational analysis only — not financial advice.',
                style: TextStyle(color: Ak.textLo, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _symbolBar() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                style: const TextStyle(color: Ak.textHi),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Symbol (bitcoin, gold, EURUSD…)',
                  hintStyle: const TextStyle(color: Ak.textLo),
                  filled: true,
                  fillColor: Ak.glassFill,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Ak.glassLine),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Ak.gold),
                  ),
                ),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) _symbol = v.trim();
                  _load();
                },
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
                onPressed: () {
                  if (_ctrl.text.trim().isNotEmpty) _symbol = _ctrl.text.trim();
                  _load();
                },
                child: const Text('Scan')),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final s in _quick)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(s),
                    onPressed: () {
                      _symbol = s;
                      _ctrl.text = s;
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tfChip(String tf, String trend) {
    final c = _biasColor(trend);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: Ak.glass(radius: 14),
      child: Column(
        children: [
          Text(tf,
              style: const TextStyle(color: Ak.textLo, fontSize: 12)),
          const SizedBox(height: 4),
          Icon(
              trend == 'bullish'
                  ? Icons.trending_up
                  : trend == 'bearish'
                      ? Icons.trending_down
                      : Icons.trending_flat,
              color: c,
              size: 20),
          const SizedBox(height: 2),
          Text(trend, style: TextStyle(color: c, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _setupCard(Map s) {
    final long = s['direction'] == 'long';
    final color = long ? Ak.up : Ak.down;
    final entry = (s['entry'] as List).map((e) => (e as num).toDouble()).toList();
    String f(num n) => n >= 1000
        ? n.toStringAsFixed(0)
        : (n >= 1 ? n.toStringAsFixed(2) : n.toStringAsFixed(5));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color),
        color: Ak.glassFill,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(long ? Icons.north_east : Icons.south_east, color: color),
              const SizedBox(width: 8),
              Text('${long ? 'LONG' : 'SHORT'} SETUP',
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Ak.glassFillStrong,
                    borderRadius: BorderRadius.circular(20)),
                child: Text('${s['rr']} R',
                    style: const TextStyle(
                        color: Ak.gold, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _row('Entry zone', '${f(entry[0])} – ${f(entry[1])}', Ak.gold),
          _row('Stop loss', f(s['stop'] as num), Ak.down),
          _row('Target', f(s['target'] as num), Ak.up),
        ],
      ),
    );
  }

  Widget _noSetupCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: Ak.glass(),
      child: const Row(
        children: [
          Icon(Icons.hourglass_empty, color: Ak.textLo),
          SizedBox(width: 10),
          Expanded(
            child: Text(
                'No clean setup right now — the timeframes disagree. '
                'Wait for alignment before scalping.',
                style: TextStyle(color: Ak.textMid, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Ak.textLo)),
          const Spacer(),
          Text(value,
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _levelsCard(List<double> sup, List<double> res) {
    String f(double n) => n >= 1000
        ? n.toStringAsFixed(0)
        : (n >= 1 ? n.toStringAsFixed(2) : n.toStringAsFixed(5));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: Ak.glass(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('KEY LEVELS',
              style: TextStyle(
                  color: Ak.textLo, fontSize: 11, letterSpacing: 2)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Resistance',
                        style: TextStyle(color: Ak.down, fontSize: 12)),
                    const SizedBox(height: 4),
                    if (res.isEmpty)
                      const Text('—', style: TextStyle(color: Ak.textLo))
                    else
                      for (final r in res.take(3))
                        Text(f(r),
                            style: const TextStyle(color: Ak.textHi)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Support',
                        style: TextStyle(color: Ak.up, fontSize: 12)),
                    const SizedBox(height: 4),
                    if (sup.isEmpty)
                      const Text('—', style: TextStyle(color: Ak.textLo))
                    else
                      for (final s in sup.take(3))
                        Text(f(s),
                            style: const TextStyle(color: Ak.textHi)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        children: [
          _Lg(color: Ak.up, label: 'Support'),
          _Lg(color: Ak.down, label: 'Resistance'),
          _Lg(color: Ak.cyan, label: 'Order block'),
          _Lg(color: Ak.gold, label: 'Entry / Stop / Target'),
        ],
      ),
    );
  }
}

class _Lg extends StatelessWidget {
  final Color color;
  final String label;
  const _Lg({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 12, height: 3, color: color),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Ak.textLo, fontSize: 11)),
        ],
      );
}

class ScalpChartPainter extends CustomPainter {
  final List<Candle> candles;
  final List<double> supports, resistances;
  final Map? bullOB, bearOB;
  final Map? setup;
  final List<double> bsl; // buy-side liquidity (targets above)
  final List<double> ssl; // sell-side liquidity (targets below)

  ScalpChartPainter({
    required this.candles,
    required this.supports,
    required this.resistances,
    required this.bullOB,
    required this.bearOB,
    required this.setup,
    this.bsl = const [],
    this.ssl = const [],
  });

  double? _n(dynamic v) => v == null ? null : (v as num).toDouble();

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    double hi = candles.first.high, lo = candles.first.low;
    for (final c in candles) {
      if (c.high > hi) hi = c.high;
      if (c.low < lo) lo = c.low;
    }
    // Include overlay prices so nothing is clipped off-screen.
    final extra = <double>[
      ...supports,
      ...resistances,
      ...bsl,
      ...ssl,
      if (setup != null) ...[
        _n((setup!['stop'])) ?? hi,
        _n((setup!['target'])) ?? lo,
      ],
    ];
    for (final v in extra) {
      if (v > hi) hi = v;
      if (v < lo) lo = v;
    }
    final range = (hi - lo).abs() < 1e-9 ? 1.0 : (hi - lo);
    hi += range * 0.05;
    lo -= range * 0.05;
    double y(double p) => size.height - ((p - lo) / (hi - lo)) * size.height;

    // Grid
    final grid = Paint()
      ..color = Ak.glassLine
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final gy = size.height * i / 4;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }

    // Order-block zones (translucent bands across the chart)
    void band(Map? ob, Color c) {
      if (ob == null) return;
      final zlo = _n(ob['lo']), zhi = _n(ob['hi']);
      if (zlo == null || zhi == null) return;
      final rect = Rect.fromLTRB(0, y(zhi), size.width, y(zlo));
      canvas.drawRect(rect, Paint()..color = c.withAlpha(28));
    }

    band(bullOB, Ak.up);
    band(bearOB, Ak.down);

    // Entry zone band (gold)
    if (setup != null && setup!['entry'] is List) {
      final e = (setup!['entry'] as List).map((x) => (x as num).toDouble()).toList();
      final rect = Rect.fromLTRB(0, y(e[1]), size.width, y(e[0]));
      canvas.drawRect(rect, Paint()..color = Ak.gold.withAlpha(30));
    }

    // Candles
    final n = candles.length;
    final slot = size.width / n;
    final bodyW = (slot * 0.6).clamp(1.0, 10.0);
    for (var i = 0; i < n; i++) {
      final c = candles[i];
      final cx = slot * i + slot / 2;
      final bull = c.close >= c.open;
      final p = Paint()
        ..color = bull ? Ak.up : Ak.down
        ..strokeWidth = 1;
      canvas.drawLine(Offset(cx, y(c.high)), Offset(cx, y(c.low)), p);
      final top = y(bull ? c.close : c.open);
      final bot = y(bull ? c.open : c.close);
      canvas.drawRect(
          Rect.fromLTRB(cx - bodyW / 2, top, cx + bodyW / 2,
              bot == top ? top + 1 : bot),
          p);
    }

    // Horizontal level lines with price labels
    void hline(double price, Color c, {bool dashed = true}) {
      final py = y(price);
      final paint = Paint()
        ..color = c
        ..strokeWidth = 1.2;
      if (dashed) {
        const dash = 6.0, gap = 4.0;
        double x = 0;
        while (x < size.width) {
          canvas.drawLine(Offset(x, py), Offset(x + dash, py), paint);
          x += dash + gap;
        }
      } else {
        canvas.drawLine(Offset(0, py), Offset(size.width, py), paint);
      }
      final tp = TextPainter(
        text: TextSpan(
            text: price >= 1000
                ? price.toStringAsFixed(0)
                : (price >= 1 ? price.toStringAsFixed(2) : price.toStringAsFixed(5)),
            style: TextStyle(color: c, fontSize: 9)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - tp.width - 2, py - 11));
    }

    for (final s in supports.take(3)) {
      hline(s, Ak.up);
    }
    for (final r in resistances.take(3)) {
      hline(r, Ak.down);
    }
    // Liquidity pools (where stops rest) — cyan above, violet below.
    for (final b in bsl.take(2)) {
      hline(b, Ak.cyan);
    }
    for (final s in ssl.take(2)) {
      hline(s, Ak.violet);
    }
    if (setup != null) {
      final st = _n(setup!['stop']);
      final tg = _n(setup!['target']);
      if (st != null) hline(st, Ak.down, dashed: false);
      if (tg != null) hline(tg, Ak.up, dashed: false);
    }
  }

  @override
  bool shouldRepaint(covariant ScalpChartPainter old) =>
      old.candles != candles || old.setup != setup;
}
