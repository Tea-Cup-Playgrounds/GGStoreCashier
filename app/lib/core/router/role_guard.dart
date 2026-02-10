import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../provider/auth_provider.dart';
import '../models/user.dart';

/// Role-based access control guard
/// Checks if the current user has permission to access specific features
class RoleGuard {
  /// Check if user has required role
  static bool hasRole(User? user, List<String> allowedRoles) {
    if (user == null) return false;
    return allowedRoles.contains(user.role);
  }

  /// Check if user is SuperAdmin
  static bool isSuperAdmin(User? user) {
    return user?.role == 'superadmin';
  }

  /// Check if user is Admin
  static bool isAdmin(User? user) {
    return user?.role == 'admin';
  }

  /// Check if user is Admin or SuperAdmin
  static bool isAdminOrAbove(User? user) {
    return user?.role == 'admin' || user?.role == 'superadmin';
  }

  /// Check if user is Employee (karyawan)
  static bool isEmployee(User? user) {
    return user?.role == 'karyawan';
  }

  /// Check if user can manage all branches (SuperAdmin only)
  static bool canManageAllBranches(User? user) {
    return user?.role == 'superadmin';
  }

  /// Check if user can manage their assigned branch (Admin)
  static bool canManageOwnBranch(User? user) {
    return user?.role == 'admin' && user?.branchId != null && user?.branchId != 0;
  }

  /// Check if user can manage users
  static bool canManageUsers(User? user) {
    return user?.role == 'admin' || user?.role == 'superadmin';
  }

  /// Check if user can manage branches (SuperAdmin only)
  static bool canManageBranches(User? user) {
    return user?.role == 'superadmin';
  }

  /// Check if user can access cashier features
  static bool canAccessCashier(User? user) {
    // All roles can access cashier
    return user != null;
  }

  /// Check if user can view analytics dashboard
  static bool canViewAnalytics(User? user) {
    return user?.role == 'admin' || user?.role == 'superadmin';
  }

  /// Check if user can manage stock
  static bool canManageStock(User? user) {
    return user?.role == 'admin' || user?.role == 'superadmin';
  }

  /// Check if user can view stock (read-only for employees)
  static bool canViewStock(User? user) {
    return user != null;
  }

  /// Check if user can transfer stock between branches
  static bool canTransferStock(User? user) {
    return user?.role == 'admin' || user?.role == 'superadmin';
  }

  /// Get accessible branch IDs for user
  static List<int> getAccessibleBranches(User? user) {
    if (user == null) return [];
    
    if (user.role == 'superadmin') {
      // SuperAdmin can access all branches (0 means all)
      return [0];
    } else if (user.role == 'admin' && user.branchId != null) {
      // Admin can only access their assigned branch
      return [user.branchId!];
    } else if (user.role == 'karyawan' && user.branchId != null) {
      // Employee can only view their assigned branch
      return [user.branchId!];
    }
    
    return [];
  }

  /// Check if user can access specific branch
  static bool canAccessBranch(User? user, int branchId) {
    if (user == null) return false;
    
    if (user.role == 'superadmin') {
      return true; // SuperAdmin can access all branches
    }
    
    return user.branchId == branchId;
  }
}

/// Widget wrapper for role-based access control
class RoleBasedWidget extends ConsumerWidget {
  final List<String> allowedRoles;
  final Widget child;
  final Widget? fallback;

  const RoleBasedWidget({
    super.key,
    required this.allowedRoles,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    if (RoleGuard.hasRole(user, allowedRoles)) {
      return child;
    }

    return fallback ?? const SizedBox.shrink();
  }
}

/// Page wrapper with role-based access control
class RoleProtectedPage extends ConsumerWidget {
  final List<String> allowedRoles;
  final Widget child;
  final String? deniedMessage;

  const RoleProtectedPage({
    super.key,
    required this.allowedRoles,
    required this.child,
    this.deniedMessage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    if (RoleGuard.hasRole(user, allowedRoles)) {
      return child;
    }

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
              deniedMessage ?? 'You do not have permission to access this page',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
