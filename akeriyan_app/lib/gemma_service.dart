import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
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

  /// Default first-test model: Gemma 3 1B (int4), ~550 MB. Small + fast to prove
  /// the pipeline. Swap to a Nano E2B/E4B .task later for a smarter, multimodal
  /// model (your 12 GB phone can handle it).
  static const String defaultModelUrl =
      'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/'
      'gemma3-1b-it-int4.task';

  static bool get isLoaded => _model != null && _chat != null;

  static Future<bool> isInstalled() => _gemma.modelManager.isModelInstalled;

  /// Where the model file lives once downloaded.
  static Future<String> modelFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/gemma_model.task';
  }

  static CancelToken? _dlCancel;

  /// Download the model with `dio` so we get real byte-level progress (received,
  /// total) for a proper UI — speed, size, ETA. Sends a HuggingFace bearer token
  /// when given, so gated Gemma models download directly. Saves to app storage
  /// and registers it with flutter_gemma. Returns the saved path.
  static Future<String> downloadModel(
    String url, {
    String? hfToken,
    required void Function(int received, int total) onProgress,
  }) async {
    final savePath = await modelFilePath();
    _dlCancel = CancelToken();
    final dio = Dio();
    await dio.download(
      url,
      savePath,
      cancelToken: _dlCancel,
      onReceiveProgress: onProgress,
      options: Options(
        followRedirects: true,
        maxRedirects: 5,
        receiveTimeout: Duration.zero, // large file — don't time out
        headers: (hfToken != null && hfToken.trim().isNotEmpty)
            ? {'Authorization': 'Bearer ${hfToken.trim()}'}
            : null,
      ),
    );
    await _gemma.modelManager.setModelPath(savePath);
    return savePath;
  }

  /// Cancel an in-flight download.
  static void cancelDownload() => _dlCancel?.cancel('cancelled by user');

  /// True if the model file has already been downloaded to app storage.
  static Future<bool> modelFileExists() async =>
      File(await modelFilePath()).exists();

  /// Register an already-on-device .task file (the reliable path for gated
  /// models). No copy/download — the plugin reads it in place.
  static Future<void> loadFromPath(String path) =>
      _gemma.modelManager.setModelPath(path);

  /// Create the inference model + chat session. Call after the model is
  /// installed (via download or loadFromPath). GPU-accelerated when available.
  static Future<void> load({int maxTokens = 1024}) async {
    await close();
    // Make sure the on-disk model is registered (e.g. after an app restart).
    if (!await _gemma.modelManager.isModelInstalled) {
      final p = await modelFilePath();
      if (await File(p).exists()) {
        await _gemma.modelManager.setModelPath(p);
      }
    }
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
