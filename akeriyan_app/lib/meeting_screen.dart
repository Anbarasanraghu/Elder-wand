import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'notification_service.dart';
import 'local_cache.dart';
import 'openwakeword_service.dart';
import 'theme.dart';
import 'widgets/nothing_loader.dart';

/// Persisted meeting notes so past meetings are viewable offline.
class MeetingStore {
  static Future<List<Map<String, dynamic>>> all() async {
    final d = await LocalCache.load('meetings');
    return d is List
        ? d.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : [];
  }

  static Future<void> add(Map<String, dynamic> m) async {
    final list = await all();
    list.insert(0, m);
    if (list.length > 50) list.removeRange(50, list.length);
    await LocalCache.save('meetings', list);
  }
}

/// Meeting / client-call recorder → AI notes. Records audio, transcribes via
/// the backend (Whisper), then summarises into a summary + action items.
class MeetingScreen extends StatefulWidget {
  final String backendUrl;
  final String token;
  const MeetingScreen(
      {super.key, required this.backendUrl, required this.token});

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  final _recorder = AudioRecorder();
  final _dio = Dio();

  bool _recording = false;
  bool _busy = false;
  int _seconds = 0;
  Timer? _timer;
  String _status = 'Tap to record your meeting';
  String _transcript = '';
  String _summary = '';
  List<String> _actions = [];
  List<Map<String, dynamic>> _recent = [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final r = await MeetingStore.all();
    if (mounted) setState(() => _recent = r);
  }

  Future<void> _toggle() async {
    if (_recording) {
      await _stopAndProcess();
    } else {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        setState(() => _status = 'Microphone permission denied.');
        return;
      }
      // Free the mic from the wake-word engine, then give the OS a moment to
      // actually release it before we grab it (avoids the recording cutting out).
      await OpenWakeWordService.pauseGlobal();
      await Future.delayed(const Duration(milliseconds: 400));
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/akeriyan_meeting.m4a';
      try {
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            sampleRate: 16000,
            androidConfig: AndroidRecordConfig(manageBluetooth: false),
          ),
          path: path,
        );
      } catch (e) {
        setState(() => _status = 'Could not start recording (mic busy).');
        OpenWakeWordService.resumeGlobal();
        return;
      }
      // Confirm it really started — if the mic was still held it won't.
      if (!await _recorder.isRecording()) {
        setState(() =>
            _status = 'Mic is busy — close other audio/voice apps and retry.');
        OpenWakeWordService.resumeGlobal();
        return;
      }
      setState(() {
        _recording = true;
        _seconds = 0;
        _transcript = '';
        _summary = '';
        _actions = [];
        _status = 'Recording…';
      });
      _timer = Timer.periodic(
          const Duration(seconds: 1), (_) => setState(() => _seconds++));
    }
  }

  Future<void> _stopAndProcess() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    OpenWakeWordService.resumeGlobal(); // give the mic back to the wake word
    setState(() {
      _recording = false;
      _busy = true;
      _status = 'Transcribing…';
    });
    if (path == null) {
      setState(() {
        _busy = false;
        _status = 'Recording failed.';
      });
      return;
    }
    try {
      // 1. audio -> transcript
      final form = FormData.fromMap({
        'audio': await MultipartFile.fromFile(path, filename: 'meeting.m4a'),
      });
      final stt = await _dio.post(
        '${widget.backendUrl}/v1/stt',
        data: form,
        options: Options(
          headers: {'Authorization': 'Bearer ${widget.token}'},
          receiveTimeout: const Duration(minutes: 10),
        ),
      );
      final transcript = (stt.data['text'] as String?) ?? '';
      setState(() {
        _transcript = transcript;
        _status = 'Summarising…';
      });
      // 2. transcript -> summary + actions
      final sum = await _dio.post(
        '${widget.backendUrl}/v1/meeting/summarize',
        data: {'transcript': transcript},
        options: Options(
          headers: {'Authorization': 'Bearer ${widget.token}'},
          receiveTimeout: const Duration(minutes: 5),
        ),
      );
      setState(() {
        _summary = (sum.data['summary'] as String?) ?? '';
        _actions =
            ((sum.data['action_items'] as List?) ?? []).map((e) => '$e').toList();
        _status = 'Done';
      });
      if (_summary.isNotEmpty) {
        await MeetingStore.add({
          'at': DateTime.now().toIso8601String(),
          'transcript': _transcript,
          'summary': _summary,
          'actions': _actions,
        });
        _loadRecent();
      }
    } catch (e) {
      setState(() => _status = 'Failed — is the backend running?');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveActionsAsReminders() async {
    final tomorrow9 = DateTime.now().add(const Duration(days: 1));
    final when = DateTime(tomorrow9.year, tomorrow9.month, tomorrow9.day, 9);
    for (final a in _actions) {
      await NotificationService.scheduleReminder(task: a, time: when);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_actions.length} action items saved as reminders'),
          backgroundColor: Ak.bg2));
    }
  }

  String get _clock {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MEETING NOTES')),
      body: Container(
        decoration: const BoxDecoration(gradient: Ak.bgGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(children: [
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _busy ? null : _toggle,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _recording ? null : Ak.goldGradient,
                    color: _recording ? Ak.down : null,
                    boxShadow: Ak.glow(
                        (_recording ? Ak.down : Ak.purple).withAlpha(90),
                        blur: 30),
                  ),
                  child: Icon(_recording ? Icons.stop : Icons.mic,
                      color: Ak.bg0, size: 52),
                ),
              ),
              const SizedBox(height: 16),
              Text(_recording ? _clock : _status,
                  style: Ak.display(size: _recording ? 24 : 14, color: Ak.textMid)),
              const SizedBox(height: 24),
              if (_busy) NothingLoader(label: _status),
              if (!_busy && (_summary.isNotEmpty || _transcript.isNotEmpty)) ...[
                if (_summary.isNotEmpty)
                  _card('Summary', Icons.summarize, Text(_summary,
                      style: const TextStyle(color: Ak.textHi, height: 1.4))),
                const SizedBox(height: 14),
                if (_actions.isNotEmpty)
                  _card(
                    'Action items',
                    Icons.checklist,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ..._actions.map((a) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('•  ',
                                      style: TextStyle(color: Ak.purple)),
                                  Expanded(
                                      child: Text(a,
                                          style: const TextStyle(
                                              color: Ak.textHi))),
                                ],
                              ),
                            )),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _saveActionsAsReminders,
                          child: Container(
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                gradient: Ak.goldGradient,
                                borderRadius: BorderRadius.circular(12)),
                            child: const Text('Save as reminders',
                                style: TextStyle(
                                    color: Ak.bg0,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                if (_transcript.isNotEmpty)
                  _card(
                    'Transcript',
                    Icons.notes,
                    Text(_transcript,
                        style: const TextStyle(color: Ak.textMid, fontSize: 13)),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy, color: Ak.textLo, size: 18),
                      onPressed: () => Clipboard.setData(
                          ClipboardData(text: _transcript)),
                    ),
                  ),
              ],
              if (!_busy && _status == 'Done' && _transcript.isEmpty)
                _card(
                    'No speech detected',
                    Icons.info_outline,
                    const Text(
                        "I couldn't hear anything. Record again, a bit closer "
                        "to the mic and make sure no other app is using it.",
                        style: TextStyle(color: Ak.textMid))),
              if (_summary.isEmpty && _recent.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Recent meetings',
                        style: Ak.display(size: 13, color: Ak.textMid))),
                const SizedBox(height: 10),
                ..._recent.map((m) => GestureDetector(
                      onTap: () => setState(() {
                        _summary = (m['summary'] ?? '').toString();
                        _actions = ((m['actions'] as List?) ?? [])
                            .map((e) => '$e')
                            .toList();
                        _transcript = (m['transcript'] ?? '').toString();
                        _status = 'Saved meeting';
                      }),
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: Ak.glass(),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  (m['at'] ?? '')
                                      .toString()
                                      .replaceFirst('T', ' ')
                                      .split('.')
                                      .first,
                                  style: const TextStyle(
                                      color: Ak.textLo, fontSize: 11)),
                              const SizedBox(height: 4),
                              Text((m['summary'] ?? '').toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Ak.textHi, fontSize: 13)),
                            ]),
                      ),
                    )),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _card(String title, IconData icon, Widget child, {Widget? trailing}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: Ak.glass(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: Ak.purple, size: 18),
          const SizedBox(width: 8),
          Text(title, style: Ak.display(size: 13, color: Ak.textMid)),
          const Spacer(),
          ?trailing,
        ]),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_recording) _recorder.stop();
    OpenWakeWordService.resumeGlobal(); // ensure the wake word resumes if we leave
    _recorder.dispose();
    super.dispose();
  }
}
