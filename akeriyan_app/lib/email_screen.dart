import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'tts_service.dart';
import 'theme.dart';
import 'widgets/nothing_loader.dart';
import 'widgets/gradient_border.dart';

/// Gmail (IMAP/SMTP) — read & summarise the inbox, and compose/send replies.
class EmailScreen extends StatefulWidget {
  final String backendUrl;
  final String token;
  const EmailScreen({super.key, required this.backendUrl, required this.token});

  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> {
  late final Dio _dio = Dio(BaseOptions(
    baseUrl: '${widget.backendUrl}/v1/email',
    headers: {'Authorization': 'Bearer ${widget.token}'},
    receiveTimeout: const Duration(seconds: 120),
  ));

  List<dynamic> _emails = [];
  String _summary = '';
  bool _loading = true;
  bool _ok = true;
  bool _summarizing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _dio.get('/inbox');
      setState(() {
        _ok = r.data['ok'] == true;
        _emails = (r.data['emails'] as List?) ?? [];
        _summary = (r.data['speak'] as String?) ?? '';
      });
      if (_ok && _emails.isNotEmpty) _loadAiSummary();
    } catch (_) {
      setState(() {
        _ok = false;
        _summary = 'Could not reach the backend.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAiSummary() async {
    setState(() => _summarizing = true);
    try {
      final r = await _dio.get('/summary');
      final s = (r.data['speak'] as String?) ?? '';
      if (s.isNotEmpty && mounted) {
        setState(() => _summary = s);
        TtsService.speak(s);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _summarizing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EMAIL'), actions: [
        IconButton(
            icon: const Icon(Icons.refresh, color: Ak.textMid),
            onPressed: _load),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Ak.purple,
        icon: const Icon(Icons.edit, color: Ak.bg0),
        label: const Text('Compose', style: TextStyle(color: Ak.bg0)),
        onPressed: _compose,
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: Ak.bgGradient),
        child: SafeArea(
          child: _loading
              ? const NothingLoader(label: 'Checking your inbox…')
              : !_ok
                  ? _setupHint()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                      children: [
                        if (_summary.isNotEmpty)
                          GradientBorder(
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.auto_awesome,
                                      color: Ak.purple, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(_summary,
                                            style: const TextStyle(
                                                color: Ak.textHi, height: 1.4)),
                                        if (_summarizing) ...[
                                          const SizedBox(height: 8),
                                          Row(children: const [
                                            SizedBox(
                                                width: 12,
                                                height: 12,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Ak.purple)),
                                            SizedBox(width: 8),
                                            Text('AI summarizing…',
                                                style: TextStyle(
                                                    color: Ak.textLo,
                                                    fontSize: 12)),
                                          ]),
                                        ],
                                      ])),
                                ]),
                          ),
                        const SizedBox(height: 16),
                        if (_emails.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                                child: Text('No new emails.',
                                    style: TextStyle(color: Ak.textLo))),
                          ),
                        ..._emails.map(_tile),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _tile(dynamic e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: Ak.glass(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(e['from'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Ak.textHi, fontWeight: FontWeight.w700))),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.reply, color: Ak.purple, size: 18),
            onPressed: () => _compose(
                to: e['from_email'] ?? '',
                subject: 'Re: ${e['subject'] ?? ''}'),
          ),
        ]),
        const SizedBox(height: 2),
        Text(e['subject'] ?? '',
            style: const TextStyle(color: Ak.textMid, fontSize: 13)),
        const SizedBox(height: 6),
        Text(e['snippet'] ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Ak.textLo, fontSize: 12)),
      ]),
    );
  }

  void _compose({String to = '', String subject = ''}) {
    final toC = TextEditingController(text: to);
    final subjC = TextEditingController(text: subject);
    final bodyC = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Ak.bg1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Compose', style: Ak.display(size: 18)),
          const SizedBox(height: 12),
          _tf(toC, 'To'),
          _tf(subjC, 'Subject'),
          _tf(bodyC, 'Message', lines: 5),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              if (toC.text.trim().isEmpty || bodyC.text.trim().isEmpty) return;
              try {
                final r = await _dio.post('/send', data: {
                  'to': toC.text.trim(),
                  'subject': subjC.text.trim(),
                  'body': bodyC.text,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(r.data['ok'] == true
                          ? 'Email sent'
                          : (r.data['error'] ?? 'Send failed')),
                      backgroundColor: Ak.bg2));
                }
              } catch (_) {}
            },
            child: Container(
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  gradient: Ak.goldGradient,
                  borderRadius: BorderRadius.circular(12)),
              child: const Text('Send',
                  style:
                      TextStyle(color: Ak.bg0, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Widget _setupHint() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.mark_email_unread_outlined,
              color: Ak.textLo, size: 48),
          const SizedBox(height: 16),
          Text(_summary,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Ak.textMid, height: 1.4)),
          const SizedBox(height: 12),
          const Text(
              '1. Turn on 2-Step Verification\n'
              '2. myaccount.google.com/apppasswords → create one\n'
              '3. Put GMAIL_USER and GMAIL_APP_PASSWORD in the backend',
              textAlign: TextAlign.left,
              style: TextStyle(color: Ak.textLo, fontSize: 12, height: 1.6)),
        ]),
      ),
    );
  }

  Widget _tf(TextEditingController c, String label, {int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          maxLines: lines,
          style: const TextStyle(color: Ak.textHi),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Ak.textLo, fontSize: 13),
            filled: true,
            fillColor: Ak.glassFill,
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Ak.glassLine)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Ak.purple)),
          ),
        ),
      );
}
