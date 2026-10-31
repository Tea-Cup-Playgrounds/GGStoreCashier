import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/access.dart';
import '../models/catalog.dart';
import '../services/auth_service.dart';
import '../services/catalog_service.dart';
import 'auth_provider.dart';

/// The signed-in user's per-location permissions, refetched whenever the user changes. A fresh copy
/// is stored with the user; when the server can't be reached the stored copy (from login or the last
/// refresh) is used, so offline selling still knows where the user may sell.
final accessProvider = FutureProvider<UserAccess>((ref) async {
  final user = ref.watch(authProvider.select((s) => s.user?.id));
  if (user == null) return UserAccess.empty;
  try {
    final access = await CatalogService.getAccess();
    await AuthService.updateStoredAccess(access);
    return access;
  } catch (_) {
    final stored = (await AuthService.getCurrentUser())?.access;
    if (stored != null && (stored.isOwner || stored.assignments.isNotEmpty)) return stored;
    rethrow;
  }
});

/// Access for deciding what the UI shows: the latest fetched copy, else the one stored at login.
final currentAccessProvider = Provider<UserAccess>((ref) {
  return ref.watch(accessProvider).valueOrNull ?? ref.watch(authProvider.select((s) => s.user?.access)) ?? UserAccess.empty;
});

/// Locations the user may view stock for, warehouse first.
final stockLocationsProvider = FutureProvider<List<Location>>((ref) async {
  final access = await ref.watch(accessProvider.future);
  final locations = await CatalogService.getLocations();
  final visible = access.locationsFor('stock.view');
  return visible == null ? locations : locations.where((l) => visible.contains(l.id)).toList();
});
