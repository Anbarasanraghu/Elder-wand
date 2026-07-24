import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'overlay_assistant.dart';
import 'theme.dart';

/// Set up the floating "assistant over other apps" panel: grant the one-time
/// draw-over permission and turn the feature on/off.
class OverlayScreen extends StatefulWidget {
  const OverlayScreen({super.key});

  @override
  State<OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<OverlayScreen> {
  bool _on = true;
  bool _granted = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final granted = await OverlayAssistant.hasPermission();
    setState(() {
      _on = p.getBool('overlay_on') ?? true;
      _granted = granted;
      _loaded = true;
    });
  }

  Future<void> _setOn(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('overlay_on', v);
    setState(() => _on = v);
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _preview() async {
    // Re-check permission live (state may be stale after granting).
    if (!await OverlayAssistant.hasPermission()) {
      _toast('Grant "Draw over other apps" first, then tap Preview again.');
      await OverlayAssistant.requestPermission();
      await _load();
      return;
    }
    try {
      await OverlayAssistant.show();
      await Future.delayed(const Duration(milliseconds: 400));
      await OverlayAssistant.update(
          status: 'This is your floating panel',
          body: 'Say "open our space" to open the app.');
      final active = await OverlayAssistant.isActive();
      _toast(active
          ? 'Panel is active — it should be at the top of your screen.'
          : 'Panel did not start (isActive=false).');
    } catch (e) {
      _toast('Overlay error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ak.bg0,
      appBar: AppBar(
        backgroundColor: Ak.bg0,
        elevation: 0,
        title: const Text('Floating Assistant',
            style: TextStyle(fontFamily: Ak.dot, letterSpacing: 2)),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  'Say "Hey Elder Wand" while you\'re in any other app and a '
                  'small panel pops up over your screen — like Google. Then '
                  'say "open our space" to jump into the full app.',
                  style: TextStyle(color: Ak.textMid, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: Ak.bento(radius: 16),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: Ak.purple,
                    title: const Text('Floating assistant',
                        style: TextStyle(color: Ak.textHi)),
                    subtitle: Text('Show a panel over other apps on wake',
                        style: TextStyle(color: Ak.textLo, fontSize: 12)),
                    value: _on,
                    onChanged: _setOn,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: Ak.bento(radius: 16),
                  child: Row(
                    children: [
                      Icon(
                          _granted
                              ? Icons.check_circle
                              : Icons.error_outline,
                          color: _granted ? Ak.green : Ak.pink),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _granted
                              ? 'Draw-over-apps permission granted.'
                              : 'Draw-over-apps permission needed.',
                          style: const TextStyle(color: Ak.textHi),
                        ),
                      ),
                      if (!_granted)
                        TextButton(
                          onPressed: () async {
                            await OverlayAssistant.requestPermission();
                            await _load();
                          },
                          child: const Text('Grant'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Ak.purple,
                    side: BorderSide(color: Ak.purple.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.preview),
                  label: const Text('Preview the panel'),
                  onPressed: _preview,
                ),
              ],
            ),
    );
  }
}
