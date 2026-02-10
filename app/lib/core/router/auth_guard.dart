import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../provider/auth_provider.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import 'role_guard.dart';

class AuthGuard {
  /// Main redirect logic with session validation
  static Future<String?> redirectLogic(BuildContext context, GoRouterState state) async {
    // Check if user is authenticated
    final isAuthenticated = await AuthService.isAuthenticated();
    
    final isLoginRoute = state.matchedLocation == '/';
    
    if (!isAuthenticated && !isLoginRoute) {
      // User is not authenticated and trying to access protected route
      // Clear any stale session data
      await AuthService.logout();
      return '/';
    }
    
    if (isAuthenticated && isLoginRoute) {
      // User is authenticated but on login page, redirect to home
      return '/home';
    }
    
    // Validate session and check role-based access
    if (isAuthenticated && !isLoginRoute) {
      try {
        final user = await AuthService.getCurrentUser();
        
        // Validate user session is still valid
        if (user == null) {
          await AuthService.logout();
          return '/';
        }
        
        // Check role-based access for specific routes
        final hasAccess = await _checkRouteAccess(state.matchedLocation, user);
        if (!hasAccess) {
          // Redirect to home if user doesn't have access
          return '/home';
        }
      } catch (e) {
        // Session validation failed, logout and redirect to login
        await AuthService.logout();
        return '/';
      }
    }
    
    // No redirect needed
    return null;
  }

  /// Check if user has access to specific route based on role
  static Future<bool> _checkRouteAccess(String route, User user) async {
    // Define role-based route access
    final Map<String, List<String>> routeAccess = {
      '/users': ['admin', 'superadmin'],
      '/branches': ['superadmin'],
      '/analytics': ['admin', 'superadmin'],
    };

    // Check if route requires specific roles
    for (var entry in routeAccess.entries) {
      if (route.startsWith(entry.key)) {
        return RoleGuard.hasRole(user, entry.value);
      }
    }

    // Default: allow access
    return true;
  }

  /// Validate session periodically
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

// Widget to show loading while checking auth status
class AuthLoadingWidget extends ConsumerWidget {
  const AuthLoadingWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}