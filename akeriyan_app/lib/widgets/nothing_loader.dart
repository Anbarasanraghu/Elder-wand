import 'package:flutter/material.dart';
import '../theme.dart';

/// Nothing-OS style loader: a big dot-matrix percentage that counts up (0→99)
/// with a segmented purple progress bar. Self-animating "estimated progress" —
/// it eases toward 99 while the real request is in flight and is removed by the
/// parent when the data arrives.
class NothingLoader extends StatefulWidget {
  final String? label;
  final int segments;

  /// Seconds the count takes to ease from 0 toward 99. Longer = slower crawl.
  final int duration;

  const NothingLoader({
    super.key,
    this.label,
    this.segments = 22,
    this.duration = 16,
  });

  @override
  State<NothingLoader> createState() => _NothingLoaderState();
}

class _NothingLoaderState extends State<NothingLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: Duration(seconds: widget.duration))
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = Curves.easeOut.transform(_c.value);
          final pct = (t * 100).clamp(0, 99).round();
          final filled = (pct / 100 * widget.segments).round();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pct.toString().padLeft(2, '0'),
                      style: Ak.display(size: 64, color: Ak.textHi, spacing: 3)),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('%', style: Ak.display(size: 18, color: Ak.textLo)),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.segments, (i) {
                  final on = i < filled;
                  return Container(
                    width: 6,
                    height: 16,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: on ? Ak.purple : Ak.glassLine,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: on
                          ? Ak.glow(Ak.purple.withAlpha(90), blur: 8)
                          : null,
                    ),
                  );
                }),
              ),
              if (widget.label != null) ...[
                const SizedBox(height: 20),
                Text(widget.label!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Ak.textMid, fontSize: 13)),
              ],
            ],
          );
        },
      ),
    );
  }
}
