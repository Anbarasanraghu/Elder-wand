import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'scalp_sentiment.dart';
import 'scalp_signal.dart';

/// Generates a designed PDF scalping report and opens the share sheet.
class ScalpReport {
  static PdfColor get _ink => PdfColor.fromInt(0xFF14181f);
  static PdfColor get _muted => PdfColor.fromInt(0xFF5b6675);
  static PdfColor get _accent => PdfColor.fromInt(0xFF3f6fb0);
  static PdfColor get _up => PdfColor.fromInt(0xFF17a673);
  static PdfColor get _down => PdfColor.fromInt(0xFFe0454b);
  static PdfColor get _panel => PdfColor.fromInt(0xFFf4f6fb);

  static Future<void> share({
    required String symbol,
    required String interval,
    required Signal s,
    required Sentiment sent,
    required DateTime at,
  }) async {
    final side = s.side;
    final sideColor = side == 'LONG' ? _up : side == 'SHORT' ? _down : _muted;
    final doc = pw.Document();
    String fmt(double? v) => v == null ? '—' : v.toStringAsFixed(v > 100 ? 2 : 4);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // header band
            pw.Container(
              color: PdfColor.fromInt(0xFF0e1116),
              padding: const pw.EdgeInsets.fromLTRB(28, 26, 28, 22),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('SCALP REPORT',
                        style: pw.TextStyle(
                            color: PdfColor.fromInt(0xFFdfe9fb),
                            fontSize: 11,
                            letterSpacing: 3,
                            fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('$symbol · $interval',
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 26,
                            fontWeight: pw.FontWeight.bold)),
                  ]),
                  pw.Text(
                    '${at.day}/${at.month}/${at.year}  '
                    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                    style: pw.TextStyle(color: PdfColor.fromInt(0xFF8b939d), fontSize: 11),
                  ),
                ],
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(28),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
                // signal badge + levels
                pw.Container(
                  padding: const pw.EdgeInsets.all(18),
                  decoration: pw.BoxDecoration(
                      color: _panel, borderRadius: pw.BorderRadius.circular(14)),
                  child: pw.Row(children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      decoration: pw.BoxDecoration(
                          color: sideColor, borderRadius: pw.BorderRadius.circular(10)),
                      child: pw.Column(children: [
                        pw.Text(side,
                            style: pw.TextStyle(
                                color: PdfColors.white, fontSize: 20, fontWeight: pw.FontWeight.bold)),
                        pw.Text('${s.confidence}% conf.',
                            style: pw.TextStyle(color: PdfColors.white, fontSize: 9)),
                      ]),
                    ),
                    pw.SizedBox(width: 20),
                    pw.Expanded(
                      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
                        _level('Entry', fmt(s.entry), _ink),
                        _level('Stop', fmt(s.sl), _down),
                        _level('Target', fmt(s.tp), _up),
                        _level('Price', fmt(s.price), _accent),
                      ]),
                    ),
                  ]),
                ),
                pw.SizedBox(height: 18),
                // indicators
                _h('Indicators'),
                pw.SizedBox(height: 8),
                pw.Wrap(spacing: 10, runSpacing: 10, children: [
                  _stat('RSI (14)', s.rsi.toStringAsFixed(1)),
                  _stat('MACD hist', s.macdHist.toStringAsFixed(4)),
                  _stat('EMA 9', fmt(s.ema9)),
                  _stat('EMA 21', fmt(s.ema21)),
                  _stat('ATR (14)', fmt(s.atr)),
                  _stat('BB mid', fmt(s.bb.mid)),
                ]),
                pw.SizedBox(height: 18),
                // reasoning
                _h('Why this signal'),
                pw.SizedBox(height: 6),
                ...s.reasons.map((r) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Text('•  ', style: pw.TextStyle(color: _accent)),
                        pw.Expanded(child: pw.Text(r, style: pw.TextStyle(color: _ink, fontSize: 11))),
                      ]),
                    )),
                pw.SizedBox(height: 18),
                // news radar
                _h('News Radar — sentiment: ${sent.label} (${(sent.score * 100).toStringAsFixed(0)})'),
                pw.SizedBox(height: 6),
                ...sent.headlines.take(6).map((hl) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      child: pw.Text('– $hl', style: pw.TextStyle(color: _muted, fontSize: 10)),
                    )),
                pw.Spacer(),
                pw.Divider(color: PdfColor.fromInt(0xFFd7dce3)),
                pw.Text(
                  'Generated by Elder Wand. This is algorithmic decision support and a news-sentiment gauge — '
                  'NOT financial advice and NOT a prediction. Markets are risky; trade at your own discretion.',
                  style: pw.TextStyle(color: _muted, fontSize: 8),
                ),
              ]),
            ),
          ],
        ),
      ),
    );

    await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'scalp-${symbol.replaceAll('/', '')}-$interval.pdf');
  }

  static pw.Widget _level(String label, String value, PdfColor color) =>
      pw.Column(children: [
        pw.Text(value, style: pw.TextStyle(color: color, fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.Text(label, style: pw.TextStyle(color: _muted, fontSize: 9)),
      ]);

  static pw.Widget _stat(String label, String value) => pw.Container(
        width: 150,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(color: _panel, borderRadius: pw.BorderRadius.circular(10)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(label, style: pw.TextStyle(color: _muted, fontSize: 9)),
          pw.SizedBox(height: 2),
          pw.Text(value, style: pw.TextStyle(color: _ink, fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ]),
      );

  static pw.Widget _h(String t) => pw.Text(t,
      style: pw.TextStyle(color: _accent, fontSize: 12, fontWeight: pw.FontWeight.bold, letterSpacing: 0.5));
}
