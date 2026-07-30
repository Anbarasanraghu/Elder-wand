import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'liquidity.dart';
import 'scalp_sentiment.dart';
import 'scalp_signal.dart';
import 'structure.dart';

/// Generates a designed PDF scalping report and opens the share sheet.
class ScalpReport {
  static PdfColor get _ink => PdfColor.fromInt(0xFF14181f);
  static PdfColor get _muted => PdfColor.fromInt(0xFF5b6675);
  static PdfColor get _accent => PdfColor.fromInt(0xFF3f6fb0);
  static PdfColor get _up => PdfColor.fromInt(0xFF17a673);
  static PdfColor get _down => PdfColor.fromInt(0xFFe0454b);
  static PdfColor get _amber => PdfColor.fromInt(0xFFc98a00);
  static PdfColor get _panel => PdfColor.fromInt(0xFFf4f6fb);

  static String _f(double? v) =>
      v == null ? '—' : v.toStringAsFixed(v > 100 ? 2 : 4);

  static Future<void> share({
    required String symbol,
    required String interval,
    required Signal s,
    required Sentiment sent,
    required Liquidity liq,
    MarketStructure? ms,
    required DateTime at,
  }) async {
    final verdictColor =
        s.verdict == 'TAKE' ? _up : s.verdict == 'AVOID' ? _down : _amber;
    final doc = pw.Document();

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(0),
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.SizedBox(height: 0),
      build: (ctx) => [
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
            // verdict banner
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                  color: verdictColor, borderRadius: pw.BorderRadius.circular(12)),
              child: pw.Row(children: [
                pw.Text(s.verdict,
                    style: pw.TextStyle(
                        color: PdfColors.white, fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(width: 14),
                pw.Expanded(
                    child: pw.Text('${s.side} · ${s.confidence}% confidence',
                        style: pw.TextStyle(color: PdfColors.white, fontSize: 13))),
              ]),
            ),
            pw.SizedBox(height: 8),
            pw.Text(s.guidance, style: pw.TextStyle(color: _ink, fontSize: 11, lineSpacing: 2)),
            pw.SizedBox(height: 16),
            // levels
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                  color: _panel, borderRadius: pw.BorderRadius.circular(12)),
              child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
                _level('Entry', _f(s.entry), _ink),
                _level('Stop', _f(s.sl), _down),
                _level('Target', _f(s.tp), _up),
                _level('Price', _f(s.price), _accent),
              ]),
            ),
            pw.SizedBox(height: 18),
            _h('Indicators'),
            pw.SizedBox(height: 8),
            pw.Wrap(spacing: 10, runSpacing: 10, children: [
              _stat('RSI (14)', s.rsi.toStringAsFixed(1)),
              _stat('MACD hist', s.macdHist.toStringAsFixed(4)),
              _stat('EMA 9', _f(s.ema9)),
              _stat('EMA 21', _f(s.ema21)),
              _stat('ATR (14)', _f(s.atr)),
              _stat('BB mid', _f(s.bb.mid)),
            ]),
            if (ms != null) ...[
              pw.SizedBox(height: 18),
              _h('Market Structure'),
              pw.SizedBox(height: 8),
              pw.Wrap(spacing: 10, runSpacing: 10, children: [
                _stat('Bias', ms.bias),
                _stat('Trend strength', '${ms.trendStrength}%'),
                _stat('Session', ms.session),
                if (ms.bos != null) _stat('Structure', ms.bos!),
                if (ms.resistance.isNotEmpty)
                  _stat('Resistance', ms.resistance.map(_f).join('  ')),
                if (ms.support.isNotEmpty)
                  _stat('Support', ms.support.map(_f).join('  ')),
                if (ms.orderBlock != null)
                  _stat('Order block',
                      '${_f(ms.orderBlock!.low)}–${_f(ms.orderBlock!.high)}'),
                if (ms.fvg != null)
                  _stat('Fair value gap',
                      '${_f(ms.fvg!.low)}–${_f(ms.fvg!.high)}'),
              ]),
            ],
            pw.SizedBox(height: 18),
            _h('Why this signal'),
            pw.SizedBox(height: 6),
            ...s.reasons.map((r) => _bullet(r, _ink)),
            pw.SizedBox(height: 18),
            _h('Liquidity — likely hunt'),
            pw.SizedBox(height: 6),
            pw.Text(liq.hunt, style: pw.TextStyle(color: _ink, fontSize: 11, lineSpacing: 2)),
            pw.SizedBox(height: 8),
            pw.Wrap(spacing: 10, runSpacing: 10, children: [
              if (liq.nearestAbove != null)
                _stat('Buy-side above', _f(liq.nearestAbove)),
              if (liq.nearestBelow != null)
                _stat('Sell-side below', _f(liq.nearestBelow)),
            ]),
            pw.SizedBox(height: 18),
            _h('News Radar — ${sent.label} (${(sent.score * 100).toStringAsFixed(0)})'),
            pw.SizedBox(height: 6),
            ...sent.headlines.take(6).map((hl) =>
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Text('– $hl', style: pw.TextStyle(color: _muted, fontSize: 10)),
                )),
            pw.SizedBox(height: 20),
            pw.Divider(color: PdfColor.fromInt(0xFFd7dce3)),
            pw.Text(
              'Generated by Elder Wand. Algorithmic decision support + a news-sentiment '
              'gauge — NOT financial advice and NOT a prediction. Markets are risky; '
              'trade at your own discretion and manage risk.',
              style: pw.TextStyle(color: _muted, fontSize: 8),
            ),
          ]),
        ),
      ],
    ));

    await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'scalp-${symbol.replaceAll('/', '')}-$interval.pdf');
  }

  static pw.Widget _bullet(String t, PdfColor ink) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('•  ', style: pw.TextStyle(color: _accent)),
          pw.Expanded(child: pw.Text(t, style: pw.TextStyle(color: ink, fontSize: 11))),
        ]),
      );

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
