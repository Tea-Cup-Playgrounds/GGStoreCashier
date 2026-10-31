import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../models/user.dart';

class AuthGuard {
  /// Redirect logic — local token check only, no network call.
  static Future<String?> redirectLogic(BuildContext context, GoRouterState state) async {
    final token = await AuthService.getToken();
    final isAuthenticated = token != null;
    final loc = state.matchedLocation;
    final isLoginRoute = loc == '/';

    if (!isAuthenticated && !isLoginRoute) return '/';
    if (isAuthenticated && isLoginRoute) return '/home';

    if (isAuthenticated && !isLoginRoute) {
      try {
        final user = await AuthService.getCurrentUser();
        if (user == null) {
          await AuthService.logout();
          return '/';
        }
        final hasAccess = await _checkRouteAccess(loc, user);
        if (!hasAccess) return '/home';
      } catch (e) {
        await AuthService.logout();
        return '/';
      }
    }

    return null;
  }

  // Pages that need a permission. The access stored with the user is used, so this works offline;
  // the API checks every request again.
  static const _routePermissions = {
    '/users': 'users.manage',
    '/vouchers': 'vouchers.manage',
  };

  static Future<bool> _checkRouteAccess(String route, User user) async {
    // /branch/edit/:id needs locations.manage at that location.
    final branchEdit = RegExp(r'^/branch/edit/(\d+)').firstMatch(route);
    if (branchEdit != null) return user.access.can('locations.manage', int.parse(branchEdit.group(1)!));
    for (final entry in _routePermissions.entries) {
      if (route.startsWith(entry.key)) return user.access.can(entry.value);
    }
    return true;
  }

  static Future<bool> validateSession() async {
    try {
      final isAuth = await AuthService.isAuthenticated();
      if (!isAuth) return false;
      final user = await AuthService.getCurrentUser();
      return user != null;
    } catch (e) {
      return false;
    }
  }
}
