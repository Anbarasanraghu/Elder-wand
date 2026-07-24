import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_registry.dart';
import 'tts_service.dart';
import 'theme.dart';

/// On-device scanning: live QR / barcode reading, and camera OCR that pulls
/// text out of a document or sign. Both run entirely on the phone (ML Kit /
/// mobile_scanner) — free, no key, works offline.
class ScanScreen extends StatefulWidget {
  final bool startOcr;
  const ScanScreen({super.key, this.startOcr = false});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late bool _ocrMode = widget.startOcr;
  final MobileScannerController _scanner = MobileScannerController();
  String? _result;
  bool _handled = false;
  bool _busy = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onQr(BarcodeCapture capture) {
    if (_handled) return;
    final value = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (value == null) return;
    _handled = true;
    ApiUsage.record('qr-scanner');
    setState(() => _result = value);
    TtsService.speakLocal('Scanned a code.');
  }

  Future<void> _scanText() async {
    setState(() => _busy = true);
    try {
      final shot = await ImagePicker()
          .pickImage(source: ImageSource.camera, imageQuality: 90);
      if (shot == null) {
        setState(() => _busy = false);
        return;
      }
      ApiUsage.record('mlkit-ocr');
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final text =
          (await recognizer.processImage(InputImage.fromFilePath(shot.path)))
              .text
              .trim();
      await recognizer.close();
      setState(() {
        _result = text.isEmpty ? 'No readable text found.' : text;
        _busy = false;
      });
      if (text.isNotEmpty) {
        final head = text.length > 160 ? text.substring(0, 160) : text;
        TtsService.speakLocal(head);
      }
    } catch (e) {
      setState(() {
        _result = "I couldn't read that ($e).";
        _busy = false;
      });
    }
  }

  bool get _isUrl {
    final r = _result;
    return r != null &&
        (r.startsWith('http://') || r.startsWith('https://'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ak.bg0,
      appBar: AppBar(
        backgroundColor: Ak.bg0,
        elevation: 0,
        title: const Text('Scan',
            style: TextStyle(fontFamily: Ak.dot, letterSpacing: 2)),
      ),
      body: Column(
        children: [
          _modeToggle(),
          Expanded(
            child: _ocrMode ? _ocrView() : _qrView(),
          ),
          if (_result != null) _resultCard(),
        ],
      ),
    );
  }

  Widget _modeToggle() => Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _pill('QR / Barcode', !_ocrMode, () {
              setState(() {
                _ocrMode = false;
                _result = null;
                _handled = false;
              });
            }),
            const SizedBox(width: 8),
            _pill('Text (OCR)', _ocrMode, () {
              setState(() {
                _ocrMode = true;
                _result = null;
              });
            }),
          ],
        ),
      );

  Widget _pill(String label, bool active, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? Ak.purple.withValues(alpha: 0.16) : Ak.glassFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: active
                      ? Ak.purple.withValues(alpha: 0.5)
                      : Ak.glassLine),
            ),
            child: Text(label,
                style: TextStyle(
                    color: active ? Ak.purple : Ak.textMid,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ),
        ),
      );

  Widget _qrView() => Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _scanner, onDetect: _onQr),
          IgnorePointer(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                border: Border.all(color: Ak.purple, width: 2),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          Positioned(
            bottom: 24,
            child: Text('Point at a QR code or barcode',
                style: TextStyle(color: Ak.textHi.withValues(alpha: 0.9))),
          ),
        ],
      );

  Widget _ocrView() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.document_scanner_outlined, size: 64, color: Ak.silver),
            const SizedBox(height: 16),
            Text('Capture a document, sign, or note',
                style: TextStyle(color: Ak.textMid)),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Ak.purple),
              onPressed: _busy ? null : _scanText,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.camera_alt_outlined, color: Ak.bg0),
              label: Text(_busy ? 'Reading…' : 'Capture text',
                  style: const TextStyle(color: Ak.bg0)),
            ),
          ],
        ),
      );

  Widget _resultCard() => Container(
        width: double.infinity,
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.all(16),
        decoration: Ak.bento(radius: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: SelectableText(_result!,
                    style: const TextStyle(color: Ak.textHi, height: 1.4)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _action(Icons.copy, 'Copy', () {
                  Clipboard.setData(ClipboardData(text: _result!));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied')));
                }),
                const SizedBox(width: 8),
                if (_isUrl)
                  _action(Icons.open_in_new, 'Open', () {
                    launchUrl(Uri.parse(_result!),
                        mode: LaunchMode.externalApplication);
                  }),
                const Spacer(),
                if (!_ocrMode)
                  _action(Icons.refresh, 'Again', () {
                    setState(() {
                      _result = null;
                      _handled = false;
                    });
                  }),
              ],
            ),
          ],
        ),
      );

  Widget _action(IconData icon, String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Ak.purple.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Ak.purple),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      color: Ak.purple,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}
