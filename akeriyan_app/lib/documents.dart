import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Generates and shares agency PDFs (proposals & invoices).
/// Uses "Rs." (not ₹) so the base PDF font renders it without a custom font.
class Documents {
  static const _agency = 'Elder Wand Tech';

  static String _rs(num v) => 'Rs. ${v.toStringAsFixed(0)}';

  static pw.Widget _h(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(t,
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold)),
      );

  static Future<void> shareProposal(Map<String, dynamic> p) async {
    final doc = pw.Document();
    final scope = ((p['scope'] as List?) ?? []).map((e) => '$e').toList();
    final timeline = ((p['timeline'] as List?) ?? []).map((e) => '$e').toList();
    final pricing = (p['pricing'] as List?) ?? [];
    final total = (p['total'] as num?) ?? 0;

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (ctx) => [
        pw.Text(_agency,
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
        pw.Divider(),
        pw.SizedBox(height: 8),
        pw.Text(p['title']?.toString() ?? 'Proposal',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        if ((p['summary']?.toString() ?? '').isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text(p['summary'].toString()),
        ],
        if (scope.isNotEmpty) ...[
          _h('Scope of work'),
          ...scope.map((s) => pw.Bullet(text: s)),
        ],
        if (timeline.isNotEmpty) ...[
          _h('Timeline'),
          ...timeline.map((t) => pw.Bullet(text: t)),
        ],
        if (pricing.isNotEmpty) ...[
          _h('Pricing'),
          pw.TableHelper.fromTextArray(
            headers: ['Item', 'Amount'],
            data: pricing
                .map((r) => [
                      (r['item'] ?? '').toString(),
                      _rs((r['amount'] as num?) ?? 0)
                    ])
                .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignments: {1: pw.Alignment.centerRight},
          ),
        ],
        pw.SizedBox(height: 10),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Total: ${_rs(total)}',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ),
        if ((p['terms']?.toString() ?? '').isNotEmpty) ...[
          _h('Terms'),
          pw.Text(p['terms'].toString(),
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        ],
      ],
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'proposal.pdf');
  }

  static Future<void> shareInvoice({
    required String client,
    required List<Map<String, dynamic>> items,
    double taxPct = 18,
    String invoiceNo = '',
    String date = '',
  }) async {
    final subtotal =
        items.fold<double>(0, (s, i) => s + ((i['amount'] as num?) ?? 0));
    final tax = subtotal * taxPct / 100;
    final total = subtotal + tax;
    final doc = pw.Document();

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (ctx) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(_agency,
                style:
                    pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.Text('INVOICE',
                style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700)),
          ],
        ),
        pw.Divider(),
        pw.SizedBox(height: 6),
        pw.Text('Bill to: $client'),
        if (invoiceNo.isNotEmpty) pw.Text('Invoice #: $invoiceNo'),
        if (date.isNotEmpty) pw.Text('Date: $date'),
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headers: ['Description', 'Amount'],
          data: items
              .map((i) => [
                    (i['desc'] ?? '').toString(),
                    _rs((i['amount'] as num?) ?? 0)
                  ])
              .toList(),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellAlignments: {1: pw.Alignment.centerRight},
        ),
        pw.SizedBox(height: 12),
        _kv('Subtotal', _rs(subtotal)),
        _kv('Tax ($taxPct%)', _rs(tax)),
        pw.Divider(),
        _kv('Total', _rs(total), bold: true),
      ],
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'invoice.pdf');
  }

  static pw.Widget _kv(String k, String v, {bool bold = false}) {
    final style = pw.TextStyle(
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        fontSize: bold ? 14 : 11);
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text('$k:  ', style: style),
            pw.SizedBox(width: 40),
            pw.Text(v, style: style),
          ],
        ),
      ),
    );
  }
}
