import 'dart:convert';

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

  /// Show the floating panel (top of the screen). Safe to call repeatedly.
  static Future<void> show() async {
    if (await FlutterOverlayWindow.isActive()) return;
    await FlutterOverlayWindow.showOverlay(
      height: 460,
      width: WindowSize.matchParent,
      alignment: OverlayAlignment.topCenter,
      flag: OverlayFlag.defaultFlag, // focusable so it can show over apps
      enableDrag: true,
      positionGravity: PositionGravity.auto,
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
