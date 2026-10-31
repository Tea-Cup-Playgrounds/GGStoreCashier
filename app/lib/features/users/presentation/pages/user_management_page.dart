import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/provider/access_provider.dart';
import '../../../../core/provider/auth_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../shared/widgets/custom_search_bar.dart';
import '../../../../shared/widgets/pull_to_refresh.dart';
import '../widgets/user_list_item.dart';
import '../widgets/user_form_dialog.dart';
import '../widgets/user_delete_dialog.dart';
import '../providers/user_management_provider.dart';

/// Users and their per-location roles. Owners see everyone; others (users.manage) see the users
/// assigned to the locations they manage — the API decides, this page shows what it returns.
class UserManagementPage extends ConsumerStatefulWidget {
  const UserManagementPage({super.key});

  @override
  ConsumerState<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends ConsumerState<UserManagementPage> {
  final _searchController = TextEditingController();
  int? _roleFilter;
  int? _locationFilter;

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

  void _reload() => ref.read(userManagementProvider.notifier).loadUsers();

  void _showUserForm({Map<String, dynamic>? user}) {
    showDialog(context: context, builder: (context) => UserFormDialog(user: user)).then((_) => _reload());
  }

  void _showDeleteDialog(Map<String, dynamic> user) {
    showDialog(context: context, builder: (context) => UserDeleteDialog(user: user)).then((_) => _reload());
  }

  void _onFilterChanged() {
    ref.read(userManagementProvider.notifier).filterUsers(roleId: _roleFilter, locationId: _locationFilter);
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(currentAccessProvider);
    if (!access.can('users.manage')) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text('Anda tidak memiliki izin mengelola pengguna', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      );
    }

    final userState = ref.watch(userManagementProvider);
    final isDesktop = MediaQuery.of(context).size.width > 768;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: const Text('Manajemen Pengguna'), centerTitle: false),
      body: Column(
        children: [
          _buildHeader(context, userState, isDesktop, access.isOwner),
          if (userState.isStale)
            Container(
              width: double.infinity,
              color: Colors.orange.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: const Text('Offline — menampilkan data tersimpan'),
            ),
          Expanded(child: _buildContent(userState, isDesktop)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, UserManagementState state, bool isDesktop, bool isOwner) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(isDesktop ? 32 : 16),
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
                child: Text(
                  isOwner ? 'Kelola semua pengguna di semua lokasi' : 'Kelola pengguna di lokasi Anda',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.6)),
                ),
              ),
              IconButton(
                onPressed: state.isLoading ? null : _reload,
                icon: state.isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.gold))
                    : const Icon(Icons.refresh),
              ),
              const SizedBox(width: 8),
              CustomButton(
                text: 'Tambah Pengguna',
                icon: Icons.add,
                onPressed: () => _showUserForm(),
                variant: ButtonVariant.primary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          CustomSearchBar(
            controller: _searchController,
            hintText: 'Cari nama atau username...',
            onChanged: (q) => ref.read(userManagementProvider.notifier).searchUsers(q),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildRoleFilter()),
              const SizedBox(width: 12),
              Expanded(child: _buildLocationFilter()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterBox<T>({required T? value, required List<DropdownMenuItem<T?>> items, required ValueChanged<T?> onChanged}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          isExpanded: true,
          dropdownColor: cs.surface,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildRoleFilter() {
    final roles = ref.watch(assignableRolesProvider).valueOrNull ?? const [];
    return _filterBox<int>(
      value: roles.any((r) => r.id == _roleFilter) ? _roleFilter : null,
      items: [
        const DropdownMenuItem(value: null, child: Text('Semua Role')),
        for (final r in roles) DropdownMenuItem(value: r.id, child: Text(r.name, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (value) {
        setState(() => _roleFilter = value);
        _onFilterChanged();
      },
    );
  }

  Widget _buildLocationFilter() {
    final locations = ref.watch(assignableLocationsProvider).valueOrNull ?? const [];
    return _filterBox<int>(
      value: locations.any((l) => l.id == _locationFilter) ? _locationFilter : null,
      items: [
        const DropdownMenuItem(value: null, child: Text('Semua Lokasi')),
        for (final l in locations) DropdownMenuItem(value: l.id, child: Text(l.name, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (value) {
        setState(() => _locationFilter = value);
        _onFilterChanged();
      },
    );
  }

  Widget _buildContent(UserManagementState state, bool isDesktop) {
    final cs = Theme.of(context).colorScheme;
    final selfId = ref.watch(authProvider.select((s) => s.user?.id));

    if (state.isLoading && state.users.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.gold));
    }

    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppTheme.destructive),
              const SizedBox(height: 16),
              Text('Gagal memuat pengguna', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(state.error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.6))),
              const SizedBox(height: 24),
              CustomButton(text: 'Coba Lagi', onPressed: _reload),
            ],
          ),
        ),
      );
    }

    if (state.users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: cs.onSurface.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text('Tidak ada pengguna ditemukan', style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
      );
    }

    return PullToRefresh(
      onRefresh: () async => _reload(),
      child: ListView.builder(
        itemCount: state.users.length,
        itemBuilder: (context, index) {
          final user = state.users[index];
          final pending = user['_pending'] == true;
          return Container(
            margin: EdgeInsets.symmetric(horizontal: isDesktop ? 32 : 16, vertical: 8),
            child: UserListItem(
              user: user,
              onEdit: pending ? null : () => _showUserForm(user: user),
              onDelete: pending || user['id'] == selfId ? null : () => _showDeleteDialog(user),
            ),
          );
        },
      ),
    );
  }
}
