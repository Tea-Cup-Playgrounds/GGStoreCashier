import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/connectivity_monitor.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../shared/widgets/custom_search_bar.dart';
import '../widgets/user_list_item.dart';
import '../widgets/user_form_dialog.dart';
import '../widgets/user_delete_dialog.dart';
import '../providers/user_management_provider.dart';
import '../../../../shared/widgets/pull_to_refresh.dart';

class UserManagementPage extends ConsumerStatefulWidget {
  const UserManagementPage({super.key});

  @override
  ConsumerState<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends ConsumerState<UserManagementPage> {
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
      builder: (context) => UserFormDialog(user: user),
    ).then((_) => ref.read(userManagementProvider.notifier).loadUsers());
  }

  void _showDeleteDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => UserDeleteDialog(user: user),
    ).then((_) => ref.read(userManagementProvider.notifier).loadUsers());
  }

  void _onSearch(String query) =>
      ref.read(userManagementProvider.notifier).searchUsers(query);

  void _onFilterChanged() {
    ref.read(userManagementProvider.notifier).filterUsers(
      role: _selectedRole == 'all' ? null : _selectedRole,
      branchId: _selectedBranch == 'all' ? null : _selectedBranch,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final userState = ref.watch(userManagementProvider);
    final isOffline = ref.watch(connectivityProvider).valueOrNull == ConnectivityStatus.offline;
    final isDesktop = MediaQuery.of(context).size.width > 768;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(isDesktop ? 32 : 24),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'User Management',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              if (userState.isStale) ...[
                                const SizedBox(width: 8),
                                const Tooltip(
                                  message: 'Data mungkin tidak terbaru',
                                  child: Icon(Icons.cloud_off, size: 14, color: Colors.orange),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Manage system users and their permissions',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: cs.onSurface.withOpacity(0.6)),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: userState.isLoading
                              ? null
                              : () => ref.read(userManagementProvider.notifier).loadUsers(),
                          icon: userState.isLoading
                              ? const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.gold))
                              : Icon(Icons.refresh, color: cs.onSurface.withOpacity(0.6)),
                        ),
                        const SizedBox(width: 12),
                        Tooltip(
                          message: isOffline ? 'Perubahan akan disimpan dan dikirim saat online' : '',
                          child: CustomButton(
                            text: 'Add User',
                            icon: Icons.add,
                            onPressed: () => _showUserForm(),
                            variant: ButtonVariant.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Offline notice
                if (isOffline) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.4)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.wifi_off, size: 14, color: Colors.orange),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Kamu offline — perubahan akan disimpan dan dikirim saat online',
                            style: TextStyle(fontSize: 12, color: Colors.orange),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                if (isDesktop)
                  Row(
                    children: [
                      Expanded(
                          flex: 2,
                          child: CustomSearchBar(
                            controller: _searchController,
                            hintText: 'Search users by name or username...',
                            onChanged: _onSearch,
                          )),
                      const SizedBox(width: 16),
                      Expanded(child: _buildRoleFilter()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildBranchFilter()),
                    ],
                  )
                else
                  Column(
                    children: [
                      CustomSearchBar(
                        controller: _searchController,
                        hintText: 'Search users...',
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
                  ),
              ],
            ),
          ),
          Expanded(child: _buildContent(userState, isDesktop, isOffline)),
        ],
      ),
    );
  }

  Widget _buildRoleFilter() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedRole,
          isExpanded: true,
          dropdownColor: cs.surface,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All Roles')),
            DropdownMenuItem(value: 'superadmin', child: Text('Super Admin')),
            DropdownMenuItem(value: 'admin', child: Text('Admin')),
            DropdownMenuItem(value: 'karyawan', child: Text('Employee')),
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedBranch,
          isExpanded: true,
          dropdownColor: cs.surface,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All Branches')),
            DropdownMenuItem(value: '1', child: Text('Main Branch')),
            DropdownMenuItem(value: '2', child: Text('Branch 2')),
          ],
          onChanged: (value) {
            setState(() => _selectedBranch = value!);
            _onFilterChanged();
          },
        ),
      ),
    );
  }

  Widget _buildContent(UserManagementState state, bool isDesktop, bool isOffline) {
    final cs = Theme.of(context).colorScheme;

    if (state.isLoading && state.users.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.gold));
    }

    if (state.error != null && state.users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppTheme.destructive),
            const SizedBox(height: 16),
            Text('Error loading users', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(state.error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withOpacity(0.6)),
                textAlign: TextAlign.center),
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
            Icon(Icons.people_outline, size: 64, color: cs.onSurface.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text('No users found', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Add your first user to get started',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withOpacity(0.6))),
            const SizedBox(height: 24),
            CustomButton(text: 'Add User', icon: Icons.add, onPressed: () => _showUserForm()),
          ],
        ),
      );
    }

    return PullToRefresh(
      onRefresh: () async => ref.read(userManagementProvider.notifier).loadUsers(),
      child: ListView.builder(
        itemCount: state.users.length,
        itemBuilder: (context, index) {
          final user = state.users[index];
          final isPending = user['_pending'] == true;
          return Container(
            margin: EdgeInsets.symmetric(horizontal: isDesktop ? 32 : 24, vertical: 8),
            child: Opacity(
              opacity: isPending ? 0.7 : 1.0,
              child: UserListItem(
                user: user,
                onEdit: () => _showUserForm(user: user),
                onDelete: () => _showDeleteDialog(user),
                // Show pending badge if this item was created/edited offline
                trailing: isPending
                    ? const Tooltip(
                        message: 'Menunggu sinkronisasi',
                        child: Icon(Icons.cloud_upload_outlined, size: 16, color: Colors.orange),
                      )
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }
}
