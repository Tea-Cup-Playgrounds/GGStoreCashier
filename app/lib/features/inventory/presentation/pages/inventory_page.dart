import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/router/app_router.dart';
import 'package:gg_store_cashier/features/inventory/domain/inventory_filter.dart';
import 'package:gg_store_cashier/core/helper/screen_type_utils.dart';
import 'package:gg_store_cashier/core/constants/screen_breakpoints.dart';
import 'package:gg_store_cashier/core/provider/auth_provider.dart';
import 'package:gg_store_cashier/core/services/product_service.dart';
import 'package:gg_store_cashier/core/models/product.dart';
import 'package:gg_store_cashier/core/helper/currency_formatter.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/inventory_header.dart';
import 'category_management_page.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> with SingleTickerProviderStateMixin {
  late final TextEditingController searchController;
  late TabController _tabController;
  InventoryFilter selectedFilter = InventoryFilter.all;
  InventoryFilter _currentFilter = InventoryFilter.all;
  
  // Products state
  List<Product> _products = [];
  bool _isLoadingProducts = true;
  String? _productsError;

  void _onSearchChanged(String value) {
    debugPrint('Search: $value');
    setState(() {}); // Trigger rebuild to filter products
  }

  @override
  void initState() {
    super.initState();
    searchController = TextEditingController();
    _tabController = TabController(length: 2, vsync: this);
    _loadProducts();
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
    searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onFilterChanged(InventoryFilter filter) {
    if (selectedFilter == filter) return;

    setState(() {
      selectedFilter = filter;
      _currentFilter = filter;
    });

    debugPrint('Filter changed to: $filter');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final isKaryawan = user?.isEmployee ?? false;
    
    final screenType = getScreenType(context);
    final orientation = getOrientation(context);
    final horizontalPadding = Breakpoints.getHorizontalPadding(screenType, orientation);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.maxContentWidth),
          child: Column(
            children: [
              // App Bar
              Container(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      Text(
                        'Inventory',
                        style: TextStyle(
                          fontSize: screenType == ScreenType.tablet ? 24 : 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (!isKaryawan)
                        ElevatedButton.icon(
                          onPressed: () {
                            context.push(AppRouter.inventoryAddItem);
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add Item'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.gold,
                            foregroundColor: AppTheme.background,
                            padding: EdgeInsets.symmetric(
                              horizontal: screenType == ScreenType.tablet ? 24 : 16,
                              vertical: screenType == ScreenType.tablet ? 16 : 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Tab Bar
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: AppTheme.gold,
                  unselectedLabelColor: AppTheme.mutedForeground,
                  indicatorColor: AppTheme.gold,
                  tabs: const [
                    Tab(text: 'Products'),
                    Tab(text: 'Categories'),
                  ],
                ),
              ),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildProductsTab(screenType, horizontalPadding),
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

  Widget _buildProductsTab(ScreenType screenType, double horizontalPadding) {
    // Filter products based on search and filter
    List<Product> filteredProducts = _products;
    
    // Apply search filter
    final searchQuery = searchController.text.toLowerCase();
    if (searchQuery.isNotEmpty) {
      filteredProducts = filteredProducts.where((product) {
        return product.name.toLowerCase().contains(searchQuery) ||
               (product.barcode?.toLowerCase().contains(searchQuery) ?? false) ||
               (product.category?.toLowerCase().contains(searchQuery) ?? false);
      }).toList();
    }
    
    // Apply stock filter
    switch (_currentFilter) {
      case InventoryFilter.low:
        filteredProducts = filteredProducts.where((p) => p.isLowStock && !p.isOutOfStock).toList();
        break;
      case InventoryFilter.out:
        filteredProducts = filteredProducts.where((p) => p.isOutOfStock).toList();
        break;
      case InventoryFilter.all:
      case InventoryFilter.other1:
      case InventoryFilter.other2:
        break;
    }

    return CustomScrollView(
      slivers: [
        SliverPersistentHeader(
          delegate: _InventoryHeaderDelegate(
            child: InventoryHeader(
              searchController: searchController,
              onSearchChanged: _onSearchChanged,
              currentFilter: _currentFilter,
              onFilterChanged: _onFilterChanged,
            ),
          ),
          pinned: true,
        ),
        
        if (_isLoadingProducts)
          const SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppTheme.gold),
                  SizedBox(height: 16),
                  Text('Loading products...'),
                ],
              ),
            ),
          )
        else if (_productsError != null)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppTheme.destructive,
                  ),
                  const SizedBox(height: 16),
                  const Text('Failed to load products'),
                  const SizedBox(height: 8),
                  Text(
                    _productsError!,
                    style: const TextStyle(color: AppTheme.mutedForeground),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _loadProducts,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          )
        else if (filteredProducts.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 64,
                    color: AppTheme.mutedForeground.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    searchQuery.isNotEmpty
                        ? 'No products found'
                        : 'No products available',
                    style: const TextStyle(
                      color: AppTheme.mutedForeground,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final product = filteredProducts[index];
                  return _ProductListTile(
                    product: product,
                    isTablet: screenType == ScreenType.tablet,
                  );
                },
                childCount: filteredProducts.length,
              ),
            ),
          ),

        SliverToBoxAdapter(
          child: SizedBox(
            height: MediaQuery.of(context).padding.bottom + 80,
          ),
        )
      ],
    );
  }
}

class _InventoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  const _InventoryHeaderDelegate({required this.child});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  double get maxExtent => 280.0;

  @override
  double get minExtent => 280.0;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return true;
  }
}

class _ProductListTile extends StatelessWidget {
  final Product product;
  final bool isTablet;

  const _ProductListTile({
    required this.product,
    this.isTablet = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isOutOfStock = product.isOutOfStock;
    final bool isLowStock = product.isLowStock;
    final Color stockColor = isOutOfStock
        ? AppTheme.destructive
        : isLowStock
            ? AppTheme.warning
            : AppTheme.success;

    final Color tileBackgroundColor = Theme.of(context).colorScheme.secondary;
    final imageSize = isTablet ? 64.0 : 48.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Container(
        decoration: BoxDecoration(
          color: tileBackgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          onTap: () {
            context.pushNamed('inventoryDetail', pathParameters: {'id': product.id});
          },
          contentPadding: EdgeInsets.symmetric(
            horizontal: isTablet ? 20 : 16, 
            vertical: isTablet ? 12 : 8
          ),

          leading: Container(
            width: imageSize,
            height: imageSize,
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(4),
            ),
            clipBehavior: Clip.antiAlias,
            child: product.image != null && product.image!.isNotEmpty
                ? Image.network(
                    ProductService.getProductImageUrl(product.image),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Image.asset(
                        ProductService.getPlaceholderImage(),
                        fit: BoxFit.cover,
                      );
                    },
                  )
                : Image.asset(
                    ProductService.getPlaceholderImage(),
                    fit: BoxFit.cover,
                  ),
          ),

          title: Text(
            product.name,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: isTablet ? 18 : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              if (product.barcode != null)
                Text(
                  'SKU: ${product.barcode}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall!
                      .copyWith(
                        color: AppTheme.mutedForeground,
                        fontSize: isTablet ? 14 : null,
                      ),
                ),
              const SizedBox(height: 2),
              Text(
                '${product.stock} in stock',
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: stockColor,
                      fontWeight: FontWeight.w500,
                      fontSize: isTablet ? 14 : null,
                    ),
              ),
            ],
          ),

          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  CurrencyFormatter.formatToRupiah(product.sellPrice),
                  style: Theme.of(context).textTheme.titleLarge!.copyWith(
                        color: AppTheme.gold,
                        fontWeight: FontWeight.bold,
                        fontSize: isTablet ? 22 : 18,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: isTablet ? 18 : 16,
                color: AppTheme.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
