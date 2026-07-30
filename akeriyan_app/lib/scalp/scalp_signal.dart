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

    return Signal(
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
