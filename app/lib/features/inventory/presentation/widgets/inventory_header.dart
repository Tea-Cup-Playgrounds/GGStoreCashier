import 'package:flutter/material.dart';
import 'package:gg_store_cashier/features/inventory/domain/inventory_filter.dart';
import '../../../../core/models/product.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_search_bar.dart';

class InventoryHeader extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final InventoryFilter currentFilter;
  final ValueChanged<InventoryFilter> onFilterChanged;
  final int totalItems;
  final int lowStockItems;
  final int outOfStockItems;

  const InventoryHeader({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.currentFilter,
    required this.onFilterChanged,
    this.totalItems = 0,
    this.lowStockItems = 0,
    this.outOfStockItems = 0,
  });

  Widget _buildSummaryTile(
    BuildContext context,
    String title,
    String value,
    Color color,
    IconData icon,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? cs.surfaceContainerHighest : cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant, width: 0.8),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget buildChip(InventoryFilter filter, String label) {
      final isSelected = filter == currentFilter;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.gold.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isSelected ? AppTheme.gold : cs.outlineVariant,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            onTap: isSelected ? null : () => onFilterChanged(filter),
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected ? AppTheme.gold : cs.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          buildChip(InventoryFilter.all, 'Semua'),
          buildChip(InventoryFilter.low, 'Stok Tipis'),
          buildChip(InventoryFilter.out, 'Habis'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomSearchBar(
            controller: searchController,
            hintText: 'Cari produk berdasarkan nama atau SKU...',
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: 12),
          _buildFilterBar(context),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildSummaryTile(
                context,
                'Total Produk',
                '$totalItems',
                AppTheme.gold,
                Icons.inventory_2_outlined,
              ),
              const SizedBox(width: 8),
              _buildSummaryTile(
                context,
                'Stok Tipis',
                '$lowStockItems',
                AppTheme.warning,
                Icons.warning_amber_rounded,
              ),
              const SizedBox(width: 8),
              _buildSummaryTile(
                context,
                'Habis',
                '$outOfStockItems',
                AppTheme.destructive,
                Icons.remove_shopping_cart_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
