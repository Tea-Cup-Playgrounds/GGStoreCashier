import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_button.dart';

class UserListItem extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool isSuperAdmin;

  const UserListItem({
    super.key,
    required this.user,
    this.onEdit,
    this.onDelete,
    this.isSuperAdmin = false,
  });

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'superadmin':
        return AppTheme.gold;
      case 'admin':
        return AppTheme.success;
      case 'karyawan':
        return AppTheme.mutedForeground;
      default:
        return AppTheme.mutedForeground;
    }
  }

  String _formatRole(String role) {
    switch (role.toLowerCase()) {
      case 'superadmin':
        return 'Super Admin';
      case 'admin':
        return 'Admin';
      case 'karyawan':
        return 'Karyawan';
      default:
        return role;
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 768;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(isDesktop ? 24 : 20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: isDesktop ? _buildDesktopLayout(context) : _buildMobileLayout(context),
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Row(
      children: [
        // Avatar
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppTheme.gold.withOpacity(0.1),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppTheme.gold.withOpacity(0.2)),
          ),
          child: Center(
            child: Text(
              user['name']?.toString().substring(0, 1).toUpperCase() ?? 'U',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppTheme.gold,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 20),
        // User Info
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user['name']?.toString() ?? 'Unknown',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppTheme.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '@${user['username']?.toString() ?? 'unknown'}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        // Role
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _getRoleColor(user['role']?.toString() ?? '').withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _getRoleColor(user['role']?.toString() ?? '').withOpacity(0.3),
              ),
            ),
            child: Text(
              _formatRole(user['role']?.toString() ?? ''),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _getRoleColor(user['role']?.toString() ?? ''),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(width: 20),
        // Branch
        Expanded(
          child: Text(
            user['branch_name']?.toString() ?? 'No Branch',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.foreground,
            ),
          ),
        ),
        const SizedBox(width: 20),
        // Created Date
        Expanded(
          child: Text(
            _formatDate(user['created_at']?.toString() ?? ''),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.mutedForeground,
            ),
          ),
        ),
        const SizedBox(width: 20),
        // Actions
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null)
              CustomButton(
                text: 'Edit',
                icon: Icons.edit,
                size: ButtonSize.small,
                variant: ButtonVariant.outline,
                onPressed: onEdit!,
              ),
            if (onEdit != null && onDelete != null)
              const SizedBox(width: 8),
            if (onDelete != null)
              CustomButton(
                text: 'Delete',
                icon: Icons.delete,
                size: ButtonSize.small,
                variant: ButtonVariant.outline,
                onPressed: onDelete!,
              ),
            if (onEdit == null && onDelete == null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.mutedForeground.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'View Only',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.mutedForeground,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.gold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.gold.withOpacity(0.2)),
              ),
              child: Center(
                child: Text(
                  user['name']?.toString().substring(0, 1).toUpperCase() ?? 'U',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppTheme.gold,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // User Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user['name']?.toString() ?? 'Unknown',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppTheme.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${user['username']?.toString() ?? 'unknown'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            // Role Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _getRoleColor(user['role']?.toString() ?? '').withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _getRoleColor(user['role']?.toString() ?? '').withOpacity(0.3),
                ),
              ),
              child: Text(
                _formatRole(user['role']?.toString() ?? ''),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _getRoleColor(user['role']?.toString() ?? ''),
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Additional Info
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cabang',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mutedForeground,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user['branch_name']?.toString() ?? 'Tidak ada cabang',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.foreground,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dibuat',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mutedForeground,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDate(user['created_at']?.toString() ?? ''),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.foreground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Actions
        Row(
          children: [
            if (onEdit != null)
              Expanded(
                child: CustomButton(
                  text: 'Edit',
                  icon: Icons.edit,
                  size: ButtonSize.small,
                  variant: ButtonVariant.outline,
                  fullWidth: true,
                  onPressed: onEdit!,
                ),
              ),
            if (onEdit != null && onDelete != null)
              const SizedBox(width: 12),
            if (onDelete != null)
              Expanded(
                child: CustomButton(
                  text: 'Delete',
                  icon: Icons.delete,
                  size: ButtonSize.small,
                  variant: ButtonVariant.outline,
                  fullWidth: true,
                  onPressed: onDelete!,
                ),
              ),
            if (onEdit == null && onDelete == null)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.mutedForeground.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'View Only',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mutedForeground,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}