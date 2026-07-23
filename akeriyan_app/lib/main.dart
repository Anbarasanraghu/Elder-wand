import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'assistant_screen.dart';
import 'foreground_service.dart';
import 'history_store.dart';
import 'theme.dart';
import 'widgets/assistant_orb.dart';
import 'widgets/gradient_border.dart';
import 'gemma_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AkeriyanForegroundService.init();
  await HistoryStore.init(); // load saved transcript (offline + survives restart)
  // Register the on-device LLM engine (LiteRT-LM) for the Gemma brain.
  try {
    await GemmaService.initEngine();
  } catch (_) {}
  runApp(const AkeriyanApp());
}

class AkeriyanApp extends StatelessWidget {
  const AkeriyanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Elder Wand',
      debugShowCheckedModeBanner: false,
      theme: Ak.theme(),
      home: const ConnectionScreen(),
    );
  }
}

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  final _dio = Dio();

  String _status = 'Not connected yet';
  Color _statusColor = Ak.textLo;
  IconData _statusIcon = Icons.circle_outlined;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _urlController.text =
          prefs.getString('backend_url') ?? 'http://192.168.1.35:8000';
      _tokenController.text = prefs.getString('device_token') ?? '';
    });
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _status = 'Connecting…';
      _statusColor = Ak.gold;
      _statusIcon = Icons.sync;
    });

    final url = _urlController.text.trim();
    final token = _tokenController.text.trim();

    try {
      final health = await _dio.get('$url/v1/health',
          options: Options(receiveTimeout: const Duration(seconds: 5)));
      if (health.data['status'] != 'ok') {
        throw Exception('Backend unhealthy');
      }
      final hello = await _dio.get('$url/v1/hello',
          options: Options(headers: {'Authorization': 'Bearer $token'}));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('backend_url', url);
      await prefs.setString('device_token', token);

      setState(() {
        _status = hello.data['message'];
        _statusColor = Ak.green;
        _statusIcon = Icons.check_circle;
      });
    } on DioException catch (e) {
      setState(() {
        if (e.response?.statusCode == 401) {
          _status = 'Wrong token. Check it matches config.py exactly.';
        } else {
          _status =
              'Cannot reach backend. Check: same Wi-Fi, IP address, firewall, backend running.';
        }
        _statusColor = Ak.pink;
        _statusIcon = Icons.error;
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _statusColor = Ak.pink;
        _statusIcon = Icons.error;
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  void _openAssistant() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssistantScreen(
          backendUrl: _urlController.text.trim(),
          token: _tokenController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: Ak.bgGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                const Center(
                    child: AssistantOrb(state: OrbState.idle, size: 150)),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    'ELDER WAND',
                    style: Ak.display(size: 34, spacing: 4, color: Ak.textHi),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text('YOUR PERSONAL AI',
                      style: Ak.display(
                          size: 12, spacing: 4, color: Ak.textMid)),
                ),
                const SizedBox(height: 40),
                _field(_urlController, 'Backend URL', Icons.dns,
                    hint: 'http://192.168.1.35:8000'),
                const SizedBox(height: 16),
                _field(_tokenController, 'Device Token', Icons.key,
                    obscure: true),
                const SizedBox(height: 28),
                _primaryButton(),
                const SizedBox(height: 14),
                TextButton.icon(
                  onPressed: _openAssistant,
                  icon: const Icon(Icons.mic_none, color: Ak.cyan),
                  label: const Text('Skip & open assistant',
                      style: TextStyle(color: Ak.cyan)),
                ),
                const SizedBox(height: 20),
                _statusCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon,
      {String? hint, bool obscure = false}) {
    return GradientBorder(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: TextField(
        controller: c,
        obscureText: obscure,
        style: const TextStyle(color: Ak.textHi),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: Ak.textLo),
          hintStyle: const TextStyle(color: Ak.textLo),
          prefixIcon: Icon(icon, color: Ak.purple, size: 20),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }

  Widget _primaryButton() {
    return GestureDetector(
      onTap: _busy ? null : _connect,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: Ak.goldGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: Ak.glow(Ak.orange.withAlpha(90), blur: 24),
        ),
        child: Center(
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Ak.bg0),
                )
              : const Text('CONNECT',
                  style: TextStyle(
                      color: Ak.bg0,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2)),
        ),
      ),
    );
  }

  Widget _statusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: Ak.glass(),
      child: Row(
        children: [
          Icon(_statusIcon, color: _statusColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_status,
                style: TextStyle(color: _statusColor, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
