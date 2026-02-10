import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/provider/auth_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/snackbar_service.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../shared/widgets/text_input.dart';
import '../../../../shared/widgets/image_input.dart';
import 'dart:io';

class CategoryManagementPage extends ConsumerStatefulWidget {
  const CategoryManagementPage({super.key});

  @override
  ConsumerState<CategoryManagementPage> createState() => _CategoryManagementPageState();
}

class _CategoryManagementPageState extends ConsumerState<CategoryManagementPage> {
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);
    
    try {
      final token = await AuthService.getToken();
      final dio = Dio(BaseOptions(
        baseUrl: ApiConfig.apiUrl,
        headers: {'Authorization': 'Bearer $token'},
      ));

      final response = await dio.get('/api/categories');
      
      setState(() {
        _categories = List<Map<String, dynamic>>.from(response.data['categories']);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        SnackBarService.error('Failed to load categories');
      }
    }
  }

  void _showAddEditDialog({Map<String, dynamic>? category}) {
    showDialog(
      context: context,
      builder: (context) => _CategoryDialog(
        category: category,
        onSaved: () {
          Navigator.pop(context);
          _loadCategories();
        },
      ),
    );
  }

  Future<void> _deleteCategory(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: const Text('Are you sure you want to delete this category?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final token = await AuthService.getToken();
      final dio = Dio(BaseOptions(
        baseUrl: ApiConfig.apiUrl,
        headers: {'Authorization': 'Bearer $token'},
      ));

      await dio.delete('/api/categories/$id');
      
      if (mounted) {
        SnackBarService.success('Category deleted successfully');
        _loadCategories();
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Failed to delete category';
        if (e is DioException && e.response?.data != null) {
          errorMessage = e.response!.data['error'] ?? errorMessage;
        }
        SnackBarService.error(errorMessage);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final userRole = user?.role ?? 'karyawan';
    
    // Check permissions
    final canAddEdit = userRole == 'admin' || userRole == 'superadmin';
    final canDelete = userRole == 'superadmin';

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _categories.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.category_outlined,
                        size: 64,
                        color: AppTheme.mutedForeground.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No categories yet',
                        style: TextStyle(
                          color: AppTheme.mutedForeground,
                          fontSize: 18,
                        ),
                      ),
                      if (canAddEdit) ...[
                        const SizedBox(height: 24),
                        CustomButton(
                          text: 'Add First Category',
                          icon: Icons.add,
                          onPressed: () => _showAddEditDialog(),
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: category['category_image'] != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  '${ApiConfig.baseUrl}/uploads/categories/${category['category_image']}',
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      width: 50,
                                      height: 50,
                                      color: AppTheme.muted,
                                      child: const Icon(Icons.category),
                                    );
                                  },
                                ),
                              )
                            : Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: AppTheme.muted,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.category),
                              ),
                        title: Text(
                          category['name'],
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: category['description'] != null
                            ? Text(category['description'])
                            : null,
                        trailing: (canAddEdit || canDelete)
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (canAddEdit)
                                    IconButton(
                                      icon: const Icon(Icons.edit),
                                      onPressed: () => _showAddEditDialog(category: category),
                                    ),
                                  if (canDelete)
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: AppTheme.destructive),
                                      onPressed: () => _deleteCategory(category['id']),
                                    ),
                                ],
                              )
                            : null,
                      ),
                    );
                  },
                ),
      floatingActionButton: (_categories.isNotEmpty && canAddEdit)
          ? FloatingActionButton(
              onPressed: () => _showAddEditDialog(),
              backgroundColor: AppTheme.gold,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  final Map<String, dynamic>? category;
  final VoidCallback onSaved;

  const _CategoryDialog({
    this.category,
    required this.onSaved,
  });

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  File? _categoryImage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?['name']);
    _descriptionController = TextEditingController(text: widget.category?['description']);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final token = await AuthService.getToken();
      final dio = Dio(BaseOptions(
        baseUrl: ApiConfig.apiUrl,
        headers: {'Authorization': 'Bearer $token'},
      ));

      final formData = FormData.fromMap({
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
      });

      if (_categoryImage != null) {
        formData.files.add(MapEntry(
          'category_image',
          await MultipartFile.fromFile(
            _categoryImage!.path,
            filename: _categoryImage!.path.split('/').last,
          ),
        ));
      }

      if (widget.category == null) {
        await dio.post('/api/categories', data: formData);
        if (mounted) {
          SnackBarService.success('Category created successfully');
        }
      } else {
        await dio.put('/api/categories/${widget.category!['id']}', data: formData);
        if (mounted) {
          SnackBarService.success('Category updated successfully');
        }
      }

      widget.onSaved();
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Failed to save category';
        if (e is DioException && e.response?.data != null) {
          errorMessage = e.response!.data['error'] ?? errorMessage;
        }
        SnackBarService.error(errorMessage);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.category == null ? 'Add Category' : 'Edit Category'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ImageInput(
                file: _categoryImage,
                label: 'Category Image',
                onChanged: (img) => setState(() => _categoryImage = img),
              ),
              const SizedBox(height: 16),
              TextInput(
                label: 'Category Name',
                hintText: 'Enter category name',
                controller: _nameController,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Category name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextInput(
                label: 'Description (Optional)',
                hintText: 'Enter description',
                controller: _descriptionController,
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        CustomButton(
          text: widget.category == null ? 'Add' : 'Update',
          onPressed: _isLoading ? null : _submit,
          isLoading: _isLoading,
        ),
      ],
    );
  }
}
