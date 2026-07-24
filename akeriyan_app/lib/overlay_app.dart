import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'overlay_assistant.dart';

/// The floating panel shown over other apps (its own tiny Flutter isolate).
/// It does no thinking — the main app pushes {status, body} via shareData and
/// this just renders it, like Google's assistant overlay.
class OverlayApp extends StatefulWidget {
  const OverlayApp({super.key});

  @override
  State<OverlayApp> createState() => _OverlayAppState();
}

class _OverlayAppState extends State<OverlayApp>
    with SingleTickerProviderStateMixin {
  String _status = 'Listening…';
  String _body = '';
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    FlutterOverlayWindow.overlayListener.listen((event) {
      try {
        final m = jsonDecode(event as String) as Map<String, dynamic>;
        setState(() {
          _status = (m['status'] as String?)?.isNotEmpty == true
              ? m['status'] as String
              : _status;
          _body = (m['body'] as String?) ?? _body;
        });
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const wand = Color(0xFFDFE9FB);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
            decoration: BoxDecoration(
              color: const Color(0xF20B0D10), // near-opaque obsidian
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 24, spreadRadius: 2),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    FadeTransition(
                      opacity: Tween(begin: 0.35, end: 1.0).animate(_pulse),
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                            color: wand, shape: BoxShape.circle),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text('Elder Wand',
                        style: TextStyle(
                            color: wand,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => OverlayAssistant.close(),
                      child: const Icon(Icons.close,
                          size: 18, color: Color(0xFF8B939D)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(_status,
                    style: const TextStyle(
                        color: Color(0xFF8B939D), fontSize: 13)),
                if (_body.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SingleChildScrollView(
                      child: Text(_body,
                          style: const TextStyle(
                              color: Color(0xFFEAEFF6),
                              fontSize: 15,
                              height: 1.4)),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => OverlayAssistant.openApp(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: wand.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_full, size: 15, color: wand),
                        SizedBox(width: 8),
                        Text('Open the app',
                            style: TextStyle(
                                color: wand,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
