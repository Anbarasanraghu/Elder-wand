import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'proactive_service.dart';
import 'theme.dart';

/// Settings for the proactive assistant: the daily morning briefing (on/off +
/// time) and low-battery alerts, plus a button to preview the briefing now.
class ProactiveScreen extends StatefulWidget {
  const ProactiveScreen({super.key});

  @override
  State<ProactiveScreen> createState() => _ProactiveScreenState();
}

class _ProactiveScreenState extends State<ProactiveScreen> {
  bool _briefOn = true;
  bool _battOn = true;
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _briefOn = p.getBool(ProactiveService.kBriefOn) ?? true;
      _battOn = p.getBool(ProactiveService.kBattOn) ?? true;
      _time = TimeOfDay(
        hour: p.getInt(ProactiveService.kBriefHour) ?? 8,
        minute: p.getInt(ProactiveService.kBriefMin) ?? 0,
      );
      _loaded = true;
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(ProactiveService.kBriefOn, _briefOn);
    await p.setBool(ProactiveService.kBattOn, _battOn);
    await p.setInt(ProactiveService.kBriefHour, _time.hour);
    await p.setInt(ProactiveService.kBriefMin, _time.minute);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) {
      setState(() => _time = t);
      await _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ak.bg0,
      appBar: AppBar(
        backgroundColor: Ak.bg0,
        elevation: 0,
        title: const Text('Proactive',
            style: TextStyle(fontFamily: Ak.dot, letterSpacing: 2)),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  'Let Elder Wand check in on you without being asked.',
                  style: TextStyle(color: Ak.textMid, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                _card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: Ak.purple,
                        title: const Text('Morning briefing',
                            style: TextStyle(color: Ak.textHi)),
                        subtitle: Text('Weather + top news, once a day',
                            style: TextStyle(color: Ak.textLo, fontSize: 12)),
                        value: _briefOn,
                        onChanged: (v) {
                          setState(() => _briefOn = v);
                          _save();
                        },
                      ),
                      if (_briefOn)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.schedule, color: Ak.silver),
                          title: const Text('Time',
                              style: TextStyle(color: Ak.textHi)),
                          trailing: Text(_time.format(context),
                              style: const TextStyle(
                                  color: Ak.purple,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16)),
                          onTap: _pickTime,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _card(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: Ak.purple,
                    title: const Text('Low-battery alerts',
                        style: TextStyle(color: Ak.textHi)),
                    subtitle: Text('Warn me below 15% (not charging)',
                        style: TextStyle(color: Ak.textLo, fontSize: 12)),
                    value: _battOn,
                    onChanged: (v) {
                      setState(() => _battOn = v);
                      _save();
                    },
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Ak.purple,
                    side: BorderSide(color: Ak.purple.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Preview briefing now'),
                  onPressed: () async {
                    await ProactiveService.deliverBriefing();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Briefing sent to your notifications')),
                      );
                    }
                  },
                ),
              ],
            ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: Ak.bento(radius: 16),
        child: child,
      );
}
