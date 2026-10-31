import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/router/app_router.dart';
import 'package:gg_store_cashier/features/inventory/domain/inventory_filter.dart';
import 'package:gg_store_cashier/core/helper/screen_type_utils.dart';
import 'package:gg_store_cashier/core/constants/screen_breakpoints.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/provider/realtime_provider.dart';
import 'package:gg_store_cashier/core/services/catalog_service.dart';
import 'package:gg_store_cashier/core/services/product_service.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/helper/currency_formatter.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/inventory_location_provider.dart';
import '../widgets/inventory_header.dart';
import '../widgets/imei_lookup_sheet.dart';
import '../../../warehouse/presentation/widgets/warehouse_menu_button.dart';
import '../widgets/location_selector.dart';
import 'category_management_page.dart';
import '../../../../shared/widgets/pull_to_refresh.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> with SingleTickerProviderStateMixin {
  late final TextEditingController searchController;
  late TabController _tabController;
  InventoryFilter _currentFilter = InventoryFilter.all;

  List<CatalogProduct> _products = [];
  bool _isLoadingProducts = true;
  String? _productsError;
  int? _loadedLocationId;

  ProviderSubscription<RealtimeProductState>? _realtimeSub;
  ProviderSubscription<Location?>? _locationSub;

  @override
  void initState() {
    super.initState();
    searchController = TextEditingController();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Legacy product events (sales, edits from older screens) still mean stock changed.
    _realtimeSub ??= ref.listenManual(realtimeProductProvider, (previous, next) {
      if (next.lastUpdateTime != previous?.lastUpdateTime) _loadProducts();
    });
    // Load once the location resolves, and again whenever the user switches location.
    _locationSub ??= ref.listenManual<Location?>(effectiveInventoryLocationProvider, (previous, next) {
      if (next != null && next.id != _loadedLocationId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadProducts();
        });
      }
    }, fireImmediately: true);
  }

  Future<void> _loadProducts() async {
    final location = ref.read(effectiveInventoryLocationProvider);
    if (location == null) return;
    setState(() {
      _isLoadingProducts = true;
      _productsError = null;
    });
    try {
      final products = await CatalogService.getProducts(locationId: location.id);
      if (mounted) {
        setState(() {
          _products = products;
          _loadedLocationId = location.id;
          _isLoadingProducts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _productsError = e.toString();
          _isLoadingProducts = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _realtimeSub?.close();
    _locationSub?.close();
    searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  List<CatalogProduct> get _filteredProducts {
    List<CatalogProduct> result = _products;
    final q = searchController.text.toLowerCase();
    if (q.isNotEmpty) {
      result = result.where((p) {
        return p.name.toLowerCase().contains(q) ||
            (p.brandName?.toLowerCase().contains(q) ?? false) ||
            (p.categoryName?.toLowerCase().contains(q) ?? false) ||
            p.variants.any((v) =>
                v.sku.toLowerCase().contains(q) ||
                (v.barcode?.toLowerCase().contains(q) ?? false) ||
                (v.name?.toLowerCase().contains(q) ?? false));
      }).toList();
    }
    switch (_currentFilter) {
      case InventoryFilter.low:
        result = result.where((p) => p.isLowStock).toList();
        break;
      case InventoryFilter.out:
        result = result.where((p) => p.isOutOfStock).toList();
        break;
      default:
        break;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final access = ref.watch(accessProvider).valueOrNull;
    final canManageCatalog = access?.can('catalog.manage') ?? false;
    final screenType = getScreenType(context);
    final orientation = getOrientation(context);
    final hPad = Breakpoints.getHorizontalPadding(screenType, orientation);

    final location = ref.watch(effectiveInventoryLocationProvider);

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.maxContentWidth),
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 0.8)),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      Text(
                        'Inventory',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Cek IMEI / Serial',
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        onPressed: () => ImeiLookupSheet.show(context),
                      ),
                      if (location != null && access != null) WarehouseMenuButton(location: location, access: access, onClosed: _loadProducts),
                      if (canManageCatalog)
                        SizedBox(
                          height: 40,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await context.push(AppRouter.inventoryAddItem);
                              _loadProducts();
                            },
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Tambah Produk'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.gold,
                              foregroundColor: isDark ? Colors.black : Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                color: cs.surface,
                child: TabBar(
                  controller: _tabController,
                  labelColor: AppTheme.gold,
                  unselectedLabelColor: cs.onSurfaceVariant,
                  indicatorColor: AppTheme.gold,
                  dividerColor: cs.outlineVariant,
                  tabs: const [
                    Tab(text: 'Produk'),
                    Tab(text: 'Kategori'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildProductsTab(screenType, hPad, location),
                    const CategoryManagementPage(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductsTab(ScreenType screenType, double hPad, Location? location) {
    final filtered = _filteredProducts;
    final cs = Theme.of(context).colorScheme;
    final locationsAsync = ref.watch(stockLocationsProvider);

    if (locationsAsync.hasError) {
      return _ErrorState(message: locationsAsync.error.toString(), onRetry: () => ref.invalidate(accessProvider));
    }
    if (!locationsAsync.isLoading && location == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('Anda belum ditugaskan ke cabang atau gudang mana pun.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ),
      );
    }

    return Column(
      children: [
        if ((locationsAsync.valueOrNull?.length ?? 0) > 1)
          Container(
            color: cs.surface,
            padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 0),
            child: const LocationSelector(),
          ),

        // ── Sticky header (search + filters + summary) ──────────────
        InventoryHeader(
          searchController: searchController,
          onSearchChanged: (_) => setState(() {}),
          currentFilter: _currentFilter,
          onFilterChanged: (f) => setState(() => _currentFilter = f),
          totalItems: _products.length,
          lowStockItems: _products.where((p) => p.isLowStock).length,
          outOfStockItems: _products.where((p) => p.isOutOfStock).length,
        ),

        // ── Content area ─────────────────────────────────────────────
        Expanded(
          child: _isLoadingProducts
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: AppTheme.gold),
                      const SizedBox(height: 16),
                      Text('Memuat produk...',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              : _productsError != null
                  ? _ErrorState(message: _productsError!, onRetry: _loadProducts)
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2_outlined,
                                  size: 56, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                              const SizedBox(height: 16),
                              Text(
                                searchController.text.isNotEmpty ? 'Produk tidak ditemukan' : 'Belum ada produk',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        )
                      : PullToRefresh(
                          onRefresh: _loadProducts,
                          child: ListView.builder(
                            padding: EdgeInsets.fromLTRB(hPad, 12, hPad, MediaQuery.of(context).padding.bottom + 80),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) => _ProductTile(
                              product: filtered[index],
                              isTablet: screenType == ScreenType.tablet,
                              onTap: () async {
                                await context.pushNamed('inventoryDetail',
                                    pathParameters: {'id': filtered[index].id.toString()});
                                _loadProducts();
                              },
                            ),
                          ),
                        ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: AppTheme.destructive),
            const SizedBox(height: 16),
            Text('Gagal memuat produk', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.gold),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final CatalogProduct product;
  final bool isTablet;
  final VoidCallback onTap;
  const _ProductTile({required this.product, required this.onTap, this.isTablet = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final imgSize = isTablet ? 60.0 : 52.0;
    final stockColor = product.isOutOfStock
        ? AppTheme.destructive
        : product.isLowStock
            ? AppTheme.warning
            : AppTheme.success;
    final stockLabel = !product.hasStock
        ? (product.kind == 'service' ? 'Jasa' : 'Digital')
        : product.isOutOfStock
            ? 'Habis'
            : product.isLowStock
                ? 'Stok Tipis · ${product.onHand}'
                : '${product.onHand} ${product.isSerialized ? 'unit' : 'stok'}';
    final range = product.priceRange;
    final priceText = range.min == range.max
        ? CurrencyFormatter.formatToRupiah(range.min)
        : '${CurrencyFormatter.formatToCompactRupiah(range.min)} – ${CurrencyFormatter.formatToCompactRupiah(range.max)}';
    final subtitle = [
      if (product.brandName != null) product.brandName!,
      if (product.variants.length > 1) '${product.variants.length} varian' else if (product.variants.isNotEmpty) product.variants.first.sku,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant, width: 0.8),
            boxShadow: isDark
                ? null
                : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: imgSize,
                  height: imgSize,
                  child: product.image != null && product.image!.isNotEmpty
                      ? Image.network(ProductService.getProductImageUrl(product.image),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Image.asset(ProductService.getPlaceholderImage(), fit: BoxFit.cover))
                      : Image.asset(ProductService.getPlaceholderImage(), fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: stockColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: stockColor.withValues(alpha: 0.25)),
                          ),
                          child: Text(stockLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: stockColor, fontWeight: FontWeight.w600)),
                        ),
                        if (product.isSerialized) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.qr_code_2_rounded, size: 14, color: cs.onSurfaceVariant),
                        ],
                        if (product.categoryName != null) ...[
                          const SizedBox(width: 6),
                          Flexible(
                              child: Text(product.categoryName!,
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                                  overflow: TextOverflow.ellipsis)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(priceText,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: AppTheme.gold, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Icon(Icons.chevron_right_rounded, size: 18, color: cs.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
