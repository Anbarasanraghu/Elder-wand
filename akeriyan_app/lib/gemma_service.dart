import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import 'memory_store.dart';

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
    final token =
        (hfToken == null || hfToken.trim().isEmpty) ? null : hfToken.trim();

    // Fetch total size first (a 1-byte ranged GET → Content-Range: .../TOTAL),
    // so we can show downloaded MB / speed / ETA from the plugin's % progress.
    var total = 0;
    try {
      final r = await Dio().get<List<int>>(
        url,
        options: Options(
          followRedirects: true,
          responseType: ResponseType.bytes,
          validateStatus: (s) => s != null && s < 400,
          headers: {
            'Range': 'bytes=0-0',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );
      final cr = r.headers.value('content-range');
      if (cr != null && cr.contains('/')) {
        total = int.tryParse(cr.split('/').last.trim()) ?? 0;
      }
    } catch (_) {}

    var lastReceived = 0;
    var lastMs = 0;
    try {
      await FlutterGemma
          .installModel(
            modelType: ModelType.gemma4,
            fileType: ModelFileType.litertlm,
          )
          .fromNetwork(url, token: token)
          .withProgress((p) {
            final received = total > 0 ? (p / 100.0 * total).round() : 0;
            final nowMs = sw.elapsedMilliseconds;
            var speed = download.value.speed;
            var eta = download.value.eta;
            if (nowMs - lastMs >= 500) {
              final dt = (nowMs - lastMs) / 1000.0;
              if (dt > 0 && lastMs > 0 && total > 0) {
                speed = (received - lastReceived) / dt;
                eta = speed > 0 ? (total - received) / speed : 0;
              }
              lastReceived = received;
              lastMs = nowMs;
            }
            download.value = GemmaDownload(
              percent: p,
              received: received,
              total: total,
              speed: speed,
              eta: eta,
              running: true,
              elapsedSec: sw.elapsed.inSeconds,
            );
          })
          .install();
      download.value = GemmaDownload(
          percent: 100,
          received: total,
          total: total,
          done: true,
          elapsedSec: sw.elapsed.inSeconds);
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
  /// A larger [maxTokens] context lets the chat remember more of the ongoing
  /// conversation (ChatGPT-style memory) across turns in a session.
  static Future<void> load({int maxTokens = 2048}) async {
    await close();
    _model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: PreferredBackend.gpu,
    );
    // Permanent facts about the user, so the brain knows them in every session.
    final mem = MemoryStore.summaryForPrompt();
    final memLine = mem.isEmpty
        ? ''
        : "\n\nThings you already know about the user (use them naturally): $mem.";
    // Concise by default (spoken replies + on-device speed), but allowed to
    // give a short real explanation when the user asks it to explain or teach.
    _chat = await _model!.createChat(
      temperature: 0.7,
      topK: 40,
      topP: 0.9,
      maxOutputTokens: 220,
      systemInstruction:
          "You are Elder Wand, the user's sharp, friendly personal assistant, "
          "in the spirit of JARVIS. You remember the ongoing conversation and "
          "refer back to it naturally. Speak in a natural, spoken style — "
          "usually one or two sentences, but give a clear, helpful explanation "
          "(a few short sentences) when the user asks you to explain, teach, or "
          "compare something. Never use markdown, bullet points, or emojis.$memLine",
    );
  }

  /// Teach the live chat a new fact mid-session (it's also persisted by
  /// MemoryStore and baked into the system prompt on the next load).
  static Future<void> noteFact(String fact) async {
    final chat = _chat;
    if (chat == null || fact.trim().isEmpty) return;
    try {
      await chat.addQueryChunk(
          Message.text(text: 'Note to remember about the user: $fact', isUser: false));
    } catch (_) {}
  }

  /// Replay prior conversation turns into the chat so the brain remembers the
  /// user across app restarts (ChatGPT-style memory). Each turn is
  /// {'user':..., 'assistant':...}, oldest first. Call once right after
  /// [load]. Long replies are trimmed so seeding stays cheap on context.
  static Future<void> seedHistory(List<Map<String, String>> turns) async {
    final chat = _chat;
    if (chat == null) return;
    for (final t in turns) {
      final u = (t['user'] ?? '').trim();
      final a = (t['assistant'] ?? '').trim();
      if (u.isEmpty || a.isEmpty) continue;
      final us = u.length > 240 ? '${u.substring(0, 240)}…' : u;
      final as_ = a.length > 240 ? '${a.substring(0, 240)}…' : a;
      try {
        await chat.addQueryChunk(Message.text(text: us, isUser: true));
        await chat.addQueryChunk(Message.text(text: as_, isUser: false));
      } catch (_) {
        break; // if the engine rejects seeding, just start fresh
      }
    }
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
  final int received; // bytes (estimated from percent × total)
  final int total; // bytes
  final double speed; // bytes/sec
  final double eta; // seconds remaining
  final bool running;
  final bool done;
  final String? error;
  final int elapsedSec;

  const GemmaDownload({
    this.percent = 0,
    this.received = 0,
    this.total = 0,
    this.speed = 0,
    this.eta = 0,
    this.running = false,
    this.done = false,
    this.error,
    this.elapsedSec = 0,
  });

  double? get fraction => (running || percent > 0) ? percent / 100.0 : null;
}
