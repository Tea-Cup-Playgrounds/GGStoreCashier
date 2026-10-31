import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/access.dart';
import '../../../../core/models/catalog.dart';
import '../../../../core/provider/access_provider.dart';
import '../../../../core/provider/auth_provider.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../shared/widgets/text_input.dart';
import '../../../../shared/widgets/password_strength_indicator.dart';
import '../../../../shared/utils/snackbar_service.dart';
import '../providers/user_management_provider.dart';

/// One editable row: a location (null = every location, owners only) and a role.
class _AssignmentRow {
  int? locationId;
  int? roleId;
  _AssignmentRow({this.locationId, this.roleId});
}

class UserFormDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic>? user;

  const UserFormDialog({super.key, this.user});

  @override
  ConsumerState<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends ConsumerState<UserFormDialog> {
  // Dropdown value standing for "every location" (location_id null).
  static const _allLocations = -1;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final List<_AssignmentRow> _rows = [];
  // Assignments at locations the acting user doesn't manage: shown, kept as they are by the API.
  final List<Map<String, dynamic>> _otherAssignments = [];
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  bool get _isEditing => widget.user != null;

  @override
  void initState() {
    super.initState();
    final access = ref.read(currentAccessProvider);
    final scope = access.locationsFor('users.manage');
    if (_isEditing) {
      _nameController.text = widget.user!['name']?.toString() ?? '';
      _usernameController.text = widget.user!['username']?.toString() ?? '';
      for (final a in (widget.user!['assignments'] as List? ?? const [])) {
        final map = Map<String, dynamic>.from(a as Map);
        final locationId = map['location_id'] as int?;
        final mine = scope == null ? (access.isOwner || locationId != null) : (locationId != null && scope.contains(locationId));
        if (mine) {
          _rows.add(_AssignmentRow(locationId: locationId ?? _allLocations, roleId: map['role_id'] as int?));
        } else {
          _otherAssignments.add(map);
        }
      }
    } else {
      final own = ref.read(authProvider).user?.defaultLocationId;
      _rows.add(_AssignmentRow(locationId: own != null && (scope == null || scope.contains(own)) ? own : null));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _isSelf => _isEditing && widget.user!['id'] == ref.read(authProvider).user?.id;

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isSelf && _rows.isEmpty && !_isEditing) {
      SnackBarService.error('Tambahkan minimal satu penugasan lokasi dan role');
      return;
    }
    if (_rows.any((r) => r.locationId == null || r.roleId == null)) {
      SnackBarService.error('Lengkapi lokasi dan role di setiap penugasan');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final userData = <String, dynamic>{
        'name': _nameController.text.trim(),
        'username': _usernameController.text.trim(),
        // You can't change your own assignments.
        if (!_isSelf)
          'assignments': [
            for (final r in _rows)
              {'location_id': r.locationId == _allLocations ? null : r.locationId, 'role_id': r.roleId},
          ],
      };
      if (_passwordController.text.isNotEmpty || !_isEditing) {
        userData['password'] = _passwordController.text;
      }

      if (_isEditing) {
        await ref.read(userManagementProvider.notifier).updateUser(widget.user!['id'] as int, userData);
        if (mounted) SnackBarService.success('Pengguna berhasil diperbarui');
      } else {
        await ref.read(userManagementProvider.notifier).createUser(userData);
        if (mounted) SnackBarService.success('Pengguna berhasil dibuat');
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) SnackBarService.error(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Nama wajib diisi';
    if (value.trim().length < 2) return 'Nama minimal 2 karakter';
    if (value.trim().length > 50) return 'Nama maksimal 50 karakter';
    if (!RegExp(r"^[a-zA-Z\s\-'\.]+$").hasMatch(value.trim())) {
      return 'Nama hanya boleh mengandung huruf, spasi, tanda hubung, apostrof, dan titik';
    }
    return null;
  }

  String? _validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) return 'Username wajib diisi';
    if (value.trim().length < 3) return 'Username minimal 3 karakter';
    if (value.trim().length > 30) return 'Username maksimal 30 karakter';
    if (!RegExp(r'^[a-zA-Z0-9_\-\.]+$').hasMatch(value.trim())) {
      return 'Username hanya boleh mengandung huruf, angka, garis bawah, tanda hubung, dan titik';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (!_isEditing && (value == null || value.isEmpty)) {
      return 'Password wajib diisi';
    }
    if (value != null && value.isNotEmpty && value.length < 8) {
      return 'Password minimal 8 karakter';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (!_isEditing && (value == null || value.isEmpty)) {
      return 'Konfirmasi password wajib diisi';
    }
    if (value != null && value.isNotEmpty && value != _passwordController.text) {
      return 'Password tidak cocok';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isEditing ? 'Edit Pengguna' : 'Tambah Pengguna Baru',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: cs.onSurface.withValues(alpha: 0.6)),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Form
            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextInput(
                        controller: _nameController,
                        label: 'Nama Lengkap',
                        hintText: 'Masukkan nama lengkap',
                        validator: _validateName,
                        prefixIcon: Icons.person_outline,
                      ),
                      const SizedBox(height: 20),
                      TextInput(
                        controller: _usernameController,
                        label: 'Username',
                        hintText: 'Masukkan username',
                        validator: _validateUsername,
                        prefixIcon: Icons.alternate_email,
                      ),
                      const SizedBox(height: 20),

                      if (_isSelf)
                        Text(
                          'Penugasan akun Anda sendiri hanya dapat diubah oleh pengguna lain.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        )
                      else
                        _AssignmentsEditor(
                          rows: _rows,
                          otherAssignments: _otherAssignments,
                          allLocationsValue: _allLocations,
                          onChanged: () => setState(() {}),
                        ),
                      const SizedBox(height: 20),

                      TextInput(
                        controller: _passwordController,
                        label: _isEditing ? 'Password Baru (kosongkan untuk tetap sama)' : 'Password',
                        hintText: 'Masukkan password',
                        obscureText: _obscurePassword,
                        validator: _validatePassword,
                        prefixIcon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          icon: Icon(
                            _obscurePassword ? Icons.visibility : Icons.visibility_off,
                            color: cs.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      PasswordStrengthIndicator(
                        password: _passwordController.text,
                        showRequirements: _passwordController.text.isNotEmpty,
                      ),
                      const SizedBox(height: 20),

                      TextInput(
                        controller: _confirmPasswordController,
                        label: 'Konfirmasi Password',
                        hintText: 'Konfirmasi password',
                        obscureText: _obscureConfirmPassword,
                        validator: _validateConfirmPassword,
                        prefixIcon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                          icon: Icon(
                            _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                            color: cs.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Actions
            Row(
              children: [
                Expanded(
                  child: CustomButton(
                    text: 'Batal',
                    variant: ButtonVariant.outline,
                    fullWidth: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: CustomButton(
                    text: _isEditing ? 'Perbarui Pengguna' : 'Buat Pengguna',
                    fullWidth: true,
                    isLoading: _isLoading,
                    onPressed: _handleSubmit,
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

/// Location + role rows. Non-owners only get the locations where they manage users and no owner role.
class _AssignmentsEditor extends ConsumerWidget {
  final List<_AssignmentRow> rows;
  final List<Map<String, dynamic>> otherAssignments;
  final int allLocationsValue;
  final VoidCallback onChanged;

  const _AssignmentsEditor({
    required this.rows,
    required this.otherAssignments,
    required this.allLocationsValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final access = ref.watch(currentAccessProvider);
    final rolesAsync = ref.watch(assignableRolesProvider);
    final locationsAsync = ref.watch(assignableLocationsProvider);

    final error = rolesAsync.error ?? locationsAsync.error;
    if (error != null) {
      return Text('Gagal memuat role/lokasi: $error', style: TextStyle(color: cs.error));
    }
    final roles = rolesAsync.valueOrNull;
    final allLocations = locationsAsync.valueOrNull;
    if (roles == null || allLocations == null) {
      return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator());
    }

    final scope = access.locationsFor('users.manage');
    final locations = scope == null ? allLocations : allLocations.where((l) => scope.contains(l.id)).toList();
    final offeredRoles = access.isOwner ? roles : roles.where((r) => !r.isOwner).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Penugasan (lokasi & role)', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        for (final (i, row) in rows.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(child: _locationField(context, access, locations, row)),
                const SizedBox(width: 8),
                Expanded(child: _roleField(context, offeredRoles, row)),
                IconButton(
                  tooltip: 'Hapus penugasan',
                  icon: Icon(Icons.remove_circle_outline, color: cs.error),
                  onPressed: () {
                    rows.removeAt(i);
                    onChanged();
                  },
                ),
              ],
            ),
          ),
        for (final a in otherAssignments)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${a['location_id'] == null ? 'Semua lokasi' : a['location_name']} — ${a['role_name']} (dikelola pengguna lain)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        TextButton.icon(
          onPressed: () {
            rows.add(_AssignmentRow());
            onChanged();
          },
          icon: const Icon(Icons.add),
          label: const Text('Tambah penugasan'),
        ),
      ],
    );
  }

  InputDecoration _decoration(BuildContext context, String label) => InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _locationField(BuildContext context, UserAccess access, List<Location> locations, _AssignmentRow row) {
    final items = [
      if (access.isOwner) DropdownMenuItem(value: allLocationsValue, child: const Text('Semua lokasi')),
      for (final l in locations)
        DropdownMenuItem(value: l.id, child: Text(l.name, overflow: TextOverflow.ellipsis)),
    ];
    final value = items.any((i) => i.value == row.locationId) ? row.locationId : null;
    return DropdownButtonFormField<int>(
      key: ObjectKey(row),
      initialValue: value,
      isExpanded: true,
      decoration: _decoration(context, 'Lokasi'),
      items: items,
      onChanged: (v) {
        row.locationId = v;
        onChanged();
      },
    );
  }

  Widget _roleField(BuildContext context, List<AssignableRole> roles, _AssignmentRow row) {
    // The owner role applies everywhere, so it is only offered on an "every location" row.
    final everywhere = row.locationId == allLocationsValue;
    final offered = everywhere ? roles : roles.where((r) => !r.isOwner).toList();
    final value = offered.any((r) => r.id == row.roleId) ? row.roleId : null;
    return DropdownButtonFormField<int>(
      // Rebuilt when the location changes, since that changes which roles are offered.
      key: ValueKey((row, row.locationId)),
      initialValue: value,
      isExpanded: true,
      decoration: _decoration(context, 'Role'),
      items: [
        for (final r in offered) DropdownMenuItem(value: r.id, child: Text(r.name, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) {
        row.roleId = v;
        onChanged();
      },
    );
  }
}
