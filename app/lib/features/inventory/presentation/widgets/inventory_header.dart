import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

// Widget yang akan menjadi bagian dari SliverPersistentHeader
class InventoryHeader extends StatelessWidget {
  const InventoryHeader({super.key});

  // Widget Pembantu untuk Kartu Ringkasan Stok
  Widget _buildSummaryTile(
      BuildContext context, String title, String value, Color iconColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  title.contains('Total')
                      ? Icons.archive_outlined
                      : Icons.warning_amber_rounded,
                  color: iconColor,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineLarge!.copyWith(
                        color: iconColor,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: AppTheme.mutedForeground,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  // Filter Bar (All, Low Stock, Out of Stock)
  Widget _buildFilterBar(BuildContext context) {
    // Current Filter State harus dikelola oleh Riverpod, ini adalah tampilan statis
    const int currentFilter = 0;

    Widget buildFilterButton(int index, String label, Color color) {
      final isSelected = index == currentFilter;
      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: index < 2 ? 8.0 : 0),
          child: ElevatedButton(
            onPressed: () {
              // TODO: Ganti State Filter Riverpod
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isSelected ? AppTheme.gold : AppTheme.surface,
              foregroundColor:
                  isSelected ? AppTheme.background : AppTheme.foreground,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              side: isSelected
                  ? BorderSide.none
                  : const BorderSide(color: AppTheme.border, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (index > 0)
                  Icon(Icons.warning_amber_rounded, size: 18, color: color),
                if (index > 0) const SizedBox(width: 4),
                Text(label, style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        buildFilterButton(0, 'All Items', AppTheme.gold),
        buildFilterButton(1, 'Low Stock (2)', AppTheme.warning),
        buildFilterButton(2, 'Out of Stock (1)', AppTheme.destructive),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // Penting: Background harus diatur agar sticky header tidak transparan
      color: AppTheme.background,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Jumlah Item
          Padding(
            padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
            child: Text(
              '8 items',
              style: Theme.of(context).textTheme.titleSmall!.copyWith(
                    color: AppTheme.mutedForeground,
                  ),
            ),
          ),

          // Search Bar
          TextFormField(
            decoration: InputDecoration(
              hintText: 'Search by name or SKU...',
              prefixIcon:
                  const Icon(Icons.search, color: AppTheme.mutedForeground),
              fillColor: AppTheme.surface,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16.0),

          // Filter Bar
          _buildFilterBar(context),
          const SizedBox(height: 16.0),

          // Ringkasan Stok
          Column(
            children: [
              Row(
                children: [
                  _buildSummaryTile(context, 'Total Items', '8', AppTheme.gold),
                  const SizedBox(width: 12),
                  _buildSummaryTile(
                      context, 'Low Stock', '2', AppTheme.warning),
                  const SizedBox(width: 12),
                  _buildSummaryTile(
                      context, 'Out of Stock', '1', AppTheme.destructive),
                ],
              ),
              const SizedBox(height: 16),
              // Placeholder bar (20 in stock, $55.00)
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.7, // Contoh 70%
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.gold,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('20 in stock',
                        style: Theme.of(context).textTheme.bodySmall),
                    Text('\$55.00',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24.0), // Padding bawah sebelum daftar item
        ],
      ),
    );
  }
}
