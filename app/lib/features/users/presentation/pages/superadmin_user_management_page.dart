import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/router/role_guard.dart';
import '../../../../core/provider/auth_provider.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../shared/widgets/custom_search_bar.dart';
import '../widgets/user_list_item.dart';
import '../widgets/user_form_dialog.dart';
import '../widgets/user_delete_dialog.dart';
import '../providers/user_management_provider.dart';

/// SuperAdmin User Management Page
/// SuperAdmin can:
/// - View all users across all branches
/// - Create/Edit/Delete any user (including admins)
/// - Manage user roles and branch assignments
/// - Access all branches
class SuperAdminUserManagementPage extends ConsumerStatefulWidget {
  const SuperAdminUserManagementPage({super.key});

  @override
  ConsumerState<SuperAdminUserManagementPage> createState() => _SuperAdminUserManagementPageState();
}

class _SuperAdminUserManagementPageState extends ConsumerState<SuperAdminUserManagementPage> {
  final _searchController = TextEditingController();
  String _selectedRole = 'all';
  String _selectedBranch = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(userManagementProvider.notifier).loadUsers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showUserForm({Map<String, dynamic>? user}) {
    showDialog(
      context: context,
      builder: (context) => UserFormDialog(
        user: user,
        isSuperAdmin: true,
      ),
    ).then((_) {
      ref.read(userManagementProvider.notifier).loadUsers();
    });
  }

  void _showDeleteDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => UserDeleteDialog(user: user),
    ).then((_) {
      ref.read(userManagementProvider.notifier).loadUsers();
    });
  }

  void _onSearch(String query) {
    ref.read(userManagementProvider.notifier).searchUsers(query);
  }

  void _onFilterChanged() {
    ref.read(userManagementProvider.notifier).filterUsers(
      role: _selectedRole == 'all' ? null : _selectedRole,
      branchId: _selectedBranch == 'all' ? null : _selectedBranch,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    // Role check
    if (!RoleGuard.isSuperAdmin(user)) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'SuperAdmin Access Only',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
        ),
      );
    }

    final userState = ref.watch(userManagementProvider);
    final isDesktop = MediaQuery.of(context).size.width > 768;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _buildHeader(context, userState, isDesktop),
          Expanded(
            child: _buildContent(userState, isDesktop),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, UserManagementState state, bool isDesktop) {
    return Container(
      padding: EdgeInsets.all(isDesktop ? 32 : 24),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.gold.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.admin_panel_settings, color: AppTheme.gold, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Manajemen Pengguna',
                            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                              color: AppTheme.foreground,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.gold.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.gold),
                          ),
                          child: const Text(
                            'SUPERADMIN',
                            style: TextStyle(
                              color: AppTheme.gold,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Kelola semua pengguna di semua cabang',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              if (isDesktop) ...[
                const SizedBox(width: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: state.isLoading ? null : () {
                        ref.read(userManagementProvider.notifier).loadUsers();
                      },
                      icon: state.isLoading 
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.gold,
                            ),
                          )
                        : const Icon(Icons.refresh, color: AppTheme.mutedForeground),
                    ),
                    const SizedBox(width: 12),
                    CustomButton(
                      text: 'Add User',
                      icon: Icons.add,
                      onPressed: () => _showUserForm(),
                      variant: ButtonVariant.primary,
                    ),
                  ],
                ),
              ],
            ],
          ),
          if (!isDesktop) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: CustomButton(
                    text: 'Add User',
                    icon: Icons.add,
                    onPressed: () => _showUserForm(),
                    variant: ButtonVariant.primary,
                    fullWidth: true,
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: state.isLoading ? null : () {
                    ref.read(userManagementProvider.notifier).loadUsers();
                  },
                  icon: state.isLoading 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.gold,
                        ),
                      )
                    : const Icon(Icons.refresh, color: AppTheme.mutedForeground),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.muted,
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          _buildFilters(isDesktop),
        ],
      ),
    );
  }

  Widget _buildFilters(bool isDesktop) {
    if (isDesktop) {
      return Row(
        children: [
          Expanded(
            flex: 2,
            child: CustomSearchBar(
              controller: _searchController,
              hintText: 'Cari pengguna berdasarkan nama atau username...',
              onChanged: _onSearch,
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            flex: 1,
            child: _buildRoleFilter(),
          ),
          const SizedBox(width: 16),
          Flexible(
            flex: 1,
            child: _buildBranchFilter(),
          ),
        ],
      );
    }

    return Column(
      children: [
        CustomSearchBar(
          controller: _searchController,
          hintText: 'Cari pengguna...',
          onChanged: _onSearch,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildRoleFilter()),
            const SizedBox(width: 12),
            Expanded(child: _buildBranchFilter()),
          ],
        ),
      ],
    );
  }

  Widget _buildRoleFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedRole,
          isExpanded: true,
          dropdownColor: AppTheme.surface,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppTheme.foreground,
          ),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('Semua Role')),
            DropdownMenuItem(value: 'superadmin', child: Text('Super Admin')),
            DropdownMenuItem(value: 'admin', child: Text('Admin')),
            DropdownMenuItem(value: 'karyawan', child: Text('Karyawan')),
          ],
          onChanged: (value) {
            setState(() => _selectedRole = value!);
            _onFilterChanged();
          },
        ),
      ),
    );
  }

  Widget _buildBranchFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedBranch,
          isExpanded: true,
          dropdownColor: AppTheme.surface,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppTheme.foreground,
          ),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('Semua Cabang')),
            DropdownMenuItem(value: '0', child: Text('Semua Cabang (Global)')),
            DropdownMenuItem(value: '1', child: Text('Cabang Satu')),
            DropdownMenuItem(value: '2', child: Text('Cabang Dua')),
            DropdownMenuItem(value: '3', child: Text('Cabang Tiga')),
            DropdownMenuItem(value: '4', child: Text('Cabang Empat')),
            DropdownMenuItem(value: '5', child: Text('Cabang Lima')),
          ],
          onChanged: (value) {
            setState(() => _selectedBranch = value!);
            _onFilterChanged();
          },
        ),
      ),
    );
  }

  Widget _buildContent(UserManagementState state, bool isDesktop) {
    if (state.isLoading && state.users.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.gold),
      );
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppTheme.destructive),
            const SizedBox(height: 16),
            Text('Error loading users', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(state.error!, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            CustomButton(
              text: 'Retry',
              onPressed: () => ref.read(userManagementProvider.notifier).loadUsers(),
            ),
          ],
        ),
      );
    }

    if (state.users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 64, color: AppTheme.mutedForeground),
            const SizedBox(height: 16),
            Text('Tidak ada pengguna ditemukan', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            CustomButton(
              text: 'Add User',
              icon: Icons.add,
              onPressed: () => _showUserForm(),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: state.users.length,
      itemBuilder: (context, index) {
        final user = state.users[index];
        return Container(
          margin: EdgeInsets.symmetric(
            horizontal: isDesktop ? 32 : 24,
            vertical: 8,
          ),
          child: UserListItem(
            user: user,
            onEdit: () => _showUserForm(user: user),
            onDelete: () => _showDeleteDialog(user),
            isSuperAdmin: true,
          ),
        );
      },
    );
  }
}
