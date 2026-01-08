import 'package:flutter/material.dart';
import 'package:gg_store_cashier/core/router/transition_factory.dart';
import 'package:gg_store_cashier/features/devices/presentation/pages/printer_devices_page.dart';
import 'package:gg_store_cashier/features/devices/presentation/pages/scanner_devices_page.dart';
import 'package:gg_store_cashier/features/inventory/presentation/pages/inventory_add_item_page.dart';
import 'package:gg_store_cashier/features/settings/presentation/pages/appearance_page.dart';
import 'package:gg_store_cashier/shared/layout/scaffold_with_bottom_navbar.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/cashier/presentation/pages/cashier_page.dart';
import '../../features/inventory/presentation/pages/inventory_page.dart';
import '../../features/inventory/presentation/pages/inventory_detail_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';

mixin AppRouter {
  static const String login = '/';
  static const String home = '/home';
  static const String cashier = '/cashier';
  static const String inventory = '/inventory';
  static const String inventoryDetail = '/inventory/detail/:id';
  static const String inventoryAddItem = '/inventory/add';
  static const String devices = '/devices';
  static const String apprearance = '/appearance';
  static const String scannerDevices = '/devices/scanner';
  static const String printerDevices = '/devices/printer';
  static const String settings = '/settings';

  static final _rootNavigatorkey = GlobalKey<NavigatorState>();
  static final homeNavKey = GlobalKey<NavigatorState>();
  static final cashierNavKey = GlobalKey<NavigatorState>();
  static final inventoryNavKey = GlobalKey<NavigatorState>();
  static final devicesNavKey = GlobalKey<NavigatorState>();
  static final settingsNavKey = GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorkey,
    initialLocation: login,
    routes: <RouteBase>[
      //  YG GK KENAK LAYOUT BOTTOM NAVBAR TARUH SINI ATAU DILUAR SHELL
      GoRoute(
        path: login,
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
          path: inventoryDetail,
          name: 'inventoryDetail',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return TransitionFactory.getSlideBuilder(
                context: context,
                state: state,
                child: InventoryDetailPage(productId: id));
          }),
      GoRoute(
        path: inventoryAddItem,
        name: 'inventoryAddItem',
        pageBuilder: (context, state) => TransitionFactory.getSlideBuilder(
            context: context,
            state: state,
            child: const InventoryAddItemPage()),
      ),
      GoRoute(
        path: apprearance,
        name: 'appearance',
        pageBuilder: (context, state) => TransitionFactory.getSlideBuilder(
            context: context,
            state: state,
            child: const AppearancePage()),
      ),
      GoRoute(
        path: scannerDevices,
        name: 'scannerDevices',
        pageBuilder: (context, state) => TransitionFactory.getSlideBuilder(
            context: context,
            state: state,
            child: const ScannerDevicesPage()),
      ),
      GoRoute(
        path: printerDevices,
        name: 'printerDevices',
        pageBuilder: (context, state) => TransitionFactory.getSlideBuilder(
            context: context,
            state: state,
            child: const PrinterDevicesPage()),
      ),
      // HALAMAN YANG BUTUH LAYOUT SCAFFOLD + BOTTOM NAV TARUH DI SINI
      StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return ScaffoldWithBottomNavbar(navigationShell);
          },
          branches: [
            StatefulShellBranch(navigatorKey: homeNavKey, routes: [
              GoRoute(
                path: home,
                name: 'home',
                builder: (context, state) => const HomePage(),
              ),
            ]),
            StatefulShellBranch(navigatorKey: cashierNavKey, routes: [
              GoRoute(
                path: cashier,
                name: 'cashier',
                builder: (context, state) => const CashierPage(),
              ),
            ]),
            StatefulShellBranch(navigatorKey: inventoryNavKey, routes: [
              GoRoute(
                path: inventory,
                name: 'inventory',
                builder: (context, state) => const InventoryPage(),
              ),
            ]),
            StatefulShellBranch(navigatorKey: settingsNavKey, routes: [
              GoRoute(
                path: settings,
                name: 'settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ]),
          ]),
    ],
  );
}
