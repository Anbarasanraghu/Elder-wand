import 'scalp_data.dart';

/// A resting-liquidity pool (cluster of equal highs = buy-side, or equal
/// lows = sell-side) where stop orders tend to sit — prime sweep targets.
class LiqLevel {
  final double price;
  final int touches;
  final bool buySide; // true = above (buy-side), false = below (sell-side)
  LiqLevel(this.price, this.touches, this.buySide);
}

class Liquidity {
  final List<LiqLevel> pools;
  final double? nearestAbove;
  final double? nearestBelow;
  final String hunt; // plain-language read of the likely liquidity hunt
  Liquidity(this.pools, this.nearestAbove, this.nearestBelow, this.hunt);
}

/// Finds liquidity pools (ICT-style) from swing pivots + equal-level clustering.
class LiquidityFinder {
  static String _f(double v) => v.toStringAsFixed(v > 100 ? 2 : 4);

  static Liquidity analyze(List<Candle> c) {
    if (c.length < 12) return Liquidity(const [], null, null, 'Not enough data.');
    const n = 2; // pivot lookback each side
    final highs = <double>[], lows = <double>[];
    for (var i = n; i < c.length - n; i++) {
      var ph = true, pl = true;
      for (var j = i - n; j <= i + n; j++) {
        if (c[j].h > c[i].h) ph = false;
        if (c[j].l < c[i].l) pl = false;
      }
      if (ph) highs.add(c[i].h);
      if (pl) lows.add(c[i].l);
    }
    final atr = Indicators.atr(c, 14);
    final tol = (atr * 0.3) + (c.last.c * 1e-5); // "equal" tolerance

    List<LiqLevel> cluster(List<double> arr, bool buy) {
      arr.sort();
      final out = <LiqLevel>[];
      var i = 0;
      while (i < arr.length) {
        var sum = arr[i];
        var cnt = 1;
        var j = i + 1;
        while (j < arr.length && (arr[j] - arr[i]).abs() <= tol) {
          sum += arr[j];
          cnt++;
          j++;
        }
        if (cnt >= 2) out.add(LiqLevel(sum / cnt, cnt, buy)); // pool: 2+ touches
        i = j;
      }
      return out;
    }

    final pools = [...cluster(highs, true), ...cluster(lows, false)]
      ..sort((a, b) => b.touches.compareTo(a.touches));
    final price = c.last.c;
    final above = pools.where((p) => p.price > price).map((p) => p.price).toList()
      ..sort();
    final below = pools.where((p) => p.price < price).map((p) => p.price).toList()
      ..sort();
    final nearestAbove = above.isEmpty ? null : above.first;
    final nearestBelow = below.isEmpty ? null : below.last;

    final dA = nearestAbove != null ? (nearestAbove - price).abs() : double.infinity;
    final dB = nearestBelow != null ? (price - nearestBelow).abs() : double.infinity;
    String hunt;
    if (dA == double.infinity && dB == double.infinity) {
      hunt = 'No clear equal-highs/lows pools nearby — no obvious liquidity to hunt right now.';
    } else if (dA <= dB) {
      hunt = 'Buy-side liquidity resting above at ${_f(nearestAbove!)}. '
          'Price may sweep those equal highs to grab stops before reversing — '
          'watch for a sweep + rejection to short, or a clean break-and-hold to ride up.';
    } else {
      hunt = 'Sell-side liquidity resting below at ${_f(nearestBelow!)}. '
          'Price may sweep those equal lows to grab stops before reversing — '
          'watch for a sweep + rejection to long, or a clean break-and-hold to ride down.';
    }
    return Liquidity(pools, nearestAbove, nearestBelow, hunt);
  }
}
