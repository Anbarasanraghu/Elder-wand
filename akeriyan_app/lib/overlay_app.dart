import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'overlay_assistant.dart';

// ---- Glyph palette (kept local so the overlay isolate is self-contained) ----
const _wand = Color(0xFFDFE9FB); // cool wand-light (primary)
const _bright = Color(0xFFF4F8FF); // brightest lumen
const _steel = Color(0xFF6F80A0); // cool steel
const _silver = Color(0xFF8B939D); // secondary
const _ink = Color(0xFFEAEFF6); // moon-white text
const _glow = Color(0xFF9FC0FF); // cool ambient glow

enum _Mode { listening, thinking, idle }

/// The floating panel shown over other apps — a premium, animated glass card.
/// It does no thinking; the main app pushes {status, body} via shareData and
/// this renders it with a reactive voice-waveform, a sweeping light border,
/// an aura, and a spring entrance.
class OverlayApp extends StatefulWidget {
  const OverlayApp({super.key});

  @override
  State<OverlayApp> createState() => _OverlayAppState();
}

class _OverlayAppState extends State<OverlayApp> with TickerProviderStateMixin {
  String _status = 'Listening…';
  String _body = '';

  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  _Mode get _mode {
    final s = _status.toLowerCase();
    if (s.contains('listen')) return _Mode.listening;
    if (s.contains('think')) return _Mode.thinking;
    return _Mode.idle;
  }

  @override
  void initState() {
    super.initState();
    FlutterOverlayWindow.overlayListener.listen((event) {
      try {
        final m = jsonDecode(event as String) as Map<String, dynamic>;
        setState(() {
          final st = (m['status'] as String?) ?? '';
          if (st.isNotEmpty) _status = st;
          _body = (m['body'] as String?) ?? _body;
        });
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _loop.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedBuilder(
            animation: _enter,
            builder: (context, child) {
              final e = Curves.easeOutBack.transform(_enter.value.clamp(0, 1));
              final fade = Curves.easeOut.transform(_enter.value.clamp(0, 1));
              return Opacity(
                opacity: fade,
                child: Transform.translate(
                  offset: Offset(0, -26 * (1 - e)),
                  child: Transform.scale(
                    scale: 0.92 + 0.08 * e,
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
                ),
              );
            },
            child: _panel(),
          ),
        ),
      ),
    );
  }

  Widget _panel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: AnimatedBuilder(
        animation: _loop,
        builder: (context, _) {
          return CustomPaint(
            foregroundPainter: _SweepBorder(_loop.value),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xF2141821), Color(0xF6080A0E)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _glow.withValues(alpha: 0.18),
                    blurRadius: 40,
                    spreadRadius: -6,
                    offset: const Offset(0, 10),
                  ),
                  const BoxShadow(
                    color: Colors.black87,
                    blurRadius: 30,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 15, 14, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _header(),
                      const SizedBox(height: 14),
                      _visual(),
                      const SizedBox(height: 12),
                      _statusLine(),
                      if (_body.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _reply(),
                      ],
                      const SizedBox(height: 16),
                      _openButton(),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        // glyph mark: a small ringed dot
        SizedBox(
          width: 20,
          height: 20,
          child: CustomPaint(painter: _GlyphMark(_loop.value)),
        ),
        const SizedBox(width: 10),
        const Text(
          'ELDER WAND',
          style: TextStyle(
            color: _wand,
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            letterSpacing: 3.4,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => OverlayAssistant.close(),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: const Icon(Icons.close_rounded, size: 15, color: _silver),
          ),
        ),
      ],
    );
  }

  Widget _visual() {
    return SizedBox(
      height: 64,
      width: double.infinity,
      child: CustomPaint(painter: _Waveform(_loop.value, _mode)),
    );
  }

  Widget _statusLine() {
    return Row(
      children: [
        _dot(),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            _status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _silver,
              fontSize: 12.5,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _dot() {
    final on = _mode != _Mode.idle;
    return AnimatedBuilder(
      animation: _loop,
      builder: (context, _) {
        final p = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(_loop.value * math.pi * 6));
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? _wand.withValues(alpha: p) : _steel,
            boxShadow: on
                ? [BoxShadow(color: _glow.withValues(alpha: 0.6 * p), blurRadius: 8)]
                : null,
          ),
        );
      },
    );
  }

  Widget _reply() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: SingleChildScrollView(
        child: Text(
          _body.trim(),
          style: const TextStyle(
            color: _ink,
            fontSize: 15.5,
            height: 1.42,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _openButton() {
    return GestureDetector(
      onTap: () => OverlayAssistant.openApp(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: const LinearGradient(
            colors: [_bright, _wand],
          ),
          boxShadow: [
            BoxShadow(
              color: _glow.withValues(alpha: 0.45),
              blurRadius: 22,
              spreadRadius: -4,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome, size: 16, color: Color(0xFF0A0C10)),
            SizedBox(width: 8),
            Text(
              'Open our space',
              style: TextStyle(
                color: Color(0xFF0A0C10),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reactive voice waveform: a row of glowing bars whose heights ripple. In
/// listening mode they breathe with a centered bell envelope; in thinking mode
/// a bright pulse travels across; idle is a calm low shimmer.
class _Waveform extends CustomPainter {
  final double t;
  final _Mode mode;
  _Waveform(this.t, this.mode);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Aura behind the bars.
    final aura = Paint()
      ..shader = RadialGradient(
        colors: [_glow.withValues(alpha: 0.22), Colors.transparent],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: size.width * 0.42));
    canvas.drawCircle(Offset(cx, cy), size.width * 0.42, aura);

    const bars = 28;
    final gap = size.width / (bars + 2);
    final barW = gap * 0.5;
    final speed = mode == _Mode.listening
        ? 8.0
        : mode == _Mode.thinking
            ? 5.0
            : 2.2;
    final phase = t * math.pi * 2 * speed;

    for (var i = 0; i < bars; i++) {
      final x = gap * (i + 1.5);
      final n = i / (bars - 1); // 0..1
      // centered bell so the middle bars are tallest
      final bell = math.exp(-math.pow((n - 0.5) * 2.6, 2).toDouble());

      double amp;
      switch (mode) {
        case _Mode.listening:
          amp = 0.30 + 0.70 * (0.5 + 0.5 * math.sin(phase + i * 0.55));
          amp *= bell;
        case _Mode.thinking:
          // a travelling gaussian pulse
          final pos = (t * 1.6) % 1.0;
          final d = (n - pos);
          amp = 0.25 + 0.85 * math.exp(-math.pow(d * 6, 2).toDouble());
        case _Mode.idle:
          amp = 0.14 + 0.16 * (0.5 + 0.5 * math.sin(phase + i * 0.7)) * bell;
      }

      final h = (size.height * 0.9) * amp.clamp(0.05, 1.0);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, cy), width: barW, height: h),
        Radius.circular(barW),
      );
      final shade = Color.lerp(_steel, _bright, (amp * bell + 0.2).clamp(0, 1))!;
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [shade, _wand.withValues(alpha: 0.65)],
        ).createShader(rect.outerRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6);
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _Waveform old) => true;
}

/// A light that sweeps around the panel's rounded border.
class _SweepBorder extends CustomPainter {
  final double t;
  _SweepBorder(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(26),
    );
    final sweep = SweepGradient(
      startAngle: 0,
      endAngle: math.pi * 2,
      transform: GradientRotation(t * math.pi * 2),
      colors: const [
        Color(0x00DFE9FB),
        Color(0x22DFE9FB),
        Color(0xCCF4F8FF), // bright arc
        Color(0x22DFE9FB),
        Color(0x00DFE9FB),
      ],
      stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..shader = sweep.createShader(Offset.zero & size);
    canvas.drawRRect(rrect.deflate(0.7), paint);

    // faint static hairline so the edge always reads
    canvas.drawRRect(
      rrect.deflate(0.7),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.05),
    );
  }

  @override
  bool shouldRepaint(covariant _SweepBorder old) => old.t != t;
}

/// Small ringed-dot brand mark that gently pulses.
class _GlyphMark extends CustomPainter {
  final double t;
  _GlyphMark(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final p = 0.5 + 0.5 * math.sin(t * math.pi * 4);
    canvas.drawCircle(
      c,
      r * (0.72 + 0.12 * p),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = _wand.withValues(alpha: 0.55 + 0.35 * p),
    );
    canvas.drawCircle(
      c,
      r * 0.28,
      Paint()
        ..color = _bright
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.5 + p),
    );
    canvas.drawCircle(c, r * 0.22, Paint()..color = _bright);
  }

  @override
  bool shouldRepaint(covariant _GlyphMark old) => old.t != t;
}
