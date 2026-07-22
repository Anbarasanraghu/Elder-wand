import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'tts_service.dart';
import 'local_cache.dart';
import 'theme.dart';
import 'widgets/gradient_border.dart';
import 'widgets/nothing_loader.dart';

/// Persisted scan history so past scans are viewable offline.
class VisionStore {
  static Future<List<Map<String, dynamic>>> all() async {
    final d = await LocalCache.load('scans');
    return d is List
        ? d.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : [];
  }

  static Future<void> add(Map<String, dynamic> m) async {
    final list = await all();
    list.insert(0, m);
    if (list.length > 60) list.removeRange(60, list.length);
    await LocalCache.save('scans', list);
  }
}

/// Camera vision — point the camera and ask. A photo is sent to the backend's
/// local vision model (moondream). Extras: OCR, translate, scan history, and
/// business-card -> CRM lead.
class VisionScreen extends StatefulWidget {
  final String backendUrl;
  final String token;
  const VisionScreen(
      {super.key, required this.backendUrl, required this.token});

  @override
  State<VisionScreen> createState() => _VisionScreenState();
}

class _VisionScreenState extends State<VisionScreen> {
  final _dio = Dio();
  final _picker = ImagePicker();
  final _question = TextEditingController();

  Uint8List? _image;
  String _answer = '';
  bool _busy = false;
  List<Map<String, dynamic>> _recent = [];

  static const _prompts = [
    'What is this?',
    'Read the text',
    'Extract all text exactly',
    'Summarize this bill',
    'Translate the text to English',
    'Translate the text to Tamil',
  ];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final r = await VisionStore.all();
    if (mounted) setState(() => _recent = r);
  }

  Options get _auth =>
      Options(headers: {'Authorization': 'Bearer ${widget.token}'});

  Future<void> _capture(ImageSource source,
      {String? promptOverride, bool asCard = false}) async {
    final XFile? shot = await _picker.pickImage(
      source: source,
      imageQuality: 72,
      maxWidth: 1280,
    );
    if (shot == null) return;
    final bytes = await shot.readAsBytes();
    final q = promptOverride ?? _question.text.trim();
    setState(() {
      _image = bytes;
      _answer = '';
      _busy = true;
    });
    try {
      final form = FormData.fromMap({
        'image': MultipartFile.fromBytes(bytes, filename: 'shot.jpg'),
        if (q.isNotEmpty) 'question': q,
      });
      final resp = await _dio.post('${widget.backendUrl}/v1/vision',
          data: form,
          options: _auth.copyWith(receiveTimeout: const Duration(minutes: 4)));
      var answer = (resp.data['speak'] as String?) ?? 'No answer.';

      if (asCard) {
        // Business card -> CRM lead: extract fields from what was read, save.
        final ex = await _dio.post('${widget.backendUrl}/v1/crm/extract',
            data: {'text': answer}, options: _auth);
        final lead = await _dio.post('${widget.backendUrl}/v1/crm/leads',
            data: ex.data, options: _auth);
        final who =
            (lead.data['company'] ?? lead.data['name'] ?? 'the lead').toString();
        answer = 'Saved "$who" to your CRM.\n\nCard read:\n$answer';
      }

      setState(() => _answer = answer);
      await VisionStore.add({
        'at': DateTime.now().toIso8601String(),
        'q': asCard ? 'Business card' : (q.isEmpty ? 'What is this?' : q),
        'a': answer,
      });
      _loadRecent();
      if (!asCard) await TtsService.speak(answer);
    } catch (e) {
      setState(() => _answer = 'Vision failed: check the backend is running.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VISION')),
      body: Container(
        decoration: const BoxDecoration(gradient: Ak.bgGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _question,
                  style: const TextStyle(color: Ak.textHi),
                  decoration: InputDecoration(
                    labelText: 'Ask about the photo (optional)',
                    labelStyle: const TextStyle(color: Ak.textLo),
                    filled: true,
                    fillColor: Ak.glassFill,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Ak.glassLine),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Ak.purple, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _prompts
                      .map((p) => ActionChip(
                            label: Text(p, style: const TextStyle(fontSize: 11)),
                            backgroundColor: Ak.glassFill,
                            side: const BorderSide(color: Ak.glassLine),
                            onPressed: () =>
                                setState(() => _question.text = p),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
                AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Container(
                    decoration: Ak.glass(radius: 16),
                    clipBehavior: Clip.antiAlias,
                    child: _image != null
                        ? Image.memory(_image!, fit: BoxFit.cover)
                        : const Center(
                            child: Icon(Icons.camera_alt_outlined,
                                color: Ak.textLo, size: 48),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                        child: _btn(Icons.camera_alt, 'Camera',
                            () => _capture(ImageSource.camera))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _btn(Icons.photo_library_outlined, 'Gallery',
                            () => _capture(ImageSource.gallery),
                            filled: false)),
                  ],
                ),
                const SizedBox(height: 10),
                _btn(Icons.contact_page, 'Scan business card → CRM lead',
                    () => _capture(ImageSource.camera,
                        promptOverride:
                            'Read this business card. List the person name, '
                            'company, phone number and email.',
                        asCard: true),
                    filled: false),
                const SizedBox(height: 18),
                if (_busy) const NothingLoader(label: 'Looking…'),
                if (_answer.isNotEmpty)
                  GradientBorder(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.auto_awesome,
                              color: Ak.purple, size: 18),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.copy,
                                color: Ak.textLo, size: 18),
                            onPressed: () => Clipboard.setData(
                                ClipboardData(text: _answer)),
                          ),
                        ]),
                        Text(_answer,
                            style: const TextStyle(
                                color: Ak.textHi, fontSize: 15, height: 1.4)),
                      ],
                    ),
                  ),
                if (_recent.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Recent scans',
                          style: Ak.display(size: 13, color: Ak.textMid))),
                  const SizedBox(height: 10),
                  ..._recent.take(15).map((s) => GestureDetector(
                        onTap: () => setState(
                            () => _answer = (s['a'] ?? '').toString()),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: Ak.glass(),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text((s['q'] ?? '').toString(),
                                    style: const TextStyle(
                                        color: Ak.purple, fontSize: 12)),
                                const SizedBox(height: 2),
                                Text((s['a'] ?? '').toString(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Ak.textMid, fontSize: 12)),
                              ]),
                        ),
                      )),
                ],
              ],
            ),
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
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: filled ? Ak.goldGradient : null,
          color: filled ? null : Ak.glassFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: filled ? Colors.transparent : Ak.glassLine),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: filled ? Ak.bg0 : Ak.textHi, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  style: TextStyle(
                      color: filled ? Ak.bg0 : Ak.textHi,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }
}
