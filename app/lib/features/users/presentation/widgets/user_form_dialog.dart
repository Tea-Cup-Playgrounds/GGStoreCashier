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
      // For admin, set their branch as default
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

      // Add branch_id if it's an existing branch, or branch_name if it's a new branch
      if (_selectedBranchId != null) {
        userData['branch_id'] = _selectedBranchId as dynamic;
      } else if (_selectedBranchName.isNotEmpty) {
        userData['branch_name'] = _selectedBranchName;
      }

      // Only include password if it's provided (for editing) or if creating new user
      if (_passwordController.text.isNotEmpty || !_isEditing) {
        userData['password'] = _passwordController.text;
      }

      if (_isEditing) {
        await ref.read(userManagementProvider.notifier).updateUser(
          widget.user!['id'],
          userData,
        );
        if (mounted) {
          SnackBarService.success('User updated successfully');
        }
      } else {
        await ref.read(userManagementProvider.notifier).createUser(userData);
        if (mounted) {
          SnackBarService.success('User created successfully');
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        SnackBarService.error(e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Name is required';
    }
    if (value.trim().length < 2) {
      return 'Name must be at least 2 characters';
    }
    if (value.trim().length > 50) {
      return 'Name must be less than 50 characters';
    }
    if (!RegExp(r"^[a-zA-Z\s\-'\.]+$").hasMatch(value.trim())) {
      return 'Name can only contain letters, spaces, hyphens, apostrophes, and periods';
    }
    return null;
  }

  String? _validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Username is required';
    }
    if (value.trim().length < 3) {
      return 'Username must be at least 3 characters';
    }
    if (value.trim().length > 30) {
      return 'Username must be less than 30 characters';
    }
    if (!RegExp(r'^[a-zA-Z0-9_\-\.]+$').hasMatch(value.trim())) {
      return 'Username can only contain letters, numbers, underscores, hyphens, and periods';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (!_isEditing && (value == null || value.isEmpty)) {
      return 'Password is required';
    }
    if (value != null && value.isNotEmpty) {
      if (value.length < 8) {
        return 'Password must be at least 8 characters';
      }
      // Additional password strength validation is handled by the indicator
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (!_isEditing && (value == null || value.isEmpty)) {
      return 'Please confirm your password';
    }
    if (value != null && value.isNotEmpty && value != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
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
                    _isEditing ? 'Edit User' : 'Add New User',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppTheme.foreground,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: AppTheme.mutedForeground),
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
                      // Name Field
                      TextInput(
                        controller: _nameController,
                        label: 'Full Name',
                        hintText: 'Enter full name',
                        validator: _validateName,
                        prefixIcon: Icons.person_outline,
                      ),
                      const SizedBox(height: 20),
                      // Username Field
                      TextInput(
                        controller: _usernameController,
                        label: 'Username',
                        hintText: 'Enter username',
                        validator: _validateUsername,
                        prefixIcon: Icons.alternate_email,
                      ),
                      const SizedBox(height: 20),
                      // Role Dropdown
                      Text(
                        'Role',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.foreground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
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
                            items: widget.isSuperAdmin
                                ? const [
                                    DropdownMenuItem(value: 'karyawan', child: Text('Employee')),
                                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                                    DropdownMenuItem(value: 'superadmin', child: Text('Super Admin')),
                                  ]
                                : const [
                                    DropdownMenuItem(value: 'karyawan', child: Text('Employee')),
                                  ],
                            onChanged: (value) {
                              setState(() {
                                _selectedRole = value!;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Branch Autocomplete
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
                            return 'Branch is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      // Password Field
                      TextInput(
                        controller: _passwordController,
                        label: _isEditing ? 'New Password (leave empty to keep current)' : 'Password',
                        hintText: 'Enter password',
                        obscureText: _obscurePassword,
                        validator: _validatePassword,
                        prefixIcon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                          icon: Icon(
                            _obscurePassword ? Icons.visibility : Icons.visibility_off,
                            color: AppTheme.mutedForeground,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {}); // Trigger rebuild for password strength indicator
                        },
                      ),
                      const SizedBox(height: 12),
                      // Password Strength Indicator
                      PasswordStrengthIndicator(
                        password: _passwordController.text,
                        showRequirements: _passwordController.text.isNotEmpty,
                      ),
                      const SizedBox(height: 20),
                      // Confirm Password Field
                      TextInput(
                        controller: _confirmPasswordController,
                        label: 'Confirm Password',
                        hintText: 'Confirm password',
                        obscureText: _obscureConfirmPassword,
                        validator: _validateConfirmPassword,
                        prefixIcon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword = !_obscureConfirmPassword;
                            });
                          },
                          icon: Icon(
                            _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                            color: AppTheme.mutedForeground,
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
                    text: 'Cancel',
                    variant: ButtonVariant.outline,
                    fullWidth: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: CustomButton(
                    text: _isEditing ? 'Update User' : 'Create User',
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