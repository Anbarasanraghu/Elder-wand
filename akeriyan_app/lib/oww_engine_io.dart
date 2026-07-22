import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// On-device wake word using an **openWakeWord** model (fast, "Hey Google"-style
/// keyword spotting). Faithful Dart port of openWakeWord's streaming pipeline:
///   mic PCM16 → melspectrogram.tflite → embedding_model.tflite → Elder_wand.tflite → score
///
/// Same public API as the old Vosk WakeWordService (start/stop/resume/listening
/// + static pauseGlobal/resumeGlobal) so the rest of the app is unchanged.
class OpenWakeWordService {
  // Model asset keys (bundled under assets/wakeword/).
  static const _melAsset = 'assets/wakeword/melspectrogram.tflite';
  static const _embAsset = 'assets/wakeword/embedding_model.tflite';
  static const _wakeAsset = 'assets/wakeword/Elder_wand.tflite';

  // openWakeWord constants.
  static const int _sr = 16000;
  static const int _chunk = 1280; // 80 ms
  static const int _melBins = 32;
  static const int _embWindow = 76;
  static const int _wakeFrames = 16;
  static const int _melMaxLen = 970; // 10 * 97
  static const int _featMaxLen = 120;

  /// Detection threshold (0..1). Tunable — lower = more sensitive.
  static double threshold = 0.5;

  static Interpreter? _mel, _emb, _wake;
  static bool _initialized = false;
  static bool _running = false;
  static bool _woken = false;
  static Function()? _onWake;

  static final AudioRecorder _rec = AudioRecorder();
  static StreamSubscription<Uint8List>? _sub;

  // Streaming state (mirrors openWakeWord AudioFeatures).
  static final List<int> _raw = <int>[]; // raw int16 samples
  static List<List<double>> _mels =
      List.generate(76, (_) => List.filled(_melBins, 1.0));
  static final List<List<double>> _feats = <List<double>>[]; // embeddings [n][96]
  static int _accum = 0;
  static final List<int> _remainder = <int>[];
  static double _dbgMax = 0;
  static int _dbgCount = 0;
  static List<int>? _melOutShape;
  static int _dbgAmp = 0; // peak raw mic amplitude over the window
  static double _dbgMelMin = 1e9, _dbgMelMax = -1e9; // transformed mel range
  static double _dbgEmbMin = 1e9, _dbgEmbMax = -1e9; // last embedding range

  bool get listening => _running;

  Future<String?> start(Function() onWake) async {
    _onWake = onWake;
    _woken = false;
    try {
      if (!_initialized) {
        _mel = await Interpreter.fromAsset(_melAsset);
        _emb = await Interpreter.fromAsset(_embAsset);
        _wake = await Interpreter.fromAsset(_wakeAsset);
        _initialized = true;
        debugPrint('[OWW] 3 models loaded');
      }
      await _startStream();
      debugPrint('[OWW] stream started, listening');
      return null;
    } catch (e, st) {
      debugPrint('[OWW] init error: $e\n$st');
      return null; // non-fatal: tap-to-talk still works
    }
  }

  static Future<void> _startStream() async {
    if (_running) return;
    if (!await _rec.hasPermission()) return;
    final stream = await _rec.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _sr,
      numChannels: 1,
      androidConfig: AndroidRecordConfig(manageBluetooth: false),
    ));
    _running = true;
    _sub = stream.listen(_onAudio, onError: (_) {});
  }

  static void _onAudio(Uint8List bytes) {
    // PCM16 little-endian → int16 samples. Use ByteData (works at any byte
    // offset) — the record plugin's chunks aren't always 2-byte aligned.
    final n = bytes.lengthInBytes ~/ 2;
    final bd = ByteData.sublistView(bytes);
    final samples = Int16List(n);
    for (int i = 0; i < n; i++) {
      samples[i] = bd.getInt16(i * 2, Endian.little);
      final a = samples[i].abs();
      if (a > _dbgAmp) _dbgAmp = a;
    }
    _streamingFeatures(samples);
    if (_feats.length >= _wakeFrames && !_woken) {
      final score = _predict();
      // DEBUG: log the peak score roughly every second so we can see levels.
      if (score > _dbgMax) _dbgMax = score;
      if (_feats.isNotEmpty) {
        for (final v in _feats.last) {
          if (v < _dbgEmbMin) _dbgEmbMin = v;
          if (v > _dbgEmbMax) _dbgEmbMax = v;
        }
      }
      if (++_dbgCount >= 12) {
        debugPrint('[OWW] peak≈${_dbgMax.toStringAsFixed(3)} '
            'amp=$_dbgAmp mel=[${_dbgMelMin.toStringAsFixed(2)},${_dbgMelMax.toStringAsFixed(2)}] '
            'emb=[${_dbgEmbMin.toStringAsFixed(2)},${_dbgEmbMax.toStringAsFixed(2)}]');
        _dbgMax = 0;
        _dbgCount = 0;
        _dbgAmp = 0;
        _dbgMelMin = 1e9;
        _dbgMelMax = -1e9;
        _dbgEmbMin = 1e9;
        _dbgEmbMax = -1e9;
      }
      if (score > threshold) {
        debugPrint('[OWW] WAKE! score=${score.toStringAsFixed(3)}');
        _woken = true;
        _fireWake();
      }
    }
  }

  // ---- openWakeWord streaming feature extraction ----
  static void _streamingFeatures(Int16List x) {
    var buf = <int>[];
    if (_remainder.isNotEmpty) {
      buf.addAll(_remainder);
      _remainder.clear();
    }
    buf.addAll(x);

    if (_accum + buf.length >= _chunk) {
      final rem = (_accum + buf.length) % _chunk;
      if (rem != 0) {
        final even = buf.sublist(0, buf.length - rem);
        _raw.addAll(even);
        _accum += even.length;
        _remainder.addAll(buf.sublist(buf.length - rem));
      } else {
        _raw.addAll(buf);
        _accum += buf.length;
      }
    } else {
      _accum += buf.length;
      _raw.addAll(buf);
    }
    if (_raw.length > _sr * 10) {
      _raw.removeRange(0, _raw.length - _sr * 10);
    }

    if (_accum >= _chunk && _accum % _chunk == 0) {
      _streamingMel(_accum);
      for (int i = _accum ~/ _chunk - 1; i >= 0; i--) {
        final ndxNeg = -8 * i;
        final end = ndxNeg == 0 ? _mels.length : _mels.length + ndxNeg;
        final start = end - _embWindow;
        if (start >= 0 && end <= _mels.length) {
          _feats.add(_embed(_mels.sublist(start, end)));
        }
      }
      _accum = 0;
    }
    if (_feats.length > _featMaxLen) {
      _feats.removeRange(0, _feats.length - _featMaxLen);
    }
  }

  static void _streamingMel(int nSamples) {
    final take = nSamples + 160 * 3;
    final startIdx = _raw.length > take ? _raw.length - take : 0;
    final audio = _raw.sublist(startIdx); // raw int16 values as-is
    final frames = _melspectrogram(audio); // [frames][32]
    _mels.addAll(frames);
    if (_mels.length > _melMaxLen) {
      _mels = _mels.sublist(_mels.length - _melMaxLen);
    }
  }

  static List<List<double>> _melspectrogram(List<int> audio) {
    final n = audio.length;
    _mel!.resizeInputTensor(0, [1, n]);
    _mel!.allocateTensors();
    // openWakeWord feeds raw int16 values as float32 (NOT normalised).
    final input = [List<double>.generate(n, (i) => audio[i].toDouble())];
    final outShape = _mel!.getOutputTensor(0).shape;
    final output = _nested(outShape);
    _mel!.run(input, output);
    _melOutShape = outShape;
    // Squeeze to [frames][32] and apply openWakeWord transform: x/10 + 2.
    final flat = _flatten(output);
    final frames = flat.length ~/ _melBins;
    final out = List.generate(
        frames,
        (f) => List<double>.generate(
            _melBins, (b) => flat[f * _melBins + b] / 10.0 + 2.0));
    for (final row in out) {
      for (final v in row) {
        if (v < _dbgMelMin) _dbgMelMin = v;
        if (v > _dbgMelMax) _dbgMelMax = v;
      }
    }
    return out;
  }

  static List<double> _embed(List<List<double>> window76) {
    // input [1, 76, 32, 1]
    final input = [
      window76.map((row) => row.map((v) => [v]).toList()).toList()
    ];
    _emb!.resizeInputTensor(0, [1, _embWindow, _melBins, 1]);
    _emb!.allocateTensors();
    final output = _nested(_emb!.getOutputTensor(0).shape);
    _emb!.run(input, output);
    return _flatten(output); // 96 values
  }

  static double _predict() {
    final feats = _feats.sublist(_feats.length - _wakeFrames); // [16][96]
    final input = [feats]; // [1,16,96]
    final output = _nested(_wake!.getOutputTensor(0).shape);
    _wake!.run(input, output);
    return _flatten(output).first;
  }

  // ---- helpers ----
  static dynamic _nested(List<int> shape) {
    if (shape.length == 1) return List<double>.filled(shape[0], 0.0);
    return List.generate(shape[0], (_) => _nested(shape.sublist(1)));
  }

  static List<double> _flatten(dynamic x, [List<double>? acc]) {
    acc ??= <double>[];
    if (x is num) {
      acc.add(x.toDouble());
    } else if (x is List) {
      for (final e in x) {
        _flatten(e, acc);
      }
    }
    return acc;
  }

  static Future<void> _fireWake() async {
    await _stopStream();
    _onWake?.call();
  }

  static Future<void> _stopStream() async {
    try {
      await _sub?.cancel();
      _sub = null;
      if (_running) await _rec.stop();
    } catch (_) {}
    _running = false;
  }

  Future<void> stop() => _stopStream();

  Future<void> resume() async {
    _woken = false;
    _resetState();
    await _startStream();
  }

  static void _resetState() {
    _raw.clear();
    _remainder.clear();
    _feats.clear();
    _accum = 0;
    _mels = List.generate(76, (_) => List.filled(_melBins, 1.0));
  }

  static Future<void> pauseGlobal() => _stopStream();

  static Future<void> resumeGlobal() async {
    _woken = false;
    _resetState();
    await _startStream();
  }
}
