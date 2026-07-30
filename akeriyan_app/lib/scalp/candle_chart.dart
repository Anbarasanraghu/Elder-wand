import 'package:flutter/material.dart';

import '../theme.dart';
import 'liquidity.dart';
import 'scalp_data.dart';

/// Lightweight candlestick chart with EMA9/EMA21 overlays + liquidity levels —
/// CustomPainter, no chart dependency.
class CandleChart extends StatelessWidget {
  final List<Candle> candles;
  final List<LiqLevel> levels;
  const CandleChart({super.key, required this.candles, this.levels = const []});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CandlePainter(candles, levels),
      size: Size.infinite,
    );
  }
}

class _CandlePainter extends CustomPainter {
  final List<Candle> c;
  final List<LiqLevel> levels;
  _CandlePainter(this.c, this.levels);

  @override
  void paint(Canvas canvas, Size size) {
    if (c.length < 2) return;
    // show the most recent N candles that fit
    final maxN = (size.width / 7).floor().clamp(20, 160);
    final data = c.length > maxN ? c.sublist(c.length - maxN) : c;

    double lo = data.first.l, hi = data.first.h;
    for (final k in data) {
      if (k.l < lo) lo = k.l;
      if (k.h > hi) hi = k.h;
    }
    final pad = (hi - lo) * 0.08 + 1e-9;
    lo -= pad;
    hi += pad;
    final range = hi - lo;
    double y(double v) => size.height - (v - lo) / range * size.height;

    // grid
    final grid = Paint()..color = Ak.glassLine..strokeWidth = 0.5;
    for (var i = 1; i < 4; i++) {
      final gy = size.height * i / 4;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }

    final w = size.width / data.length;
    final bodyW = (w * 0.62).clamp(1.5, 9.0);
    for (var i = 0; i < data.length; i++) {
      final k = data[i];
      final x = w * i + w / 2;
      final up = k.c >= k.o;
      final col = up ? Ak.up : Ak.down;
      final wick = Paint()..color = col..strokeWidth = 1;
      canvas.drawLine(Offset(x, y(k.h)), Offset(x, y(k.l)), wick);
      final top = y(up ? k.c : k.o);
      final bot = y(up ? k.o : k.c);
      final body = Paint()..color = col;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x - bodyW / 2, top, x + bodyW / 2, bot + 0.5),
          const Radius.circular(1.5),
        ),
        body,
      );
    }

    // EMA overlays
    void ema(int p, Color color) {
      final closes = c.map((e) => e.c).toList();
      final e = Indicators.ema(closes, p);
      final seg = e.length > data.length ? e.sublist(e.length - data.length) : e;
      final path = Path();
      for (var i = 0; i < seg.length; i++) {
        final x = w * i + w / 2;
        final yy = y(seg[i]);
        if (i == 0) {
          path.moveTo(x, yy);
        } else {
          path.lineTo(x, yy);
        }
      }
      canvas.drawPath(
          path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.4);
    }

    ema(9, Ak.purple);
    ema(21, Ak.violet.withValues(alpha: 0.8));

    // liquidity levels (dashed): buy-side above = red, sell-side below = green
    for (final lv in levels) {
      if (lv.price < lo || lv.price > hi) continue;
      final ly = y(lv.price);
      final col = (lv.buySide ? Ak.down : Ak.up).withValues(alpha: 0.55);
      final p = Paint()..color = col..strokeWidth = 1;
      for (double dx = 0; dx < size.width - 4; dx += 8) {
        canvas.drawLine(Offset(dx, ly), Offset(dx + 4, ly), p);
      }
      final tp = TextPainter(
        text: TextSpan(
            text: '${lv.buySide ? 'BSL' : 'SSL'} ×${lv.touches}',
            style: TextStyle(color: col, fontSize: 8, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, ly - 10));
    }

    // last price line + label
    final last = data.last.c;
    final ly = y(last);
    final lp = Paint()
      ..color = Ak.textMid.withValues(alpha: 0.6)
      ..strokeWidth = 0.7;
    for (double dx = 0; dx < size.width; dx += 6) {
      canvas.drawLine(Offset(dx, ly), Offset(dx + 3, ly), lp);
    }
    final tp = TextPainter(
      text: TextSpan(
          text: last.toStringAsFixed(last > 100 ? 2 : 4),
          style: const TextStyle(color: Ak.textHi, fontSize: 10, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    final bg = Rect.fromLTWH(size.width - tp.width - 10, ly - 8, tp.width + 8, 16);
    canvas.drawRRect(RRect.fromRectAndRadius(bg, const Radius.circular(3)),
        Paint()..color = Ak.bg2);
    tp.paint(canvas, Offset(size.width - tp.width - 6, ly - 7));
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) => true;
}
