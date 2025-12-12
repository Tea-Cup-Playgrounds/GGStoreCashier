import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/pos/presentation/pages/pos_page.dart';
import '../../features/inventory/presentation/pages/inventory_page.dart';
import '../../features/inventory/presentation/pages/inventory_detail_page.dart';
import '../../features/devices/presentation/pages/devices_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';

class AppRouter {
  static const String login = '/';
  static const String dashboard = '/dashboard';
  static const String pos = '/pos';
  static const String inventory = '/inventory';
  static const String inventoryDetail = '/inventory/:id';
  static const String devices = '/devices';
  static const String settings = '/settings';

  static final GoRouter router = GoRouter(
    initialLocation: login,
    routes: [
      GoRoute(
        path: login,
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: dashboard,
        name: 'dashboard',
        builder: (context, state) => const DashboardPage(),
      ),
      GoRoute(
        path: pos,
        name: 'pos',
        builder: (context, state) => const PosPage(),
      ),
      GoRoute(
        path: inventory,
        name: 'inventory',
        builder: (context, state) => const InventoryPage(),
      ),
      GoRoute(
        path: inventoryDetail,
        name: 'inventoryDetail',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return InventoryDetailPage(productId: id);
        },
      ),
      GoRoute(
        path: devices,
        name: 'devices',
        builder: (context, state) => const DevicesPage(),
      ),
      GoRoute(
        path: settings,
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
      ),
    ],
  );
}