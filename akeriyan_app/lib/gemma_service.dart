import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

/// On-device LLM brain powered by flutter_gemma 1.x + the LiteRT-LM engine.
///
/// Runs Gemma entirely on the phone — no backend, no network, no PC. Defaults to
/// **Gemma 4 E4B** (the most capable that runs well on a 12 GB phone), which is a
/// `.litertlm` model handled by [LiteRtLmEngine]. (The older `.task` gemma-3n
/// files are NOT readable — they need this LiteRT-LM path instead.)
class GemmaService {
  static InferenceModel? _model;
  static InferenceChat? _chat;

  /// Most capable default: Gemma 4 E4B (LiteRT-LM). ~4.4 GB — big download, but
  /// the plugin uses a resumable background downloader. Swap the `E4B` for `E2B`
  /// in the URL for a smaller/faster (~3 GB) but still very capable model.
  static const String defaultModelUrl =
      'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/'
      'resolve/main/gemma-4-E4B-it.litertlm';

  static bool get isLoaded => _model != null && _chat != null;

  /// Register the LiteRT-LM engine. Call once at app startup (main()).
  static Future<void> initEngine() async {
    await FlutterGemma.initialize(
      inferenceEngines: const [LiteRtLmEngine()],
    );
  }

  // ---- download state (owned by the service; survives leaving the screen) ----
  static final ValueNotifier<GemmaDownload> download =
      ValueNotifier<GemmaDownload>(const GemmaDownload());

  static bool get isDownloading => download.value.running;

  /// True if a model is installed and ready to load.
  static Future<bool> modelFileExists() async {
    try {
      return (await FlutterGemma.listInstalledModels()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Download + install the model via the plugin's robust (resumable, background)
  /// downloader. Sends the HuggingFace token when given. Fire-and-forget; watch
  /// [download]. Progress is a percentage (0..100).
  static Future<void> startDownload(String url, {String? hfToken}) async {
    if (isDownloading) return;
    final sw = Stopwatch()..start();
    download.value = const GemmaDownload(running: true);
    final token = (hfToken == null || hfToken.trim().isEmpty) ? null : hfToken.trim();
    try {
      await FlutterGemma
          .installModel(
            modelType: ModelType.gemma4,
            fileType: ModelFileType.litertlm,
          )
          .fromNetwork(url, token: token)
          .withProgress((p) {
            download.value = GemmaDownload(
              percent: p,
              running: true,
              elapsedSec: sw.elapsed.inSeconds,
            );
          })
          .install();
      download.value = GemmaDownload(
          percent: 100, done: true, elapsedSec: sw.elapsed.inSeconds);
    } catch (e) {
      download.value = GemmaDownload(error: e.toString());
    }
  }

  /// Remove all installed models (start fresh).
  static Future<void> deleteModelFile() async {
    await close();
    try {
      for (final id in await FlutterGemma.listInstalledModels()) {
        await FlutterGemma.uninstallModel(id);
      }
    } catch (_) {}
    download.value = const GemmaDownload();
  }

  /// Load the active model into memory + open a chat. GPU-accelerated.
  static Future<void> load({int maxTokens = 1024}) async {
    await close();
    _model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: PreferredBackend.gpu,
    );
    _chat = await _model!.createChat(temperature: 0.6, topK: 40, topP: 0.9);
  }

  /// Stream a reply token-by-token. Throws if the model isn't loaded.
  static Stream<String> ask(String prompt) async* {
    final chat = _chat;
    if (chat == null) {
      throw StateError('Gemma model not loaded — call load() first.');
    }
    await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
    await for (final r in chat.generateChatResponseAsync()) {
      if (r is TextResponse) yield r.token;
    }
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
  final int percent; // 0..100
  final bool running;
  final bool done;
  final String? error;
  final int elapsedSec;

  const GemmaDownload({
    this.percent = 0,
    this.running = false,
    this.done = false,
    this.error,
    this.elapsedSec = 0,
  });

  double? get fraction => (running || percent > 0) ? percent / 100.0 : null;
}
