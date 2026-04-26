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
  final List<Product> products;
  final bool isLandscape;

  const InventoryHeader({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.currentFilter,
    required this.onFilterChanged,
    required this.products,
    this.isLandscape = false,
  });

  Widget _buildSummaryTile(
    BuildContext context,
    String title,
    String value,
    Color iconColor,
  ) {
    final cardPadding = isLandscape ? 8.0 : 16.0;
    final iconSize = isLandscape ? 16.0 : 22.0;
    final valueStyle = isLandscape
        ? Theme.of(context).textTheme.titleLarge?.copyWith(color: iconColor)
        : Theme.of(context).textTheme.headlineLarge?.copyWith(color: iconColor);
    final labelStyle = isLandscape
        ? Theme.of(context).textTheme.labelSmall
        : Theme.of(context).textTheme.bodySmall;

    return Expanded(
      child: Container(
        padding: EdgeInsets.all(cardPadding),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondary,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  title.contains('Total')
                      ? Icons.archive_outlined
                      : Icons.warning_amber_rounded,
                  color: iconColor,
                  size: iconSize,
                ),
                const SizedBox(width: 6),
                Text(value, style: valueStyle),
              ],
            ),
            if (!isLandscape) const SizedBox(height: 6),
            Text(title, style: labelStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    final btnPadding = isLandscape
        ? const EdgeInsets.symmetric(vertical: 6, horizontal: 12)
        : const EdgeInsets.symmetric(vertical: 12, horizontal: 16);
    final minWidth = isLandscape ? 80.0 : 110.0;

    Widget buildButton(InventoryFilter filter, String label) {
      final bool isSelected = filter == currentFilter;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.surface
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.outlineVariant,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: OutlinedButton(
              onPressed: isSelected ? null : () => onFilterChanged(filter),
              style: OutlinedButton.styleFrom(
                side: BorderSide.none,
                backgroundColor: Colors.transparent,
                padding: btnPadding,
                shape: const StadiumBorder(),
              ),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                style: (isLandscape
                        ? Theme.of(context).textTheme.labelSmall
                        : Theme.of(context).textTheme.labelLarge)!
                    .copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.outlineVariant,
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
          buildButton(InventoryFilter.all, 'Semua'),
          buildButton(InventoryFilter.low, 'Stok Rendah'),
          buildButton(InventoryFilter.out, 'Habis'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalItems = products.length;
    final lowStock = products.where((p) => p.isLowStock && !p.isOutOfStock).length;
    final outOfStock = products.where((p) => p.isOutOfStock).length;

    final topPadding = isLandscape ? 4.0 : 8.0;
    final bottomPadding = isLandscape ? 6.0 : 16.0;
    final sectionGap = isLandscape ? 6.0 : 16.0;

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
            child: Text(
              '$totalItems produk',
              style: (isLandscape
                      ? Theme.of(context).textTheme.labelSmall
                      : Theme.of(context).textTheme.titleSmall)
                  ?.copyWith(color: AppTheme.mutedForeground),
            ),
          ),

          CustomSearchBar(
            controller: searchController,
            hintText: 'Cari items berdasarkan nama atau sku..',
            onChanged: onSearchChanged,
          ),

          SizedBox(height: sectionGap),
          _buildFilterBar(context),
          SizedBox(height: sectionGap),

          Row(
            children: [
              _buildSummaryTile(context, 'Total Item', '$totalItems', AppTheme.gold),
              const SizedBox(width: 8),
              _buildSummaryTile(context, 'Stok Rendah', '$lowStock', AppTheme.warning),
              const SizedBox(width: 8),
              _buildSummaryTile(context, 'Habis', '$outOfStock', AppTheme.destructive),
            ],
          ),
        ],
      ),
    );
  }
}
