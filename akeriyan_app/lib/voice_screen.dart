import 'package:flutter/material.dart';

import 'theme.dart';
import 'tts_service.dart';

/// Pick the assistant's voice by ear — the phone doesn't label gender, so you
/// preview each one and choose the one you like (male, female, whichever).
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  List<Map<String, String>> _voices = [];
  String? _selectedName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final voices = await TtsService.englishVoices();
    final cur = await TtsService.currentVoice();
    if (!mounted) return;
    setState(() {
      _voices = voices;
      _selectedName = cur?['name'];
      _loading = false;
    });
  }

  String _label(Map<String, String> v) {
    final loc = (v['locale'] ?? '').toLowerCase();
    final region = loc.contains('en-us')
        ? 'English · US'
        : loc.contains('en-gb')
            ? 'English · UK'
            : loc.contains('en-in')
                ? 'English · India'
                : loc.contains('en-au')
                    ? 'English · Australia'
                    : 'English';
    // Voices are numbered so you can tell them apart while previewing.
    return region;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VOICE')),
      body: Stack(
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(gradient: Ak.bgGradient),
            child: SizedBox.expand(),
          ),
          Positioned.fill(child: Ak.ambientGlow()),
          SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _voices.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: Text(
                            'No voices found. Install voices in\nSettings → System → '
                            'Text-to-speech → Google → Install voice data.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Ak.textMid),
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(4, 0, 4, 14),
                            child: Text(
                              'Tap a voice to hear it. The phone doesn’t label male/female, '
                              'so pick the one you like by ear — it’s saved as Elder Wand’s voice.',
                              style: TextStyle(color: Ak.textMid, fontSize: 13, height: 1.5),
                            ),
                          ),
                          for (var i = 0; i < _voices.length; i++)
                            _voiceTile(_voices[i], i + 1),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _voiceTile(Map<String, String> v, int n) {
    final selected = v['name'] == _selectedName;
    final quality = v['quality'] ?? '';
    final hq = quality == 'very high' || quality == 'high';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: Ak.bento(radius: 16, glow: selected),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          onTap: () async {
            await TtsService.selectVoice(v);
            setState(() => _selectedName = v['name']);
            await TtsService.previewVoice(v);
          },
          leading: CircleAvatar(
            backgroundColor: selected ? Ak.gold.withValues(alpha: 0.2) : Ak.glassFill,
            child: Text('$n',
                style: TextStyle(
                    color: selected ? Ak.gold : Ak.textMid,
                    fontWeight: FontWeight.w600)),
          ),
          title: Text('${_label(v)}  ·  Voice $n',
              style: const TextStyle(color: Ak.textHi, fontSize: 14.5)),
          subtitle: Text(hq ? 'High quality' : 'Standard',
              style: TextStyle(
                  color: hq ? Ak.green : Ak.textLo, fontSize: 11.5)),
          trailing: selected
              ? const Icon(Icons.check_circle, color: Ak.gold)
              : IconButton(
                  icon: const Icon(Icons.play_circle_outline, color: Ak.textMid),
                  onPressed: () => TtsService.previewVoice(v),
                ),
        ),
      ),
    );
  }
}
