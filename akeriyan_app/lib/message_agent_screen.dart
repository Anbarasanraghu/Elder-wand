import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'message_agent.dart';
import 'theme.dart';

/// Message Agent — create and manage scheduled reminders that message people
/// (auto SMS/Email/Telegram, one-tap WhatsApp) on the day-before and on the day.
class MessageAgentScreen extends StatelessWidget {
  const MessageAgentScreen({super.key});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ak.bg0,
      appBar: AppBar(
        backgroundColor: Ak.bg0,
        elevation: 0,
        title: const Text('Message Agent',
            style: TextStyle(fontFamily: Ak.dot, letterSpacing: 2)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Ak.silver),
            onPressed: () => showModalBottomSheet(
              context: context,
              backgroundColor: Ak.bg1,
              isScrollControlled: true,
              builder: (_) => const _AgentSettingsSheet(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Ak.purple,
        icon: const Icon(Icons.add, color: Ak.bg0),
        label: const Text('New', style: TextStyle(color: Ak.bg0)),
        onPressed: () => showModalBottomSheet(
          context: context,
          backgroundColor: Ak.bg1,
          isScrollControlled: true,
          builder: (_) => const _NewTaskSheet(),
        ),
      ),
      body: ValueListenableBuilder<List<MessageTask>>(
        valueListenable: MessageStore.tasks,
        builder: (context, tasks, _) {
          if (tasks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No scheduled messages yet.\n\nTap New to remind someone — '
                  'it can auto-send SMS, Email or Telegram, and open WhatsApp '
                  'pre-filled, on the day before and on the day.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Ak.textMid, height: 1.5),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: tasks.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _taskCard(context, tasks[i]),
          );
        },
      ),
    );
  }

  Widget _taskCard(BuildContext context, MessageTask t) {
    final d = t.due;
    final when = '${_months[d.month - 1]} ${d.day}, ${d.year}';
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: Ak.bento(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t.name,
                    style: const TextStyle(
                        color: Ak.textHi,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
              Text(when,
                  style: const TextStyle(color: Ak.purple, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          Text(t.message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Ak.textMid, fontSize: 13, height: 1.3)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final c in t.channels) _chip(c),
              const Spacer(),
              Text(
                [
                  if (t.dayBefore) 'day before',
                  if (t.onDay) 'on day',
                ].join(' + '),
                style: TextStyle(color: Ak.textLo, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                onPressed: () async {
                  await MessageStore.sendNow(t);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sent now (test)')));
                  }
                },
                icon: const Icon(Icons.send, size: 15, color: Ak.silver),
                label: const Text('Test now',
                    style: TextStyle(color: Ak.silver, fontSize: 12)),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Ak.textLo),
                onPressed: () => MessageStore.remove(t.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String c) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Ak.purple.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(c,
            style: const TextStyle(
                color: Ak.purple, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}

// ---------------------------------------------------------------------------
class _NewTaskSheet extends StatefulWidget {
  const _NewTaskSheet();
  @override
  State<_NewTaskSheet> createState() => _NewTaskSheetState();
}

class _NewTaskSheetState extends State<_NewTaskSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _tg = TextEditingController();
  final _msg = TextEditingController();
  DateTime _due = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  final Set<String> _channels = {'sms'};
  bool _dayBefore = true;
  bool _onDay = true;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + pad),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New message reminder',
                style: TextStyle(
                    color: Ak.textHi,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            _field(_name, 'Who (name)', Icons.person_outline),
            _field(_phone, 'Phone with country code (e.g. 9198…)',
                Icons.phone_outlined,
                keyboard: TextInputType.phone),
            _field(_msg, 'Message to send them', Icons.chat_bubble_outline,
                maxLines: 3),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _picker('Date',
                      '${_due.day}/${_due.month}/${_due.year}', () async {
                    final p = await showDatePicker(
                      context: context,
                      initialDate: _due,
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2100),
                    );
                    if (p != null) setState(() => _due = p);
                  }),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _picker('Time', _time.format(context), () async {
                    final p = await showTimePicker(
                        context: context, initialTime: _time);
                    if (p != null) setState(() => _time = p);
                  }),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text('Channels',
                style: TextStyle(color: Ak.textMid, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _chan('sms', 'SMS · auto'),
                _chan('whatsapp', 'WhatsApp · tap'),
                _chan('email', 'Email · auto'),
                _chan('telegram', 'Telegram · auto'),
              ],
            ),
            if (_channels.contains('email'))
              _field(_email, 'Their email', Icons.mail_outline,
                  keyboard: TextInputType.emailAddress),
            if (_channels.contains('telegram'))
              _field(_tg, 'Their Telegram chat ID', Icons.send_outlined),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: Ak.purple,
              title: const Text('Remind the day before',
                  style: TextStyle(color: Ak.textHi, fontSize: 14)),
              value: _dayBefore,
              onChanged: (v) => setState(() => _dayBefore = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: Ak.purple,
              title: const Text('Remind on the day',
                  style: TextStyle(color: Ak.textHi, fontSize: 14)),
              value: _onDay,
              onChanged: (v) => setState(() => _onDay = v),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Ak.purple,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Scheduling…' : 'Schedule',
                    style: const TextStyle(
                        color: Ak.bg0, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _msg.text.trim().isEmpty) {
      _toast('Add a name and a message.');
      return;
    }
    if (!_dayBefore && !_onDay) {
      _toast('Pick at least one time (day before / on the day).');
      return;
    }
    setState(() => _busy = true);
    // Ask for SMS permission if needed (fully-automatic send).
    if (_channels.contains('sms')) {
      final st = await Permission.sms.request();
      if (!st.isGranted) {
        _toast('SMS permission is needed to auto-send texts.');
        setState(() => _busy = false);
        return;
      }
    }
    final phone = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    final task = MessageTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      phone: phone,
      email: _email.text.trim(),
      telegramChatId: _tg.text.trim(),
      message: _msg.text.trim(),
      due: DateTime(_due.year, _due.month, _due.day),
      channels: _channels,
      dayBefore: _dayBefore,
      onDay: _onDay,
      fireHour: _time.hour,
    );
    final n = await MessageStore.add(task);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(n > 0
              ? 'Scheduled $n reminder${n == 1 ? '' : 's'} for ${task.name}.'
              : 'Saved, but both dates are in the past.')));
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  Widget _chan(String key, String label) {
    final on = _channels.contains(key);
    return FilterChip(
      label: Text(label),
      selected: on,
      showCheckmark: false,
      backgroundColor: Ak.glassFill,
      selectedColor: Ak.purple.withValues(alpha: 0.22),
      labelStyle: TextStyle(
          color: on ? Ak.purple : Ak.textMid,
          fontSize: 12,
          fontWeight: FontWeight.w600),
      side: BorderSide(
          color: on ? Ak.purple.withValues(alpha: 0.5) : Ak.glassLine),
      onSelected: (_) => setState(() =>
          on ? _channels.remove(key) : _channels.add(key)),
    );
  }

  Widget _field(TextEditingController c, String hint, IconData icon,
      {int maxLines = 1, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        style: const TextStyle(color: Ak.textHi),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Ak.textLo, fontSize: 13),
          prefixIcon: Icon(icon, color: Ak.silver, size: 19),
          filled: true,
          fillColor: Ak.glassFill,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _picker(String label, String value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Ak.glassFill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text('$label: ',
                style: TextStyle(color: Ak.textLo, fontSize: 13)),
            Text(value,
                style: const TextStyle(
                    color: Ak.textHi, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
class _AgentSettingsSheet extends StatefulWidget {
  const _AgentSettingsSheet();
  @override
  State<_AgentSettingsSheet> createState() => _AgentSettingsSheetState();
}

class _AgentSettingsSheetState extends State<_AgentSettingsSheet> {
  final _gu = TextEditingController();
  final _gp = TextEditingController();
  final _tk = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _gu.text = p.getString(MessageStore.kGmailUser) ?? '';
    _gp.text = p.getString(MessageStore.kGmailPass) ?? '';
    _tk.text = p.getString(MessageStore.kTgToken) ?? '';
    setState(() {});
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(MessageStore.kGmailUser, _gu.text.trim());
    await p.setString(MessageStore.kGmailPass, _gp.text.trim());
    await p.setString(MessageStore.kTgToken, _tk.text.trim());
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + pad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Agent settings',
              style: TextStyle(
                  color: Ak.textHi, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Only needed for auto Email (a Gmail address + app password) and '
            'auto Telegram (a bot token). SMS and WhatsApp need none.',
            style: TextStyle(color: Ak.textLo, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          _f(_gu, 'Your Gmail address'),
          _f(_gp, 'Gmail app password', obscure: true),
          _f(_tk, 'Telegram bot token (optional)'),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Ak.purple),
              onPressed: _save,
              child: const Text('Save',
                  style: TextStyle(color: Ak.bg0, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _f(TextEditingController c, String hint, {bool obscure = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          obscureText: obscure,
          style: const TextStyle(color: Ak.textHi),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Ak.textLo, fontSize: 13),
            filled: true,
            fillColor: Ak.glassFill,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
      );
}
