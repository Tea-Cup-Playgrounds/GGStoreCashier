import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import 'role_guard.dart';

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

  static Future<bool> _checkRouteAccess(String route, User user) async {
    final routeAccess = {
      '/users': ['admin', 'superadmin'],
      '/branches': ['superadmin'],
      '/analytics': ['admin', 'superadmin'],
    };
    for (var entry in routeAccess.entries) {
      if (route.startsWith(entry.key)) {
        return RoleGuard.hasRole(user, entry.value);
      }
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
