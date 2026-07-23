import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

import 'gemma_service.dart';

/// Proof-of-concept screen to try the on-device Gemma brain on the real phone:
/// download a model (with live speed/size/ETA that survives leaving the page),
/// load it, and measure answer speed + quality.
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

  // On-device speech-to-text + text-to-speech (no PC).
  final stt.SpeechToText _stt = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _sttReady = false;
  bool _listening = false;

  String _status = 'Checking...';
  bool _busy = false;
  bool _ready = false;
  String _answer = '';
  String _timing = '';

  @override
  void initState() {
    super.initState();
    GemmaService.download.addListener(_onDownload);
    _tts.setLanguage('en-US');
    _tts.awaitSpeakCompletion(true);
    _refresh();
  }

  /// Fully on-device voice turn: mic -> speech_to_text -> Gemma -> flutter_tts.
  /// No backend, no network, no PC.
  Future<void> _talk() async {
    if (!_ready) {
      setState(() => _status = 'Load the model first.');
      return;
    }
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    _sttReady = _sttReady || await _stt.initialize();
    if (!_sttReady) {
      setState(() => _status = 'Speech recognition unavailable (mic permission?).');
      return;
    }
    setState(() {
      _listening = true;
      _answer = '';
      _status = 'Listening...';
    });
    await _stt.listen(
      onResult: (r) {
        setState(() => _askCtrl.text = r.recognizedWords);
        if (r.finalResult) {
          setState(() {
            _listening = false;
            _status = 'Thinking...';
          });
          if (r.recognizedWords.trim().isNotEmpty) _ask();
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  void _onDownload() {
    final d = GemmaService.download.value;
    if (d.done) {
      setState(() => _status = 'Download complete. Tap "Load model".');
    } else if (d.error != null) {
      setState(() => _status = d.error!.contains('cancel')
          ? 'Download cancelled.'
          : 'Download failed: ${d.error}\n(If the model is gated, add your '
              'HuggingFace token and accept the license on the model page.)');
    }
  }

  Future<void> _refresh() async {
    if (GemmaService.isDownloading) {
      setState(() => _status = 'Download in progress...');
      return;
    }
    final exists = await GemmaService.modelFileExists();
    setState(() => _status = exists
        ? 'Model already downloaded. Tap "Load model".'
        : 'No model yet. Add your HuggingFace token and tap Download.');
  }

  String _elapsed(int s) {
    final m = s ~/ 60, sec = s % 60;
    return m > 0 ? '${m}m ${sec}s' : '${sec}s';
  }

  String _mb(int b) =>
      b <= 0 ? '—' : '${(b / (1024 * 1024)).toStringAsFixed(0)} MB';
  String _spd(double bps) =>
      bps <= 0 ? '—' : '${(bps / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  String _eta(double s) {
    if (s <= 0 || s.isInfinite || s.isNaN) return '—';
    final m = s ~/ 60, sec = (s % 60).round();
    return m > 0 ? '${m}m ${sec}s' : '${sec}s';
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

  void _download() {
    // Fire-and-forget: the service owns the download, so it keeps running even
    // if you leave this screen. We just watch GemmaService.download.
    GemmaService.startDownload(_urlCtrl.text.trim(), hfToken: _tokenCtrl.text);
    setState(() => _status = 'Downloading...');
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
      setState(() {
        _status = 'Speaking...';
        _timing =
            'first token: ${((firstMs ?? 0) / 1000).toStringAsFixed(2)}s  •  '
            '$tokens tokens  •  ${tps.toStringAsFixed(1)} tok/s';
      });
      // Speak the reply on-device (flutter_tts) — the last PC-free piece.
      if (_answer.trim().isNotEmpty) await _tts.speak(_answer.trim());
      setState(() => _status = 'Done.');
    } catch (e) {
      setState(() => _answer = 'Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    GemmaService.download.removeListener(_onDownload);
    _stt.stop();
    _tts.stop();
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
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
          const SizedBox(height: 16),

          // ---- Download card ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Download model',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

                  // live progress — driven by the service, survives navigation
                  ValueListenableBuilder<GemmaDownload>(
                    valueListenable: GemmaService.download,
                    builder: (_, d, _) {
                      if (!d.running && d.percent == 0) {
                        return const SizedBox.shrink();
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LinearProgressIndicator(value: d.fraction),
                          const SizedBox(height: 6),
                          Text(
                            '${d.percent}%   •   ${_elapsed(d.elapsedSec)} elapsed',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _stat('Downloaded',
                                  '${_mb(d.received)}${d.total > 0 ? ' / ${_mb(d.total)}' : ''}'),
                              _stat('Speed', _spd(d.speed)),
                              _stat('ETA', _eta(d.eta)),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                      );
                    },
                  ),

                  ValueListenableBuilder<GemmaDownload>(
                    valueListenable: GemmaService.download,
                    builder: (_, d, _) => Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: (d.running || _busy) ? null : _download,
                            icon: const Icon(Icons.download),
                            label: Text(d.running ? 'Downloading...' : 'Download'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              await GemmaService.deleteModelFile();
                              setState(() {
                                _ready = false;
                                _status = 'Deleted. Download a fresh copy.';
                              });
                            },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Start over (delete)'),
                    ),
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
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_busy || !_ready) ? null : _ask,
                  icon: const Icon(Icons.send),
                  label: const Text('Ask (type)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: !_ready ? null : _talk,
                  style: FilledButton.styleFrom(
                      backgroundColor:
                          _listening ? Colors.red : null),
                  icon: Icon(_listening ? Icons.stop : Icons.mic),
                  label: Text(_listening ? 'Listening' : 'Talk'),
                ),
              ),
            ],
          ),
          const Text(
            'Talk = fully on-device: your voice → text → Gemma → spoken reply. '
            'No PC, no internet.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
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
