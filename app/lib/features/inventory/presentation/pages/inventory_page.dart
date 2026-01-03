import 'package:flutter/material.dart';
import 'package:gg_store_cashier/core/router/app_router.dart';
import 'package:gg_store_cashier/features/inventory/domain/inventory_filter.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/inventory_header.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
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

    // ============================
    // TODO: FETCH KE API
    // ============================
    // fetchInventory(
    //   filter: filter,
    //   search: searchController.text,
    // );

    debugPrint('Filter changed to: $filter');
  }

  @override
  Widget build(BuildContext context) {
    // Data dummy untuk daftar produk
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
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          // 1. App Bar
          SliverAppBar(
            title: const Text('Inventory'),
            backgroundColor: AppTheme.background,
            elevation: 0,
            centerTitle: false,
            pinned: true, // Membuat AppBar tetap di atas
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: ElevatedButton.icon(
                  onPressed: () {
                    context.push(AppRouter.inventoryAddItem);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add Item'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.gold,
                    foregroundColor: AppTheme.background,
                  ),
                ),
              ),
            ],
            scrolledUnderElevation: 0,
          ),

          // 2. STICKY HEADER untuk Search, Filter, dan Summary
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
          // Items
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final product = dummyProducts[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: _ProductListTile(
                    image: product['image'],
                    name: product['name'],
                    sku: product['sku'],
                    inStock: product['inStock'],
                    price: product['price'],
                    isLowStock: product['isLowStock'],
                  ),
                );
              },
              childCount: dummyProducts.length,
            ),
          ),

          // Padding di bagian bawah agar BottomNav tidak menutupi item terakhir
          SliverToBoxAdapter(
            child: SizedBox(
              height:
                  // Tambahkan padding standar + tinggi Bottom Navigation Bar (sekitar 60-80)
                  MediaQuery.of(context).padding.bottom + 80,
            ),
          )
        ],
      ),
    );
  }
}

// Delegate untuk membuat InventoryHeader menjadi Sticky
class _InventoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  const _InventoryHeaderDelegate({required this.child});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  double get maxExtent =>
      280.0; // Sesuaikan tinggi maksimum yang dibutuhkan header

  @override
  double get minExtent =>
      280.0; // Atur min dan maxExtent sama agar tidak bisa diciutkan

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

  const _ProductListTile({
    required this.name,
    required this.sku,
    required this.inStock,
    required this.price,
    required this.isLowStock,
    required this.image,
  });

  @override
  Widget build(BuildContext context) {
    final bool isOutOfStock = inStock == 0;
    final Color stockColor = isOutOfStock
        ? AppTheme.destructive
        : isLowStock
            ? AppTheme.warning
            : AppTheme.success;

    final Color tileBackgroundColor = AppTheme.surface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Container(
        decoration: BoxDecoration(
          color: tileBackgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border, width: 1.0),
        ),
        child: ListTile(
          // ===============================================
          // LOGIKA NAVIGASI: Mengarahkan ke InventoryDetailPage
          // ===============================================
          onTap: () {
            context.pushNamed('inventoryDetail', pathParameters: {'id': sku});
          },
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),

          // ... (Bagian Leading, Title, Subtitle, Trailing tetap sama)
          // ...

          leading: Container(
            width: 48,
            height: 48, // ✅ FIXED SQUARE
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(4),
            ),
            clipBehavior: Clip.antiAlias, // 🔥 WAJIB agar image ikut rounded
            child: Image.network(
              image,
              fit: BoxFit.cover, // ✅ isi kotak tanpa gepeng
            ),
          ),

          title: Text(
            name,
            style: Theme.of(context).textTheme.titleMedium,
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
                    .copyWith(color: AppTheme.mutedForeground),
              ),
              const SizedBox(height: 2),
              Text(
                '$inStock in stock',
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: stockColor,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),

          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '\$${price.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleLarge!.copyWith(
                      color: AppTheme.gold,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: AppTheme.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
