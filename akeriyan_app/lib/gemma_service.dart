import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/pigeon.g.dart';

/// On-device LLM brain (proof-of-concept) powered by flutter_gemma.
///
/// Runs a Gemma model entirely on the phone — no backend, no network, no PC.
/// This is a POC to prove speed + answer quality on the real device before we
/// route the whole assistant through it.
///
/// Getting the model onto the phone (Gemma is license-gated on HuggingFace):
///   Option A — public URL: paste a direct .task URL and tap Download.
///   Option B — manual file (reliable for gated models):
///     1. Accept the license at huggingface.co/litert-community/Gemma3-1B-IT
///     2. Download the .task file.
///     3. Push it to the phone, e.g.
///        adb push Gemma3-1B-IT_...q4_ekv4096.task /sdcard/Download/gemma.task
///     4. Enter that path and tap "Load from file".
class GemmaService {
  static final _gemma = FlutterGemmaPlugin.instance;
  static InferenceModel? _model;
  static InferenceChat? _chat;

  /// Upgraded default: Gemma 3 Nano E2B (int4), ~3.1 GB — much smarter than the
  /// 1B and multimodal (can also see images). Your 12 GB phone handles it well.
  /// Gated: accept the license at huggingface.co/google/gemma-3n-E2B-it-litert-preview
  /// then use your HF token. (The tiny Gemma3-1B-IT/gemma3-1b-it-int4.task is a
  /// lighter fallback if you want a faster/smaller model.)
  static const String defaultModelUrl =
      'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/'
      'gemma-3n-E2B-it-int4.task';

  static bool get isLoaded => _model != null && _chat != null;

  static Future<bool> isInstalled() => _gemma.modelManager.isModelInstalled;

  static const _kReadyPath = 'gemma_ready_model_path';

  /// Per-URL file path — each model keeps its OWN file so a half-finished
  /// download of one model can never corrupt another (the bug that produced
  /// "Unable to read the file in zip archive" when switching 1B <-> E2B).
  static Future<String> pathForUrl(String url) async {
    final dir = await getApplicationDocumentsDirectory();
    final segs = Uri.parse(url).pathSegments;
    final name = segs.isNotEmpty ? segs.last : 'model.task';
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '${dir.path}/$safe';
  }

  /// Path of a fully-downloaded, ready-to-load model (or null).
  static Future<String?> readyModelPath() async {
    final p = (await SharedPreferences.getInstance()).getString(_kReadyPath);
    return (p != null && await File(p).exists()) ? p : null;
  }

  static bool _cancelled = false;

  /// Live download state, owned by the service (not any screen). The download
  /// keeps running when you leave the page; reopening just re-reads this.
  static final ValueNotifier<GemmaDownload> download =
      ValueNotifier<GemmaDownload>(const GemmaDownload());

  static bool get isDownloading => download.value.running;

  /// Start a RESUMABLE, auto-retrying model download. If the connection drops
  /// mid-file (common on big files / flaky networks), it reconnects and resumes
  /// from the bytes already saved using an HTTP Range request, instead of
  /// failing or restarting. Publishes progress to [download]. Fire-and-forget.
  static Future<void> startDownload(String url, {String? hfToken}) async {
    if (isDownloading) return;
    _cancelled = false;
    final savePath = await pathForUrl(url);
    final file = File(savePath);
    final dio = Dio();
    final sw = Stopwatch()..start();
    var lastReceived = 0;
    var lastMs = 0;
    const maxRetries = 12;
    var attempt = 0;

    download.value = const GemmaDownload(running: true);
    try {
      while (true) {
        var start = await file.exists() ? await file.length() : 0;
        try {
          final headers = <String, String>{};
          if (hfToken != null && hfToken.trim().isNotEmpty) {
            headers['Authorization'] = 'Bearer ${hfToken.trim()}';
          }
          if (start > 0) headers['Range'] = 'bytes=$start-';

          final resp = await dio.get<ResponseBody>(
            url,
            options: Options(
              responseType: ResponseType.stream,
              followRedirects: true,
              maxRedirects: 5,
              receiveTimeout: Duration.zero,
              headers: headers,
              validateStatus: (s) => s != null && s < 400,
            ),
          );

          // If we asked to resume but the server sent the whole file (200, not
          // 206), start over from scratch so we don't corrupt the file.
          var received = start;
          var mode = FileMode.append;
          if (start > 0 && resp.statusCode == 200) {
            start = 0;
            received = 0;
            mode = FileMode.write;
          }

          // Total size: from Content-Range (bytes s-e/TOTAL) or Content-Length.
          var total = 0;
          final cr = resp.headers.value('content-range');
          if (cr != null && cr.contains('/')) {
            total = int.tryParse(cr.split('/').last.trim()) ?? 0;
          } else {
            final cl = resp.headers.value('content-length');
            total = (int.tryParse(cl ?? '0') ?? 0) + start;
          }

          final sink = file.openWrite(mode: mode);
          try {
            await for (final chunk in resp.data!.stream) {
              if (_cancelled) throw const _CancelledException();
              sink.add(chunk);
              received += chunk.length;
              final nowMs = sw.elapsedMilliseconds;
              var speed = download.value.speed;
              var eta = download.value.eta;
              if (nowMs - lastMs >= 400) {
                final dt = (nowMs - lastMs) / 1000.0;
                if (dt > 0 && lastMs > 0) {
                  speed = (received - lastReceived) / dt;
                  eta = speed > 0 ? (total - received) / speed : 0;
                }
                lastReceived = received;
                lastMs = nowMs;
              }
              download.value = GemmaDownload(
                  received: received,
                  total: total,
                  speed: speed,
                  eta: eta,
                  running: true);
            }
          } finally {
            await sink.flush();
            await sink.close();
          }

          // Done when we've reached the known total (or total is unknown).
          if (total == 0 || received >= total) break;
          // Stream ended early without an error — loop resumes via Range.
          throw const _IncompleteException();
        } on _CancelledException {
          rethrow;
        } on DioException catch (e) {
          // 416 = Range Not Satisfiable: the file is already fully downloaded.
          if (e.response?.statusCode == 416 && start > 0) break;
          if (_cancelled) rethrow;
          attempt++;
          if (attempt > maxRetries) rethrow;
          download.value = GemmaDownload(
            received: download.value.received,
            total: download.value.total,
            running: true,
          );
          await Future<void>.delayed(Duration(seconds: 2 + attempt));
        } catch (e) {
          if (_cancelled) rethrow;
          attempt++;
          if (attempt > maxRetries) rethrow;
          // brief backoff, then resume from the bytes already on disk
          download.value = GemmaDownload(
            received: download.value.received,
            total: download.value.total,
            running: true,
            speed: 0,
            eta: 0,
          );
          await Future<void>.delayed(Duration(seconds: 2 + attempt));
        }
      }
      await _gemma.modelManager.setModelPath(savePath);
      (await SharedPreferences.getInstance()).setString(_kReadyPath, savePath);
      download.value = GemmaDownload(
          received: download.value.received,
          total: download.value.total,
          done: true);
    } on _CancelledException {
      download.value = const GemmaDownload();
    } catch (e) {
      download.value = GemmaDownload(
          received: download.value.received,
          total: download.value.total,
          error: e.toString());
    }
  }

  /// Cancel an in-flight download (keeps the partial file so it can resume).
  static void cancelDownload() {
    _cancelled = true;
  }

  /// Delete ALL downloaded/partial model files (start completely fresh).
  static Future<void> deleteModelFile() async {
    await close();
    final dir = await getApplicationDocumentsDirectory();
    for (final f in dir.listSync()) {
      if (f is File &&
          (f.path.endsWith('.task') || f.path.endsWith('gemma_model.task'))) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    (await SharedPreferences.getInstance()).remove(_kReadyPath);
    download.value = const GemmaDownload();
  }

  /// True if a fully-downloaded model is ready to load.
  static Future<bool> modelFileExists() async =>
      (await readyModelPath()) != null;

  /// Register an already-on-device .task file (the reliable path for gated
  /// models). No copy/download — the plugin reads it in place.
  static Future<void> loadFromPath(String path) =>
      _gemma.modelManager.setModelPath(path);

  /// Create the inference model + chat session. Call after the model is
  /// installed (via download or loadFromPath). GPU-accelerated when available.
  static Future<void> load({int maxTokens = 1024}) async {
    await close();
    // Register the fully-downloaded model file (survives app restarts).
    final ready = await readyModelPath();
    if (ready == null) {
      throw StateError('No fully-downloaded model — download one first.');
    }
    await _gemma.modelManager.setModelPath(ready);
    _model = await _gemma.createModel(
      modelType: ModelType.gemmaIt,
      maxTokens: maxTokens,
      preferredBackend: PreferredBackend.gpu,
    );
    _chat = await _model!.createChat(
      temperature: 0.6,
      topK: 40,
      topP: 0.9,
      tokenBuffer: 256,
    );
  }

  /// Stream a reply token-by-token. Throws if the model isn't loaded.
  static Stream<String> ask(String prompt) async* {
    final chat = _chat;
    if (chat == null) {
      throw StateError('Gemma model not loaded — call load() first.');
    }
    await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
    yield* chat.generateChatResponseAsync();
  }

  static Future<void> close() async {
    try {
      await _model?.close();
    } catch (_) {}
    _model = null;
    _chat = null;
  }
}

/// Immutable snapshot of the current download, published via
/// [GemmaService.download] so any screen can reflect the live state.
class GemmaDownload {
  final int received;
  final int total;
  final double speed; // bytes/sec
  final double eta; // seconds remaining
  final bool running;
  final bool done;
  final String? error;

  const GemmaDownload({
    this.received = 0,
    this.total = 0,
    this.speed = 0,
    this.eta = 0,
    this.running = false,
    this.done = false,
    this.error,
  });

  double? get fraction => total > 0 ? received / total : null;
}

class _CancelledException implements Exception {
  const _CancelledException();
}

class _IncompleteException implements Exception {
  const _IncompleteException();
}
