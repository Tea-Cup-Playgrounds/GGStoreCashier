import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/router/app_router.dart';
import 'package:gg_store_cashier/features/inventory/domain/inventory_filter.dart';
import 'package:gg_store_cashier/core/helper/screen_type_utils.dart';
import 'package:gg_store_cashier/core/constants/screen_breakpoints.dart';
import 'package:gg_store_cashier/core/provider/auth_provider.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/inventory_header.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  late final TextEditingController searchController;
  InventoryFilter selectedFilter = InventoryFilter.all;
  InventoryFilter _currentFilter = InventoryFilter.all;

  void _onSearchChanged(String value) {
    debugPrint('Search: $value');
  }

  @override
  void initState() {
    super.initState();
    searchController = TextEditingController();
  }

  @override
  void dispose() {
    searchController.dispose();
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
    
    final List<Map<String, dynamic>> dummyProducts = [
      {
        'image': "https://picsum.photos/200",
        'name': 'Premium Sunglasses',
        'sku': 'SUN-003',
        'inStock': 4,
        'price': 149.99,
        'isLowStock': true,
      },
      {
        'image': "https://picsum.photos/200",
        'name': 'Gold Bracelet',
        'sku': 'BRC-004',
        'inStock': 12,
        'price': 199.99,
        'isLowStock': false,
      },
      {
        'image': "https://picsum.photos/200/300",
        'name': 'Silk Scarf',
        'sku': 'SCF-005',
        'inStock': 22,
        'price': 79.99,
        'isLowStock': false,
      },
      {
        'image': "https://picsum.photos/200",
        'name': 'Diamond Earrings',
        'sku': 'EAR-006',
        'inStock': 0,
        'price': 449.99,
        'isLowStock': true,
      },
      {
        'image': "https://picsum.photos/200",
        'name': 'Cashmere Sweater',
        'sku': 'SWT-007',
        'inStock': 3,
        'price': 259.99,
        'isLowStock': true,
      },
      {
        'image': "https://picsum.photos/200",
        'name': 'Pearl Necklace',
        'sku': 'NCK-008',
        'inStock': 7,
        'price': 349.99,
        'isLowStock': false,
      },
    ];

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.maxContentWidth),
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                title: Text(
                  'Inventory',
                  style: TextStyle(fontSize: screenType == ScreenType.tablet ? 24 : null),
                ),
                backgroundColor: Theme.of(context).colorScheme.surface,
                elevation: 0,
                centerTitle: false,
                pinned: true,
                actions: [
                  // Hide "Add Item" button for karyawan
                  if (!isKaryawan)
                    Padding(
                      padding: EdgeInsets.only(right: horizontalPadding),
                      child: ElevatedButton.icon(
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
                    ),
                ],
                scrolledUnderElevation: 0,
              ),

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
              
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final product = dummyProducts[index];
                      return _ProductListTile(
                        image: product['image'],
                        name: product['name'],
                        sku: product['sku'],
                        inStock: product['inStock'],
                        price: product['price'],
                        isLowStock: product['isLowStock'],
                        isTablet: screenType == ScreenType.tablet,
                      );
                    },
                    childCount: dummyProducts.length,
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.of(context).padding.bottom + 80,
                ),
              )
            ],
          ),
        ),
      ),
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
  final String name;
  final String sku;
  final int inStock;
  final double price;
  final bool isLowStock;
  final String image;
  final bool isTablet;

  const _ProductListTile({
    required this.name,
    required this.sku,
    required this.inStock,
    required this.price,
    required this.isLowStock,
    required this.image,
    this.isTablet = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isOutOfStock = inStock == 0;
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
            context.pushNamed('inventoryDetail', pathParameters: {'id': sku});
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
            child: Image.network(
              image,
              fit: BoxFit.cover,
            ),
          ),

          title: Text(
            name,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: isTablet ? 18 : null,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(
                'SKU: $sku',
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
                '$inStock in stock',
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
              Text(
                '\${price.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleLarge!.copyWith(
                      color: AppTheme.gold,
                      fontWeight: FontWeight.bold,
                      fontSize: isTablet ? 22 : null,
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
