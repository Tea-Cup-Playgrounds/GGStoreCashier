import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/helper/currency_formatter.dart';
import 'package:gg_store_cashier/core/models/access.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/services/catalog_service.dart';
import 'package:gg_store_cashier/core/services/product_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import '../providers/inventory_location_provider.dart';
import '../widgets/location_price_dialog.dart';
import '../widgets/location_selector.dart';
import '../widgets/movements_sheet.dart';
import '../widgets/stock_adjust_sheet.dart';
import 'product_form_page.dart';
import 'units_page.dart';

/// One catalog product: its variants, and stock / price at the selected location.
class ProductDetailPage extends ConsumerStatefulWidget {
  final int productId;

  const ProductDetailPage({super.key, required this.productId});

  @override
  ConsumerState<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends ConsumerState<ProductDetailPage> {
  CatalogProduct? _product;
  bool _loading = true;
  String? _error;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _product == null;
      _error = null;
    });
    try {
      final product = await CatalogService.getProduct(widget.productId);
      if (mounted) setState(() => _product = product);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProductFormPage(product: _product)),
    );
    if (saved == true) _load();
  }

  Future<void> _delete() async {
    final product = _product!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Produk'),
        content: Text('Hapus "${product.name}" dari katalog? Riwayat penjualan dan stok tetap tersimpan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await CatalogService.deleteProduct(product.id);
      SnackBarService.success('Produk berhasil dihapus');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final access = ref.watch(accessProvider).valueOrNull ?? UserAccess.empty;
    final location = ref.watch(effectiveInventoryLocationProvider);
    final locationCount = ref.watch(stockLocationsProvider).valueOrNull?.length ?? 0;
    final product = _product;
    final canManage = access.can('catalog.manage');

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: Text(product?.name ?? 'Detail Produk',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          if (product != null && canManage) ...[
            IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit Produk', onPressed: _edit),
            _deleting
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.destructive)))
                : IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppTheme.destructive),
                    tooltip: 'Hapus Produk',
                    onPressed: _delete),
          ],
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.gold))
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    TextButton(onPressed: _load, child: const Text('Coba Lagi')),
                  ]),
                )
              : RefreshIndicator(
                  color: AppTheme.gold,
                  onRefresh: _load,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 24),
                    children: [
                      _Header(product: product!),
                      if (product.hasStock && locationCount > 1) ...[
                        const SizedBox(height: 16),
                        const LocationSelector(),
                      ],
                      const SizedBox(height: 16),
                      Text('Varian', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      for (final variant in product.variants.where((v) => v.isActive))
                        _VariantCard(
                          product: product,
                          variant: variant,
                          location: location,
                          access: access,
                          onChanged: _load,
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _Header extends StatelessWidget {
  final CatalogProduct product;
  const _Header({required this.product});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chips = <String>[
      if (product.kind == 'service') 'Jasa',
      if (product.kind == 'digital') 'Digital',
      if (product.isSerialized && product.serialType != null) serialTypeLabel(product.serialType!),
      if (product.warrantyMonths > 0) 'Garansi ${product.warrantyMonths} bulan',
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant, width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 72,
              height: 72,
              child: product.image != null && product.image!.isNotEmpty
                  ? Image.network(ProductService.getProductImageUrl(product.image),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Image.asset(ProductService.getPlaceholderImage(), fit: BoxFit.cover))
                  : Image.asset(ProductService.getPlaceholderImage(), fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text([product.brandName, product.categoryName].whereType<String>().join(' · '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: chips
                        .map((c) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.gold.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(c,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(color: AppTheme.goldDark, fontWeight: FontWeight.w600)),
                            ))
                        .toList(),
                  ),
                ],
                if (product.description != null && product.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(product.description!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VariantCard extends StatelessWidget {
  final CatalogProduct product;
  final ProductVariant variant;
  final Location? location;
  final UserAccess access;
  final VoidCallback onChanged;

  const _VariantCard({
    required this.product,
    required this.variant,
    required this.location,
    required this.access,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = product.stock.where((s) => s.variantId == variant.id).toList();
    final here = location == null ? null : rows.where((s) => s.locationId == location!.id).firstOrNull;
    final elsewhere = rows.where((s) => s.locationId != location?.id && s.onHand > 0).toList();
    final onHand = here?.onHand ?? 0;
    final price = here?.sellPrice ?? variant.basePrice;
    final hasOverride = here?.locationPrice != null;
    final label = product.variantLabel(variant);
    final loc = location;

    final actions = <Widget>[
      if (loc != null && product.hasStock && !product.isSerialized && access.can('stock.adjust', loc.id))
        _ActionChip(
          icon: Icons.tune_rounded,
          label: 'Sesuaikan stok',
          onTap: () async {
            final saved = await StockAdjustSheet.show(context,
                location: loc, variantLabel: label, variantId: variant.id, currentQty: onHand);
            if (saved == true) onChanged();
          },
        ),
      if (loc != null && product.isSerialized && access.can('stock.view', loc.id))
        _ActionChip(
          icon: Icons.qr_code_2_rounded,
          label: 'Unit / IMEI',
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => UnitsPage(product: product, variant: variant, location: loc),
            ));
            onChanged();
          },
        ),
      if (loc != null && product.hasStock && access.can('prices.manage_location', loc.id))
        _ActionChip(
          icon: Icons.sell_outlined,
          label: 'Harga lokasi',
          onTap: () async {
            final saved = await showLocationPriceDialog(context,
                location: loc,
                variantLabel: label,
                variantId: variant.id,
                basePrice: variant.basePrice,
                currentOverride: here?.locationPrice);
            if (saved == true) onChanged();
          },
        ),
      if (loc != null && product.hasStock && access.can('stock.view', loc.id))
        _ActionChip(
          icon: Icons.history_rounded,
          label: 'Riwayat',
          onTap: () => MovementsSheet.show(context, location: loc, variantLabel: label, variantId: variant.id),
        ),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(variant.name ?? 'Standar',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(['SKU ${variant.sku}', if (variant.barcode != null) variant.barcode!].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(CurrencyFormatter.formatToRupiah(price),
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: AppTheme.gold, fontWeight: FontWeight.bold)),
                  if (hasOverride)
                    Text('harga lokasi · dasar ${CurrencyFormatter.formatToCompactRupiah(variant.basePrice)}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          if (product.hasStock && loc != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(loc.isWarehouse ? Icons.warehouse_outlined : Icons.storefront_outlined,
                    size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${loc.label}: $onHand ${product.isSerialized ? 'unit' : 'stok'}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: onHand <= 0 ? AppTheme.destructive : null,
                          )),
                ),
                if (here?.avgCost != null && access.canSeeCost(loc.id))
                  Text('HPP ${CurrencyFormatter.formatToCompactRupiah(here!.avgCost!)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ],
          if (elsewhere.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Lokasi lain: ${elsewhere.map((s) => '${s.locationCode ?? s.locationName} ${s.onHand}').join(' · ')}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: AppTheme.gold),
      label: Text(label),
      onPressed: onTap,
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    );
  }
}
