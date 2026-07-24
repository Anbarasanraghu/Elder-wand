import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'tts_service.dart';
import 'notification_service.dart';
import 'app_launcher.dart';
import 'apps_list_screen.dart';
import 'dart:async';
import 'dart:convert';
import 'openwakeword_service.dart';
import 'location_service.dart';
import 'vision_screen.dart';
import 'crm_screen.dart';
import 'alerts_screen.dart';
import 'alerts_poller.dart';
import 'projects_screen.dart';
import 'meeting_screen.dart';
import 'docs_screen.dart';
import 'invoice_screen.dart';
import 'trading_tools_screen.dart';
import 'email_screen.dart';
import 'foreground_service.dart';
import 'notification_reader.dart';
import 'whatsapp_sender.dart';
import 'phone_caller.dart';
import 'sms_sender.dart';
import 'flashlight_service.dart';
import 'history_store.dart';
import 'gemma_test_screen.dart';
import 'gemma_service.dart';
import 'voice_screen.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'history_screen.dart';
import 'trading_screen.dart';
import 'scalp_screen.dart';
import 'pro_screen.dart';
import 'live_agent_screen.dart';
import 'theme.dart';
import 'widgets/assistant_orb.dart';

class AssistantScreen extends StatefulWidget {
  final String backendUrl;
  final String token;

  const AssistantScreen({
    super.key,
    required this.backendUrl,
    required this.token,
  });

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen>
    with WidgetsBindingObserver {
  final _recorder = AudioRecorder();
  final _dio = Dio();
  final _wake = OpenWakeWordService();
  final stt.SpeechToText _stt = stt.SpeechToText(); // on-device speech-to-text
  bool _sttReady = false;

  bool _wakeActive = false;
  Timer? _autoStop;
  String _response = '';
  bool _recording = false;
  bool _thinking = false;
  bool _lastOnDevice = false; // was the last reply produced fully on the phone?
  bool _gemmaLoading = false; // on-device model warming up
  static const String _wakeReply = 'Yeah?'; // spoken when the wake word fires
  String _heard = 'Say "Hey Elder Wand" or tap the orb';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initTts();
    _autoLoadGemma(); // load the on-device brain so chat runs on the phone
    // Start the foreground (microphone) service FIRST so the OS permits mic
    // capture while the app is in the background, then start listening.
    AkeriyanForegroundService.start().whenComplete(_startWakeWord);
    NotificationReader.start();
    AlertsPoller.start(widget.backendUrl, widget.token);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // "Hey Elder Wand" should keep working when the app is hidden (like
    // "Hey Google"). The foreground service keeps the listener alive in the
    // background, so we do NOT stop it on pause. On resume we just make sure
    // it's still listening (restart if the OS killed it).
    if (state == AppLifecycleState.resumed) {
      if (!_recording && !_thinking && !_wake.listening) {
        _startWakeWord();
      }
    }
  }

  /// If an on-device model has been downloaded, load it into memory at startup
  /// so conversation is answered on the phone (not the backend). Runs in the
  /// background; harmless if no model is installed yet.
  Future<void> _autoLoadGemma() async {
    try {
      if (GemmaService.isLoaded) return;
      if (!await GemmaService.modelFileExists()) return;
      if (mounted) setState(() => _gemmaLoading = true);
      await GemmaService.load();
    } catch (_) {
      // stays on the backend brain if load fails
    } finally {
      if (mounted) setState(() => _gemmaLoading = false);
    }
  }

  Future<void> _initTts() async {
    await TtsService.init(widget.backendUrl, widget.token);
  }

  /// Body for /v1/nlu/parse, including the phone's GPS so weather / briefings
  /// use where you actually are. Falls back gracefully if location is off.
  Future<Map<String, dynamic>> _nluBody(String text, {String lang = 'en'}) async {
    final pos = await LocationService.current();
    return {
      'text': text,
      'lang': lang,
      if (pos != null) 'lat': pos.latitude,
      if (pos != null) 'lon': pos.longitude,
    };
  }

  Future<void> _startWakeWord() async {
    await _wake.start(_onWakeWordDetected);
    if (mounted) setState(() => _wakeActive = _wake.listening);
  }

  void _onWakeWordDetected() async {
    // Release the mic from the wake listener, then record the command.
    await _wake.stop();
    setState(() => _wakeActive = false);
    SystemSound.play(SystemSoundType.click); // earcon: "I'm awake"
    await TtsService.speakLocal(_wakeReply);
    await Future.delayed(const Duration(milliseconds: 600));
    await _onDeviceTurn(); // on-device STT (falls back to recorder+Whisper)
  }

  /// End the command recording as soon as you stop talking (a short pause),
  /// instead of always waiting a fixed window — big perceived speed-up. A hard
  /// 6-second cap ensures it never hangs if the mic reading is unreliable.
  void _beginEndpointing({bool followUp = false}) {
    bool speechSeen = false;
    int silenceMs = 0, elapsedMs = 0;
    const stepMs = 150;
    // In a follow-up window we give up sooner if nothing is said.
    final quietCap = followUp ? 4500 : 6000;
    _autoStop?.cancel();
    _autoStop = Timer.periodic(const Duration(milliseconds: stepMs), (t) async {
      if (!_recording) {
        t.cancel();
        return;
      }
      elapsedMs += stepMs;
      double db = -160;
      try {
        db = (await _recorder.getAmplitude()).current; // dBFS, ~0 = loud
      } catch (_) {}
      if (db > -28) {
        speechSeen = true;
        silenceMs = 0;
      } else if (speechSeen) {
        silenceMs += stepMs;
      }
      // Follow-up window with no speech at all -> quietly return to wake word.
      if (followUp && !speechSeen && elapsedMs >= quietCap) {
        t.cancel();
        await _recorder.stop();
        if (mounted) setState(() => _recording = false);
        await _resumeWake();
        return;
      }
      // Stop after ~0.9s of silence following speech, or at the 6s cap.
      if ((speechSeen && silenceMs >= 900) || elapsedMs >= 6000) {
        t.cancel();
        if (_recording) _stopAndTranscribe();
      }
    });
  }

  /// Continuous conversation: after a reply, listen briefly for a natural
  /// follow-up so you don't have to say "Hey Akeriyan" again. If you stay
  /// silent it slips back to wake-word listening on its own.
  Future<void> _listenForFollowUp() async {
    await _onDeviceTurn(followUp: true);
  }
  

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoStop?.cancel();
    _wake.stop();
    _stt.stop();
    TtsService.stop();
    AlertsPoller.stop();
    super.dispose();
  }

  /// Top status chip: is the on-device brain ready? Tap to open the loader.
  Widget _brainStatusChip() {
    late final String label;
    late final Color color;
    late final IconData icon;
    if (_gemmaLoading) {
      label = 'Loading on-device brain…';
      color = Colors.amberAccent;
      icon = Icons.hourglass_top;
    } else if (GemmaService.isLoaded) {
      label = 'On-device brain ready';
      color = Colors.tealAccent;
      icon = Icons.smartphone;
    } else {
      label = 'On-device brain off — tap to set up';
      color = Colors.grey;
      icon = Icons.cloud_outlined;
    }
    return GestureDetector(
      onTap: () async {
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const GemmaTestScreen()));
        if (mounted) await _autoLoadGemma(); // pick up a freshly loaded model
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  /// Small chip showing which brain produced the current reply:
  /// teal "On-device" (phone/Gemma) or amber "Backend (PC)".
  Widget _brainBadge() {
    final onDevice = _lastOnDevice;
    final color = onDevice ? Colors.tealAccent : Colors.amberAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(onDevice ? Icons.smartphone : Icons.dns,
              size: 12, color: color),
          const SizedBox(width: 4),
          Text(onDevice ? 'On-device' : 'Backend (PC)',
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _toggleMic() async {
    if (_recording) {
      _autoStop?.cancel();
      if (_stt.isListening) {
        await _stt.stop(); // finalises on-device STT -> _onDeviceTurn continues
      } else {
        await _stopAndTranscribe();
      }
    } else {
      // Manual mic press: pause wake listening so it doesn't fight for the mic.
      await _wake.stop();
      setState(() => _wakeActive = false);
      await _onDeviceTurn();
    }
  }

  Future<bool> _startRecording() async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      setState(() => _heard = 'Microphone permission denied.');
      await _resumeWake();
      return false;
    }
    // The wake engine was just stopped by the caller — give the OS a moment to
    // actually release the mic before we grab it (else the recording collapses).
    await _wake.stop();
    await Future.delayed(const Duration(milliseconds: 400));
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/akeriyan_input.m4a';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          // Disable the plugin's Bluetooth-SCO handling — it crashes the app
          // ("Reply already submitted") when a BT audio device is connected.
          androidConfig: AndroidRecordConfig(manageBluetooth: false),
        ),
        path: path,
      );
    } catch (_) {
      setState(() => _heard = 'Mic is busy — tap again.');
      await _resumeWake();
      return false;
    }
    if (!await _recorder.isRecording()) {
      setState(() => _heard = 'Mic is busy — close other audio apps, tap again.');
      await _resumeWake();
      return false;
    }
    setState(() {
      _recording = true;
      _heard = 'Listening... speak your command.';
    });
    return true;
  }

  Future<void> _stopAndTranscribe() async {
    final path = await _recorder.stop();
    setState(() {
      _recording = false;
      _thinking = true;
      _heard = 'Thinking...';
      _response = '';
    });

    if (path == null) {
      setState(() {
        _thinking = false;
        _heard = 'Recording failed. Try again.';
      });
      await _resumeWake();
      return;
    }
    

    try {
      // 1. Speech -> text via backend Whisper (fallback path; on-device STT is
      // preferred and handled in _onDeviceTurn).
      final form = FormData.fromMap({
        'audio': await MultipartFile.fromFile(path, filename: 'input.m4a'),
      });
      final sttResp = await _dio.post(
        '${widget.backendUrl}/v1/stt',
        data: form,
        options: Options(
          headers: {'Authorization': 'Bearer ${widget.token}'},
          receiveTimeout: const Duration(minutes: 5),
        ),
      );
      final text = (sttResp.data['text'] as String?) ?? '';
      final lang = (sttResp.data['language'] == 'ta') ? 'ta' : 'en';
      if (text.trim().isEmpty) {
        setState(() {
          _thinking = false;
          _heard = "I didn't catch that. Try again.";
        });
        await _resumeWake();
        return;
      }
      await _finishTurn(text, lang);
    } catch (e) {
      setState(() {
        _thinking = false;
        _heard = 'Error: $e';
      });
      await _resumeWake();
    }
  }

  /// Fully on-device capture: release the wake mic, listen with the phone's
  /// speech_to_text (no backend/Whisper), then respond. Falls back to the
  /// recorder + backend Whisper if on-device recognition isn't available.
  Future<void> _onDeviceTurn({bool followUp = false}) async {
    await _wake.stop();
    if (mounted) setState(() => _wakeActive = false);
    _sttReady = _sttReady ||
        await _stt.initialize(onError: (_) {}, onStatus: (_) {});
    if (!_sttReady) {
      if (await _startRecording()) _beginEndpointing(followUp: followUp);
      return;
    }
    if (mounted) {
      setState(() {
        _recording = true;
        _heard = followUp ? 'Listening… (follow-up)' : 'Listening…';
      });
    }
    final completer = Completer<String>();
    await _stt.listen(
      onResult: (r) {
        if (mounted) setState(() => _heard = '"${r.recognizedWords}"');
        if (r.finalResult && !completer.isCompleted) {
          completer.complete(r.recognizedWords);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(seconds: 30),
        pauseFor: Duration(seconds: followUp ? 3 : 4),
      ),
    );
    final text = await completer.future
        .timeout(const Duration(seconds: 35), onTimeout: () => '');
    if (mounted) setState(() => _recording = false);
    if (text.trim().isEmpty) {
      if (!followUp && mounted) {
        setState(() => _heard = "I didn't catch that. Try again.");
      }
      await _resumeWake();
      return;
    }
    await _finishTurn(text, 'en'); // on-device STT uses the device locale
  }

  /// Given recognized [text], understand + respond — on-device Gemma for plain
  /// chat, backend for actions — then speak. Shared by both STT paths.
  Future<void> _finishTurn(String text, String lang) async {
    bool spoke = false;
    setState(() {
      _thinking = true;
      _heard = '"$text"';
      _response = '';
    });
    try {
      // On-device brain first: plain conversation answered on the phone.
      final handledOnDevice = await _tryGemmaChat(text);
      if (handledOnDevice) spoke = true;

      // Backend path — actions/skills, or when Gemma isn't loaded.
      if (!handledOnDevice) {
        _lastOnDevice = false;
        Map<String, dynamic>? nluData;
        bool chatStreamed = false;
        String streamedSpeak = '';
        try {
          final r = await _converseStream(text, lang);
          if (r['mode'] == 'chat') {
            chatStreamed = true;
            streamedSpeak = (r['speak'] as String?) ?? '';
          } else {
            nluData = (r['data'] as Map).cast<String, dynamic>();
          }
        } catch (_) {
          final nlu = await _dio.post(
            '${widget.backendUrl}/v1/nlu/parse',
            data: await _nluBody(text, lang: lang),
            options: Options(
              headers: {'Authorization': 'Bearer ${widget.token}'},
            ),
          );
          nluData = (nlu.data as Map).cast<String, dynamic>();
        }

        if (chatStreamed) {
          setState(() => _response = streamedSpeak);
          HistoryStore.add(
              youSaid: text, akeriyanSaid: streamedSpeak, intent: 'chat');
          spoke = true;
        } else {
          String speak = (nluData!['speak'] as String?) ?? '';
          final intent = nluData['intent'] as String?;
          final slots = (nluData['slots'] as Map?) ?? {};
          final actions = nluData['actions'] as List?;
          if (intent == 'multi' && actions != null && actions.isNotEmpty) {
            for (final a in actions) {
              final m = a as Map;
              await _handleIntent(
                m['intent'] as String?,
                (m['slots'] as Map?) ?? {},
                (m['speak'] as String?) ?? '',
              );
            }
          } else {
            speak = await _handleIntent(intent, slots, speak);
          }
          setState(() => _response = speak);
          HistoryStore.add(
              youSaid: text, akeriyanSaid: speak, intent: intent ?? 'unknown');
          spoke = true;
          await TtsService.speak(speak,
              lang: (nluData['speak_lang'] as String?) ?? 'en');
        }
      }
    } catch (e) {
      setState(() => _heard = 'Error: $e');
    } finally {
      _autoStop?.cancel();
      setState(() => _thinking = false);
      if (spoke) {
        await _listenForFollowUp();
      } else {
        await _resumeWake();
      }
    }
  }

  // Action/skill keywords — when NONE appear it's plain conversation the
  // on-device Gemma can answer itself (mirrors the backend's routing).
  static final RegExp _actionHint = RegExp(
      r'\b(remind|reminder|alarm|timer|call|dial|ring|text|sms|message|whatsapp|'
      r'open|launch|flashlight|torch|notification|weather|temperature|forecast|'
      r'news|headline|briefing|email|inbox|gmail|mail|lead|pipeline|crm|remember|'
      r'forget|translate|search|google|price|chart|market|stock|crypto|bitcoin|'
      r'ethereum|buy|sell|trade|trading|analysis|analyse|analyze|scalp|watch|'
      r'monitor|gold|silver|forex|routine)\b',
      caseSensitive: false);

  /// If the on-device Gemma model is loaded and this is plain conversation
  /// (not an action), answer it entirely on the phone (LLM) and speak the
  /// reply. Returns true if handled on-device; false to fall back to the
  /// backend (actions, or Gemma not loaded, or any error).
  Future<bool> _tryGemmaChat(String text) async {
    if (!GemmaService.isLoaded || _actionHint.hasMatch(text)) return false;
    try {
      final sb = StringBuffer();
      setState(() {
        _response = '';
        _lastOnDevice = true; // this reply is coming from the phone
      });
      await for (final tok in GemmaService.ask(text)) {
        sb.write(tok);
        setState(() => _response = sb.toString());
      }
      final reply = sb.toString().trim();
      if (reply.isEmpty) {
        setState(() => _lastOnDevice = false);
        return false;
      }
      setState(() => _response = reply);
      HistoryStore.add(youSaid: text, akeriyanSaid: reply, intent: 'chat');
      await TtsService.speakLocal(reply); // phone neural voice, no PC wait
      return true;
    } catch (_) {
      setState(() => _lastOnDevice = false);
      return false;
    }
  }

  /// Calls the streaming turn endpoint. For plain chat it plays the reply
  /// sentence-by-sentence as WAV chunks arrive (returns {'mode':'chat',...}
  /// once playback finishes). For actions it returns {'mode':'result','data':...}
  /// — the same shape as /nlu/parse — for the caller to handle. Throws on any
  /// transport error so the caller can fall back to the classic path.
  Future<Map<String, dynamic>> _converseStream(String text, String lang) async {
    final resp = await _dio.post(
      '${widget.backendUrl}/v1/converse/stream',
      data: await _nluBody(text, lang: lang),
      options: Options(
        headers: {'Authorization': 'Bearer ${widget.token}'},
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(minutes: 5),
      ),
    );

    final byteStream = (resp.data as ResponseBody).stream;
    final List<int> buf = <int>[];
    bool isChat = false;
    String fullSpeak = '';
    Map<String, dynamic>? result;

    TtsService.beginStream();
    try {
      await for (final chunk in byteStream) {
        buf.addAll(chunk);
        int nl;
        // Decode only COMPLETE lines (avoids splitting multi-byte UTF-8).
        while ((nl = buf.indexOf(10)) >= 0) {
          final line = utf8.decode(buf.sublist(0, nl), allowMalformed: true).trim();
          buf.removeRange(0, nl + 1);
          if (line.isEmpty) continue;
          final ev = jsonDecode(line) as Map<String, dynamic>;
          switch (ev['type']) {
            case 'meta':
              isChat = true;
              break;
            case 'text':
              fullSpeak = ('$fullSpeak ${ev['delta'] ?? ''}').trim();
              if (mounted) setState(() => _response = fullSpeak);
              break;
            case 'audio':
              TtsService.enqueueWav(base64Decode(ev['b64'] as String));
              break;
            case 'result':
              result = Map<String, dynamic>.from(ev);
              break;
            case 'done':
              if (ev['speak'] != null) fullSpeak = ev['speak'] as String;
              break;
            case 'error':
              throw Exception(ev['speak'] ?? 'stream error');
          }
        }
      }
    } finally {
      if (isChat) await TtsService.endStream();
    }

    if (isChat) return {'mode': 'chat', 'speak': fullSpeak};
    if (result != null) return {'mode': 'result', 'data': result};
    throw Exception('empty stream response');
  }

  /// Runs the phone-side action for an intent and returns the final spoken line.
  Future<String> _handleIntent(
      String? intent, Map slots, String speak) async {
    switch (intent) {
      case 'create_reminder':
        if (slots['time'] != null) {
          await NotificationService.scheduleReminder(
            task: (slots['text'] as String?) ?? 'Reminder',
            time: DateTime.parse(slots['time'] as String),
            daily: slots['recurrence'] == 'FREQ=DAILY',
          );
        }
        break;

      case 'set_timer':
        final secs = (slots['seconds'] as num?)?.toInt() ?? 0;
        if (secs > 0) {
          await NotificationService.scheduleReminder(
            task: 'Timer finished ⏰',
            time: DateTime.now().add(Duration(seconds: secs)),
          );
        } else {
          speak = 'How long should the timer be?';
        }
        break;

      case 'open_app':
        final opened =
            await AppLauncher.openByName((slots['app'] as String?) ?? '');
        speak = opened != null
            ? 'Opening $opened.'
            : "I couldn't find an app called ${slots['app']}.";
        break;

      case 'read_notifications':
        final ok = await NotificationReader.hasPermission();
        if (!ok) {
          speak = 'Please grant notification access first. Opening settings.';
          await NotificationReader.requestPermission();
        } else {
          speak = slots['kind'] == 'all'
              ? NotificationReader.allSpoken()
              : NotificationReader.latestSpoken();
        }
        break;

      case 'phone_call':
        final number = slots['number'] as String?;
        if (number != null) {
          await PhoneCaller.call(number);
        } else if ((speak).isEmpty) {
          speak = "I don't have that number saved.";
        }
        break;

      case 'send_sms':
        final number = slots['number'] as String?;
        final message = (slots['message'] as String?) ?? '';
        if (number != null && message.isNotEmpty) {
          await SmsSender.send(number: number, message: message);
        } else if (number == null) {
          speak = speak.isEmpty ? "I don't have that number saved." : speak;
        }
        break;

      case 'whatsapp_send':
        final number = slots['number'] as String?;
        final message = (slots['message'] as String?) ?? '';
        if (number != null && message.isNotEmpty) {
          await WhatsAppSender.openChat(phoneNumber: number, message: message);
        }
        break;

      case 'toggle_flashlight':
        final on = slots['state'] != 'off';
        final ok = await FlashlightService.set(on);
        if (!ok) speak = "I couldn't control the flashlight on this phone.";
        break;

      case 'routine':
        speak = await _runRoutine((slots['name'] as String?) ?? '');
        break;

      case 'market_analysis':
        // The backend already put the spoken analysis in `speak`.
        // Open the live chart for the coin the user asked about.
        final coin = (slots['symbol'] as String?) ??
            (slots['resolved'] as String?) ??
            'bitcoin';
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TradingScreen(
                backendUrl: widget.backendUrl,
                token: widget.token,
                initialSymbol: coin,
              ),
            ),
          );
        }
        break;

      case 'stock_analysis':
        final ticker = (slots['symbol'] as String?) ?? 'apple';
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TradingScreen(
                backendUrl: widget.backendUrl,
                token: widget.token,
                initialSymbol: ticker,
                stock: true,
              ),
            ),
          );
        }
        break;

      case 'scalp_analysis':
        final sym = (slots['symbol'] as String?) ?? 'bitcoin';
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ScalpScreen(
                backendUrl: widget.backendUrl,
                token: widget.token,
                initialSymbol: sym,
              ),
            ),
          );
        }
        break;

      case 'pro_analysis':
        final psym = (slots['symbol'] as String?) ?? 'bitcoin';
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProScreen(
                backendUrl: widget.backendUrl,
                token: widget.token,
                initialSymbol: psym,
              ),
            ),
          );
        }
        break;

      case 'watch_market':
        final wsym = (slots['symbol'] as String?) ?? 'bitcoin';
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LiveAgentScreen(
                backendUrl: widget.backendUrl,
                token: widget.token,
                symbol: wsym,
              ),
            ),
          );
        }
        break;

    // weather / news / web_search / translate / math / chat / smalltalk:
    // the backend already put the full answer in `speak`. Nothing to do here.
    }
    return speak;
  }

  /// Simple multi-step routines. "Good morning" -> greet + read notifications.
  Future<String> _runRoutine(String name) async {
    switch (name) {
      case 'good_morning':
        final notes = await NotificationReader.hasPermission()
            ? NotificationReader.allSpoken()
            : '';
        return 'Good morning, Anbarasan. ${notes.isEmpty ? '' : 'Here is what you missed. $notes'}';
      case 'good_night':
        await FlashlightService.set(false);
        return 'Good night, Anbarasan. Sleep well.';
      case 'leaving_home':
        await FlashlightService.set(false);
        return 'Take care, Anbarasan. Flashlight off and ready to go.';
      default:
        return 'Routine done.';
    }
  }

  /// Runs a text command directly (used by the quick-action chips) — the same
  /// NLU + act + speak flow as a spoken command, minus the recording.
  Future<void> _runCommand(String text) async {
    if (_thinking || _recording) return;
    await _wake.stop();
    setState(() {
      _wakeActive = false;
      _thinking = true;
      _heard = '"$text"';
      _response = '';
    });
    try {
      final nlu = await _dio.post(
        '${widget.backendUrl}/v1/nlu/parse',
        data: await _nluBody(text),
        options: Options(headers: {'Authorization': 'Bearer ${widget.token}'}),
      );
      String speak = (nlu.data['speak'] as String?) ?? '';
      final intent = nlu.data['intent'] as String?;
      final slots = (nlu.data['slots'] as Map?) ?? {};
      final actions = nlu.data['actions'] as List?;
      if (intent == 'multi' && actions != null && actions.isNotEmpty) {
        for (final a in actions) {
          final m = a as Map;
          await _handleIntent(m['intent'] as String?,
              (m['slots'] as Map?) ?? {}, (m['speak'] as String?) ?? '');
        }
      } else {
        speak = await _handleIntent(intent, slots, speak);
      }
      setState(() => _response = speak);
      HistoryStore.add(
          youSaid: text, akeriyanSaid: speak, intent: intent ?? 'unknown');
      await TtsService.speak(speak);
    } catch (e) {
      setState(() => _heard = 'Error: $e');
    } finally {
      setState(() => _thinking = false);
      await _resumeWake();
    }
  }

  OrbState get _orbState {
    if (_recording) return OrbState.recording;
    if (_thinking) return OrbState.thinking;
    if (_wakeActive) return OrbState.listening;
    return OrbState.idle;
  }

  Future<void> _resumeWake() async {
    await _wake.resume();
    if (mounted) setState(() => _wakeActive = true);
  }

  static const _quickActions = <(String, IconData, String)>[
    ('Pro BTC', Icons.insights, 'full analysis of bitcoin'),
    ('Scalp BTC', Icons.bolt, 'scalp bitcoin'),
    ('Gold', Icons.diamond_outlined, 'gold price'),
    ('USD/INR', Icons.currency_exchange, 'dollar to rupee'),
    ('Weather', Icons.wb_sunny_outlined, "what's the weather"),
    ('Briefing', Icons.wb_twilight, 'brief me'),
    ('News', Icons.article_outlined, 'top news headlines'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = _orbState;
    final statusText = _recording
        ? 'Listening to you…'
        : _thinking
            ? 'Thinking…'
            : _wakeActive
                ? 'Listening for "Hey Elder Wand"'
                : 'Tap the orb to talk';

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('ELDER WAND'),
        actions: [
          _navIcon(Icons.candlestick_chart, 'Markets',
              () => _go(TradingScreen(
                  backendUrl: widget.backendUrl, token: widget.token))),
          _navIcon(Icons.business_center, 'CRM',
              () => _go(CrmScreen(
                  backendUrl: widget.backendUrl, token: widget.token))),
          PopupMenuButton<int>(
            icon: const Icon(Icons.more_vert, color: Ak.textMid),
            color: Ak.bg2,
            onSelected: (i) {
              switch (i) {
                case 0:
                  _go(VisionScreen(
                      backendUrl: widget.backendUrl, token: widget.token));
                case 1:
                  _go(AlertsScreen(
                      backendUrl: widget.backendUrl, token: widget.token));
                case 2:
                  _go(ProjectsScreen(
                      backendUrl: widget.backendUrl, token: widget.token));
                case 3:
                  _go(MeetingScreen(
                      backendUrl: widget.backendUrl, token: widget.token));
                case 4:
                  _go(DocsScreen(
                      backendUrl: widget.backendUrl, token: widget.token));
                case 5:
                  _go(const InvoiceScreen());
                case 6:
                  _go(TradingToolsScreen(
                      backendUrl: widget.backendUrl, token: widget.token));
                case 7:
                  _go(EmailScreen(
                      backendUrl: widget.backendUrl, token: widget.token));
                case 8:
                  _go(const HistoryScreen());
                case 9:
                  _go(const AppsListScreen());
                case 10:
                  _go(const GemmaTestScreen());
                case 11:
                  _go(const VoiceScreen());
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 0,
                  child: _MenuRow(Icons.center_focus_strong, 'Vision')),
              PopupMenuItem(
                  value: 1,
                  child: _MenuRow(
                      Icons.notifications_active_outlined, 'Alerts')),
              PopupMenuItem(
                  value: 2, child: _MenuRow(Icons.folder_open, 'Projects')),
              PopupMenuItem(
                  value: 3, child: _MenuRow(Icons.mic_none, 'Meeting notes')),
              PopupMenuItem(
                  value: 4,
                  child: _MenuRow(Icons.menu_book, 'Documents (ask)')),
              PopupMenuItem(
                  value: 5, child: _MenuRow(Icons.receipt_long, 'Invoice')),
              PopupMenuItem(
                  value: 6,
                  child: _MenuRow(Icons.show_chart, 'Trading tools')),
              PopupMenuItem(
                  value: 7, child: _MenuRow(Icons.mail_outline, 'Email')),
              PopupMenuItem(
                  value: 8, child: _MenuRow(Icons.history, 'History')),
              PopupMenuItem(value: 9, child: _MenuRow(Icons.apps, 'Apps')),
              PopupMenuItem(
                  value: 10,
                  child: _MenuRow(Icons.memory, 'On-device AI (test)')),
              PopupMenuItem(
                  value: 11,
                  child: _MenuRow(Icons.record_voice_over, 'Voice')),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Stack(
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(gradient: Ak.bgGradient),
            child: SizedBox.expand(),
          ),
          Positioned.fill(child: Ak.ambientGlow()),
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              child: Column(
                children: [
                  // Presence — the particle orb; tap to talk
                  GestureDetector(
                    onTap: _thinking ? null : _toggleMic,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 22, horizontal: 18),
                      decoration: Ak.bento(glow: _recording || _wakeActive),
                      child: Column(
                        children: [
                          AssistantOrb(state: state, size: 140),
                          const SizedBox(height: 14),
                          Text(statusText,
                              style: const TextStyle(
                                  color: Ak.textMid, fontSize: 13)),
                          const SizedBox(height: 8),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: Text(
                              _heard,
                              key: ValueKey(_heard),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 16,
                                  color: Ak.textHi,
                                  fontWeight: FontWeight.w500,
                                  height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_response.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _responseCard(),
                  ],
                  const SizedBox(height: 14),
                  Center(child: _brainStatusChip()),
                  const SizedBox(height: 22),
                  _sectionLabel('QUICK ASK'),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 84,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _quickActions.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (_, i) {
                        final (label, icon, cmd) = _quickActions[i];
                        return _quickAction(label, icon, cmd);
                      },
                    ),
                  ),
                  const SizedBox(height: 22),
                  _sectionLabel('EXPLORE'),
                  const SizedBox(height: 12),
                  _deckGrid(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String s) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(s, style: Ak.display(size: 13, color: Ak.textMid, spacing: 3)),
        ),
      );

  Widget _responseCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: Ak.bento(glow: _lastOnDevice),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
                gradient: Ak.goldGradient, shape: BoxShape.circle),
            child: const Icon(Icons.auto_awesome, size: 14, color: Ak.bg0),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _brainBadge(),
                Text(_response,
                    style: const TextStyle(
                        fontSize: 15, color: Ak.textHi, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deckGrid() {
    final features = <(String, String, IconData, Widget, bool)>[
      ('Vision', 'Camera + ask', Icons.center_focus_strong,
          VisionScreen(backendUrl: widget.backendUrl, token: widget.token), true),
      ('Markets', 'Charts & trades', Icons.candlestick_chart,
          TradingScreen(backendUrl: widget.backendUrl, token: widget.token), false),
      ('On-device AI', 'Your phone brain', Icons.memory,
          const GemmaTestScreen(), true),
      ('Memory', 'Past chats', Icons.history, const HistoryScreen(), false),
      ('Meeting', 'Record & sum up', Icons.mic_none,
          MeetingScreen(backendUrl: widget.backendUrl, token: widget.token), false),
      ('Email', 'Inbox & compose', Icons.mail_outline,
          EmailScreen(backendUrl: widget.backendUrl, token: widget.token), false),
      ('Alerts', 'Price & RSI', Icons.notifications_active_outlined,
          AlertsScreen(backendUrl: widget.backendUrl, token: widget.token), false),
      ('CRM', 'Leads & pipeline', Icons.business_center,
          CrmScreen(backendUrl: widget.backendUrl, token: widget.token), false),
      ('Projects', 'Tasks & notes', Icons.folder_open,
          ProjectsScreen(backendUrl: widget.backendUrl, token: widget.token), false),
      ('Documents', 'Ask your notes', Icons.menu_book,
          DocsScreen(backendUrl: widget.backendUrl, token: widget.token), false),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.62,
      children: [
        for (final (label, sub, icon, screen, glow) in features)
          _deckTile(label, sub, icon, () => _go(screen), glow: glow),
      ],
    );
  }

  Widget _deckTile(String label, String subtitle, IconData icon,
      VoidCallback onTap, {bool glow = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: Ak.bento(radius: 18, glow: glow),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: glow ? const Color(0x2696BEFF) : Ak.glassFill,
              ),
              child: Icon(icon, color: glow ? Ak.gold : Ak.textHi, size: 19),
            ),
            const Spacer(),
            Text(label,
                style: const TextStyle(
                    color: Ak.textHi,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(color: Ak.textLo, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _navIcon(IconData icon, String tip, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: Ak.textMid),
      tooltip: tip,
      onPressed: onTap,
    );
  }

  void _go(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Widget _quickAction(String label, IconData icon, String command) {
    return GestureDetector(
      onTap: () => _runCommand(command),
      child: Container(
        width: 74,
        decoration: Ak.glass(radius: 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Ak.gold, size: 26),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(color: Ak.textMid, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// A row inside the app-bar overflow menu.
class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuRow(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: Ak.purple, size: 20),
      const SizedBox(width: 12),
      Text(label, style: const TextStyle(color: Ak.textHi)),
    ]);
  }
}