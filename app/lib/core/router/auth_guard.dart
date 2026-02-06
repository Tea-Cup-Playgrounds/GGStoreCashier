import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../provider/auth_provider.dart';
import '../services/auth_service.dart';

class AuthGuard {
  static Future<String?> redirectLogic(BuildContext context, GoRouterState state) async {
    // Check if user is authenticated
    final isAuthenticated = await AuthService.isAuthenticated();
    
    final isLoginRoute = state.matchedLocation == '/';
    
    if (!isAuthenticated && !isLoginRoute) {
      // User is not authenticated and trying to access protected route
      return '/';
    }
    
    if (isAuthenticated && isLoginRoute) {
      // User is authenticated but on login page, redirect to home
      return '/home';
    }
    
    // No redirect needed
    return null;
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