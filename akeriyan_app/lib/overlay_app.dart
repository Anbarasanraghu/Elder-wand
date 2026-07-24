import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'overlay_assistant.dart';

// ---- Glyph palette (local so the overlay isolate is self-contained) ----
const _wand = Color(0xFFDFE9FB); // cool wand-light
const _silver = Color(0xFF8B939D); // secondary
const _ink = Color(0xFFEAEFF6); // moon-white text

/// A slim, Google-style assistant bar shown over other apps. Understated and
/// fast: a small pulsing mic dot, the status or reply text, and a close. No
/// flashy effects. The main app pushes {status, body} via shareData.
class OverlayApp extends StatefulWidget {
  const OverlayApp({super.key});

  @override
  State<OverlayApp> createState() => _OverlayAppState();
}

class _OverlayAppState extends State<OverlayApp>
    with TickerProviderStateMixin {
  String _status = 'Listening…';
  String _body = '';

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();

  bool get _active =>
      !_status.toLowerCase().contains('tap') && _body.isEmpty;

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
    _pulse.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasReply = _body.trim().isNotEmpty;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedBuilder(
            animation: _enter,
            builder: (context, child) {
              final e = Curves.easeOutCubic.transform(_enter.value);
              return Opacity(
                opacity: e,
                child: Transform.translate(
                  offset: Offset(0, -14 * (1 - e)),
                  child: child,
                ),
              );
            },
            child: GestureDetector(
              onTap: hasReply ? () => OverlayAssistant.openApp() : null,
              child: Container(
                margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xF20B0D10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, 8)),
                  ],
                ),
                child: Row(
                  children: [
                    _dot(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        hasReply ? _body.trim() : _status,
                        maxLines: hasReply ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: hasReply ? _ink : _silver,
                          fontSize: hasReply ? 14.5 : 13.5,
                          height: 1.35,
                          fontWeight: hasReply ? FontWeight.w500 : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (hasReply) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.north_east_rounded, size: 16, color: _wand),
                    ],
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => OverlayAssistant.close(),
                      child: const Icon(Icons.close_rounded, size: 18, color: _silver),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Small mic-style dot that softly breathes while active.
  Widget _dot() {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = _active ? _pulse.value : 1.0;
        return Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _wand.withValues(alpha: 0.55 + 0.45 * t),
            boxShadow: _active
                ? [BoxShadow(color: _wand.withValues(alpha: 0.5 * t), blurRadius: 8)]
                : null,
          ),
        );
      },
    );
  }
}
