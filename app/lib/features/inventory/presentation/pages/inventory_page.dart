import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/bottom_navigation.dart';
// Import Header baru
import '../widgets/inventory_header.dart';
import 'inventory_detail_page.dart';

class InventoryPage extends StatelessWidget {
  const InventoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Data dummy untuk daftar produk
    final List<Map<String, dynamic>> dummyProducts = [
      {
        'name': 'Premium Sunglasses',
        'sku': 'SUN-003',
        'inStock': 4,
        'price': 149.99,
        'isLowStock': true,
        'icon': Icons.archive_outlined
      },
      {
        'name': 'Gold Bracelet',
        'sku': 'BRC-004',
        'inStock': 12,
        'price': 199.99,
        'isLowStock': false,
        'icon': Icons.diamond_outlined
      },
      {
        'name': 'Silk Scarf',
        'sku': 'SCF-005',
        'inStock': 22,
        'price': 79.99,
        'isLowStock': false,
        'icon': Icons.all_inbox
      },
      {
        'name': 'Diamond Earrings',
        'sku': 'EAR-006',
        'inStock': 0,
        'price': 449.99,
        'isLowStock': true,
        'icon': Icons.diamond_outlined
      },
      {
        'name': 'Cashmere Sweater',
        'sku': 'SWT-007',
        'inStock': 3,
        'price': 259.99,
        'isLowStock': true,
        'icon': Icons.archive_outlined
      },
      {
        'name': 'Pearl Necklace',
        'sku': 'NCK-008',
        'inStock': 7,
        'price': 349.99,
        'isLowStock': false,
        'icon': Icons.diamond_outlined
      },
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          // 1. SLIVER APP BAR (Sticky)
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
                    // TODO: Aksi Tambah Item
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
            // Hilangkan garis kuning dengan mengatur scrolledUnderElevation
            scrolledUnderElevation: 0,
          ),

          // 2. STICKY HEADER untuk Search, Filter, dan Summary
          SliverPersistentHeader(
            delegate: _InventoryHeaderDelegate(
              child: const InventoryHeader(),
            ),
            pinned: true, // Membuat header tetap di atas saat di-scroll
            floating: false,
          ),

          // 3. SLIVER LIST (Daftar Produk yang dapat di-scroll)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final product = dummyProducts[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: _ProductListTile(
                    name: product['name'],
                    sku: product['sku'],
                    inStock: product['inStock'],
                    price: product['price'],
                    isLowStock: product['isLowStock'],
                    iconData: product['icon'],
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
      bottomNavigationBar: const BottomNavigation(),
    );
  }
}

// =========================================================================
// WIDGET PEMBANTU SLIVER
// =========================================================================

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
      300.0; // Sesuaikan tinggi maksimum yang dibutuhkan header

  @override
  double get minExtent =>
      300.0; // Atur min dan maxExtent sama agar tidak bisa diciutkan

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return true;
  }
}

// File: lib/features/inventory/presentation/pages/inventory_page.dart

// ... (Kode sebelumnya untuk InventoryPage, SliverAppBar, SliverPersistentHeader, dll.)

// =========================================================================
// WIDGET ITEM LIST (Disesuaikan untuk Navigasi)
// =========================================================================

class _ProductListTile extends StatelessWidget {
  final String name;
  final String sku; // SKU akan digunakan sebagai productId untuk navigasi
  final int inStock;
  final double price;
  final bool isLowStock;
  final IconData iconData;

  const _ProductListTile({
    required this.name,
    required this.sku,
    required this.inStock,
    required this.price,
    required this.isLowStock,
    required this.iconData,
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
            // Kita navigasi ke InventoryDetailPage dan mengirimkan SKU sebagai productId
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => InventoryDetailPage(productId: sku),
              ),
            );
          },
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),

          // ... (Bagian Leading, Title, Subtitle, Trailing tetap sama)
          // ...

          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Icon(iconData, color: AppTheme.mutedForeground, size: 24),
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
              if (isLowStock || isOutOfStock)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color:
                        isOutOfStock ? AppTheme.destructive : AppTheme.warning,
                    size: 18,
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
