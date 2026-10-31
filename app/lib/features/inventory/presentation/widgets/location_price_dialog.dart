import 'package:flutter/material.dart';
import 'package:gg_store_cashier/core/helper/currency_formatter.dart';
import 'package:gg_store_cashier/core/helper/rupiah_input_formatter.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/services/catalog_service.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';

/// Sets or clears a variant's price at one location. Returns true when saved.
Future<bool?> showLocationPriceDialog(
  BuildContext context, {
  required Location location,
  required String variantLabel,
  required int variantId,
  required double basePrice,
  double? currentOverride,
}) {
  final controller = TextEditingController(
    text: currentOverride != null
        ? RupiahInputFormatter()
            .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: currentOverride.round().toString()))
            .text
        : '',
  );

  Future<void> save(BuildContext ctx, double? price) async {
    try {
      await CatalogService.setLocationPrice(locationId: location.id, variantId: variantId, sellPrice: price);
      SnackBarService.success(price == null ? 'Harga kembali ke harga dasar' : 'Harga cabang disimpan');
      if (ctx.mounted) Navigator.pop(ctx, true);
    } catch (e) {
      SnackBarService.error(e.toString());
    }
  }

  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Harga di Lokasi Ini'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$variantLabel\n${location.label}', style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text('Harga dasar: ${CurrencyFormatter.formatToRupiah(basePrice)}', style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [RupiahInputFormatter()],
            decoration: const InputDecoration(labelText: 'Harga jual di lokasi ini', hintText: 'Rp0'),
          ),
        ],
      ),
      actions: [
        if (currentOverride != null)
          TextButton(onPressed: () => save(ctx, null), child: const Text('Pakai harga dasar')),
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(
          onPressed: () {
            final price = RupiahInputFormatter.parseRupiahAsDouble(controller.text);
            if (price == null || price < 0) {
              SnackBarService.error('Harga tidak valid');
              return;
            }
            save(ctx, price);
          },
          child: const Text('Simpan'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}
