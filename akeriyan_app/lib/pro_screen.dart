import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'theme.dart';
import 'widgets/nothing_loader.dart';
import 'trading_screen.dart' show Candle;
import 'scalp_screen.dart' show ScalpChartPainter;
import 'live_agent_screen.dart';

/// AKERIYAN PRO — the full institutional terminal: AI decision, liquidity map,
/// economic news (ForexFactory), sentiment, session, and the chart with
/// everything drawn on it.
class ProScreen extends StatefulWidget {
  final String backendUrl;
  final String token;
  final String initialSymbol;

  const ProScreen({
    super.key,
    required this.backendUrl,
    required this.token,
    this.initialSymbol = 'bitcoin',
  });

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
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
      final res = await _dio.get('${widget.backendUrl}/v1/market/pro',
          queryParameters: {'symbol': _symbol},
          options: Options(
              headers: {'Authorization': 'Bearer ${widget.token}'},
              receiveTimeout: const Duration(seconds: 180),
              sendTimeout: const Duration(seconds: 30)));
      if (!mounted) return; // user left the screen mid-load
      final d = Map<String, dynamic>.from(res.data);
      if (d['ok'] != true) {
        setState(() {
          _error = (d['speak'] as String?) ?? 'No analysis for "$_symbol".';
          _loading = false;
        });
        return;
      }
      setState(() {
        _d = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not reach the pro service.\n$e';
        _loading = false;
      });
    }
  }

  Color _dirColor(String a) => a == 'LONG'
      ? Ak.up
      : (a == 'SHORT' ? Ak.down : Ak.gold);

  double _toD(dynamic v) => (v as num).toDouble();
  List<double> _toList(dynamic v) =>
      (v as List? ?? []).map((e) => (e as num).toDouble()).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(_d == null ? 'PRO TERMINAL' : 'PRO · ${_d!['base']}'),
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
              icon: const Icon(Icons.refresh, color: Ak.textMid),
              onPressed: _load),
          const SizedBox(width: 6),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: Ak.bgGradient),
        child: SafeArea(
          child: _loading
              ? _loadingView()
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

  Widget _loadingView() => const NothingLoader(
        label: 'Reading the market…\nbias · liquidity · news · sentiment',
      );

  Widget _content() {
    final d = _d!;
    final dec = Map<String, dynamic>.from(d['decision'] ?? {});
    final tfs = Map<String, dynamic>.from(d['timeframes'] ?? {});
    final liq = Map<String, dynamic>.from(d['liquidity'] ?? {});
    final cal = Map<String, dynamic>.from(d['calendar'] ?? {});
    final sent = Map<String, dynamic>.from(d['sentiment'] ?? {});
    final sess = Map<String, dynamic>.from(d['session'] ?? {});
    final candles = (d['candles'] as List)
        .map((c) => Candle(_toD(c['o']), _toD(c['h']), _toD(c['l']), _toD(c['c'])))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _symbolBar(),
          const SizedBox(height: 14),
          _decisionHero(d, dec),
          const SizedBox(height: 14),
          _tfRow(d['bias'] as String? ?? 'neutral', tfs),
          const SizedBox(height: 14),
          _chartCard(candles, d, liq),
          const SizedBox(height: 8),
          _legend(),
          const SizedBox(height: 16),
          _liquidityCard(liq),
          const SizedBox(height: 14),
          _newsCard(cal),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _sentimentCard(sent)),
            const SizedBox(width: 12),
            Expanded(child: _sessionCard(sess)),
          ]),
          const SizedBox(height: 14),
          _reasonsCard(dec),
          const SizedBox(height: 12),
          const Center(
            child: Text('Elder Wand Pro — educational analysis, not financial advice.',
                style: TextStyle(color: Ak.textLo, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  // -------- Decision hero (the star) --------
  Widget _decisionHero(Map d, Map dec) {
    final action = (dec['action'] as String?) ?? 'WAIT';
    final conf = (dec['confidence'] as String?) ?? 'low';
    final score = (dec['score'] as num?)?.toInt() ?? 0;
    final color = _dirColor(action);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color, width: 1.5),
        gradient: LinearGradient(
          colors: [color.withAlpha(28), Ak.glassFill],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Ak.gold, size: 18),
              const SizedBox(width: 8),
              const Text('AI DECISION',
                  style: TextStyle(
                      color: Ak.textLo, fontSize: 11, letterSpacing: 3)),
              const Spacer(),
              Text('\$${_fmtNum(_toD(d['price']))}',
                  style: const TextStyle(
                      color: Ak.textHi, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(action,
                  style: TextStyle(
                      color: color,
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1)),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$conf confidence',
                      style: const TextStyle(color: Ak.textMid, fontSize: 13)),
                  Text('Bias: ${d['bias']}',
                      style: const TextStyle(color: Ak.textLo, fontSize: 12)),
                ],
              ),
              const Spacer(),
              _scoreGauge(score, color),
            ],
          ),
          const SizedBox(height: 14),
          Text((dec['reasoning'] as String?) ?? '',
              style: const TextStyle(
                  color: Ak.textHi, fontSize: 14, height: 1.45)),
        ],
      ),
    );
  }

  Widget _scoreGauge(int score, Color color) {
    return SizedBox(
      width: 62,
      height: 62,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 62,
            height: 62,
            child: CircularProgressIndicator(
              value: (score / 100).clamp(0.0, 1.0),
              strokeWidth: 6,
              backgroundColor: Ak.glassLine,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$score',
                  style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const Text('score',
                  style: TextStyle(color: Ak.textLo, fontSize: 8)),
            ],
          ),
        ],
      ),
    );
  }

  // -------- Timeframe row --------
  Widget _tfRow(String bias, Map tfs) {
    Color c(String t) =>
        t == 'bullish' ? Ak.up : (t == 'bearish' ? Ak.down : Ak.textLo);
    return Row(
      children: [
        for (final tf in ['4h', '1h', '15m', '1m'])
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: Ak.glass(radius: 14),
              child: Column(
                children: [
                  Text(tf, style: const TextStyle(color: Ak.textLo, fontSize: 11)),
                  const SizedBox(height: 3),
                  Icon(
                      (tfs[tf] == 'bullish')
                          ? Icons.trending_up
                          : (tfs[tf] == 'bearish')
                              ? Icons.trending_down
                              : Icons.trending_flat,
                      color: c((tfs[tf] as String?) ?? ''),
                      size: 18),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // -------- Chart --------
  Widget _chartCard(List<Candle> candles, Map d, Map liq) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: Ak.glass(),
      child: AspectRatio(
        aspectRatio: 1.2,
        child: CustomPaint(
          painter: ScalpChartPainter(
            candles: candles,
            supports: _toList(d['supports']),
            resistances: _toList(d['resistances']),
            bullOB: (d['order_blocks'] as Map?)?['bullish'] as Map?,
            bearOB: (d['order_blocks'] as Map?)?['bearish'] as Map?,
            setup: d['setup'] as Map?,
            bsl: _toList(liq['bsl']),
            ssl: _toList(liq['ssl']),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  // -------- Liquidity --------
  Widget _liquidityCard(Map liq) {
    final bsl = _toList(liq['bsl']);
    final ssl = _toList(liq['ssl']);
    final sweep = liq['sweep'] as Map?;
    return _card('LIQUIDITY MAP', Icons.water_drop_outlined, [
      if (sweep != null)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (sweep['type'] == 'bullish' ? Ak.up : Ak.down)
                .withAlpha(28),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.bolt,
                  color: sweep['type'] == 'bullish' ? Ak.up : Ak.down,
                  size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Sweep: ${sweep['desc']}',
                    style: const TextStyle(color: Ak.textHi, fontSize: 13)),
              ),
            ],
          ),
        ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _levelList('Buy-side (above)', Ak.cyan, bsl),
          ),
          Expanded(
            child: _levelList('Sell-side (below)', Ak.violet, ssl),
          ),
        ],
      ),
    ]);
  }

  Widget _levelList(String title, Color color, List<double> levels) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(color: color, fontSize: 12)),
        const SizedBox(height: 4),
        if (levels.isEmpty)
          const Text('—', style: TextStyle(color: Ak.textLo))
        else
          for (final l in levels.take(3))
            Text(_fmtNum(l), style: const TextStyle(color: Ak.textHi)),
      ],
    );
  }

  // -------- News (ForexFactory) --------
  Widget _newsCard(Map cal) {
    final events = (cal['events'] as List? ?? []);
    final risk = (cal['news_risk'] as String?) ?? 'low';
    final riskColor =
        risk == 'high' ? Ak.down : (risk == 'elevated' ? Ak.gold : Ak.up);
    return _card('ECONOMIC NEWS', Icons.event_note, [
      Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
                color: riskColor.withAlpha(30),
                borderRadius: BorderRadius.circular(20)),
            child: Text('news risk: $risk',
                style: TextStyle(color: riskColor, fontSize: 11)),
          ),
          const Spacer(),
          const Text('ForexFactory',
              style: TextStyle(color: Ak.textLo, fontSize: 10)),
        ],
      ),
      const SizedBox(height: 10),
      if (events.isEmpty)
        const Text('No major events in the window.',
            style: TextStyle(color: Ak.textLo))
      else
        for (final e in events.take(5)) _eventRow(e as Map),
    ]);
  }

  Widget _eventRow(Map e) {
    final impact = (e['impact'] as String?) ?? '';
    final ic = impact == 'High' ? Ak.down : Ak.gold;
    final h = (e['in_hours'] as num?)?.toDouble() ?? 0;
    final when = h < 0
        ? 'now'
        : (h < 1 ? '${(h * 60).round()}m' : '${h.toStringAsFixed(0)}h');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(width: 8, height: 8,
              decoration: BoxDecoration(color: ic, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
                color: Ak.glassFillStrong,
                borderRadius: BorderRadius.circular(6)),
            child: Text('${e['currency']}',
                style: const TextStyle(color: Ak.textMid, fontSize: 10)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${e['title']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Ak.textHi, fontSize: 13)),
          ),
          Text('in $when',
              style: TextStyle(
                  color: (e['imminent'] == true) ? Ak.down : Ak.textLo,
                  fontSize: 11,
                  fontWeight: (e['imminent'] == true)
                      ? FontWeight.bold
                      : FontWeight.normal)),
        ],
      ),
    );
  }

  // -------- Sentiment --------
  Widget _sentimentCard(Map sent) {
    final fng = sent['fear_greed'] as Map?;
    final news = Map<String, dynamic>.from(sent['news'] ?? {});
    final mood = (news['mood'] as String?) ?? 'neutral';
    final moodColor =
        mood == 'bullish' ? Ak.up : (mood == 'bearish' ? Ak.down : Ak.textLo);
    return _card('SENTIMENT', Icons.psychology_outlined, [
      if (fng != null) ...[
        Row(
          children: [
            Text('${fng['value']}',
                style: TextStyle(
                    color: _fngColor((fng['value'] as num).toInt()),
                    fontSize: 26,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${fng['label']}',
                  style: TextStyle(
                      color: _fngColor((fng['value'] as num).toInt()),
                      fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: ((fng['value'] as num).toDouble() / 100).clamp(0, 1),
          minHeight: 6,
          backgroundColor: Ak.glassLine,
          color: _fngColor((fng['value'] as num).toInt()),
        ),
        const SizedBox(height: 4),
        const Text('Fear & Greed',
            style: TextStyle(color: Ak.textLo, fontSize: 10)),
        const SizedBox(height: 8),
      ],
      Row(
        children: [
          Icon(
              mood == 'bullish'
                  ? Icons.sentiment_satisfied
                  : mood == 'bearish'
                      ? Icons.sentiment_dissatisfied
                      : Icons.sentiment_neutral,
              color: moodColor,
              size: 18),
          const SizedBox(width: 6),
          Text('News: $mood', style: TextStyle(color: moodColor, fontSize: 13)),
        ],
      ),
    ]);
  }

  Color _fngColor(int v) => v <= 25
      ? Ak.down
      : (v <= 45 ? Ak.gold : (v >= 75 ? Ak.up : Ak.cyan));

  // -------- Session --------
  Widget _sessionCard(Map sess) {
    final vol = (sess['volatility'] as String?) ?? 'low';
    final vc = vol == 'high' ? Ak.up : (vol == 'medium' ? Ak.gold : Ak.textLo);
    final active = (sess['active'] as List? ?? []).join(' · ');
    return _card('SESSION', Icons.public, [
      Text(active,
          style: const TextStyle(
              color: Ak.textHi, fontSize: 15, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text('volatility: $vol', style: TextStyle(color: vc, fontSize: 12)),
      const SizedBox(height: 6),
      Text((sess['note'] as String?) ?? '',
          style: const TextStyle(color: Ak.textLo, fontSize: 11, height: 1.3)),
    ]);
  }

  // -------- Reasons --------
  Widget _reasonsCard(Map dec) {
    final reasons = (dec['reasons'] as List? ?? []);
    if (reasons.isEmpty) return const SizedBox.shrink();
    return _card('WHY (CONFLUENCE)', Icons.checklist, [
      for (final r in reasons)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• ', style: TextStyle(color: Ak.gold)),
              Expanded(
                child: Text('$r',
                    style: const TextStyle(color: Ak.textMid, fontSize: 13)),
              ),
            ],
          ),
        ),
    ]);
  }

  // -------- Shared pieces --------
  Widget _card(String title, IconData icon, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: Ak.glass(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Ak.gold, size: 16),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      color: Ak.textLo, fontSize: 11, letterSpacing: 2)),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
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
                child: const Text('Analyze')),
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

  Widget _legend() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(spacing: 12, runSpacing: 4, children: [
        _Lg(color: Ak.cyan, label: 'Buy-side liq'),
        _Lg(color: Ak.violet, label: 'Sell-side liq'),
        _Lg(color: Ak.up, label: 'Support'),
        _Lg(color: Ak.down, label: 'Resistance'),
        _Lg(color: Ak.gold, label: 'Entry/Stop/Target'),
      ]),
    );
  }

  String _fmtNum(double n) => n >= 1000
      ? n.toStringAsFixed(0)
      : (n >= 1 ? n.toStringAsFixed(2) : n.toStringAsFixed(5));
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
