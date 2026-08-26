import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/services/connectivity_monitor.dart';
import 'package:gg_store_cashier/core/services/notification_service.dart';
import 'package:gg_store_cashier/core/services/offline_queue.dart';
import 'package:gg_store_cashier/core/services/sync_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/shared/widgets/connectivity_banner.dart';
import 'package:go_router/go_router.dart';

class ScaffoldWithBottomNavbar extends ConsumerStatefulWidget {
  const ScaffoldWithBottomNavbar(this.navigationShell, {super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<ScaffoldWithBottomNavbar> createState() => _ScaffoldWithBottomNavbarState();
}

class _ScaffoldWithBottomNavbarState extends ConsumerState<ScaffoldWithBottomNavbar> {
  ProviderSubscription<AsyncValue<ConnectivityStatus>>? _connectivitySub;

  // "Press again to exit" guard
  DateTime? _lastBackPress;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ConnectivityMonitor.instance.start();
    _connectivitySub ??= ref.listenManual(connectivityProvider, (previous, next) {
      final prev = previous?.valueOrNull;
      final curr = next.valueOrNull;
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

  void _onTap(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  /// Called by [PopScope] before the system back is processed.
  /// Returns false (block pop) to handle navigation ourselves.
  Future<bool> _onBackPressed() async {
    final currentIndex = widget.navigationShell.currentIndex;

    // If not on tab 0, go home instead of exiting.
    if (currentIndex != 0) {
      _onTap(0);
      return false;
    }

    // On tab 0 — double-tap to exit.
    final now = DateTime.now();
    if (_lastBackPress == null || now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Tekan sekali lagi untuk keluar'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          backgroundColor: AppTheme.surfaceElevated,
        ),
      );
      return false; // don't exit yet
    }

    // Second tap within 2 s → exit
    await SystemNavigator.pop();
    return false; // let SystemNavigator handle it
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _onBackPressed();
      },
      child: isLandscape
          ? _LandscapeLayout(navigationShell: widget.navigationShell, onTap: _onTap)
          : _PortraitLayout(navigationShell: widget.navigationShell, onTap: _onTap),
    );
  }
}

// ── Portrait: original bottom nav layout ─────────────────────────────────────

class _PortraitLayout extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  final ValueChanged<int> onTap;

  const _PortraitLayout({
    required this.navigationShell,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingCount = ref.watch(pendingOfflineCountProvider).valueOrNull ?? 0;
    final cs = Theme.of(context).colorScheme;
    final currentIndex = navigationShell.currentIndex;

    return Scaffold(
      body: Column(
        children: [
          const ConnectivityBanner(),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(
            top: BorderSide(color: cs.outlineVariant, width: 1.2),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 80,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _navItems(pendingCount).asMap().entries.map((e) {
                final i = e.key;
                final item = e.value;
                return _BottomNavItem(
                  icon: item.icon,
                  activeIcon: item.activeIcon,
                  label: item.label,
                  isActive: currentIndex == i,
                  badgeCount: item.badge,
                  onTap: () => onTap(i),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Landscape: side rail layout ───────────────────────────────────────────────

class _LandscapeLayout extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  final ValueChanged<int> onTap;

  const _LandscapeLayout({
    required this.navigationShell,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingCount = ref.watch(pendingOfflineCountProvider).valueOrNull ?? 0;
    final cs = Theme.of(context).colorScheme;
    final currentIndex = navigationShell.currentIndex;
    final items = _navItems(pendingCount);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ConnectivityBanner(),
            Expanded(
              child: Row(
                children: [
                  // Side navigation rail
                  Container(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      border: Border(
                        right: BorderSide(color: cs.outlineVariant, width: 1.2),
                      ),
                    ),
                    child: NavigationRail(
                      selectedIndex: currentIndex,
                      onDestinationSelected: onTap,
                      backgroundColor: cs.surface,
                      labelType: NavigationRailLabelType.all,
                      selectedIconTheme: const IconThemeData(color: AppTheme.gold, size: 22),
                      unselectedIconTheme: IconThemeData(color: cs.onSurface.withValues(alpha: 0.55), size: 22),
                      selectedLabelTextStyle: const TextStyle(
                        color: AppTheme.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      unselectedLabelTextStyle: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.55),
                        fontSize: 11,
                      ),
                      indicatorColor: AppTheme.gold.withValues(alpha: 0.12),
                      destinations: items.map((item) {
                        return NavigationRailDestination(
                          icon: item.badge > 0
                              ? Badge(
                                  label: Text('${item.badge}'),
                                  child: Icon(item.icon),
                                )
                              : Icon(item.icon),
                          selectedIcon: item.badge > 0
                              ? Badge(
                                  label: Text('${item.badge}'),
                                  child: Icon(item.activeIcon),
                                )
                              : Icon(item.activeIcon),
                          label: Text(item.label),
                        );
                      }).toList(),
                    ),
                  ),
                  // Page content
                  Expanded(child: navigationShell),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared nav item data ──────────────────────────────────────────────────────

class _NavItemData {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int badge;
  const _NavItemData(this.icon, this.activeIcon, this.label, {this.badge = 0});
}

List<_NavItemData> _navItems(int pendingCount) => [
      const _NavItemData(Icons.home_outlined, Icons.home, 'Beranda'),
      _NavItemData(Icons.shopping_cart_outlined, Icons.shopping_cart, 'Kasir', badge: pendingCount),
      const _NavItemData(Icons.inventory_2_outlined, Icons.inventory_2, 'Inventori'),
      const _NavItemData(Icons.settings_outlined, Icons.settings, 'Pengaturan'),
    ];

// ── Portrait bottom nav item widget ──────────────────────────────────────────

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final int badgeCount;

  const _BottomNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.gold.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    isActive ? activeIcon : icon,
                    key: ValueKey(isActive),
                    color: isActive
                        ? Theme.of(context).bottomNavigationBarTheme.selectedItemColor
                        : Theme.of(context).bottomNavigationBarTheme.unselectedItemColor,
                    size: 20,
                  ),
                ),
                if (badgeCount > 0)
                  Positioned(
                    top: -4,
                    right: -6,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badgeCount > 99 ? '99+' : '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive
                    ? Theme.of(context).bottomNavigationBarTheme.selectedItemColor
                    : Theme.of(context).bottomNavigationBarTheme.unselectedItemColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
