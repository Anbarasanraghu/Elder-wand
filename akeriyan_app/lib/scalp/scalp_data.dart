import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Twelve Data config (free API key) + the symbols the terminal trades.
class ScalpConfig {
  static const _k = 'td_api_key';
  static const symbols = <String>[
    'XAU/USD', 'EUR/USD', 'GBP/USD', 'USD/JPY', 'AUD/USD', 'USD/CAD', 'XAG/USD'
  ];

  static Future<String> key() async =>
      (await SharedPreferences.getInstance()).getString(_k) ?? '';
  static Future<void> setKey(String v) async =>
      (await SharedPreferences.getInstance()).setString(_k, v.trim());
}

class NoApiKey implements Exception {}

class Candle {
  final DateTime t;
  final double o, h, l, c;
  Candle(this.t, this.o, this.h, this.l, this.c);
}

class TdClient {
  /// Candles for a symbol/interval ("1min" | "5min"), oldest→newest.
  static Future<List<Candle>> candles(String symbol, String interval,
      {int size = 120}) async {
    final key = await ScalpConfig.key();
    if (key.isEmpty) throw NoApiKey();
    final url = 'https://api.twelvedata.com/time_series'
        '?symbol=${Uri.encodeComponent(symbol)}&interval=$interval'
        '&outputsize=$size&order=ASC&apikey=$key';
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (j['status'] == 'error') {
      throw '${j['message'] ?? 'Twelve Data error'}';
    }
    final vals = (j['values'] as List?) ?? [];
    return vals
        .map((v) => Candle(
              DateTime.parse('${v['datetime']}'),
              double.parse('${v['open']}'),
              double.parse('${v['high']}'),
              double.parse('${v['low']}'),
              double.parse('${v['close']}'),
            ))
        .toList();
  }
}

/// Technical indicators computed on-device from candles.
class Indicators {
  static List<double> ema(List<double> x, int p) {
    if (x.isEmpty) return [];
    final k = 2 / (p + 1);
    final out = <double>[];
    double e = x.first;
    for (final v in x) {
      e = v * k + e * (1 - k);
      out.add(e);
    }
    return out;
  }

  static double rsi(List<double> x, int p) {
    if (x.length <= p) return 50;
    double g = 0, l = 0;
    for (var i = x.length - p; i < x.length; i++) {
      final d = x[i] - x[i - 1];
      if (d >= 0) {
        g += d;
      } else {
        l -= d;
      }
    }
    final al = l / p;
    if (al == 0) return 100;
    final rs = (g / p) / al;
    return 100 - 100 / (1 + rs);
  }

  static ({double macd, double signal, double hist}) macd(List<double> x) {
    if (x.length < 26) return (macd: 0, signal: 0, hist: 0);
    final e12 = ema(x, 12), e26 = ema(x, 26);
    final m = [for (var i = 0; i < x.length; i++) e12[i] - e26[i]];
    final sig = ema(m, 9);
    return (macd: m.last, signal: sig.last, hist: m.last - sig.last);
  }

  static ({double up, double mid, double low}) bollinger(
      List<double> x, int p, double k) {
    if (x.length < p) return (up: 0, mid: 0, low: 0);
    final seg = x.sublist(x.length - p);
    final mean = seg.reduce((a, b) => a + b) / p;
    final varr =
        seg.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / p;
    final sd = math.sqrt(varr);
    return (up: mean + k * sd, mid: mean, low: mean - k * sd);
  }

  static double atr(List<Candle> c, int p) {
    if (c.length <= p) return 0;
    double s = 0;
    for (var i = c.length - p; i < c.length; i++) {
      final tr = math.max(
          c[i].h - c[i].l,
          math.max((c[i].h - c[i - 1].c).abs(), (c[i].l - c[i - 1].c).abs()));
      s += tr;
    }
    return s / p;
  }
}
