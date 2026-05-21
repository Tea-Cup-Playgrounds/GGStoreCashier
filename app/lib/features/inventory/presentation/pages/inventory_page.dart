import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/router/app_router.dart';
import 'package:gg_store_cashier/features/inventory/domain/inventory_filter.dart';
import 'package:gg_store_cashier/core/helper/screen_type_utils.dart';
import 'package:gg_store_cashier/core/constants/screen_breakpoints.dart';
import 'package:gg_store_cashier/core/provider/auth_provider.dart';
import 'package:gg_store_cashier/core/provider/realtime_provider.dart';
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

  List<Product> _products = [];
  bool _isLoadingProducts = true;
  String? _productsError;

  ProviderSubscription<RealtimeProductState>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    searchController = TextEditingController();
    _tabController = TabController(length: 2, vsync: this);
    _loadProducts();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _realtimeSub ??= ref.listenManual(realtimeProductProvider, (previous, next) {
      if (next.lastUpdateTime != previous?.lastUpdateTime) _loadProducts();
    });
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoadingProducts = true;
      _productsError = null;
    });
    try {
      final products = await ProductService.getProducts();
      setState(() {
        _products = products;
        _isLoadingProducts = false;
      });
    } catch (e) {
      setState(() {
        _productsError = e.toString();
        _isLoadingProducts = false;
      });
    }
  }

  @override
  void dispose() {
    _realtimeSub?.close();
    searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  List<Product> get _filteredProducts {
    List<Product> result = _products;
    final q = searchController.text.toLowerCase();
    if (q.isNotEmpty) {
      result = result.where((p) {
        return p.name.toLowerCase().contains(q) ||
            (p.barcode?.toLowerCase().contains(q) ?? false) ||
            (p.category?.toLowerCase().contains(q) ?? false);
      }).toList();
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
              // ── App bar ──────────────────────────────────────────────
              Container(
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(
                    bottom: BorderSide(color: cs.outlineVariant, width: 0.8),
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      Text(
                        'Inventory',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const Spacer(),
                      if (!isKaryawan)
                        SizedBox(
                          height: 40,
                          child: ElevatedButton.icon(
                            onPressed: () => context.push(AppRouter.inventoryAddItem),
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

              // ── Tab bar ──────────────────────────────────────────────
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

              // ── Tab views ────────────────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildProductsTab(screenType, hPad),
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

  Widget _buildProductsTab(ScreenType screenType, double hPad) {
    final filtered = _filteredProducts;
    final cs = Theme.of(context).colorScheme;

    return PullToRefresh(
      onRefresh: _loadProducts,
      child: CustomScrollView(
        slivers: [
          // ── Sticky header ──────────────────────────────────────────
          SliverPersistentHeader(
            pinned: true,
            delegate: _HeaderDelegate(
              child: InventoryHeader(
                searchController: searchController,
                onSearchChanged: (_) => setState(() {}),
                currentFilter: _currentFilter,
                onFilterChanged: (f) => setState(() => _currentFilter = f),
                totalItems: _products.length,
                lowStockItems: _products.where((p) => p.isLowStock && !p.isOutOfStock).length,
                outOfStockItems: _products.where((p) => p.isOutOfStock).length,
              ),
            ),
          ),

          // ── Loading ────────────────────────────────────────────────
          if (_isLoadingProducts)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: AppTheme.gold),
                    const SizedBox(height: 16),
                    Text(
                      'Memuat produk...',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            )

          // ── Error ──────────────────────────────────────────────────
          else if (_productsError != null)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 56, color: AppTheme.destructive),
                      const SizedBox(height: 16),
                      Text('Gagal memuat produk', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        _productsError!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _loadProducts,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Coba Lagi'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.gold),
                      ),
                    ],
                  ),
                ),
              ),
            )

          // ── Empty ──────────────────────────────────────────────────
          else if (filtered.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 56,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      searchController.text.isNotEmpty ? 'Produk tidak ditemukan' : 'Belum ada produk',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            )

          // ── List ───────────────────────────────────────────────────
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _ProductTile(
                    product: filtered[index],
                    isTablet: screenType == ScreenType.tablet,
                  ),
                  childCount: filtered.length,
                ),
              ),
            ),

          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.bottom + 80),
          ),
        ],
      ),
    );
  }
}

// ── Sliver header delegate ────────────────────────────────────────────────────

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  const _HeaderDelegate({required this.child});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;

  @override
  double get maxExtent => 220;
  @override
  double get minExtent => 220;
  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate old) => true;
}

// ── Product tile ──────────────────────────────────────────────────────────────

class _ProductTile extends StatelessWidget {
  final Product product;
  final bool isTablet;

  const _ProductTile({required this.product, this.isTablet = false});

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
        onTap: () => context.pushNamed('inventoryDetail', pathParameters: {'id': product.id}),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant, width: 0.8),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            children: [
              // ── Image ──────────────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: imgSize,
                  height: imgSize,
                  child: product.image != null && product.image!.isNotEmpty
                      ? Image.network(
                          ProductService.getProductImageUrl(product.image),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Image.asset(
                            ProductService.getPlaceholderImage(),
                            fit: BoxFit.cover,
                          ),
                        )
                      : Image.asset(
                          ProductService.getPlaceholderImage(),
                          fit: BoxFit.cover,
                        ),
                ),
              ),
              const SizedBox(width: 12),

              // ── Info ───────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (product.barcode != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'SKU: ${product.barcode}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
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
                          child: Text(
                            stockLabel,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: stockColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        if (product.category != null) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              product.category!,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // ── Price + chevron ────────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.formatToRupiah(product.sellPrice),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppTheme.gold,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
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
