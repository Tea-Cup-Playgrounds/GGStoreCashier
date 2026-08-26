import 'package:flutter/material.dart';
import 'package:gg_store_cashier/features/inventory/domain/inventory_filter.dart';
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

  // Category filter
  final List<String> categories;
  final String? selectedCategory;
  final ValueChanged<String?> onCategoryChanged;

  const InventoryHeader({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.currentFilter,
    required this.onFilterChanged,
    this.totalItems = 0,
    this.lowStockItems = 0,
    this.outOfStockItems = 0,
    this.categories = const [],
    this.selectedCategory,
    required this.onCategoryChanged,
  });

  Widget _buildSummaryTile(
    BuildContext context, {
    required InventoryFilter filter,
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final isSelected = currentFilter == filter;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onFilterChanged(filter),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.12) : (isDark ? cs.surfaceContainerHighest : cs.surface),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : cs.outlineVariant,
              width: isSelected ? 2 : 0.8,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.20),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : (isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]),
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
          // ── Search + category filter row ──────────────────────────
          Row(
            children: [
              Expanded(
                child: CustomSearchBar(
                  controller: searchController,
                  hintText: 'Cari produk berdasarkan nama atau SKU...',
                  onChanged: onSearchChanged,
                ),
              ),
              if (categories.isNotEmpty) ...[
                const SizedBox(width: 10),
                _CategoryDropdown(
                  categories: categories,
                  selected: selectedCategory,
                  onChanged: onCategoryChanged,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // ── Summary tiles (also act as stock filter) ──────────────
          Row(
            children: [
              _buildSummaryTile(
                context,
                filter: InventoryFilter.all,
                title: 'Total Produk',
                value: '$totalItems',
                color: AppTheme.gold,
                icon: Icons.inventory_2_outlined,
              ),
              const SizedBox(width: 8),
              _buildSummaryTile(
                context,
                filter: InventoryFilter.low,
                title: 'Stok Tipis',
                value: '$lowStockItems',
                color: AppTheme.warning,
                icon: Icons.warning_amber_rounded,
              ),
              const SizedBox(width: 8),
              _buildSummaryTile(
                context,
                filter: InventoryFilter.out,
                title: 'Habis',
                value: '$outOfStockItems',
                color: AppTheme.destructive,
                icon: Icons.remove_shopping_cart_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Category dropdown ─────────────────────────────────────────────────────────

class _CategoryDropdown extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _CategoryDropdown({
    required this.categories,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isActive = selected != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isActive ? AppTheme.gold.withValues(alpha: 0.10) : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? AppTheme.gold : cs.outlineVariant,
          width: isActive ? 1.5 : 0.8,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: selected,
          isDense: true,
          dropdownColor: cs.surface,
          borderRadius: BorderRadius.circular(12),
          icon: Icon(
            Icons.category_outlined,
            size: 18,
            color: isActive ? AppTheme.gold : cs.onSurfaceVariant,
          ),
          hint: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.category_outlined, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                'Kategori',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isActive ? AppTheme.gold : cs.onSurface,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
          items: [
            // "All categories" option
            DropdownMenuItem<String?>(
              value: null,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Text('Semua Kategori', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface)),
                ],
              ),
            ),
            ...categories.map(
              (cat) => DropdownMenuItem<String?>(
                value: cat,
                child: Text(
                  cat,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface,
                      ),
                ),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
