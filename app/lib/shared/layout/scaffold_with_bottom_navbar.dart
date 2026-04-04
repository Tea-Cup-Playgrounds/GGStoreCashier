import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/services/connectivity_monitor.dart';
import 'package:gg_store_cashier/core/services/notification_service.dart';
import 'package:gg_store_cashier/core/services/sync_service.dart';
import 'package:gg_store_cashier/shared/widgets/bottom_navigation.dart';
import 'package:gg_store_cashier/shared/widgets/connectivity_banner.dart';
import 'package:go_router/go_router.dart';

class ScaffoldWithBottomNavbar extends ConsumerStatefulWidget {
  const ScaffoldWithBottomNavbar(this.navigationShell, {super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<ScaffoldWithBottomNavbar> createState() =>
      _ScaffoldWithBottomNavbarState();
}

class _ScaffoldWithBottomNavbarState
    extends ConsumerState<ScaffoldWithBottomNavbar> {
  ProviderSubscription<AsyncValue<ConnectivityStatus>>? _connectivitySub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _connectivitySub ??= ref.listenManual(connectivityProvider, (previous, next) {
      final prev = previous?.valueOrNull;
      final curr = next.valueOrNull;

      // Only react to genuine transitions (prev must be known and different).
      // This prevents the initial online emission from triggering sync/notifications.
      if (prev == null || prev == curr) return;

      if (curr == ConnectivityStatus.online) {
        SyncService.syncAll();
        NotificationService.showOnlineNotification();
      } else if (curr == ConnectivityStatus.offline) {
        NotificationService.showOfflineNotification();
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const ConnectivityBanner(),
          Expanded(child: widget.navigationShell),
        ],
      ),
      bottomNavigationBar: BottomNavigation(widget.navigationShell),
    );
  }
}
