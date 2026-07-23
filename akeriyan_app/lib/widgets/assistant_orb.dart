import 'dart:math' as math;
import 'package:flutter/material.dart';

enum OrbState { idle, listening, recording, thinking, speaking }

/// The Elder Wand core: a sphere made of orbiting particles (points evenly
/// spread on a sphere, rotated in 3D and projected to 2D). Monochrome cool
/// "wand-light" — the only light on screen. Reacts to state.
class AssistantOrb extends StatefulWidget {
  final OrbState state;
  final double size;
  const AssistantOrb({super.key, required this.state, this.size = 240});

  @override
  State<AssistantOrb> createState() => _AssistantOrbState();
}

class _AssistantOrbState extends State<AssistantOrb>
    with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 16))
        ..repeat();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))
        ..repeat();

  late final List<List<double>> _pts = _fibonacciSphere(150);

  static List<List<double>> _fibonacciSphere(int n) {
    final out = <List<double>>[];
    final phi = math.pi * (3 - math.sqrt(5)); // golden angle
    for (var i = 0; i < n; i++) {
      final y = 1 - (i / (n - 1)) * 2; // 1 → -1
      final r = math.sqrt(1 - y * y);
      final th = phi * i;
      out.add([math.cos(th) * r, y, math.sin(th) * r]);
    }
    return out;
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.state == OrbState.listening ||
        widget.state == OrbState.recording;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_spin, _pulse]),
        builder: (_, _) {
          final breathe = 0.5 + 0.5 * math.sin(_pulse.value * 2 * math.pi);
          return CustomPaint(
            painter: _ParticleOrbPainter(
              points: _pts,
              spin: _spin.value * 2 * math.pi * (active ? 2.2 : 1),
              breathe: breathe,
              active: active,
              thinking: widget.state == OrbState.thinking,
              speaking: widget.state == OrbState.speaking,
            ),
          );
        },
      ),
    );
  }
}

class _ParticleOrbPainter extends CustomPainter {
  final List<List<double>> points;
  final double spin, breathe;
  final bool active, thinking, speaking;

  _ParticleOrbPainter({
    required this.points,
    required this.spin,
    required this.breathe,
    required this.active,
    required this.thinking,
    required this.speaking,
  });

  static const _lumen = Color(0xFFDFE9FB);
  static const _lumenBright = Color(0xFFF4F8FF);
  static const _glowBlue = Color(0xFF96BEFF);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final energy = active
        ? 1.0
        : thinking
            ? 0.92
            : speaking
                ? 0.9
                : 0.78;
    final R = size.width * 0.33 * (1 + 0.03 * breathe + (active ? 0.05 : 0));

    // Outer halo glow.
    final glowR = R * 1.9;
    canvas.drawCircle(
      Offset(cx, cy),
      glowR,
      Paint()
        ..shader = RadialGradient(colors: [
          _glowBlue.withValues(
              alpha: 0.16 + 0.10 * breathe + (active ? 0.10 : 0)),
          _glowBlue.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: glowR)),
    );

    // Inner core light.
    final coreR = R * 0.55;
    canvas.drawCircle(
      Offset(cx, cy),
      coreR,
      Paint()
        ..shader = RadialGradient(colors: [
          _lumenBright.withValues(alpha: (0.45 + 0.25 * breathe) * energy),
          _lumenBright.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: coreR)),
    );

    // Project & depth-sort the particles.
    const tilt = 0.42;
    final cosT = math.cos(tilt), sinT = math.sin(tilt);
    final cosY = math.cos(spin), sinY = math.sin(spin);
    final proj = <List<double>>[]; // [sx, sy, depth]
    for (final p in points) {
      var x = p[0], y = p[1], z = p[2];
      if (thinking) {
        // twist by latitude for a swirling "thinking" feel
        final tw = y * 1.5;
        final cz = math.cos(tw), sz = math.sin(tw);
        final nx = x * cz - z * sz;
        z = x * sz + z * cz;
        x = nx;
      }
      // rotate around Y, then tilt around X
      final rx = x * cosY - z * sinY;
      z = x * sinY + z * cosY;
      x = rx;
      final ry = y * cosT - z * sinT;
      z = y * sinT + z * cosT;
      y = ry;
      proj.add([cx + x * R, cy + y * R, (z + 1) / 2]);
    }
    proj.sort((a, b) => a[2].compareTo(b[2]));

    final dot = Paint();
    for (final pr in proj) {
      final depth = pr[2]; // 0 back → 1 front
      final radius = 1.0 + depth * 2.3;
      final alpha = ((0.10 + depth * 0.8) * energy).clamp(0.0, 1.0);
      dot.color = (depth > 0.72 ? _lumenBright : _lumen).withValues(alpha: alpha);
      canvas.drawCircle(Offset(pr[0], pr[1]), radius, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticleOrbPainter old) => true;
}
