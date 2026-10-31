import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import '../providers/inventory_location_provider.dart';

/// Horizontal chips for picking which branch / warehouse the inventory shows.
class LocationSelector extends ConsumerWidget {
  const LocationSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final locations = ref.watch(stockLocationsProvider).valueOrNull ?? const [];
    final current = ref.watch(effectiveInventoryLocationProvider);

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: locations.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final location = locations[i];
          final selected = location.id == current?.id;
          return ChoiceChip(
            avatar: Icon(location.isWarehouse ? Icons.warehouse_outlined : Icons.storefront_outlined,
                size: 16, color: selected ? AppTheme.gold : cs.onSurfaceVariant),
            label: Text(location.label),
            selected: selected,
            showCheckmark: false,
            selectedColor: AppTheme.gold.withValues(alpha: 0.15),
            side: BorderSide(color: selected ? AppTheme.gold : cs.outlineVariant),
            labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected ? AppTheme.gold : cs.onSurface,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
            onSelected: (_) => ref.read(selectedInventoryLocationProvider.notifier).state = location.id,
          );
        },
      ),
    );
  }
}
