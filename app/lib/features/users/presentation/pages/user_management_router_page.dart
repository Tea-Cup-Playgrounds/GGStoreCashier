import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/provider/auth_provider.dart';
import '../../../../core/router/role_guard.dart';
import 'superadmin_user_management_page.dart';
import 'admin_user_management_page.dart';

/// Router page that directs to the appropriate user management page based on role
class UserManagementRouterPage extends ConsumerWidget {
  const UserManagementRouterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    // Route based on user role
    if (RoleGuard.isSuperAdmin(user)) {
      return const SuperAdminUserManagementPage();
    } else if (RoleGuard.isAdmin(user)) {
      return const AdminUserManagementPage();
    }

    // Default: Access denied
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.lock_outline,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              'Access Denied',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'You do not have permission to manage users',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
