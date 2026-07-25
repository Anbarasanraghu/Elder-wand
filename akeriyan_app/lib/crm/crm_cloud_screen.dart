import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../whatsapp_sender.dart';
import '../sms_sender.dart';
import '../phone_caller.dart';
import 'crm_config.dart';
import 'crm_service.dart';
import 'lead_generator_screen.dart';
import 'outreach_sheet.dart';

const _stageLabels = {
  'new': 'New',
  'contacted': 'Contacted',
  'qualified': 'Qualified',
  'proposal': 'Proposal',
  'won': 'Won',
  'lost': 'Lost',
};

/// Cloud CRM (Supabase) — the Phase 1 data spine. Works with no PC / no server.
class CrmCloudScreen extends StatefulWidget {
  const CrmCloudScreen({super.key});

  @override
  State<CrmCloudScreen> createState() => _CrmCloudScreenState();
}

class _CrmCloudScreenState extends State<CrmCloudScreen> {
  bool _ready = false;
  bool _loading = true;
  String _stage = 'new';
  List<Lead> _leads = [];
  Map<String, int> _counts = {};

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final ok = await CrmConfig.init();
    setState(() => _ready = ok);
    if (ok) await _refresh();
    setState(() => _loading = false);
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final leads = await CrmService.leads(stage: _stage);
      // Show the leads immediately — the chip counts are secondary and must
      // never be able to blank the list if they fail.
      if (mounted) setState(() => _leads = leads);
      debugPrint('[CRM] applied ${leads.length} leads to the list');
    } catch (e, st) {
      debugPrint('[CRM] leads refresh ERROR: $e\n$st');
      _toast('CRM error: $e');
    }
    try {
      final counts = await CrmService.stageCounts();
      if (mounted) setState(() => _counts = counts);
    } catch (e) {
      debugPrint('[CRM] stageCounts ERROR: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ak.bg0,
      appBar: AppBar(
        backgroundColor: Ak.bg0,
        elevation: 0,
        title: const Text('CRM',
            style: TextStyle(fontFamily: Ak.dot, letterSpacing: 2)),
        actions: [
          if (_ready)
            IconButton(
              icon: const Icon(Icons.bolt, color: Ak.purple),
              tooltip: 'Generate leads',
              onPressed: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LeadGeneratorScreen()));
                _refresh();
              },
            ),
          if (_ready)
            IconButton(
              icon: const Icon(Icons.refresh, color: Ak.silver),
              onPressed: _refresh,
            ),
        ],
      ),
      floatingActionButton: _ready
          ? FloatingActionButton.extended(
              backgroundColor: Ak.purple,
              icon: const Icon(Icons.person_add_alt, color: Ak.bg0),
              label: const Text('Lead', style: TextStyle(color: Ak.bg0)),
              onPressed: () async {
                await showModalBottomSheet(
                  context: context,
                  backgroundColor: Ak.bg1,
                  isScrollControlled: true,
                  builder: (_) => const _AddLeadSheet(),
                );
                _refresh();
              },
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _ready
              ? _crm()
              : _ConnectView(onConnected: _boot),
    );
  }

  Widget _crm() {
    return Column(
      children: [
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final s in CrmService.stages)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${_stageLabels[s]} · ${_counts[s] ?? 0}'),
                    selected: _stage == s,
                    showCheckmark: false,
                    backgroundColor: Ak.glassFill,
                    selectedColor: Ak.purple.withValues(alpha: 0.22),
                    labelStyle: TextStyle(
                        color: _stage == s ? Ak.purple : Ak.textMid,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                    side: BorderSide(
                        color: _stage == s
                            ? Ak.purple.withValues(alpha: 0.5)
                            : Ak.glassLine),
                    onSelected: (_) {
                      setState(() => _stage = s);
                      _refresh();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _leads.isEmpty
              ? Center(
                  child: Text('No ${_stageLabels[_stage]!.toLowerCase()} leads.',
                      style: TextStyle(color: Ak.textLo)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: _leads.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _leadCard(_leads[i]),
                ),
        ),
      ],
    );
  }

  Widget _leadCard(Lead l) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => CrmLeadScreen(lead: l)));
        _refresh();
      },
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: Ak.bento(radius: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.name,
                      style: const TextStyle(
                          color: Ak.textHi,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  if (l.company.isNotEmpty)
                    Text(l.company,
                        style: TextStyle(color: Ak.textMid, fontSize: 12)),
                ],
              ),
            ),
            if (l.value > 0)
              Text('₹${l.value.toStringAsFixed(0)}',
                  style: const TextStyle(color: Ak.purple, fontSize: 13)),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Ak.textLo),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
class _ConnectView extends StatefulWidget {
  final VoidCallback onConnected;
  const _ConnectView({required this.onConnected});
  @override
  State<_ConnectView> createState() => _ConnectViewState();
}

class _ConnectViewState extends State<_ConnectView> {
  final _url = TextEditingController();
  final _key = TextEditingController();

  @override
  void initState() {
    super.initState();
    _url.text = CrmConfig.url;
    _key.text = CrmConfig.key;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Connect your free Supabase project (one-time, no credit card):\n\n'
          '1. supabase.com → New project.\n'
          '2. SQL Editor → paste supabase/crm_schema.sql → Run.\n'
          '3. Project Settings → API → copy the URL and the anon public key '
          'below.',
          style: TextStyle(color: Ak.textMid, height: 1.5, fontSize: 13),
        ),
        const SizedBox(height: 18),
        _f(_url, 'Project URL (https://xxxx.supabase.co)'),
        _f(_key, 'anon public key'),
        const SizedBox(height: 8),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Ak.purple,
              padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: () async {
            await CrmConfig.save(_url.text, _key.text);
            widget.onConnected();
          },
          child: const Text('Connect',
              style: TextStyle(color: Ak.bg0, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _f(TextEditingController c, String hint) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          style: const TextStyle(color: Ak.textHi, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Ak.textLo, fontSize: 12),
            filled: true,
            fillColor: Ak.glassFill,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
class _AddLeadSheet extends StatefulWidget {
  const _AddLeadSheet();
  @override
  State<_AddLeadSheet> createState() => _AddLeadSheetState();
}

class _AddLeadSheetState extends State<_AddLeadSheet> {
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _website = TextEditingController();
  final _source = TextEditingController();
  final _value = TextEditingController();
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
            const Text('New lead',
                style: TextStyle(
                    color: Ak.textHi,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            _f(_name, 'Name *'),
            _f(_company, 'Company'),
            _f(_phone, 'Phone (with country code)'),
            _f(_email, 'Email'),
            _f(_website, 'Website'),
            _f(_source, 'Source (Maps, referral…)'),
            _f(_value, 'Deal value (₹)', number: true),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Ak.purple,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Saving…' : 'Add lead',
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
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await CrmService.addLead(
        name: _name.text.trim(),
        company: _company.text.trim(),
        phone: _phone.text.replaceAll(RegExp(r'[^0-9+]'), ''),
        email: _email.text.trim(),
        website: _website.text.trim(),
        source: _source.text.trim(),
        value: num.tryParse(_value.text.trim()) ?? 0,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _busy = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Widget _f(TextEditingController c, String hint, {bool number = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: number ? TextInputType.number : null,
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

// ---------------------------------------------------------------------------
class CrmLeadScreen extends StatefulWidget {
  final Lead lead;
  const CrmLeadScreen({super.key, required this.lead});
  @override
  State<CrmLeadScreen> createState() => _CrmLeadScreenState();
}

class _CrmLeadScreenState extends State<CrmLeadScreen> {
  late String _stage = widget.lead.stage;
  final _note = TextEditingController();
  List<Map<String, dynamic>> _acts = [];
  List<Map<String, dynamic>> _fups = [];

  Lead get l => widget.lead;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final a = await CrmService.activities(l.id);
      final f = await CrmService.followups(l.id);
      setState(() {
        _acts = a;
        _fups = f;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ak.bg0,
      appBar: AppBar(
        backgroundColor: Ak.bg0,
        elevation: 0,
        title: Text(l.name,
            style: const TextStyle(fontFamily: Ak.dot, letterSpacing: 1)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Ak.silver),
            onPressed: () async {
              await CrmService.deleteLead(l.id);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          if (l.company.isNotEmpty)
            Text(l.company, style: TextStyle(color: Ak.textMid)),
          const SizedBox(height: 12),
          _actions(),
          const SizedBox(height: 14),
          _details(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: Ak.purple,
                  padding: const EdgeInsets.symmetric(vertical: 13)),
              onPressed: () async {
                await showModalBottomSheet(
                  context: context,
                  backgroundColor: Ak.bg1,
                  isScrollControlled: true,
                  builder: (_) => OutreachSheet(lead: l),
                );
                _load();
              },
              icon: const Icon(Icons.campaign_outlined, color: Ak.bg0),
              label: const Text('Send outreach',
                  style: TextStyle(color: Ak.bg0, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 14),
          _stageRow(),
          const SizedBox(height: 18),
          _addNote(),
          const SizedBox(height: 8),
          for (final a in _acts) _actTile(a),
          const SizedBox(height: 18),
          _sectionLabel('FOLLOW-UPS'),
          TextButton.icon(
            onPressed: _addFollowup,
            icon: const Icon(Icons.add, size: 16, color: Ak.purple),
            label: const Text('Add follow-up',
                style: TextStyle(color: Ak.purple)),
          ),
          for (final f in _fups) _fupTile(f),
        ],
      ),
    );
  }

  Widget _actions() {
    return Row(
      children: [
        if (l.phone.isNotEmpty) ...[
          _act(Icons.call, 'Call', () => PhoneCaller.call(l.phone)),
          _act(Icons.chat, 'WhatsApp',
              () => WhatsAppSender.openChat(phoneNumber: l.phone, message: '')),
          _act(Icons.sms, 'SMS',
              () => SmsSender.send(number: l.phone, message: '')),
        ],
        if (l.email.isNotEmpty)
          _act(Icons.mail_outline, 'Email',
              () => launchUrl(Uri.parse('mailto:${l.email}'))),
      ],
    );
  }

  Widget _details() {
    final rows = <Widget>[];
    void add(IconData ic, String label, String value, {VoidCallback? tap}) {
      if (value.trim().isEmpty) return;
      rows.add(
        InkWell(
          onTap: tap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(ic, size: 16, color: Ak.silver),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(color: Ak.textLo, fontSize: 11)),
                      const SizedBox(height: 1),
                      Text(value,
                          style: TextStyle(
                              color: tap != null ? Ak.purple : Ak.textHi,
                              fontSize: 14,
                              height: 1.3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    add(Icons.category_outlined, 'Category', l.category);
    add(Icons.phone_outlined, 'Phone', l.phone,
        tap: l.phone.isEmpty ? null : () => PhoneCaller.call(l.phone));
    add(Icons.mail_outline, 'Email', l.email,
        tap: l.email.isEmpty
            ? null
            : () => launchUrl(Uri.parse('mailto:${l.email}')));
    add(Icons.language, 'Website', l.website, tap: l.website.isEmpty
        ? null
        : () => launchUrl(
            Uri.parse(l.website.startsWith('http')
                ? l.website
                : 'https://${l.website}'),
            mode: LaunchMode.externalApplication));
    add(Icons.place_outlined, 'Address', l.address, tap: l.address.isEmpty
        ? null
        : () => launchUrl(Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(l.address)}')));
    if (l.notes.trim().isNotEmpty) {
      add(Icons.share_outlined, 'Social / notes', l.notes);
    }
    add(Icons.travel_explore, 'Source', l.source);

    if (rows.isEmpty) {
      return Text(
        'No contact details on record for this lead yet. Try the website or a '
        'quick search to enrich it.',
        style: TextStyle(color: Ak.textLo, fontSize: 12, height: 1.4),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: Ak.bento(radius: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );
  }

  Widget _act(IconData i, String label, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: Ak.bento(radius: 12),
            child: Column(
              children: [
                Icon(i, color: Ak.purple, size: 20),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(color: Ak.textMid, fontSize: 11)),
              ],
            ),
          ),
        ),
      );

  Widget _stageRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: Ak.bento(radius: 12),
      child: Row(
        children: [
          const Text('Stage', style: TextStyle(color: Ak.textMid)),
          const Spacer(),
          DropdownButton<String>(
            value: _stage,
            dropdownColor: Ak.bg2,
            underline: const SizedBox.shrink(),
            style: const TextStyle(color: Ak.purple, fontWeight: FontWeight.w700),
            items: [
              for (final s in CrmService.stages)
                DropdownMenuItem(value: s, child: Text(_stageLabels[s]!)),
            ],
            onChanged: (v) async {
              if (v == null) return;
              setState(() => _stage = v);
              await CrmService.setStage(l.id, v);
            },
          ),
        ],
      ),
    );
  }

  Widget _addNote() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _note,
            style: const TextStyle(color: Ak.textHi),
            decoration: InputDecoration(
              hintText: 'Add a note / log a touch…',
              hintStyle: const TextStyle(color: Ak.textLo, fontSize: 13),
              filled: true,
              fillColor: Ak.glassFill,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.send, color: Ak.purple),
          onPressed: () async {
            if (_note.text.trim().isEmpty) return;
            await CrmService.addActivity(l.id, 'note', _note.text.trim());
            _note.clear();
            _load();
          },
        ),
      ],
    );
  }

  Widget _actTile(Map<String, dynamic> a) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.circle, size: 7, color: Ak.silver),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${a['body'] ?? ''}',
                  style: TextStyle(color: Ak.textMid, fontSize: 13)),
            ),
          ],
        ),
      );

  Future<void> _addFollowup() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    await CrmService.addFollowup(l.id, d, 'Follow up');
    _load();
  }

  Widget _fupTile(Map<String, dynamic> f) {
    final due = DateTime.tryParse('${f['due_at']}') ?? DateTime.now();
    final done = f['done'] == true;
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      activeColor: Ak.purple,
      value: done,
      title: Text('${f['note'] ?? 'Follow up'}',
          style: TextStyle(
              color: done ? Ak.textLo : Ak.textHi,
              decoration: done ? TextDecoration.lineThrough : null)),
      subtitle: Text('${due.day}/${due.month}/${due.year}',
          style: TextStyle(color: Ak.textLo, fontSize: 12)),
      onChanged: (v) async {
        await CrmService.setFollowupDone('${f['id']}', v ?? false);
        _load();
      },
    );
  }

  Widget _sectionLabel(String t) => Text(t,
      style: TextStyle(
          color: Ak.textLo,
          fontSize: 11,
          letterSpacing: 2,
          fontWeight: FontWeight.w700));
}
