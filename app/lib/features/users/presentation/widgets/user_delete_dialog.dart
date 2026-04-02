import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../shared/utils/snackbar_service.dart';
import '../providers/user_management_provider.dart';

class UserDeleteDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> user;

  const UserDeleteDialog({super.key, required this.user});

  @override
  ConsumerState<UserDeleteDialog> createState() => _UserDeleteDialogState();
}

class _UserDeleteDialogState extends ConsumerState<UserDeleteDialog> {
  bool _isLoading = false;

  Future<void> _handleDelete() async {
    setState(() => _isLoading = true);
    try {
      await ref
          .read(userManagementProvider.notifier)
          .deleteUser(widget.user['id']);
      if (mounted) {
        SnackBarService.success('User deleted successfully');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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
        return 'Employee';
      default:
        return role;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final roleStr = widget.user['role']?.toString() ?? '';
    final roleColor = _getRoleColor(roleStr);

    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.destructive.withOpacity(0.1),
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Icon(Icons.delete_outline,
                  size: 32, color: AppTheme.destructive),
            ),
            const SizedBox(height: 20),

            Text(
              'Delete User',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.onSurface.withOpacity(0.6)),
                children: [
                  const TextSpan(text: 'Are you sure you want to delete '),
                  TextSpan(
                    text: widget.user['name']?.toString() ?? 'this user',
                    style: TextStyle(
                        color: cs.onSurface, fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(text: '? This action cannot be undone.'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // User info card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.gold.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: AppTheme.gold.withOpacity(0.2)),
                    ),
                    child: Center(
                      child: Text(
                        widget.user['name']
                                ?.toString()
                                .substring(0, 1)
                                .toUpperCase() ??
                            'U',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppTheme.gold, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.user['name']?.toString() ?? 'Unknown',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@${widget.user['username']?.toString() ?? 'unknown'}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.6)),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: roleColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: roleColor.withOpacity(0.3)),
                    ),
                    child: Text(
                      _formatRole(roleStr),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: roleColor,
                          fontWeight: FontWeight.w500,
                          fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: CustomButton(
                    text: 'Cancel',
                    variant: ButtonVariant.outline,
                    fullWidth: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: CustomButton(
                    text: 'Delete',
                    fullWidth: true,
                    isLoading: _isLoading,
                    onPressed: _handleDelete,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
