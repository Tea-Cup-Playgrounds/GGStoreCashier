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
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 768;
    
    return Dialog(
      backgroundColor: AppTheme.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 40 : 16,
        vertical: isDesktop ? 40 : 24,
      ),
      child: Container(
        width: isDesktop ? 600 : double.infinity,
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                border: Border(
                  bottom: BorderSide(color: AppTheme.border),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.gold.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      widget.category == null ? Icons.add_circle_outline : Icons.edit_outlined,
                      color: AppTheme.gold,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.category == null ? 'Add New Category' : 'Edit Category',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.foreground,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.category == null 
                              ? 'Create a new product category'
                              : 'Update category information',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppTheme.mutedForeground),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            
            // Form Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Image Upload Section
                      ImageInput(
                        file: _categoryImage,
                        label: 'Category Image',
                        onChanged: (img) => setState(() => _categoryImage = img),
                        height: 200,
                      ),
                      const SizedBox(height: 24),
                      
                      // Category Name
                      TextInput(
                        label: 'Category Name',
                        hintText: 'Enter category name',
                        controller: _nameController,
                        prefixIcon: Icons.category_outlined,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Category name is required';
                          }
                          if (value.trim().length < 2) {
                            return 'Category name must be at least 2 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      
                      // Description
                      TextInput(
                        label: 'Description (Optional)',
                        hintText: 'Enter category description',
                        controller: _descriptionController,
                        prefixIcon: Icons.description_outlined,
                        maxLines: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Footer Actions
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border(
                  top: BorderSide(color: AppTheme.border),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: CustomButton(
                      text: 'Cancel',
                      variant: ButtonVariant.outline,
                      fullWidth: true,
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: isDesktop ? 1 : 2,
                    child: CustomButton(
                      text: widget.category == null ? 'Create Category' : 'Update Category',
                      icon: widget.category == null ? Icons.add : Icons.check,
                      fullWidth: true,
                      isLoading: _isLoading,
                      onPressed: _submit,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
