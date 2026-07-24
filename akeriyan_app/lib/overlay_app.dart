import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'overlay_assistant.dart';

// ---- palette (local so the overlay isolate is self-contained) ----
const _wand = Color(0xFFDFE9FB); // cool wand-light accent
const _ink = Color(0xFFF6F8FC); // near-white text
const _dark = Color(0xFF2C3038); // dark circular buttons / avatar

/// Frosted-glass assistant card shown over other apps (bottom of screen).
/// Light translucent glassmorphism: an avatar, a message bubble, and floating
/// dark circular buttons on the corners. The main app pushes {status, body}.
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
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  bool get _active => _body.isEmpty;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasReply = _body.trim().isNotEmpty;
    final msg = hasReply ? _body.trim() : _status;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _glassCard(msg),
                  Positioned(
                    top: -8,
                    right: -8,
                    child: _circleBtn(
                        Icons.close_rounded, () => OverlayAssistant.close()),
                  ),
                  Positioned(
                    bottom: -8,
                    right: -8,
                    child: _circleBtn(Icons.near_me_rounded,
                        () => OverlayAssistant.openApp()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _glassCard(String msg) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.28),
                Colors.white.withValues(alpha: 0.12),
              ],
            ),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.45), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(),
              const SizedBox(height: 14),
              _bubble(msg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar() {
    return SizedBox(
      width: 48,
      height: 48,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final t = _active ? _pulse.value : 0.0;
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (_active)
                Container(
                  width: 44 + 12 * t,
                  height: 44 + 12 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _wand.withValues(alpha: 0.30 * (1 - t)),
                  ),
                ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _dark,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.auto_awesome, color: _wand, size: 22),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bubble(String text) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 170),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.20),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(6),
          topRight: Radius.circular(22),
          bottomLeft: Radius.circular(22),
          bottomRight: Radius.circular(22),
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: SingleChildScrollView(
        child: Text(
          text,
          style: const TextStyle(
            color: _ink,
            fontSize: 15,
            height: 1.4,
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 1)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _dark,
          border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
