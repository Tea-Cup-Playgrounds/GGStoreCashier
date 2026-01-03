import 'package:flutter/material.dart';
import 'package:gg_store_cashier/features/inventory/domain/inventory_filter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_search_bar.dart';

class InventoryHeader extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  final InventoryFilter currentFilter;
  final ValueChanged<InventoryFilter> onFilterChanged;

  const InventoryHeader({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.currentFilter,
    required this.onFilterChanged,
  });

  Widget _buildSummaryTile(
    BuildContext context,
    String title,
    String value,
    Color iconColor,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
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
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  value,
                  style: Theme.of(context)
                      .textTheme
                      .headlineLarge
                      ?.copyWith(color: iconColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }

  // =============================
  // Filter Bar
  // =============================
  Widget _buildFilterBar(BuildContext context) {
    Widget buildButton(
      InventoryFilter filter,
      String label,
    ) {
      final bool isSelected = filter == currentFilter;

      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 110),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color:
                  isSelected ? AppTheme.card : Colors.transparent, // ✨ tambahan
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isSelected ? AppTheme.foreground : AppTheme.border,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: OutlinedButton(
              onPressed: isSelected
                  ? null
                  : () {
                      onFilterChanged(filter);
                    },
              style: OutlinedButton.styleFrom(
                side: BorderSide.none,
                backgroundColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                shape: const StadiumBorder(),
              ),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                style: Theme.of(context).textTheme.labelLarge!.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected
                          ? AppTheme.foreground
                          : AppTheme.mutedForeground,
                    ),
                child: Text(label),
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          buildButton(InventoryFilter.all, 'All Items'),
          buildButton(InventoryFilter.low, 'Low Stock'),
          buildButton(InventoryFilter.out, 'Out of Stock'),
          buildButton(InventoryFilter.other1, 'Something'),
          buildButton(InventoryFilter.other2, 'Something'),
        ],
      ),
    );
  }

  // =============================
  // BUILD
  // =============================
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            child: Text(
              '8 items',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: AppTheme.mutedForeground),
            ),
          ),

          CustomSearchBar(
            controller: searchController,
            hintText: 'Cari items berdasarkan nama atau sku..',
            onChanged: onSearchChanged,
          ),

          const SizedBox(height: 16),

          _buildFilterBar(context),

          const SizedBox(height: 16),
          Row(
            children: [
              _buildSummaryTile(context, 'Total Items', '8', AppTheme.gold),
              const SizedBox(width: 12),
              _buildSummaryTile(context, 'Low Stock', '2', AppTheme.warning),
              const SizedBox(width: 12),
              _buildSummaryTile(
                  context, 'Out of Stock', '1', AppTheme.destructive),
            ],
          ),
          // summary & lainnya (tidak diubah)
        ],
      ),
    );
  }
}
