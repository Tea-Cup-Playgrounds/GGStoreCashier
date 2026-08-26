import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/router/app_router.dart';
import 'package:gg_store_cashier/features/inventory/domain/inventory_filter.dart';
import 'package:gg_store_cashier/core/helper/screen_type_utils.dart';
import 'package:gg_store_cashier/core/constants/screen_breakpoints.dart';
import 'package:gg_store_cashier/core/provider/auth_provider.dart';
import 'package:gg_store_cashier/core/provider/realtime_store_provider.dart';
import 'package:gg_store_cashier/core/provider/socket_provider.dart';
import 'package:gg_store_cashier/core/services/product_service.dart';
import 'package:gg_store_cashier/core/models/product.dart';
import 'package:gg_store_cashier/core/helper/currency_formatter.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/inventory_header.dart';
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
  String? _selectedCategory; // null = all categories
  List<String> _categories = [];
  bool _isInitialLoading = true;
  String? _productsError;
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    searchController = TextEditingController();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentTab = _tabController.index;
        });
      }
    });

    _initialSync();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  /// First open: fetch from network → seed SQLite.
  /// productStoreProvider takes over from there, polling every 500 ms.
  Future<void> _initialSync() async {
    if (mounted) setState(() => _isInitialLoading = true);
    try {
      final user = ref.read(authProvider).user;
      final branchId = (user != null && !user.isSuperAdmin) ? user.branchId : null;
      final products = await ProductService.getProducts(
        branchId: branchId,
        forceRefresh: true,
      );
      await ref.read(productStoreProvider(branchId).notifier).seedFromHttp(products);
      if (mounted) {
        setState(() {
          _productsError = null;
          // Build sorted unique category list from fetched products
          final cats = products.map((p) => p.category).whereType<String>().where((c) => c.isNotEmpty).toSet().toList()
            ..sort();
          _categories = cats;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _productsError = e.toString());
    } finally {
      if (mounted) setState(() => _isInitialLoading = false);
    }
  }

  /// Pull-to-refresh: re-fetch network → reseed SQLite.
  Future<void> _refresh() async {
    if (mounted) setState(() => _productsError = null);
    try {
      final user = ref.read(authProvider).user;
      final branchId = (user != null && !user.isSuperAdmin) ? user.branchId : null;
      final products = await ProductService.getProducts(
        branchId: branchId,
        forceRefresh: true,
      );
      await ref.read(productStoreProvider(branchId).notifier).seedFromHttp(products);
      if (mounted) {
        setState(() {
          final cats = products.map((p) => p.category).whereType<String>().where((c) => c.isNotEmpty).toSet().toList()
            ..sort();
          _categories = cats;
          // Reset selected category if it no longer exists after refresh
          if (_selectedCategory != null && !cats.contains(_selectedCategory)) {
            _selectedCategory = null;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _productsError = e.toString());
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ── Filtering ─────────────────────────────────────────────────────────────

  List<Product> _applyFilters(List<Product> source) {
    var result = source;
    final q = searchController.text.toLowerCase();
    if (q.isNotEmpty) {
      result = result
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              (p.barcode?.toLowerCase().contains(q) ?? false) ||
              (p.category?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    if (_selectedCategory != null) {
      result = result.where((p) => p.category == _selectedCategory).toList();
    }
    switch (_currentFilter) {
      case InventoryFilter.low:
        result = result.where((p) => p.isLowStock && !p.isOutOfStock).toList();
        break;
      case InventoryFilter.out:
        result = result.where((p) => p.isOutOfStock).toList();
        break;
      default:
        break;
    }
    return result;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final user = ref.watch(authProvider).user;
    final isKaryawan = user?.isEmployee ?? false;
    final screenType = getScreenType(context);
    final orientation = getOrientation(context);
    final hPad = Breakpoints.getHorizontalPadding(screenType, orientation);

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.maxContentWidth),
          child: Column(
            children: [
              // ── Top bar ────────────────────────────────────────────
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
                      const SizedBox(width: 8),
                      _LiveDot(provider: socketConnectionProvider),
                      const Spacer(),
                      if (!isKaryawan)
                        SizedBox(
                          height: 40,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              bool? changed;

                              if (_currentTab == 0) {
                                changed = await context.push(AppRouter.inventoryAddItem);
                              } else {
                                changed = await context.push(AppRouter.categoryForm);
                              }
                              if (changed == true && mounted) {
                                _refresh();
                              }
                            },
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: Text(
                              _currentTab == 0 ? 'Tambah Produk' : 'Tambah Kategori',
                            ),
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

              // ── Tabs ───────────────────────────────────────────────
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

              // ── Tab views ──────────────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildProductsTab(screenType, hPad, user),
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

  Widget _buildProductsTab(ScreenType screenType, double hPad, dynamic user) {
    final cs = Theme.of(context).colorScheme;
    final branchId = (user != null && !user.isSuperAdmin) ? user.branchId : null;

    // SQLite-backed store — auto-updated every 500 ms via WS
    final storeProducts = ref.watch(productStoreProvider(branchId));
    final filtered = _applyFilters(storeProducts);

    return Column(
      children: [
        // ── Header (search + filter chips + counts) ────────────────
        InventoryHeader(
          searchController: searchController,
          onSearchChanged: (_) => setState(() {}),
          currentFilter: _currentFilter,
          onFilterChanged: (f) => setState(() => _currentFilter = f),
          totalItems: storeProducts.length,
          lowStockItems: storeProducts.where((p) => p.isLowStock && !p.isOutOfStock).length,
          outOfStockItems: storeProducts.where((p) => p.isOutOfStock).length,
          categories: _categories,
          selectedCategory: _selectedCategory,
          onCategoryChanged: (c) => setState(() => _selectedCategory = c),
        ),

        // ── Content ────────────────────────────────────────────────
        Expanded(
          child: _isInitialLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: AppTheme.gold, strokeWidth: 2),
                      const SizedBox(height: 16),
                      Text('Memuat produk...',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              : _productsError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 56, color: AppTheme.destructive),
                            const SizedBox(height: 16),
                            Text('Gagal memuat produk', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text(_productsError!,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: _initialSync,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Coba Lagi'),
                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.gold),
                            ),
                          ],
                        ),
                      ),
                    )
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
                          onRefresh: _refresh,
                          child: ListView.builder(
                            padding: EdgeInsets.fromLTRB(hPad, 12, hPad, MediaQuery.of(context).padding.bottom + 80),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) => _ProductTile(
                              product: filtered[index],
                              isTablet: screenType == ScreenType.tablet,
                              onTap: () async {
                                final changed = await context.pushNamed(
                                  'inventoryDetail',
                                  pathParameters: {'id': filtered[index].id},
                                );
                                if (changed == true && mounted) _refresh();
                              },
                            ),
                          ),
                        ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Product list tile
// ─────────────────────────────────────────────────────────────────────────────

class _ProductTile extends StatelessWidget {
  final Product product;
  final bool isTablet;
  final VoidCallback? onTap;
  const _ProductTile({required this.product, this.isTablet = false, this.onTap});

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
    final stockLabel = product.isOutOfStock
        ? 'Habis'
        : product.isLowStock
            ? 'Stok Tipis'
            : '${product.stock} stok';

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
                    if (product.barcode != null) ...[
                      const SizedBox(height: 2),
                      Text('SKU: ${product.barcode}',
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
                        if (product.category != null) ...[
                          const SizedBox(width: 6),
                          Flexible(
                              child: Text(product.category!,
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
                  Text(CurrencyFormatter.formatToRupiah(product.sellPrice),
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

// ─────────────────────────────────────────────────────────────────────────────
// Live connection dot
// ─────────────────────────────────────────────────────────────────────────────

/// Green = connected, red = disconnected.
class _LiveDot extends ConsumerWidget {
  final ProviderBase<AsyncValue<bool>> provider;
  const _LiveDot({required this.provider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLive = ref.watch(provider).valueOrNull ?? false;
    return Tooltip(
      message: isLive ? 'Live updates aktif' : 'Tidak terhubung — data mungkin tidak terbaru',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isLive ? AppTheme.success : AppTheme.destructive,
          boxShadow: isLive
              ? [BoxShadow(color: AppTheme.success.withValues(alpha: 0.5), blurRadius: 6, spreadRadius: 1)]
              : null,
        ),
      ),
    );
  }
}
