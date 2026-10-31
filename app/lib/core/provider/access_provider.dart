import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/access.dart';
import '../models/catalog.dart';
import '../services/catalog_service.dart';
import 'auth_provider.dart';

/// The signed-in user's per-location permissions, refetched whenever the user changes.
final accessProvider = FutureProvider<UserAccess>((ref) async {
  final user = ref.watch(authProvider.select((s) => s.user?.id));
  if (user == null) return UserAccess.empty;
  return CatalogService.getAccess();
});

/// Locations the user may view stock for, warehouse first.
final stockLocationsProvider = FutureProvider<List<Location>>((ref) async {
  final access = await ref.watch(accessProvider.future);
  final locations = await CatalogService.getLocations();
  final visible = access.locationsFor('stock.view');
  return visible == null ? locations : locations.where((l) => visible.contains(l.id)).toList();
});
