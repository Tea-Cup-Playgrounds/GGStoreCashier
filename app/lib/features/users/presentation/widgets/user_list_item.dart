import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/helper/date_formatter.dart';
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
      default:
        return Colors.grey;
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
    return DateFormatter.format(dateString);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width > 768;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(isDesktop ? 24 : 20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: isDesktop
          ? _buildDesktopLayout(context, cs)
          : _buildMobileLayout(context, cs),
    );
  }

  Widget _buildDesktopLayout(BuildContext context, ColorScheme cs) {
    return Row(
      children: [
        _buildAvatar(context, 56, 28),
        const SizedBox(width: 20),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user['name']?.toString() ?? 'Unknown',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('@${user['username']?.toString() ?? 'unknown'}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withOpacity(0.6))),
            ],
          ),
        ),
        Expanded(child: _buildRoleBadge(context)),
        const SizedBox(width: 20),
        Expanded(
          child: Text(user['branch_name']?.toString() ?? 'No Branch',
              style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Text(
              _formatDate(user['created_at']?.toString() ?? ''),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withOpacity(0.6))),
        ),
        const SizedBox(width: 20),
        _buildActions(context, cs),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context, ColorScheme cs) {
    return Column(
      children: [
        Row(
          children: [
            _buildAvatar(context, 48, 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user['name']?.toString() ?? 'Unknown',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('@${user['username']?.toString() ?? 'unknown'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.6))),
                ],
              ),
            ),
            _buildRoleBadge(context),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cabang',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.5),
                          fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(user['branch_name']?.toString() ?? 'Tidak ada cabang',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dibuat',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.5),
                          fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(_formatDate(user['created_at']?.toString() ?? ''),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
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
            if (onEdit != null && onDelete != null) const SizedBox(width: 12),
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
                    color: cs.onSurface.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('View Only',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.5)),
                      textAlign: TextAlign.center),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAvatar(BuildContext context, double size, double radius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.gold.withOpacity(0.1),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppTheme.gold.withOpacity(0.2)),
      ),
      child: Center(
        child: Text(
          user['name']?.toString().substring(0, 1).toUpperCase() ?? 'U',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppTheme.gold, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildRoleBadge(BuildContext context) {
    final roleStr = user['role']?.toString() ?? '';
    final color = _getRoleColor(roleStr);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        _formatRole(roleStr),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color, fontWeight: FontWeight.w500, fontSize: 11),
      ),
    );
  }

  Widget _buildActions(BuildContext context, ColorScheme cs) {
    return Row(
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
        if (onEdit != null && onDelete != null) const SizedBox(width: 8),
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
              color: cs.onSurface.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('View Only',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.5))),
          ),
      ],
    );
  }
}
