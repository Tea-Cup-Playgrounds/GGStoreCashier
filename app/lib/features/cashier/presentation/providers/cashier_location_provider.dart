import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/provider/auth_provider.dart';

/// Locations where the signed-in user may sell.
final salesLocationsProvider = FutureProvider<List<Location>>((ref) async {
  final access = await ref.watch(accessProvider.future);
  final locations = await ref.watch(stockLocationsProvider.future);
  return locations.where((l) => access.can('sales.create', l.id)).toList();
});

final selectedCashierLocationProvider = StateProvider<int?>((ref) => null);

/// The location the cashier sells from: the picked one, else the user's default location, else the
/// first branch they may sell at.
final cashierLocationProvider = Provider<Location?>((ref) {
  final locations = ref.watch(salesLocationsProvider).valueOrNull ?? const [];
  if (locations.isEmpty) return null;
  final picked = ref.watch(selectedCashierLocationProvider);
  final own = ref.watch(authProvider.select((s) => s.user?.defaultLocationId));
  for (final id in [picked, own]) {
    final match = locations.where((l) => l.id == id);
    if (match.isNotEmpty) return match.first;
  }
  final branches = locations.where((l) => !l.isWarehouse);
  return branches.isNotEmpty ? branches.first : locations.first;
});
