import 'package:flutter/material.dart';
import 'documents.dart';
import 'theme.dart';

/// Simple invoice builder → shareable PDF (line items + tax + total).
class InvoiceScreen extends StatefulWidget {
  const InvoiceScreen({super.key});

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  final _client = TextEditingController();
  final _invoiceNo = TextEditingController();
  final _tax = TextEditingController(text: '18');
  final List<Map<String, TextEditingController>> _items = [
    {'desc': TextEditingController(), 'amount': TextEditingController()},
  ];

  double get _subtotal => _items.fold(
      0, (s, i) => s + (double.tryParse(i['amount']!.text) ?? 0));
  double get _total =>
      _subtotal * (1 + (double.tryParse(_tax.text) ?? 0) / 100);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('INVOICE')),
      body: Container(
        decoration: const BoxDecoration(gradient: Ak.bgGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _tf(_client, 'Bill to (client / company)'),
              Row(children: [
                Expanded(child: _tf(_invoiceNo, 'Invoice # (optional)')),
                const SizedBox(width: 10),
                Expanded(child: _tf(_tax, 'Tax %', number: true)),
              ]),
              const SizedBox(height: 8),
              Text('Line items', style: Ak.display(size: 13, color: Ak.textMid)),
              const SizedBox(height: 8),
              ..._items.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(
                          flex: 3, child: _tf(e.value['desc']!, 'Description')),
                      const SizedBox(width: 8),
                      Expanded(
                          flex: 2,
                          child: _tf(e.value['amount']!, 'Amount',
                              number: true)),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Ak.down),
                        onPressed: _items.length > 1
                            ? () => setState(() => _items.removeAt(e.key))
                            : null,
                      ),
                    ]),
                  )),
              TextButton.icon(
                onPressed: () => setState(() => _items.add({
                      'desc': TextEditingController(),
                      'amount': TextEditingController()
                    })),
                icon: const Icon(Icons.add, color: Ak.purple),
                label: const Text('Add item',
                    style: TextStyle(color: Ak.purple)),
              ),
              const Divider(color: Ak.glassLine),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Total: Rs. ${_total.toStringAsFixed(0)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: Ak.textHi,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final items = _items
                      .where((i) => i['desc']!.text.trim().isNotEmpty)
                      .map((i) => {
                            'desc': i['desc']!.text.trim(),
                            'amount': double.tryParse(i['amount']!.text) ?? 0,
                          })
                      .toList();
                  if (_client.text.trim().isEmpty || items.isEmpty) return;
                  await Documents.shareInvoice(
                    client: _client.text.trim(),
                    items: items,
                    taxPct: double.tryParse(_tax.text) ?? 0,
                    invoiceNo: _invoiceNo.text.trim(),
                  );
                },
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      gradient: Ak.goldGradient,
                      borderRadius: BorderRadius.circular(12)),
                  child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.picture_as_pdf, color: Ak.bg0),
                        SizedBox(width: 8),
                        Text('Generate & share PDF',
                            style: TextStyle(
                                color: Ak.bg0, fontWeight: FontWeight.w800)),
                      ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _tf(TextEditingController c, String label, {bool number = false}) {
    return TextField(
      controller: c,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(color: Ak.textHi),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Ak.textLo, fontSize: 12),
        filled: true,
        fillColor: Ak.glassFill,
        isDense: true,
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Ak.glassLine)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Ak.purple)),
      ),
    );
  }
}
