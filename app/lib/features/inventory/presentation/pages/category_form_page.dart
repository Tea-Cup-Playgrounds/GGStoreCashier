import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:go_router/go_router.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/snackbar_service.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../shared/widgets/text_input.dart';
import '../../../../shared/widgets/image_input.dart';

/// Route extra: pass a Map<String, dynamic> category to edit, or null to create.
class CategoryFormPage extends StatefulWidget {
  final Map<String, dynamic>? category;

  const CategoryFormPage({super.key, this.category});

  @override
  State<CategoryFormPage> createState() => _CategoryFormPageState();
}

class _CategoryFormPageState extends State<CategoryFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  File? _categoryImage;
  bool _imageRemoved = false;
  bool _isLoading = false;

  bool get _isEditing => widget.category != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?['name'] ?? '');
    _descriptionController = TextEditingController(text: widget.category?['description'] ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Image is mandatory for new categories
    if (!_isEditing && _categoryImage == null) {
      SnackBarService.error('Gambar kategori wajib dipilih');
      return;
    }

    // When editing, prevent saving if image was removed without a replacement
    if (_isEditing && _imageRemoved && _categoryImage == null) {
      SnackBarService.error('Gambar kategori wajib dipilih');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final token = await AuthService.getToken();
      final dio = Dio(BaseOptions(
        baseUrl: ApiConfig.apiUrl,
        headers: {
          'Authorization': 'Bearer $token',
          ...ApiConfig.defaultHeaders,
        },
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
      ));

      final formData = FormData.fromMap({
        'name': _nameController.text.trim(),
        if (_descriptionController.text.trim().isNotEmpty) 'description': _descriptionController.text.trim(),
      });

      if (_categoryImage != null) {
        final filename = _categoryImage!.path.split('/').last;
        final ext = filename.split('.').last.toLowerCase();
        final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';
        formData.files.add(MapEntry(
          'category_image',
          await MultipartFile.fromFile(
            _categoryImage!.path,
            filename: filename,
            contentType: http_parser.MediaType.parse(mimeType),
          ),
        ));
      }

      if (_isEditing) {
        await dio.put('/api/categories/${widget.category!['id']}', data: formData);
        if (mounted) SnackBarService.success('Kategori berhasil diperbarui');
      } else {
        await dio.post('/api/categories', data: formData);
        if (mounted) SnackBarService.success('Kategori berhasil ditambahkan');
      }

      if (mounted) context.pop(true); // true = refresh list
    } catch (e) {
      if (mounted) {
        String msg = _isEditing ? 'Gagal memperbarui kategori' : 'Gagal menambahkan kategori';
        if (e is DioException && e.response?.data != null) {
          msg = e.response!.data['error'] ?? msg;
        }
        SnackBarService.error(msg);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Kategori' : 'Tambah Kategori'),
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isLoading ? null : () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Info card ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.gold.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.gold.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.gold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _isEditing ? Icons.edit_outlined : Icons.add_circle_outline,
                        color: AppTheme.gold,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isEditing
                            ? 'Perbarui informasi kategori produk.'
                            : 'Buat kategori baru untuk mengelompokkan produk.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Gambar ─────────────────────────────────────────────────
              ImageInput(
                file: _categoryImage,
                label: 'Gambar Kategori',
                isRequired: !_isEditing,
                imageUrl: _imageRemoved
                    ? null
                    : (widget.category?['category_image'] != null
                        ? '${ApiConfig.apiUrl}/uploads/categories/${widget.category!['category_image']}'
                        : null),
                onChanged: (img) => setState(() {
                  _categoryImage = img;
                  if (img == null) _imageRemoved = true;
                }),
                height: 200,
              ),
              const SizedBox(height: 24),

              // ── Nama ───────────────────────────────────────────────────
              TextInput(
                label: 'Nama Kategori',
                hintText: 'Contoh: Elektronik, Makanan, dll.',
                controller: _nameController,
                prefixIcon: Icons.category_outlined,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Nama kategori wajib diisi';
                  }
                  if (value.trim().length < 2) {
                    return 'Minimal 2 karakter';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // ── Deskripsi ──────────────────────────────────────────────
              TextInput(
                label: 'Deskripsi (Opsional)',
                hintText: 'Tambahkan deskripsi singkat kategori ini',
                controller: _descriptionController,
                prefixIcon: Icons.description_outlined,
                maxLines: 3,
              ),
              const SizedBox(height: 32),

              // ── Tombol simpan ──────────────────────────────────────────
              CustomButton(
                text: _isEditing ? 'Simpan Perubahan' : 'Tambah Kategori',
                icon: _isEditing ? Icons.check : Icons.add,
                size: ButtonSize.large,
                fullWidth: true,
                isLoading: _isLoading,
                onPressed: _isLoading ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
