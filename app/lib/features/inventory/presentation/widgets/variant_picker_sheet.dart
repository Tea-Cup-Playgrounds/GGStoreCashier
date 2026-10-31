import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gg_store_cashier/core/helper/currency_formatter.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/services/catalog_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';

/// A variant chosen in [VariantPickerSheet], with its product for name / IMEI settings.
class PickedVariant {
  final CatalogProduct product;
  final ProductVariant variant;
  const PickedVariant(this.product, this.variant);

  String get label => product.variantLabel(variant);
}

/// Searches the catalog (goods only) and returns the tapped variant. With [locationId] the rows
/// show on-hand stock there.
class VariantPickerSheet extends StatefulWidget {
  final int? locationId;
  final bool onlyInStock;

  const VariantPickerSheet({super.key, this.locationId, this.onlyInStock = false});

  static Future<PickedVariant?> show(BuildContext context, {int? locationId, bool onlyInStock = false}) =>
      showModalBottomSheet<PickedVariant>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => VariantPickerSheet(locationId: locationId, onlyInStock: onlyInStock),
      );

  @override
  State<VariantPickerSheet> createState() => _VariantPickerSheetState();
}

class _VariantPickerSheetState extends State<VariantPickerSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<CatalogProduct> _products = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await CatalogService.getProducts(locationId: widget.locationId, search: _search.text.trim());
      if (mounted) setState(() => _products = products.where((p) => p.kind == 'goods').toList());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = [
      for (final p in _products)
        for (final v in p.variants)
          if (!widget.onlyInStock || (v.onHand ?? 0) > 0) PickedVariant(p, v),
    ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pilih Barang', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), _load);
              },
              onSubmitted: (_) => _load(),
              decoration: const InputDecoration(
                hintText: 'Cari nama, SKU, atau scan barcode',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.gold))
                  : _error != null
                      ? Center(child: Text(_error!))
                      : rows.isEmpty
                          ? Center(child: Text('Barang tidak ditemukan', style: TextStyle(color: cs.onSurfaceVariant)))
                          : ListView.separated(
                              controller: scrollController,
                              itemCount: rows.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final row = rows[i];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    row.product.isSerialized ? Icons.qr_code_2_rounded : Icons.inventory_2_outlined,
                                    color: AppTheme.gold,
                                  ),
                                  title: Text(row.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text([
                                    row.variant.sku,
                                    if (row.variant.barcode != null) row.variant.barcode!,
                                  ].join(' · ')),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(CurrencyFormatter.formatToRupiah(row.variant.price),
                                          style: Theme.of(context).textTheme.labelMedium),
                                      if (widget.locationId != null)
                                        Text('Stok ${row.variant.onHand ?? 0}',
                                            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                                    ],
                                  ),
                                  onTap: () => Navigator.pop(context, row),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
