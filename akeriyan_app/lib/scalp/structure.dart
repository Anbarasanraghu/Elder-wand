import 'scalp_data.dart';

class Zone {
  final double low, high;
  final bool bull;
  Zone(this.low, this.high, this.bull);
  double get mid => (low + high) / 2;
}

/// Pro-grade market structure read from candles: bias, trend strength, key
/// support/resistance, order block, fair-value gap, break-of-structure, and
/// the active trading session.
class MarketStructure {
  final String bias; // Bullish | Bearish | Ranging
  final int trendStrength; // 0..100
  final List<double> resistance;
  final List<double> support;
  final Zone? orderBlock;
  final Zone? fvg;
  final String? bos; // "Bullish BOS" | "Bearish BOS" | null
  final String session; // e.g. "London + New York (peak)"
  final bool sessionHot;

  MarketStructure({
    required this.bias,
    required this.trendStrength,
    required this.resistance,
    required this.support,
    required this.orderBlock,
    required this.fvg,
    required this.bos,
    required this.session,
    required this.sessionHot,
  });
}

class StructureFinder {
  static ({String name, bool hot}) session(DateTime utc) {
    final h = utc.hour + utc.minute / 60.0;
    final london = h >= 8 && h < 17;
    final ny = h >= 13 && h < 22;
    final tokyo = h >= 0 && h < 9;
    if (london && ny) return (name: 'London + New York (peak)', hot: true);
    if (london) return (name: 'London', hot: true);
    if (ny) return (name: 'New York', hot: true);
    if (tokyo) return (name: 'Tokyo / Asian', hot: false);
    if (h >= 22 || h < 8) return (name: 'Sydney / Asian', hot: false);
    return (name: 'Off-session', hot: false);
  }

  static MarketStructure analyze(List<Candle> c) {
    final closes = c.map((e) => e.c).toList();
    final price = closes.last;
    final e9 = Indicators.ema(closes, 9).last;
    final e21 = Indicators.ema(closes, 21).last;
    final e50 = closes.length >= 50 ? Indicators.ema(closes, 50).last : e21;
    final atr = Indicators.atr(c, 14);

    String bias;
    if (e9 > e21 && e21 > e50 && price > e50) {
      bias = 'Bullish';
    } else if (e9 < e21 && e21 < e50 && price < e50) {
      bias = 'Bearish';
    } else {
      bias = 'Ranging';
    }
    final strength = ((e9 - e50).abs() / (price == 0 ? 1 : price) * 400 * 100)
        .clamp(0, 100)
        .round();

    // pivots
    const n = 2;
    final pHigh = <double>[], pLow = <double>[];
    int? lastSwingHiIdx, lastSwingLoIdx;
    for (var i = n; i < c.length - n; i++) {
      var ph = true, pl = true;
      for (var j = i - n; j <= i + n; j++) {
        if (c[j].h > c[i].h) ph = false;
        if (c[j].l < c[i].l) pl = false;
      }
      if (ph) {
        pHigh.add(c[i].h);
        lastSwingHiIdx = i;
      }
      if (pl) {
        pLow.add(c[i].l);
        lastSwingLoIdx = i;
      }
    }
    List<double> pick(List<double> arr, bool above) {
      final tol = atr * 0.25 + price * 1e-5;
      final f = arr.where((v) => above ? v > price : v < price).toList()
        ..sort();
      final out = <double>[];
      for (final v in (above ? f : f.reversed)) {
        if (out.every((o) => (o - v).abs() > tol)) out.add(v);
        if (out.length >= 3) break;
      }
      return out;
    }

    final resistance = pick(pHigh, true);
    final support = pick(pLow, false);

    // break of structure
    String? bos;
    if (lastSwingHiIdx != null &&
        price > c[lastSwingHiIdx].h &&
        bias != 'Bearish') {
      bos = 'Bullish BOS';
    } else if (lastSwingLoIdx != null &&
        price < c[lastSwingLoIdx].l &&
        bias != 'Bullish') {
      bos = 'Bearish BOS';
    }

    // order block: last opposite candle before a strong impulse
    Zone? ob;
    for (var i = c.length - 2; i > 2 && i > c.length - 30; i--) {
      final body = (c[i].c - c[i].o);
      if (body > atr * 0.9 && c[i - 1].c < c[i - 1].o) {
        ob = Zone(c[i - 1].l, c[i - 1].h, true); // bullish OB
        break;
      }
      if (-body > atr * 0.9 && c[i - 1].c > c[i - 1].o) {
        ob = Zone(c[i - 1].l, c[i - 1].h, false); // bearish OB
        break;
      }
    }

    // fair value gap (3-candle imbalance), nearest unfilled
    Zone? fvg;
    for (var i = c.length - 2; i > 1 && i > c.length - 30; i--) {
      if (c[i - 1].h < c[i + 1].l) {
        final z = Zone(c[i - 1].h, c[i + 1].l, true);
        if (price >= z.low) {
          fvg = z;
          break;
        }
      }
      if (c[i - 1].l > c[i + 1].h) {
        final z = Zone(c[i + 1].h, c[i - 1].l, false);
        if (price <= z.high) {
          fvg = z;
          break;
        }
      }
    }

    final ss = session(DateTime.now().toUtc());
    return MarketStructure(
      bias: bias,
      trendStrength: strength,
      resistance: resistance,
      support: support,
      orderBlock: ob,
      fvg: fvg,
      bos: bos,
      session: ss.name,
      sessionHot: ss.hot,
    );
  }
}
