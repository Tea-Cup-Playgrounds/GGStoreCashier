import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/provider/auth_provider.dart';

/// The location the inventory screens show stock for. null until the user picks one; use
/// [effectiveInventoryLocationProvider] to read it with the default applied.
final selectedInventoryLocationProvider = StateProvider<int?>((ref) => null);

/// Selected location, defaulting to the user's own branch, then the first visible location.
final effectiveInventoryLocationProvider = Provider<Location?>((ref) {
  final locations = ref.watch(stockLocationsProvider).valueOrNull ?? const [];
  if (locations.isEmpty) return null;
  final selected = ref.watch(selectedInventoryLocationProvider);
  final ownBranch = ref.watch(authProvider.select((s) => s.user?.branchId));
  for (final id in [selected, ownBranch]) {
    if (id == null) continue;
    final match = locations.where((l) => l.id == id);
    if (match.isNotEmpty) return match.first;
  }
  return locations.first;
});
