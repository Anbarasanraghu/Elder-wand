import 'dart:async';

import 'package:flutter/material.dart';

import 'gemma_service.dart';

/// Proof-of-concept screen to try the on-device Gemma brain on the real phone:
/// get a model onto the device, load it, and measure answer speed + quality.
class GemmaTestScreen extends StatefulWidget {
  const GemmaTestScreen({super.key});

  @override
  State<GemmaTestScreen> createState() => _GemmaTestScreenState();
}

class _GemmaTestScreenState extends State<GemmaTestScreen> {
  final _urlCtrl = TextEditingController(text: GemmaService.defaultModelUrl);
  final _pathCtrl = TextEditingController(text: '/sdcard/Download/gemma.task');
  final _askCtrl = TextEditingController(text: 'Tell me a fun fact about space.');

  String _status = 'Not loaded.';
  int _progress = 0;
  bool _busy = false;
  bool _ready = false;
  String _answer = '';
  String _timing = '';

  @override
  void initState() {
    super.initState();
    _refreshInstalled();
  }

  Future<void> _refreshInstalled() async {
    final installed = await GemmaService.isInstalled();
    setState(() => _status =
        installed ? 'Model file installed. Tap "Load model".' : 'No model installed yet.');
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _progress = 0;
      _status = 'Downloading model...';
    });
    try {
      await for (final p in GemmaService.downloadFromUrl(_urlCtrl.text.trim())) {
        setState(() => _progress = p);
      }
      setState(() => _status = 'Downloaded. Tap "Load model".');
    } catch (e) {
      setState(() => _status = 'Download failed: $e\n(Gemma is gated — use the '
          '"Load from file" path instead.)');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _loadFromFile() async {
    setState(() {
      _busy = true;
      _status = 'Registering file...';
    });
    try {
      await GemmaService.loadFromPath(_pathCtrl.text.trim());
      setState(() => _status = 'File registered. Tap "Load model".');
    } catch (e) {
      setState(() => _status = 'Could not register file: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _loadModel() async {
    setState(() {
      _busy = true;
      _status = 'Loading model into memory (first time is slow)...';
    });
    final t0 = DateTime.now();
    try {
      await GemmaService.load(maxTokens: 1024);
      final dt = DateTime.now().difference(t0).inMilliseconds / 1000;
      setState(() {
        _ready = true;
        _status = 'Model loaded in ${dt.toStringAsFixed(1)}s. Ask away!';
      });
    } catch (e) {
      setState(() => _status = 'Load failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _ask() async {
    if (!_ready) return;
    setState(() {
      _busy = true;
      _answer = '';
      _timing = '';
    });
    final t0 = DateTime.now();
    int? firstMs;
    var tokens = 0;
    try {
      await for (final tok in GemmaService.ask(_askCtrl.text.trim())) {
        firstMs ??= DateTime.now().difference(t0).inMilliseconds;
        tokens++;
        setState(() => _answer += tok);
      }
      final totalMs = DateTime.now().difference(t0).inMilliseconds;
      final tps = tokens / (totalMs / 1000);
      setState(() => _timing =
          'first token: ${((firstMs ?? 0) / 1000).toStringAsFixed(2)}s  •  '
          '$tokens tokens  •  ${tps.toStringAsFixed(1)} tok/s');
    } catch (e) {
      setState(() => _answer = 'Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _pathCtrl.dispose();
    _askCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('On-device Gemma (POC)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_status),
          if (_busy && _progress > 0) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _progress / 100),
            Text('$_progress%'),
          ],
          const Divider(height: 32),

          const Text('Option A — download from a PUBLIC .task URL',
              style: TextStyle(fontWeight: FontWeight.bold)),
          TextField(controller: _urlCtrl, maxLines: 2,
              decoration: const InputDecoration(labelText: 'model .task URL')),
          const SizedBox(height: 8),
          FilledButton(onPressed: _busy ? null : _download,
              child: const Text('Download')),

          const Divider(height: 32),
          const Text('Option B — load a file already on the phone (gated models)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          TextField(controller: _pathCtrl,
              decoration: const InputDecoration(labelText: 'on-device .task path')),
          const SizedBox(height: 8),
          FilledButton(onPressed: _busy ? null : _loadFromFile,
              child: const Text('Register file')),

          const Divider(height: 32),
          FilledButton.icon(
            onPressed: _busy ? null : _loadModel,
            icon: const Icon(Icons.memory),
            label: const Text('Load model'),
          ),

          const Divider(height: 32),
          TextField(controller: _askCtrl, maxLines: 2,
              decoration: const InputDecoration(labelText: 'your question')),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: (_busy || !_ready) ? null : _ask,
            icon: const Icon(Icons.send),
            label: const Text('Ask on-device'),
          ),
          const SizedBox(height: 16),
          if (_answer.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_answer),
            ),
          if (_timing.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_timing, style: const TextStyle(color: Colors.teal)),
          ],
        ],
      ),
    );
  }
}
