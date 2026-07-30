import 'scalp_data.dart';

/// A per-candle scalping signal with the evidence behind it. Algorithmic
/// decision support — NOT financial advice, NOT a guarantee.
class Signal {
  final String side; // LONG | SHORT | WAIT
  final int confidence; // 0..95
  final List<String> reasons;
  final double price;
  final double? entry, sl, tp;
  final double rsi, macdHist, ema9, ema21, atr;
  final ({double up, double mid, double low}) bb;
  final String verdict; // TAKE | CAUTION | AVOID
  final String guidance; // full plain-language description

  Signal({
    required this.side,
    required this.confidence,
    required this.reasons,
    required this.price,
    required this.entry,
    required this.sl,
    required this.tp,
    required this.rsi,
    required this.macdHist,
    required this.ema9,
    required this.ema21,
    required this.atr,
    required this.bb,
    required this.verdict,
    required this.guidance,
  });
}

class SignalEngine {
  static Signal compute(List<Candle> c) {
    final closes = c.map((x) => x.c).toList();
    final e9 = Indicators.ema(closes, 9);
    final e21 = Indicators.ema(closes, 21);
    final rsi = Indicators.rsi(closes, 14);
    final macd = Indicators.macd(closes);
    final bb = Indicators.bollinger(closes, 20, 2);
    final atr = Indicators.atr(c, 14);
    final price = closes.last;

    var bull = 0, bear = 0;
    final reasons = <String>[];

    if (e9.last > e21.last) {
      bull++;
      reasons.add('EMA9 above EMA21 — short-term uptrend');
    } else {
      bear++;
      reasons.add('EMA9 below EMA21 — short-term downtrend');
    }
    if (macd.hist > 0) {
      bull++;
      reasons.add('MACD histogram positive — bullish momentum');
    } else {
      bear++;
      reasons.add('MACD histogram negative — bearish momentum');
    }
    if (rsi > 55 && rsi < 70) {
      bull++;
      reasons.add('RSI ${rsi.toStringAsFixed(0)} — bullish, room to run');
    } else if (rsi < 45 && rsi > 30) {
      bear++;
      reasons.add('RSI ${rsi.toStringAsFixed(0)} — bearish, room to fall');
    }
    if (rsi >= 70) reasons.add('RSI ${rsi.toStringAsFixed(0)} overbought — caution');
    if (rsi <= 30) reasons.add('RSI ${rsi.toStringAsFixed(0)} oversold — caution');
    if (closes.length > 3) {
      if (price > closes[closes.length - 3]) {
        bull++;
      } else {
        bear++;
      }
    }
    // price vs Bollinger mid
    if (bb.mid > 0) {
      if (price > bb.mid) {
        bull++;
      } else {
        bear++;
      }
    }

    final net = bull - bear;
    String side;
    int conf;
    if (net >= 2) {
      side = 'LONG';
      conf = (50 + net * 10).clamp(0, 95);
    } else if (net <= -2) {
      side = 'SHORT';
      conf = (50 + (-net) * 10).clamp(0, 95);
    } else {
      side = 'WAIT';
      conf = 40;
    }

    double? entry, sl, tp;
    if (side != 'WAIT' && atr > 0) {
      entry = price;
      if (side == 'LONG') {
        sl = price - atr * 1.2;
        tp = price + atr * 1.8;
      } else {
        sl = price + atr * 1.2;
        tp = price - atr * 1.8;
      }
    }

    // ---- verdict: TAKE / CAUTION / AVOID + full guidance ----
    String f(double? v) => v == null ? '—' : v.toStringAsFixed(v > 100 ? 2 : 4);
    final extreme = side == 'LONG' ? rsi >= 72 : rsi <= 28;
    final thinVol = atr < price * 0.0004; // very low ATR ⇒ chop
    String verdict, guidance;
    if (side == 'WAIT') {
      verdict = 'AVOID';
      guidance =
          'No clean edge right now — the indicators disagree (EMA, MACD, RSI and '
          'momentum are mixed), which is typical of chop where scalps get chewed '
          'up. Standing aside IS a position. Wait until EMA9/EMA21 align with the '
          'MACD histogram and RSI is trending (not flat) before committing.';
    } else if (extreme) {
      verdict = 'CAUTION';
      guidance =
          '$side bias, but RSI is ${side == 'LONG' ? 'overbought' : 'oversold'} '
          'at ${rsi.toStringAsFixed(0)} — entering now risks '
          '${side == 'LONG' ? 'buying the top' : 'selling the bottom'} right into '
          'a snap-back. Better: wait for a pullback to EMA9/EMA21, or a confirmed '
          'continuation (break of the last swing) before taking it.';
    } else if (thinVol) {
      verdict = 'CAUTION';
      guidance =
          '$side bias, but volatility (ATR ${f(atr)}) is very low — likely a '
          'consolidation/range where price whipsaws and stops get tapped by '
          'noise. Wait for a volatility expansion or a clean break of the range '
          'before scalping.';
    } else if (conf >= 70) {
      verdict = 'TAKE';
      guidance =
          'Clean $side setup with $conf% confidence: trend, momentum and '
          'RSI all agree. Plan — enter near ${f(entry)}, stop ${f(sl)}, target '
          '${f(tp)} (about 1.5R). Risk only 1–2% of your account, and move the '
          'stop to break-even once price reaches +1R. Skip it if high-impact news '
          'is due within a few minutes.';
    } else {
      verdict = 'CAUTION';
      guidance =
          '$side bias with moderate $conf% confidence — the confluence is '
          'only partial. Either wait for one more confirmation (MACD flip, a break '
          'of structure, or an RSI push through 50), or take it at reduced size '
          'with a tight stop at ${f(sl)}.';
    }

    return Signal(
      verdict: verdict,
      guidance: guidance,
      side: side,
      confidence: conf,
      reasons: reasons,
      price: price,
      entry: entry,
      sl: sl,
      tp: tp,
      rsi: rsi,
      macdHist: macd.hist,
      ema9: e9.last,
      ema21: e21.last,
      atr: atr,
      bb: bb,
    );
  }
}
