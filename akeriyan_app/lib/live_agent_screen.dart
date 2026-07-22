import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'theme.dart';

/// AKERIYAN LIVE AGENT — a real-time monitor that sits on a symbol, streams
/// the price, watches your key levels tick-by-tick and calls out entries,
/// stops, targets and liquidity sweeps as they happen (with optional voice).
class LiveAgentScreen extends StatefulWidget {
  final String backendUrl;
  final String token;
  final String symbol;

  const LiveAgentScreen({
    super.key,
    required this.backendUrl,
    required this.token,
    required this.symbol,
  });

  @override
  State<LiveAgentScreen> createState() => _LiveAgentScreenState();
}

class _AgentEvent {
  final String text;
  final IconData icon;
  final Color color;
  final DateTime at;
  _AgentEvent(this.text, this.icon, this.color) : at = DateTime.now();
}

class _LiveAgentScreenState extends State<LiveAgentScreen> {
  final _dio = Dio();
  final _tts = FlutterTts();

  Timer? _priceTimer;
  Timer? _analysisTimer;

  double? _price;
  double? _prevPrice;
  double _changePc = 0;
  Color _flash = Ak.textHi;
  String _base = '';

  bool _running = true;
  bool _voice = false;
  bool _loadingAnalysis = true;

  Map<String, dynamic>? _analysis; // levels from scalp
  final List<_AgentEvent> _log = [];
  final Set<String> _fired = {}; // dedupe level events

  @override
  void initState() {
    super.initState();
    _base = widget.symbol;
    _tts.setLanguage('en-IN');
    _tts.setSpeechRate(0.5);
    _add('Agent started — monitoring ${widget.symbol}.', Icons.play_circle,
        Ak.cyan);
    _refreshAnalysis();
    _priceTimer =
        Timer.periodic(const Duration(seconds: 4), (_) => _tick());
    _analysisTimer =
        Timer.periodic(const Duration(seconds: 75), (_) => _refreshAnalysis());
  }

  @override
  void dispose() {
    _priceTimer?.cancel();
    _analysisTimer?.cancel();
    _tts.stop();
    super.dispose();
  }

  // ---- Data ----
  Future<void> _refreshAnalysis() async {
    try {
      final r = await _dio.get('${widget.backendUrl}/v1/market/scalp',
          queryParameters: {'symbol': widget.symbol},
          options:
              Options(headers: {'Authorization': 'Bearer ${widget.token}'}));
      final d = Map<String, dynamic>.from(r.data);
      if (d['ok'] == true) {
        setState(() {
          _analysis = d;
          _base = (d['base'] as String?) ?? widget.symbol;
          _loadingAnalysis = false;
        });
        final bias = d['bias'];
        _add('Re-analyzed: bias $bias.', Icons.autorenew, Ak.textMid);
      }
    } catch (_) {/* keep last analysis */}
  }

  Future<void> _tick() async {
    if (!_running) return;
    try {
      final r = await _dio.get('${widget.backendUrl}/v1/market/price',
          queryParameters: {'symbol': widget.symbol},
          options:
              Options(headers: {'Authorization': 'Bearer ${widget.token}'}));
      final d = Map<String, dynamic>.from(r.data);
      if (d['ok'] != true) return;
      final p = (d['price'] as num).toDouble();
      setState(() {
        _prevPrice = _price;
        _price = p;
        _changePc = (d['change_pc'] as num?)?.toDouble() ?? _changePc;
        if (_prevPrice != null) {
          _flash = p > _prevPrice! ? Ak.green : (p < _prevPrice! ? Ak.pink : Ak.textHi);
        }
      });
      _evaluate(p);
    } catch (_) {/* transient network — ignore this tick */}
  }

  // ---- The signal engine: fires events as price crosses key levels ----
  void _evaluate(double price) {
    final a = _analysis;
    if (a == null || _prevPrice == null) return;
    final prev = _prevPrice!;

    void crossUp(double lvl, String key, String msg, IconData ic, Color c) {
      if (prev < lvl && price >= lvl && _fired.add('$key-up')) {
        _fired.remove('$key-down');
        _add(msg, ic, c, speak: true);
      }
    }

    void crossDown(double lvl, String key, String msg, IconData ic, Color c) {
      if (prev > lvl && price <= lvl && _fired.add('$key-down')) {
        _fired.remove('$key-up');
        _add(msg, ic, c, speak: true);
      }
    }

    final f = _fmt;
    final setup = a['setup'] as Map?;
    if (setup != null) {
      final entry =
          (setup['entry'] as List).map((e) => (e as num).toDouble()).toList();
      final stop = (setup['stop'] as num).toDouble();
      final target = (setup['target'] as num).toDouble();
      final long = setup['direction'] == 'long';

      // Entry zone.
      final inZone = price >= entry[0] && price <= entry[1];
      final wasIn = prev >= entry[0] && prev <= entry[1];
      if (inZone && !wasIn && _fired.add('entry')) {
        _add('Price entered the ${long ? 'LONG' : 'SHORT'} entry zone '
            '${f(entry[0])}–${f(entry[1])}. Setup is active.',
            Icons.my_location, Ak.gold, speak: true);
      }
      // Stop / target.
      if (long) {
        crossDown(stop, 'stop', '⛔ Stop level ${f(stop)} hit.',
            Icons.gpp_bad, Ak.pink);
        crossUp(target, 'target', '🎯 Target ${f(target)} reached!',
            Icons.emoji_events, Ak.green);
      } else {
        crossUp(stop, 'stop', '⛔ Stop level ${f(stop)} hit.',
            Icons.gpp_bad, Ak.pink);
        crossDown(target, 'target', '🎯 Target ${f(target)} reached!',
            Icons.emoji_events, Ak.green);
      }
    }

    // Support / resistance crossings.
    for (final r in _dl(a['resistances'])) {
      crossUp(r, 'res$r', 'Broke resistance ${f(r)}.', Icons.trending_up,
          Ak.green);
    }
    for (final s in _dl(a['supports'])) {
      crossDown(s, 'sup$s', 'Lost support ${f(s)}.', Icons.trending_down,
          Ak.pink);
    }

    // Liquidity sweeps.
    final liq = a['liquidity'] as Map?;
    if (liq != null) {
      for (final b in _dl(liq['bsl'])) {
        crossUp(b, 'bsl$b', 'Swept buy-side liquidity at ${f(b)}.',
            Icons.water_drop, Ak.cyan);
      }
      for (final s in _dl(liq['ssl'])) {
        crossDown(s, 'ssl$s', 'Swept sell-side liquidity at ${f(s)}.',
            Icons.water_drop, Ak.violet);
      }
    }

    // Sharp move (velocity).
    final move = ((price - prev).abs() / prev) * 100;
    if (move >= 0.25) {
      _add('⚡ Sharp ${price > prev ? 'up' : 'down'} move ${move.toStringAsFixed(2)}%.',
          Icons.bolt, price > prev ? Ak.green : Ak.pink);
    }
  }

  List<double> _dl(dynamic v) =>
      (v as List? ?? []).map((e) => (e as num).toDouble()).toList();

  void _add(String text, IconData icon, Color color, {bool speak = false}) {
    setState(() {
      _log.insert(0, _AgentEvent(text, icon, color));
      if (_log.length > 60) _log.removeLast();
    });
    if (speak && _voice) {
      _tts.speak('$_base. ${text.replaceAll(RegExp(r'[⛔🎯⚡]'), '')}');
    }
  }

  String _fmt(double n) => n >= 1000
      ? n.toStringAsFixed(0)
      : (n >= 1 ? n.toStringAsFixed(2) : n.toStringAsFixed(5));

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('LIVE · $_base'),
        actions: [
          IconButton(
            tooltip: _voice ? 'Voice alerts on' : 'Voice alerts off',
            icon: Icon(_voice ? Icons.volume_up : Icons.volume_off,
                color: _voice ? Ak.gold : Ak.textMid),
            onPressed: () => setState(() => _voice = !_voice),
          ),
          IconButton(
            tooltip: _running ? 'Pause' : 'Resume',
            icon: Icon(_running ? Icons.pause_circle : Icons.play_circle,
                color: Ak.gold),
            onPressed: () {
              setState(() => _running = !_running);
              _add(_running ? 'Resumed monitoring.' : 'Paused.',
                  _running ? Icons.play_arrow : Icons.pause, Ak.textMid);
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: Ak.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              _liveHeader(),
              _statusStrip(),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 6),
                child: Row(
                  children: [
                    Text('AGENT FEED',
                        style: TextStyle(
                            color: Ak.textLo, fontSize: 11, letterSpacing: 2)),
                  ],
                ),
              ),
              Expanded(child: _feed()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _liveHeader() {
    final up = _changePc >= 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(18),
      decoration: Ak.glass(),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('LIVE PRICE',
                  style: TextStyle(
                      color: Ak.textLo, fontSize: 10, letterSpacing: 2)),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: TextStyle(
                    color: _flash,
                    fontSize: 32,
                    fontWeight: FontWeight.w800),
                child: Text(_price == null ? '—' : _fmt(_price!)),
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${up ? '▲' : '▼'} ${_changePc.abs().toStringAsFixed(2)}%',
                  style: TextStyle(
                      color: up ? Ak.green : Ak.pink,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('24h', style: const TextStyle(color: Ak.textLo, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusStrip() {
    final bias = _analysis?['bias'] as String?;
    final biasColor = bias == 'bullish'
        ? Ak.green
        : (bias == 'bearish' ? Ak.pink : Ak.textLo);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: Ak.glass(radius: 16),
      child: Row(
        children: [
          _PulseDot(active: _running),
          const SizedBox(width: 10),
          Text(_running ? 'MONITORING' : 'PAUSED',
              style: TextStyle(
                  color: _running ? Ak.green : Ak.textLo,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 1)),
          const Spacer(),
          if (_loadingAnalysis)
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Ak.gold))
          else if (bias != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                  color: biasColor.withAlpha(28),
                  borderRadius: BorderRadius.circular(20)),
              child: Text('bias: $bias',
                  style: TextStyle(color: biasColor, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _feed() {
    if (_log.isEmpty) {
      return const Center(
          child: Text('Watching the tape…',
              style: TextStyle(color: Ak.textLo)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _log.length,
      itemBuilder: (_, i) {
        final e = _log[i];
        final t = e.at;
        final time =
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Ak.glassFill,
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: e.color, width: 3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(e.icon, color: e.color, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(e.text,
                    style: const TextStyle(color: Ak.textHi, fontSize: 13.5)),
              ),
              const SizedBox(width: 8),
              Text(time,
                  style: const TextStyle(color: Ak.textLo, fontSize: 10)),
            ],
          ),
        );
      },
    );
  }
}

class _PulseDot extends StatefulWidget {
  final bool active;
  const _PulseDot({required this.active});
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final glow = widget.active ? (0.4 + 0.6 * _c.value) : 0.3;
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.active ? Ak.green : Ak.textLo,
            boxShadow: widget.active
                ? [BoxShadow(color: Ak.green.withAlpha((glow * 180).round()), blurRadius: 10)]
                : null,
          ),
        );
      },
    );
  }
}
