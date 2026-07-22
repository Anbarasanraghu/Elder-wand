import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

enum OrbState { idle, listening, recording, thinking, speaking }

/// The glowing, breathing AI orb at the heart of AKERIYAN.
/// Flows a Google/Gemini-style multi-colour gradient — pure Flutter.
class AssistantOrb extends StatefulWidget {
  final OrbState state;
  final double size;
  const AssistantOrb({super.key, required this.state, this.size = 240});

  @override
  State<AssistantOrb> createState() => _AssistantOrbState();
}

class _AssistantOrbState extends State<AssistantOrb>
    with TickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))
        ..repeat();
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))
        ..repeat();

  // Gemini-style flowing palette.
  static const _blue = Color(0xFF4285F4);
  static const _purple = Color(0xFF9B72CB);
  static const _pink = Color(0xFFD96570);
  static const _cyan = Color(0xFF00BCD4);

  @override
  void dispose() {
    _pulse.dispose();
    _spin.dispose();
    super.dispose();
  }

  List<Color> get _palette {
    switch (widget.state) {
      case OrbState.recording:
        return const [_pink, _purple, _blue, _pink];
      case OrbState.thinking:
        return const [_purple, _cyan, _blue, _purple];
      default:
        return const [_blue, _purple, _pink, _cyan, _blue];
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulse, _spin]),
        builder: (_, _) {
          final breathe = 0.5 + 0.5 * math.sin(_pulse.value * 2 * math.pi);
          return CustomPaint(
            painter: _OrbPainter(
              t: breathe,
              spin: _spin.value * 2 * math.pi,
              palette: _palette,
              active: widget.state != OrbState.idle,
              thinking: widget.state == OrbState.thinking,
            ),
          );
        },
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double t; // 0..1 breathing
  final double spin; // radians
  final List<Color> palette;
  final bool active;
  final bool thinking;

  _OrbPainter({
    required this.t,
    required this.spin,
    required this.palette,
    required this.active,
    required this.thinking,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final c1 = palette.first;
    final c2 = palette.length > 2 ? palette[2] : palette.last;

    final pulseAmt = active ? 0.10 : 0.05;
    final coreR = r * (0.52 + pulseAmt * t);

    // Outer aura glow (blends two palette colours).
    final aura = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.lerp(c1, c2, t)!.withAlpha((90 * (0.6 + 0.4 * t)).round()),
          c1.withAlpha(0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    canvas.drawCircle(center, r * (0.85 + 0.15 * t), aura);

    // Rotating multi-colour ring (energy) — full Gemini sweep.
    final ringRect = Rect.fromCircle(center: center, radius: coreR + r * 0.14);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.035
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        transform: GradientRotation(spin),
        colors: palette,
      ).createShader(ringRect);
    final sweep = thinking ? math.pi * 1.3 : math.pi * 2;
    canvas.drawArc(ringRect, spin, sweep, false, ring);

    // Core sphere — colourful multi-stop radial with a bright highlight.
    final core = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.4),
        colors: [
          Color.lerp(palette[0], Colors.white, 0.55)!,
          palette[0],
          palette.length > 1 ? palette[1] : palette[0],
          Color.lerp(c2, Ak.bg0, 0.2)!,
        ],
        stops: const [0.0, 0.4, 0.72, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: coreR));
    canvas.drawCircle(center, coreR, core);

    // Inner glossy highlight.
    final gloss = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white.withAlpha(70), Colors.white.withAlpha(0)],
      ).createShader(Rect.fromCircle(
          center: center.translate(-coreR * 0.28, -coreR * 0.32),
          radius: coreR * 0.6));
    canvas.drawCircle(
        center.translate(-coreR * 0.28, -coreR * 0.32), coreR * 0.55, gloss);

    // Rim light.
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withAlpha(40);
    canvas.drawCircle(center, coreR, rim);
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.t != t || old.spin != spin || old.thinking != thinking;
}
