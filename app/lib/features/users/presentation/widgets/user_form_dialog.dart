import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../shared/widgets/text_input.dart';
import '../../../../shared/widgets/password_strength_indicator.dart';
import '../../../../shared/widgets/branch_autocomplete.dart';
import '../../../../shared/utils/snackbar_service.dart';
import '../providers/user_management_provider.dart';

class UserFormDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic>? user;
  final bool isSuperAdmin;
  final int? restrictedBranchId;

  const UserFormDialog({
    super.key,
    this.user,
    this.isSuperAdmin = false,
    this.restrictedBranchId,
  });

  @override
  ConsumerState<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends ConsumerState<UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String _selectedRole = 'karyawan';
  String _selectedBranch = '1';
  String _selectedBranchName = '';
  int? _selectedBranchId;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  bool get _isEditing => widget.user != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _nameController.text = widget.user!['name']?.toString() ?? '';
      _usernameController.text = widget.user!['username']?.toString() ?? '';
      _selectedRole = widget.user!['role']?.toString() ?? 'karyawan';
      _selectedBranch = widget.user!['branch_id']?.toString() ?? '1';
      _selectedBranchId = widget.user!['branch_id'];
      _selectedBranchName = widget.user!['branch_name']?.toString() ?? '';
    } else if (widget.restrictedBranchId != null) {
      _selectedBranch = widget.restrictedBranchId.toString();
      _selectedBranchId = widget.restrictedBranchId;
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

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final userData = <String, dynamic>{
        'name': _nameController.text.trim(),
        'username': _usernameController.text.trim(),
        'role': _selectedRole,
      };

      if (_selectedBranchId != null) {
        userData['branch_id'] = _selectedBranchId as dynamic;
      } else if (_selectedBranchName.isNotEmpty) {
        userData['branch_name'] = _selectedBranchName;
      }

      if (_passwordController.text.isNotEmpty || !_isEditing) {
        userData['password'] = _passwordController.text;
      }

      if (_isEditing) {
        await ref
            .read(userManagementProvider.notifier)
            .updateUser(widget.user!['id'], userData);
        if (mounted) SnackBarService.success('Pengguna berhasil diperbarui');
      } else {
        await ref.read(userManagementProvider.notifier).createUser(userData);
        if (mounted) SnackBarService.success('Pengguna berhasil dibuat');
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) SnackBarService.error(e.toString());
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
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
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
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close,
                      color: cs.onSurface.withOpacity(0.6)),
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

                      // Role dropdown
                      Text(
                        'Role',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
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
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: cs.onSurface),
                            items: widget.isSuperAdmin
                                ? const [
                                    DropdownMenuItem(
                                        value: 'karyawan',
                                        child: Text('Karyawan')),
                                    DropdownMenuItem(
                                        value: 'admin',
                                        child: Text('Admin')),
                                    DropdownMenuItem(
                                        value: 'superadmin',
                                        child: Text('Super Admin')),
                                  ]
                                : const [
                                    DropdownMenuItem(
                                        value: 'karyawan',
                                        child: Text('Karyawan')),
                                  ],
                            onChanged: (value) =>
                                setState(() => _selectedRole = value!),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      BranchAutocomplete(
                        initialValue: _selectedBranch,
                        initialBranchName: _selectedBranchName,
                        enabled: widget.restrictedBranchId == null,
                        onChanged: (branchId, branchName) {
                          setState(() {
                            _selectedBranchId = branchId;
                            _selectedBranchName = branchName;
                            if (branchId != null) {
                              _selectedBranch = branchId.toString();
                            }
                          });
                        },
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Cabang wajib dipilih';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      TextInput(
                        controller: _passwordController,
                        label: _isEditing
                            ? 'Password Baru (kosongkan untuk tetap sama)'
                            : 'Password',
                        hintText: 'Masukkan password',
                        obscureText: _obscurePassword,
                        validator: _validatePassword,
                        prefixIcon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: cs.onSurface.withOpacity(0.6),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      PasswordStrengthIndicator(
                        password: _passwordController.text,
                        showRequirements:
                            _passwordController.text.isNotEmpty,
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
                          onPressed: () => setState(() =>
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword),
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: cs.onSurface.withOpacity(0.6),
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
