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

/// Admin User Management Page
/// Admin can:
/// - View users only in their assigned branch
/// - Create/Edit/Delete employees (karyawan) in their branch
/// - Cannot manage other admins or superadmins
/// - Limited to their branch scope
class AdminUserManagementPage extends ConsumerStatefulWidget {
  const AdminUserManagementPage({super.key});

  @override
  ConsumerState<AdminUserManagementPage> createState() => _AdminUserManagementPageState();
}

class _AdminUserManagementPageState extends ConsumerState<AdminUserManagementPage> {
  final _searchController = TextEditingController();
  String _selectedRole = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authState = ref.read(authProvider);
      final user = authState.user;
      
      if (user != null && user.branchId != null) {
        // Load users filtered by admin's branch
        ref.read(userManagementProvider.notifier).filterUsers(
          branchId: user.branchId.toString(),
        );
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showUserForm({Map<String, dynamic>? user}) {
    final authState = ref.read(authProvider);
    final currentUser = authState.user;

    showDialog(
      context: context,
      builder: (context) => UserFormDialog(
        user: user,
        isSuperAdmin: false,
        restrictedBranchId: currentUser?.branchId,
      ),
    ).then((_) {
      if (currentUser != null && currentUser.branchId != null) {
        ref.read(userManagementProvider.notifier).filterUsers(
          branchId: currentUser.branchId.toString(),
        );
      }
    });
  }

  void _showDeleteDialog(Map<String, dynamic> user) {
    // Check if user can be deleted by admin
    if (user['role'] == 'admin' || user['role'] == 'superadmin') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anda tidak dapat menghapus pengguna admin atau superadmin'),
          backgroundColor: AppTheme.destructive,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => UserDeleteDialog(user: user),
    ).then((_) {
      final authState = ref.read(authProvider);
      final currentUser = authState.user;
      if (currentUser != null && currentUser.branchId != null) {
        ref.read(userManagementProvider.notifier).filterUsers(
          branchId: currentUser.branchId.toString(),
        );
      }
    });
  }

  void _onSearch(String query) {
    ref.read(userManagementProvider.notifier).searchUsers(query);
  }

  void _onFilterChanged() {
    final authState = ref.read(authProvider);
    final user = authState.user;
    
    if (user != null && user.branchId != null) {
      ref.read(userManagementProvider.notifier).filterUsers(
        role: _selectedRole == 'all' ? null : _selectedRole,
        branchId: user.branchId.toString(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    // Role check
    if (!RoleGuard.isAdmin(user)) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'Admin Access Only',
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
          _buildHeader(context, userState, isDesktop, user),
          Expanded(
            child: _buildContent(userState, isDesktop),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, UserManagementState state, bool isDesktop, user) {
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
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.manage_accounts, color: Colors.blue, size: 28),
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
                            color: Colors.blue.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue),
                          ),
                          child: const Text(
                            'ADMIN',
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Kelola karyawan di cabang Anda',
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
                        if (user != null && user.branchId != null) {
                          ref.read(userManagementProvider.notifier).filterUsers(
                            branchId: user.branchId.toString(),
                          );
                        }
                      },
                      icon: state.isLoading 
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.blue,
                            ),
                          )
                        : const Icon(Icons.refresh, color: AppTheme.mutedForeground),
                    ),
                    const SizedBox(width: 12),
                    CustomButton(
                      text: 'Tambah Karyawan',
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
                    text: 'Tambah Karyawan',
                    icon: Icons.add,
                    onPressed: () => _showUserForm(),
                    variant: ButtonVariant.primary,
                    fullWidth: true,
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: state.isLoading ? null : () {
                    if (user != null && user.branchId != null) {
                      ref.read(userManagementProvider.notifier).filterUsers(
                        branchId: user.branchId.toString(),
                      );
                    }
                  },
                  icon: state.isLoading 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.blue,
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
              hintText: 'Cari karyawan berdasarkan nama atau username...',
              onChanged: _onSearch,
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            flex: 1,
            child: _buildRoleFilter(),
          ),
        ],
      );
    }

    return Column(
      children: [
        CustomSearchBar(
          controller: _searchController,
          hintText: 'Cari karyawan...',
          onChanged: _onSearch,
        ),
        const SizedBox(height: 16),
        _buildRoleFilter(),
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

  Widget _buildContent(UserManagementState state, bool isDesktop) {
    if (state.isLoading && state.users.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.blue),
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
              onPressed: () {
                final authState = ref.read(authProvider);
                final user = authState.user;
                if (user != null && user.branchId != null) {
                  ref.read(userManagementProvider.notifier).filterUsers(
                    branchId: user.branchId.toString(),
                  );
                }
              },
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
            Text('Tidak ada karyawan ditemukan', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            CustomButton(
              text: 'Tambah Karyawan',
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
        final canEdit = user['role'] == 'karyawan';
        final canDelete = user['role'] == 'karyawan';
        
        return Container(
          margin: EdgeInsets.symmetric(
            horizontal: isDesktop ? 32 : 24,
            vertical: 8,
          ),
          child: UserListItem(
            user: user,
            onEdit: canEdit ? () => _showUserForm(user: user) : null,
            onDelete: canDelete ? () => _showDeleteDialog(user) : null,
            isSuperAdmin: false,
          ),
        );
      },
    );
  }
}
