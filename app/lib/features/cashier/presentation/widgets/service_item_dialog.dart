import 'package:flutter/material.dart';
import 'package:gg_store_cashier/core/helper/rupiah_input_formatter.dart';
import 'package:gg_store_cashier/core/models/product.dart';

/// Price and note for a service / digital item (repair labour, pulsa) typed at the counter.
/// Returns (price, note) or null when cancelled.
Future<(double, String)?> showServiceItemDialog(BuildContext context, Product product) {
  final price = TextEditingController(
    text: RupiahInputFormatter()
        .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: product.sellPrice.round().toString()))
        .text,
  );
  final note = TextEditingController();
  final isDigital = product.kind == 'digital';

  return showDialog<(double, String)>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(product.name),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: price,
          keyboardType: TextInputType.number,
          inputFormatters: [RupiahInputFormatter()],
          decoration: const InputDecoration(labelText: 'Harga jual'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: note,
          autofocus: true,
          keyboardType: isDigital ? TextInputType.phone : TextInputType.text,
          decoration: InputDecoration(labelText: isDigital ? 'Nomor tujuan' : 'Keterangan (mis. unit yang diservis)'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
        FilledButton(
          onPressed: () {
            final value = RupiahInputFormatter.parseRupiahAsDouble(price.text);
            if (value == null || value <= 0) return;
            Navigator.pop(ctx, (value, note.text.trim()));
          },
          child: const Text('Tambah'),
        ),
      ],
    ),
  ).whenComplete(() {
    price.dispose();
    note.dispose();
  });
}
