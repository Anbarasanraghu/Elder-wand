import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'tts_service.dart';
import 'theme.dart';
import 'widgets/gradient_border.dart';
import 'widgets/nothing_loader.dart';

/// Ask-your-documents (RAG) — upload PDFs/notes, then ask questions and get
/// answers grounded in them with sources. All local (embeddings + LLM).
class DocsScreen extends StatefulWidget {
  final String backendUrl;
  final String token;
  const DocsScreen({super.key, required this.backendUrl, required this.token});

  @override
  State<DocsScreen> createState() => _DocsScreenState();
}

class _DocsScreenState extends State<DocsScreen> {
  late final Dio _dio = Dio(BaseOptions(
    baseUrl: '${widget.backendUrl}/v1/docs',
    headers: {'Authorization': 'Bearer ${widget.token}'},
    receiveTimeout: const Duration(minutes: 5),
  ));

  final _question = TextEditingController();
  List<dynamic> _docs = [];
  String _answer = '';
  List<String> _sources = [];
  bool _busy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _loadDocs() async {
    try {
      final r = await _dio.get('');
      setState(() => _docs = r.data['docs'] as List);
    } catch (_) {}
  }

  Future<void> _ask() async {
    final q = _question.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _busy = true;
      _answer = '';
      _sources = [];
      _status = 'Searching your documents…';
    });
    try {
      final r = await _dio.post('/ask', data: {'question': q});
      setState(() {
        _answer = (r.data['answer'] as String?) ?? '';
        _sources = ((r.data['sources'] as List?) ?? []).map((e) => '$e').toList();
        _status = '';
      });
      TtsService.speak(_answer);
    } catch (_) {
      setState(() => _status = 'Ask failed — is the backend running?');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pasteDialog() async {
    final name = TextEditingController();
    final text = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Ak.bg2,
        title: Text('Paste a note', style: Ak.display(size: 16)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: name,
              style: const TextStyle(color: Ak.textHi),
              decoration: const InputDecoration(
                  hintText: 'Name (e.g. acme_notes)',
                  hintStyle: TextStyle(color: Ak.textLo)),
            ),
            TextField(
              controller: text,
              maxLines: 6,
              style: const TextStyle(color: Ak.textHi),
              decoration: const InputDecoration(
                  hintText: 'Paste text…',
                  hintStyle: TextStyle(color: Ak.textLo)),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (text.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              setState(() {
                _busy = true;
                _status = 'Indexing…';
              });
              try {
                await _dio.post('/ingest_text', data: {
                  'name': name.text.trim().isEmpty
                      ? 'note'
                      : name.text.trim(),
                  'text': text.text,
                });
                _loadDocs();
                setState(() => _status = 'Note indexed');
              } catch (_) {}
              if (mounted) setState(() => _busy = false);
            },
            child: const Text('Add', style: TextStyle(color: Ak.purple)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DOCUMENTS')),
      body: Container(
        decoration: const BoxDecoration(gradient: Ak.bgGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _btn(Icons.note_add, 'Add note / paste text', _pasteDialog),
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(_status,
                    style: const TextStyle(color: Ak.textLo, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              if (_docs.isNotEmpty) ...[
                Text('Indexed (${_docs.length})',
                    style: Ak.display(size: 13, color: Ak.textMid)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _docs
                      .map((d) => Chip(
                            label: Text(d['doc'],
                                style: const TextStyle(
                                    color: Ak.textHi, fontSize: 12)),
                            backgroundColor: Ak.glassFill,
                            side: const BorderSide(color: Ak.glassLine),
                            deleteIconColor: Ak.textLo,
                            onDeleted: () async {
                              await _dio.delete('/${d['doc']}');
                              _loadDocs();
                            },
                          ))
                      .toList(),
                ),
                const SizedBox(height: 20),
              ],
              // Ask box
              TextField(
                controller: _question,
                style: const TextStyle(color: Ak.textHi),
                onSubmitted: (_) => _ask(),
                decoration: InputDecoration(
                  labelText: 'Ask your documents…',
                  labelStyle: const TextStyle(color: Ak.textLo),
                  filled: true,
                  fillColor: Ak.glassFill,
                  suffixIcon: IconButton(
                      icon: const Icon(Icons.send, color: Ak.purple),
                      onPressed: _ask),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Ak.glassLine)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Ak.purple)),
                ),
              ),
              const SizedBox(height: 16),
              if (_busy)
                const NothingLoader(label: 'Searching your documents…'),
              if (_answer.isNotEmpty)
                GradientBorder(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.auto_awesome,
                              color: Ak.purple, size: 18),
                          const SizedBox(width: 8),
                          Text('Answer',
                              style: Ak.display(size: 13, color: Ak.textMid)),
                        ]),
                        const SizedBox(height: 10),
                        Text(_answer,
                            style: const TextStyle(
                                color: Ak.textHi, height: 1.4)),
                        if (_sources.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text('Sources: ${_sources.join(', ')}',
                              style: const TextStyle(
                                  color: Ak.textLo, fontSize: 11)),
                        ],
                      ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _btn(IconData icon, String label, VoidCallback onTap,
      {bool filled = true}) {
    return GestureDetector(
      onTap: _busy ? null : onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: filled ? Ak.goldGradient : null,
          color: filled ? null : Ak.glassFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: filled ? Colors.transparent : Ak.glassLine),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: filled ? Ak.bg0 : Ak.textHi, size: 18),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: filled ? Ak.bg0 : Ak.textHi,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }
}
