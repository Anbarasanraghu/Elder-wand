import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// Google/Gemini-style animated multi-colour gradient border around a box.
/// A rotating sweep gradient forms a glowing ring; the inside stays on-theme.
class GradientBorder extends StatefulWidget {
  final Widget child;
  final double radius;
  final double thickness;
  final EdgeInsetsGeometry padding;
  final Color fill;
  final bool glow;

  const GradientBorder({
    super.key,
    required this.child,
    this.radius = 16,
    this.thickness = 1.8,
    this.padding = const EdgeInsets.all(16),
    this.fill = Ak.bg1,
    this.glow = true,
  });

  // Gemini-ish flowing palette (loops back to the first for a seamless spin).
  static const List<Color> colors = [
    Color(0xFF4285F4), // blue
    Color(0xFF9B72CB), // purple
    Color(0xFFD96570), // pink
    Color(0xFF00BCD4), // cyan
    Color(0xFF4285F4),
  ];

  @override
  State<GradientBorder> createState() => _GradientBorderState();
}

class _GradientBorderState extends State<GradientBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 5))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final sweep = SweepGradient(
          colors: GradientBorder.colors,
          transform: GradientRotation(_c.value * 2 * math.pi),
        );
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: sweep,
            boxShadow: widget.glow
                ? [
                    BoxShadow(
                      color: GradientBorder.colors[
                              (_c.value * 4).floor() % 4]
                          .withAlpha(70),
                      blurRadius: 18,
                      spreadRadius: -2,
                    )
                  ]
                : null,
          ),
          padding: EdgeInsets.all(widget.thickness),
          child: Container(
            decoration: BoxDecoration(
              color: widget.fill,
              borderRadius:
                  BorderRadius.circular(widget.radius - widget.thickness),
            ),
            padding: widget.padding,
            child: widget.child,
          ),
        );
      },
    );
  }
}
