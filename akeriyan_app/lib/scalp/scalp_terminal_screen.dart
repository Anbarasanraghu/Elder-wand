import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'candle_chart.dart';
import 'scalp_data.dart';
import 'scalp_report.dart';
import 'scalp_sentiment.dart';
import 'scalp_signal.dart';

/// Live 1m/5m scalping terminal — chart + per-minute signal + News Radar + PDF.
/// Data: Twelve Data free API (~1-3s, polled to respect the free tier).
class ScalpTerminalScreen extends StatefulWidget {
  const ScalpTerminalScreen({super.key});

  @override
  State<ScalpTerminalScreen> createState() => _ScalpTerminalScreenState();
}

class _ScalpTerminalScreenState extends State<ScalpTerminalScreen> {
  String _symbol = 'XAU/USD';
  String _tf = '1min';
  List<Candle> _candles = [];
  Signal? _sig;
  Sentiment? _sent;
  bool _loading = true;
  bool _needKey = false;
  String? _error;
  Timer? _timer;
  DateTime? _sentAt;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    if ((await ScalpConfig.key()).isEmpty) {
      setState(() {
        _needKey = true;
        _loading = false;
      });
      return;
    }
    await _poll();
    // ~9s => 6.7 req/min, under Twelve Data free 8/min.
    _timer = Timer.periodic(const Duration(seconds: 9), (_) => _poll());
  }

  Future<void> _poll() async {
    try {
      final c = await TdClient.candles(_symbol, _tf);
      if (!mounted) return;
      setState(() {
        _candles = c;
        _sig = c.length > 30 ? SignalEngine.compute(c) : null;
        _error = null;
        _loading = false;
      });
    } on NoApiKey {
      _timer?.cancel();
      if (mounted) setState(() => _needKey = true);
      return;
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
    // sentiment on symbol change or every 60s (Google News — no TD quota)
    if (_sent == null ||
        _sentAt == null ||
        DateTime.now().difference(_sentAt!).inSeconds > 60) {
      final s = await NewsSentiment.forSymbol(_symbol);
      _sentAt = DateTime.now();
      if (mounted) setState(() => _sent = s);
    }
  }

  void _reload() {
    setState(() {
      _candles = [];
      _sig = null;
      _sent = null;
      _loading = true;
    });
    _poll();
  }

  @override
  Widget build(BuildContext context) {
    if (_needKey) return _keyGate();
    return Scaffold(
      backgroundColor: Ak.bg0,
      appBar: AppBar(
        backgroundColor: Ak.bg0,
        elevation: 0,
        title: const Text('Scalp Terminal',
            style: TextStyle(fontFamily: Ak.dot, letterSpacing: 2)),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined, color: Ak.purple),
            tooltip: 'PDF report',
            onPressed: (_sig == null || _sent == null)
                ? null
                : () => ScalpReport.share(
                      symbol: _symbol,
                      interval: _tf,
                      s: _sig!,
                      sent: _sent!,
                      at: DateTime.now(),
                    ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
              children: [
                _controls(),
                const SizedBox(height: 10),
                SizedBox(
                  height: 250,
                  child: _candles.length < 2
                      ? Center(
                          child: Text(_error ?? 'No data',
                              style: TextStyle(color: Ak.textLo)))
                      : Container(
                          decoration: Ak.bento(radius: 14),
                          padding: const EdgeInsets.all(8),
                          child: CandleChart(candles: _candles),
                        ),
                ),
                const SizedBox(height: 12),
                if (_sig != null) _signalCard(_sig!),
                const SizedBox(height: 12),
                if (_sig != null) _indicators(_sig!),
                const SizedBox(height: 12),
                _newsRadar(),
                const SizedBox(height: 10),
                Text(
                  'Not financial advice. Signals are algorithmic and sentiment is '
                  'a gauge — not a prediction. Data ~1-3s (free tier).',
                  style: TextStyle(color: Ak.textLo, fontSize: 11, height: 1.4),
                ),
              ],
            ),
    );
  }

  Widget _controls() {
    final price = _candles.isNotEmpty ? _candles.last.c : 0.0;
    final prev = _candles.length > 1 ? _candles[_candles.length - 2].c : price;
    final chg = price - prev;
    final up = chg >= 0;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: Ak.bento(radius: 12),
          child: DropdownButton<String>(
            value: _symbol,
            dropdownColor: Ak.bg2,
            underline: const SizedBox.shrink(),
            style: const TextStyle(
                color: Ak.textHi, fontWeight: FontWeight.w700, fontSize: 15),
            items: [
              for (final s in ScalpConfig.symbols)
                DropdownMenuItem(value: s, child: Text(s)),
            ],
            onChanged: (v) {
              if (v != null) {
                _symbol = v;
                _reload();
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        _tfBtn('1min', '1m'),
        _tfBtn('5min', '5m'),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(price.toStringAsFixed(price > 100 ? 2 : 4),
                style: const TextStyle(
                    color: Ak.textHi, fontSize: 18, fontWeight: FontWeight.w800)),
            Text('${up ? '+' : ''}${chg.toStringAsFixed(price > 100 ? 2 : 4)}',
                style: TextStyle(color: up ? Ak.up : Ak.down, fontSize: 12)),
          ],
        ),
      ],
    );
  }

  Widget _tfBtn(String tf, String label) {
    final on = _tf == tf;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () {
          if (!on) {
            _tf = tf;
            _reload();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: on ? Ak.purple.withValues(alpha: 0.18) : Ak.glassFill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: on ? Ak.purple.withValues(alpha: 0.5) : Ak.glassLine),
          ),
          child: Text(label,
              style: TextStyle(
                  color: on ? Ak.purple : Ak.textMid,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
        ),
      ),
    );
  }

  Widget _signalCard(Signal s) {
    final col = s.side == 'LONG'
        ? Ak.up
        : s.side == 'SHORT'
            ? Ak.down
            : Ak.silver;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: Ak.bento(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                    color: col, borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: [
                    Text(s.side,
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: 18,
                            fontWeight: FontWeight.w900)),
                    Text('${s.confidence}%',
                        style: const TextStyle(color: Colors.black87, fontSize: 10)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _lvl('Entry', s.entry),
                    _lvl('Stop', s.sl, color: Ak.down),
                    _lvl('Target', s.tp, color: Ak.up),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final r in s.reasons.take(4))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: col)),
                  Expanded(
                      child: Text(r,
                          style: TextStyle(color: Ak.textMid, fontSize: 12.5))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _lvl(String label, double? v, {Color color = Ak.textHi}) => Column(
        children: [
          Text(v == null ? '—' : v.toStringAsFixed(v > 100 ? 2 : 4),
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w700)),
          Text(label, style: TextStyle(color: Ak.textLo, fontSize: 10)),
        ],
      );

  Widget _indicators(Signal s) {
    Widget chip(String l, String v) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: Ak.bento(radius: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, style: TextStyle(color: Ak.textLo, fontSize: 10)),
            Text(v,
                style: const TextStyle(
                    color: Ak.textHi, fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
        );
    return Wrap(spacing: 8, runSpacing: 8, children: [
      chip('RSI', s.rsi.toStringAsFixed(0)),
      chip('MACD h', s.macdHist.toStringAsFixed(3)),
      chip('EMA9', s.ema9.toStringAsFixed(s.ema9 > 100 ? 2 : 4)),
      chip('EMA21', s.ema21.toStringAsFixed(s.ema21 > 100 ? 2 : 4)),
      chip('ATR', s.atr.toStringAsFixed(s.atr > 100 ? 2 : 4)),
    ]);
  }

  Widget _newsRadar() {
    final s = _sent;
    final col = s == null
        ? Ak.silver
        : s.label == 'Bullish'
            ? Ak.up
            : s.label == 'Bearish'
                ? Ak.down
                : Ak.silver;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: Ak.bento(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.newspaper, size: 16, color: col),
            const SizedBox(width: 8),
            Text('News Radar',
                style: const TextStyle(
                    color: Ak.textHi, fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                  color: col.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(s?.label ?? '…',
                  style: TextStyle(color: col, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 8),
          if (s == null)
            Text('Loading headlines…', style: TextStyle(color: Ak.textLo, fontSize: 12))
          else
            for (final h in s.headlines.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text('· $h',
                    style: TextStyle(color: Ak.textMid, fontSize: 12, height: 1.3)),
              ),
        ],
      ),
    );
  }

  Widget _keyGate() {
    final ctrl = TextEditingController();
    return Scaffold(
      backgroundColor: Ak.bg0,
      appBar: AppBar(
          backgroundColor: Ak.bg0,
          elevation: 0,
          title: const Text('Scalp Terminal',
              style: TextStyle(fontFamily: Ak.dot, letterSpacing: 2))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Live forex & gold data needs a free Twelve Data API key:\n\n'
            '1. twelvedata.com → sign up (free, no card)\n'
            '2. Copy your API key\n3. Paste it below.\n\n'
            'Free tier: 8 requests/min — the terminal polls every ~9s.',
            style: TextStyle(color: Ak.textMid, height: 1.5, fontSize: 13),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: ctrl,
            style: const TextStyle(color: Ak.textHi),
            decoration: InputDecoration(
              hintText: 'Twelve Data API key',
              hintStyle: const TextStyle(color: Ak.textLo, fontSize: 13),
              filled: true,
              fillColor: Ak.glassFill,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Ak.purple,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              await ScalpConfig.setKey(ctrl.text.trim());
              setState(() {
                _needKey = false;
                _loading = true;
              });
              _boot();
            },
            child: const Text('Connect',
                style: TextStyle(color: Ak.bg0, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
