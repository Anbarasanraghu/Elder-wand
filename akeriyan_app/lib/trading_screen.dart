import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'theme.dart';
import 'widgets/nothing_loader.dart';
import 'scalp_screen.dart';
import 'live_agent_screen.dart';

/// Live crypto candlestick chart + AKERIYAN's analysis.
/// Data comes from the backend (free Binance public market data).
class TradingScreen extends StatefulWidget {
  final String backendUrl;
  final String token;
  final String initialSymbol; // spoken name or ticker, e.g. "bitcoin" / "BTC"
  final bool stock; // false = crypto (Binance), true = stock (Yahoo)

  const TradingScreen({
    super.key,
    required this.backendUrl,
    required this.token,
    this.initialSymbol = 'bitcoin',
    this.stock = false,
  });

  @override
  State<TradingScreen> createState() => _TradingScreenState();
}

class _TradingScreenState extends State<TradingScreen> {
  final _dio = Dio();
  final _symbolCtrl = TextEditingController();

  String _symbol = 'bitcoin';
  String _interval = '1h';
  bool _loading = true;
  bool _showEma = false;
  bool _showBb = false;
  String? _error;
  Map<String, dynamic>? _data;

  static const _quickCoins = ['BTC', 'ETH', 'SOL', 'BNB', 'XRP', 'DOGE'];
  static const _quickStocks = [
    'AAPL', 'TSLA', 'NVDA', 'INFY', 'NIFTY',
    'GOLD', 'SILVER', 'CRUDE', 'EURUSD', 'USDINR'
  ];
  static const _cryptoIntervals = ['1h', '4h', '1d', '1w'];
  static const _stockIntervals = ['1d', '1w', '1mo', '1y'];

  List<String> get _quickList => widget.stock ? _quickStocks : _quickCoins;
  List<String> get _intervals =>
      widget.stock ? _stockIntervals : _cryptoIntervals;

  @override
  void initState() {
    super.initState();
    _symbol = widget.initialSymbol;
    _interval = widget.stock ? '1d' : '1h';
    _symbolCtrl.text = _symbol;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final endpoint =
          widget.stock ? '/v1/market/stock' : '/v1/market/analyze';
      final res = await _dio.get(
        '${widget.backendUrl}$endpoint',
        queryParameters: {'symbol': _symbol, 'interval': _interval},
        options: Options(headers: {'Authorization': 'Bearer ${widget.token}'}),
      );
      final data = Map<String, dynamic>.from(res.data);
      if (data['ok'] != true) {
        setState(() {
          _error = (data['speak'] as String?) ?? 'No data for "$_symbol".';
          _loading = false;
        });
        return;
      }
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not reach the market service.\n$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pair = widget.stock ? '' : ' / USDT';
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(_data == null
            ? 'MARKET'
            : '${_data!['base']}$pair'.toUpperCase()),
        actions: [
          IconButton(
            icon: const Icon(Icons.radar, color: Ak.cyan),
            tooltip: 'Live agent',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LiveAgentScreen(
                    backendUrl: widget.backendUrl,
                    token: widget.token,
                    symbol: _symbol),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.bolt, color: Ak.gold),
            tooltip: 'Scalp analysis',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ScalpScreen(
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
          child: Column(
            children: [
              _controls(),
              Expanded(child: _chartArea()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _symbolCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Coin (bitcoin, ETH, solana...)',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) {
                    _symbol = v.trim().isEmpty ? _symbol : v.trim();
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  _symbol = _symbolCtrl.text.trim().isEmpty
                      ? _symbol
                      : _symbolCtrl.text.trim();
                  _load();
                },
                child: const Text('Go'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in _quickList)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      label: Text(c),
                      onPressed: () {
                        _symbol = c;
                        _symbolCtrl.text = c;
                        _load();
                      },
                    ),
                  ),
                const VerticalDivider(width: 16),
                for (final iv in _intervals)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(iv),
                      selected: _interval == iv,
                      onSelected: (_) {
                        setState(() => _interval = iv);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartArea() {
    if (_loading) {
      return const NothingLoader(label: 'Analyzing the market…');
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    final data = _data!;
    final candles = (data['candles'] as List)
        .map((c) => Candle(
              (c['o'] as num).toDouble(),
              (c['h'] as num).toDouble(),
              (c['l'] as num).toDouble(),
              (c['c'] as num).toDouble(),
            ))
        .toList();

    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: AspectRatio(
              aspectRatio: 1.4,
              child: CustomPaint(
                painter: CandleChartPainter(
                  candles: candles,
                  sma20: _rollingSma(candles, 20),
                  sma50: _rollingSma(candles, 50),
                  ema9: _showEma ? _rollingEma(candles, 9) : const [],
                  ema21: _showEma ? _rollingEma(candles, 21) : const [],
                  bbUpper: _showBb ? _rollingBb(candles, 20, true) : const [],
                  bbLower: _showBb ? _rollingBb(candles, 20, false) : const [],
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              FilterChip(
                label: const Text('EMA 9/21', style: TextStyle(fontSize: 11)),
                selected: _showEma,
                onSelected: (v) => setState(() => _showEma = v),
                selectedColor: Ak.purple,
                backgroundColor: Ak.glassFill,
                side: const BorderSide(color: Ak.glassLine),
                labelStyle:
                    TextStyle(color: _showEma ? Ak.bg0 : Ak.textMid),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Bollinger', style: TextStyle(fontSize: 11)),
                selected: _showBb,
                onSelected: (v) => setState(() => _showBb = v),
                selectedColor: Ak.purple,
                backgroundColor: Ak.glassFill,
                side: const BorderSide(color: Ak.glassLine),
                labelStyle: TextStyle(color: _showBb ? Ak.bg0 : Ak.textMid),
              ),
            ]),
          ),
          _legend(),
          _analysisPanel(data),
        ],
      ),
    );
  }

  Widget _legend() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Dot(color: Ak.up, label: 'SMA 20'),
          SizedBox(width: 16),
          _Dot(color: Ak.down, label: 'SMA 50'),
        ],
      ),
    );
  }

  String get _cur {
    final c = _data?['currency'] as String?;
    if (c == 'INR') return '₹';
    if (c == null || c == 'USD') return '\$';
    return '$c ';
  }

  Widget _analysisPanel(Map<String, dynamic> d) {
    final change = (d['change_pc'] as num).toDouble();
    final up = change >= 0;
    final rsi = (d['rsi'] as num?)?.toDouble();
    final trend = (d['trend'] as String?) ?? 'neutral';
    final trendColor = trend == 'bullish'
        ? Ak.up
        : (trend == 'bearish' ? Ak.down : Ak.textMid);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$_cur${_fmt((d['price'] as num).toDouble())}',
                  style: const TextStyle(
                      fontSize: 30, fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              Text('${up ? '▲' : '▼'} ${change.abs().toStringAsFixed(2)}%',
                  style: TextStyle(
                      fontSize: 18,
                      color: up ? Ak.up : Ak.down)),
              const Spacer(),
              Chip(
                label: Text(trend.toUpperCase(),
                    style: TextStyle(
                        color: trendColor, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _stat('High', '$_cur${_fmt((d['high_24h'] as num).toDouble())}'),
              _stat('Low', '$_cur${_fmt((d['low_24h'] as num).toDouble())}'),
              if (d['sma20'] != null)
                _stat('SMA 20', '$_cur${_fmt((d['sma20'] as num).toDouble())}'),
              if (d['sma50'] != null)
                _stat('SMA 50', '$_cur${_fmt((d['sma50'] as num).toDouble())}'),
              if (d['ema9'] != null)
                _stat('EMA 9', '$_cur${_fmt((d['ema9'] as num).toDouble())}'),
              if (d['ema21'] != null)
                _stat('EMA 21', '$_cur${_fmt((d['ema21'] as num).toDouble())}'),
              if (d['macd'] != null)
                _stat(
                    'MACD',
                    '${((d['macd']['hist'] as num) >= 0) ? '▲' : '▼'} '
                        '${_fmt((d['macd']['hist'] as num).toDouble())}'),
              if (d['bollinger'] != null)
                _stat('BB up',
                    '$_cur${_fmt((d['bollinger']['upper'] as num).toDouble())}'),
              if (d['bollinger'] != null)
                _stat('BB low',
                    '$_cur${_fmt((d['bollinger']['lower'] as num).toDouble())}'),
            ],
          ),
          if (rsi != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const SizedBox(width: 46, child: Text('RSI')),
                Expanded(
                  child: LinearProgressIndicator(
                    value: (rsi / 100).clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: Ak.glassFillStrong,
                    color: rsi >= 70
                        ? Ak.down
                        : (rsi <= 30 ? Ak.up : Ak.textMid),
                  ),
                ),
                const SizedBox(width: 8),
                Text(rsi.toStringAsFixed(0)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Card(
            color: Colors.white10,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.smart_toy, color: Ak.purple, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text((d['speak'] as String?) ?? '',
                        style: const TextStyle(fontSize: 15, height: 1.4)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Not financial advice — indicators only.',
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  /// Rolling SMA per candle index (null until enough history).
  static List<double?> _rollingSma(List<Candle> candles, int period) {
    final out = List<double?>.filled(candles.length, null);
    double sum = 0;
    for (var i = 0; i < candles.length; i++) {
      sum += candles[i].close;
      if (i >= period) sum -= candles[i - period].close;
      if (i >= period - 1) out[i] = sum / period;
    }
    return out;
  }

  static List<double?> _rollingEma(List<Candle> candles, int period) {
    final out = List<double?>.filled(candles.length, null);
    if (candles.length < period) return out;
    final k = 2 / (period + 1);
    double ema = 0;
    for (var i = 0; i < period; i++) {
      ema += candles[i].close;
    }
    ema /= period;
    out[period - 1] = ema;
    for (var i = period; i < candles.length; i++) {
      ema = candles[i].close * k + ema * (1 - k);
      out[i] = ema;
    }
    return out;
  }

  static List<double?> _rollingBb(
      List<Candle> candles, int period, bool upper) {
    final out = List<double?>.filled(candles.length, null);
    for (var i = period - 1; i < candles.length; i++) {
      double sum = 0;
      for (var j = i - period + 1; j <= i; j++) {
        sum += candles[j].close;
      }
      final mid = sum / period;
      double varSum = 0;
      for (var j = i - period + 1; j <= i; j++) {
        final diff = candles[j].close - mid;
        varSum += diff * diff;
      }
      final sd = math.sqrt(varSum / period);
      out[i] = upper ? mid + 2 * sd : mid - 2 * sd;
    }
    return out;
  }

  static String _fmt(double n) {
    if (n >= 1000) {
      return n.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
    }
    if (n >= 1) return n.toStringAsFixed(2);
    return n.toStringAsFixed(6);
  }
}

class Candle {
  final double open, high, low, close;
  Candle(this.open, this.high, this.low, this.close);
}

class _Dot extends StatelessWidget {
  final Color color;
  final String label;
  const _Dot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 3, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

class CandleChartPainter extends CustomPainter {
  final List<Candle> candles;
  final List<double?> sma20;
  final List<double?> sma50;
  final List<double?> ema9;
  final List<double?> ema21;
  final List<double?> bbUpper;
  final List<double?> bbLower;

  CandleChartPainter({
    required this.candles,
    required this.sma20,
    required this.sma50,
    this.ema9 = const [],
    this.ema21 = const [],
    this.bbUpper = const [],
    this.bbLower = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    double hi = candles.first.high, lo = candles.first.low;
    for (final c in candles) {
      if (c.high > hi) hi = c.high;
      if (c.low < lo) lo = c.low;
    }
    final range = (hi - lo).abs() < 1e-9 ? 1.0 : (hi - lo);
    final pad = range * 0.06;
    hi += pad;
    lo -= pad;

    double y(double price) =>
        size.height - ((price - lo) / (hi - lo)) * size.height;

    // grid
    final grid = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final gy = size.height * i / 4;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }

    final n = candles.length;
    final slot = size.width / n;
    final bodyW = (slot * 0.6).clamp(1.0, 14.0);

    final green = Paint()..color = Ak.up;
    final red = Paint()..color = Ak.down;

    for (var i = 0; i < n; i++) {
      final c = candles[i];
      final cx = slot * i + slot / 2;
      final bull = c.close >= c.open;
      final paint = bull ? green : red;

      // wick
      canvas.drawLine(Offset(cx, y(c.high)), Offset(cx, y(c.low)),
          paint..strokeWidth = 1);
      // body
      final top = y(bull ? c.close : c.open);
      final bottom = y(bull ? c.open : c.close);
      final rect = Rect.fromLTRB(
          cx - bodyW / 2, top, cx + bodyW / 2, bottom == top ? top + 1 : bottom);
      canvas.drawRect(rect, paint);
    }

    _drawSma(canvas, size, sma20, Ak.up, y, slot);
    _drawSma(canvas, size, sma50, Ak.down, y, slot);
    _drawSma(canvas, size, ema9, Ak.purple, y, slot);
    _drawSma(canvas, size, ema21, Ak.silver, y, slot);
    _drawSma(canvas, size, bbUpper, Ak.violet, y, slot, width: 1.0);
    _drawSma(canvas, size, bbLower, Ak.violet, y, slot, width: 1.0);
  }

  void _drawSma(Canvas canvas, Size size, List<double?> sma, Color color,
      double Function(double) y, double slot,
      {double width = 1.6}) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    Path? path;
    for (var i = 0; i < sma.length; i++) {
      final v = sma[i];
      if (v == null) continue;
      final cx = slot * i + slot / 2;
      final p = Offset(cx, y(v));
      if (path == null) {
        path = Path()..moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    if (path != null) {
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CandleChartPainter old) =>
      old.candles != candles ||
      old.ema9.length != ema9.length ||
      old.bbUpper.length != bbUpper.length;
}
