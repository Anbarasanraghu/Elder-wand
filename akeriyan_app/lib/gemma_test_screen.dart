import 'dart:async';

import 'package:flutter/material.dart';

import 'gemma_service.dart';

/// Proof-of-concept screen to try the on-device Gemma brain on the real phone:
/// download a model (with live speed/size/ETA), load it, and measure answer
/// speed + quality.
class GemmaTestScreen extends StatefulWidget {
  const GemmaTestScreen({super.key});

  @override
  State<GemmaTestScreen> createState() => _GemmaTestScreenState();
}

class _GemmaTestScreenState extends State<GemmaTestScreen> {
  final _urlCtrl = TextEditingController(text: GemmaService.defaultModelUrl);
  final _tokenCtrl = TextEditingController();
  final _askCtrl =
      TextEditingController(text: 'Tell me a fun fact about space.');

  String _status = 'Checking...';
  bool _busy = false;
  bool _downloading = false;
  bool _ready = false;

  // Download stats
  int _received = 0;
  int _total = 0;
  double _speed = 0; // bytes/sec
  double _eta = 0; // seconds
  final _sw = Stopwatch();
  int _lastReceived = 0;
  int _lastMs = 0;

  String _answer = '';
  String _timing = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final exists = await GemmaService.modelFileExists();
    setState(() => _status = exists
        ? 'Model already downloaded. Tap "Load model".'
        : 'No model yet. Paste your HuggingFace token and tap Download.');
  }

  // ---- formatters ----
  String _mb(int b) => '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  String _spd(double bps) => bps <= 0
      ? '—'
      : '${(bps / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  String _eta_(double s) {
    if (s <= 0 || s.isInfinite || s.isNaN) return '—';
    final m = (s ~/ 60), sec = (s % 60).round();
    return m > 0 ? '${m}m ${sec}s' : '${sec}s';
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _downloading = true;
      _received = 0;
      _total = 0;
      _speed = 0;
      _eta = 0;
      _lastReceived = 0;
      _lastMs = 0;
      _status = 'Connecting...';
    });
    _sw
      ..reset()
      ..start();
    try {
      await GemmaService.downloadModel(
        _urlCtrl.text.trim(),
        hfToken: _tokenCtrl.text,
        onProgress: (received, total) {
          final nowMs = _sw.elapsedMilliseconds;
          // Update speed roughly every 400 ms for a stable readout.
          if (nowMs - _lastMs >= 400 || received == total) {
            final dt = (nowMs - _lastMs) / 1000.0;
            if (dt > 0 && _lastMs > 0) {
              _speed = (received - _lastReceived) / dt;
              _eta = _speed > 0 ? (total - received) / _speed : 0;
            }
            _lastReceived = received;
            _lastMs = nowMs;
          }
          setState(() {
            _received = received;
            _total = total;
            _status = 'Downloading...';
          });
        },
      );
      setState(() => _status = 'Download complete. Tap "Load model".');
    } catch (e) {
      final msg = e.toString().contains('cancel')
          ? 'Download cancelled.'
          : 'Download failed: $e\n(If the model is gated, add your HuggingFace '
              'token above — accept the license on the model page first.)';
      setState(() => _status = msg);
    } finally {
      _sw.stop();
      setState(() {
        _busy = false;
        _downloading = false;
      });
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
    _tokenCtrl.dispose();
    _askCtrl.dispose();
    super.dispose();
  }

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final pct = _total > 0 ? _received / _total : null;
    return Scaffold(
      appBar: AppBar(title: const Text('On-device Gemma (POC)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_status),
          const SizedBox(height: 16),

          // ---- Download card ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Download model',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _tokenCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'HuggingFace token (for gated Gemma models)',
                      hintText: 'hf_...',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _urlCtrl,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'model .task URL',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // live progress
                  if (_downloading || _received > 0) ...[
                    LinearProgressIndicator(value: pct),
                    const SizedBox(height: 4),
                    Text(
                      pct != null
                          ? '${(pct * 100).toStringAsFixed(1)}%'
                          : 'starting...',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _stat('Downloaded',
                            '${_mb(_received)}${_total > 0 ? ' / ${_mb(_total)}' : ''}'),
                        _stat('Speed', _spd(_speed)),
                        _stat('ETA', _eta_(_eta)),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _download,
                          icon: const Icon(Icons.download),
                          label: const Text('Download'),
                        ),
                      ),
                      if (_downloading) ...[
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: GemmaService.cancelDownload,
                          child: const Text('Cancel'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          FilledButton.icon(
            onPressed: _busy ? null : _loadModel,
            icon: const Icon(Icons.memory),
            label: const Text('Load model'),
          ),

          const Divider(height: 32),
          TextField(
            controller: _askCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'your question',
              border: OutlineInputBorder(),
            ),
          ),
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
