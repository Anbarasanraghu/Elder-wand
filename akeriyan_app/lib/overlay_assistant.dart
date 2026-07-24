import 'dart:convert';
import 'dart:ui' as ui;

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// Drives the floating "assistant over other apps" panel (like Google's
/// overlay). The MAIN app isolate keeps doing the thinking (wake word, STT,
/// Gemma, TTS) and just pushes what to *show* into the overlay isolate via
/// [update]. Needs the one-time "Draw over other apps" permission.
class OverlayAssistant {
  static const _pkg = 'com.anbarasan.akeriyan_app';

  static Future<bool> hasPermission() =>
      FlutterOverlayWindow.isPermissionGranted();

  static Future<void> requestPermission() async {
    await FlutterOverlayWindow.requestPermission();
  }

  static Future<bool> isActive() => FlutterOverlayWindow.isActive();

  /// Show the floating panel pinned to the TOP of the screen. Always closes any
  /// stale window first so it can't get stuck off-screen (a dragged/auto
  /// position previously placed it above the top edge, making it invisible).
  static Future<void> show() async {
    try {
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
      }
    } catch (_) {}
    // The plugin's height is in PHYSICAL pixels, but Flutter lays out in
    // LOGICAL pixels — so convert (≈340 logical px tall for the glass card),
    // otherwise the card overflows on high-density screens.
    final dpr = ui.PlatformDispatcher.instance.views.isNotEmpty
        ? ui.PlatformDispatcher.instance.views.first.devicePixelRatio
        : 3.0;
    await FlutterOverlayWindow.showOverlay(
      height: (340 * dpr).round(),
      width: WindowSize.matchParent,
      alignment: OverlayAlignment.bottomCenter, // sit at the BOTTOM
      flag: OverlayFlag.defaultFlag, // focusable so it can show over apps
      enableDrag: false,
      positionGravity: PositionGravity.none,
      // Explicit start position overrides any stale/saved offset that was
      // pushing the window off-screen. (0,0) + bottom gravity => screen bottom.
      startPosition: const OverlayPosition(0, 0),
      overlayTitle: 'Elder Wand',
    );
  }

  /// Push the current state/text to the panel.
  static Future<void> update({required String status, String body = ''}) async {
    await FlutterOverlayWindow.shareData(
        jsonEncode({'status': status, 'body': body}));
  }

  static Future<void> close() async {
    if (await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.closeOverlay();
    }
  }

  /// Bring the full Elder Wand app to the foreground ("open our space").
  static Future<void> openApp() async {
    await close();
    final intent = AndroidIntent(
      action: 'android.intent.action.MAIN',
      package: _pkg,
      componentName: '$_pkg.MainActivity',
      flags: <int>[
        Flag.FLAG_ACTIVITY_NEW_TASK,
        Flag.FLAG_ACTIVITY_REORDER_TO_FRONT,
      ],
    );
    try {
      await intent.launch();
    } catch (_) {}
  }
}
