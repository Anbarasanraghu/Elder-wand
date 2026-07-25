import 'package:flutter/material.dart';

import '../theme.dart';
import 'crm_service.dart';
import 'outreach_service.dart';

/// Bottom sheet to send templated outreach to a lead over WhatsApp / Email /
/// SMS. Auto-logs the touch and can set a follow-up.
class OutreachSheet extends StatefulWidget {
  final Lead lead;
  const OutreachSheet({super.key, required this.lead});

  @override
  State<OutreachSheet> createState() => _OutreachSheetState();
}

class _OutreachSheetState extends State<OutreachSheet> {
  List<OutreachTemplate> _templates = [];
  int _sel = 0;
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _followUp = true;
  bool _busy = false;

  Lead get l => widget.lead;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _templates = await TemplateStore.load();
    _apply(0);
    setState(() {});
  }

  void _apply(int i) {
    if (i < 0 || i >= _templates.length) return;
    _sel = i;
    _subject.text = fillTemplate(_templates[i].subject, l);
    _body.text = fillTemplate(_templates[i].body, l);
  }

  Future<void> _send(String channel) async {
    setState(() => _busy = true);
    try {
      if (channel == 'whatsapp') {
        await Outreach.whatsapp(l, _body.text.trim());
      } else if (channel == 'sms') {
        await Outreach.sms(l, _body.text.trim());
      } else {
        final auto =
            await Outreach.email(l, _subject.text.trim(), _body.text.trim());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(auto
                  ? 'Email sent to ${l.email}'
                  : 'Opened mail app (add Gmail app-password in Message Agent settings to auto-send)')));
        }
      }
      if (_followUp) {
        await CrmService.addFollowup(
            l.id, DateTime.now().add(const Duration(days: 3)), 'Follow up');
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Send failed: $e')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

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
            Row(
              children: [
                Text('Outreach · ${l.name}',
                    style: const TextStyle(
                        color: Ak.textHi,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const TemplatesScreen()));
                    await _load();
                  },
                  child: const Text('Templates',
                      style: TextStyle(color: Ak.silver, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_templates.isNotEmpty)
              Wrap(
                spacing: 8,
                children: [
                  for (var i = 0; i < _templates.length; i++)
                    ChoiceChip(
                      label: Text(_templates[i].name),
                      selected: _sel == i,
                      showCheckmark: false,
                      backgroundColor: Ak.glassFill,
                      selectedColor: Ak.purple.withValues(alpha: 0.22),
                      labelStyle: TextStyle(
                          color: _sel == i ? Ak.purple : Ak.textMid,
                          fontSize: 12),
                      onSelected: (_) => setState(() => _apply(i)),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            _field(_subject, 'Subject (email)'),
            const SizedBox(height: 8),
            _field(_body, 'Message', lines: 5),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: Ak.purple,
              dense: true,
              title: const Text('Set a follow-up in 3 days',
                  style: TextStyle(color: Ak.textHi, fontSize: 13)),
              value: _followUp,
              onChanged: (v) => setState(() => _followUp = v ?? true),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (l.phone.isNotEmpty)
                  _btn(Icons.chat, 'WhatsApp', () => _send('whatsapp')),
                if (l.email.isNotEmpty)
                  _btn(Icons.mail_outline, 'Email', () => _send('email')),
                if (l.phone.isNotEmpty)
                  _btn(Icons.sms_outlined, 'SMS', () => _send('sms')),
              ],
            ),
            if (l.phone.isEmpty && l.email.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('This lead has no phone or email yet.',
                    style: TextStyle(color: Ak.textLo, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _btn(IconData i, String label, VoidCallback onTap) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: Ak.purple,
                padding: const EdgeInsets.symmetric(vertical: 12)),
            onPressed: _busy ? null : onTap,
            icon: Icon(i, size: 16, color: Ak.bg0),
            label: Text(label,
                style: const TextStyle(
                    color: Ak.bg0, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ),
      );

  Widget _field(TextEditingController c, String hint, {int lines = 1}) =>
      TextField(
        controller: c,
        maxLines: lines,
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
      );
}

// ---------------------------------------------------------------------------
class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key});
  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  List<OutreachTemplate> _t = [];

  @override
  void initState() {
    super.initState();
    TemplateStore.load().then((v) => setState(() => _t = v));
  }

  Future<void> _persist() => TemplateStore.save(_t);

  Future<void> _edit(int? i) async {
    final tpl = i == null ? OutreachTemplate('', '', '') : _t[i];
    final name = TextEditingController(text: tpl.name);
    final subject = TextEditingController(text: tpl.subject);
    final body = TextEditingController(text: tpl.body);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Ak.bg2,
        title: Text(i == null ? 'New template' : 'Edit template',
            style: const TextStyle(color: Ak.textHi)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _tf(name, 'Name'),
            _tf(subject, 'Subject'),
            _tf(body, 'Body — use {name} and {company}', lines: 5),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      setState(() {
        final v = OutreachTemplate(
            name.text.trim(), subject.text.trim(), body.text.trim());
        if (i == null) {
          _t.add(v);
        } else {
          _t[i] = v;
        }
      });
      await _persist();
    }
  }

  Widget _tf(TextEditingController c, String h, {int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          maxLines: lines,
          style: const TextStyle(color: Ak.textHi),
          decoration: InputDecoration(
              hintText: h, hintStyle: const TextStyle(color: Ak.textLo)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ak.bg0,
      appBar: AppBar(
        backgroundColor: Ak.bg0,
        elevation: 0,
        title: const Text('Templates',
            style: TextStyle(fontFamily: Ak.dot, letterSpacing: 2)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Ak.purple,
        onPressed: () => _edit(null),
        child: const Icon(Icons.add, color: Ak.bg0),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: _t.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) => Container(
          padding: const EdgeInsets.all(14),
          decoration: Ak.bento(radius: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_t[i].name,
                        style: const TextStyle(
                            color: Ak.textHi, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(_t[i].body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Ak.textMid, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Ak.silver),
                  onPressed: () => _edit(i)),
              IconButton(
                  icon: const Icon(Icons.delete_outline, color: Ak.textLo),
                  onPressed: () async {
                    setState(() => _t.removeAt(i));
                    await _persist();
                  }),
            ],
          ),
        ),
      ),
    );
  }
}
