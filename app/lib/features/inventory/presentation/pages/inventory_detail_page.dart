import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gg_store_cashier/core/config/api_config.dart';
import 'package:gg_store_cashier/core/services/auth_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import 'package:gg_store_cashier/shared/widgets/custom_button.dart';
import 'package:gg_store_cashier/shared/widgets/image_input.dart';
import 'package:gg_store_cashier/shared/widgets/text_input.dart';
import 'package:gg_store_cashier/shared/widgets/searchable_dropdown.dart';
import 'package:gg_store_cashier/core/services/product_service.dart';
import 'package:gg_store_cashier/core/models/product.dart';

class InventoryDetailPage extends StatefulWidget {
  final String productId;
  final bool isNewItem;

  const InventoryDetailPage({
    super.key,
    required this.productId,
    this.isNewItem = false,
  });

  @override
  State<InventoryDetailPage> createState() => _InventoryDetailPageState();
}

class _InventoryDetailPageState extends State<InventoryDetailPage> {
  final _formKey = GlobalKey<FormState>();

  File? _pickedImage;
  String? _imageUrl;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isDeleting = false;
  Product? _currentProduct;

  // Category dropdown
  List<DropdownItem<int>> _categoryItems = [];
  int? _selectedCategoryId;
  bool _isLoadingCategories = false;

  late TextEditingController _productNameController;
  late TextEditingController _skuController;
  late TextEditingController _stockController;
  late TextEditingController _priceController;
  late TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _productNameController = TextEditingController();
    _skuController = TextEditingController();
    _stockController = TextEditingController();
    _priceController = TextEditingController();
    _descriptionController = TextEditingController();

    _loadCategories();
    if (!widget.isNewItem) {
      _loadProductData();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoadingCategories = true);
    try {
      final token = await AuthService.getToken();
      final dio = Dio(BaseOptions(
        baseUrl: ApiConfig.apiUrl,
        headers: {'Authorization': 'Bearer $token', ...ApiConfig.defaultHeaders},
      ));
      final res = await dio.get('/api/categories');
      final list = res.data['categories'] as List;
      setState(() {
        _categoryItems = list
            .map((e) => DropdownItem<int>(
                  value: e['id'] as int,
                  label: e['name'].toString(),
                  icon: Icons.category_outlined,
                ))
            .toList();
        _isLoadingCategories = false;
      });
    } catch (_) {
      setState(() => _isLoadingCategories = false);
    }
  }

  Future<void> _loadProductData() async {
    try {
      setState(() => _isLoading = true);
      final product = await ProductService.getProductDetail(int.parse(widget.productId));
      setState(() {
        _currentProduct = product;
        _productNameController.text = product.name;
        _skuController.text = product.barcode ?? '';
        _stockController.text = product.stock.toString();
        _priceController.text = product.sellPrice.toString();
        _descriptionController.text = product.description ?? '';
        _imageUrl = ProductService.getProductImageUrl(product.image);
        _selectedCategoryId = product.categoryId;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      SnackBarService.error('Gagal memuat detail produk: $e');
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _saveChanges() async {
    if (_currentProduct == null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await ProductService.updateProduct(
        product: _currentProduct!.copyWith(categoryId: _selectedCategoryId),
        name: _productNameController.text.trim(),
        barcode: _skuController.text.trim(),
        stock: int.tryParse(_stockController.text.trim()) ?? 0,
        sellPrice: double.tryParse(_priceController.text.trim()) ?? 0.0,
        description: _descriptionController.text.trim(),
        imageFile: _pickedImage,
      );
      SnackBarService.success('Produk berhasil disimpan');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      SnackBarService.error('Gagal menyimpan: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDelete() async {
    if (_currentProduct == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Produk'),
        content: Text('Hapus "${_currentProduct!.name}"? Tindakan ini tidak dapat dibatalkan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await ProductService.deleteProduct(int.parse(_currentProduct!.id));
      SnackBarService.success('Produk berhasil dihapus');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      SnackBarService.error('Gagal menghapus: $e');
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  void dispose() {
    _productNameController.dispose();
    _skuController.dispose();
    _stockController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.isNewItem ? 'Tambah Produk' : 'Edit Produk',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          if (!widget.isNewItem)
            _isDeleting
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.destructive),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppTheme.destructive),
                    tooltip: 'Hapus Produk',
                    onPressed: _confirmDelete,
                  ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.gold))
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Gambar ──────────────────────────────────────────
                    ImageInput(
                      file: _pickedImage,
                      imageUrl: _imageUrl,
                      label: 'Gambar Produk',
                      onChanged: (file) => setState(() => _pickedImage = file),
                    ),
                    const SizedBox(height: 24),

                    // ── Nama Produk ──────────────────────────────────────
                    TextInput(
                      label: 'Nama Produk *',
                      hintText: 'Masukkan nama produk',
                      controller: _productNameController,
                      prefixIcon: Icons.inventory_2_outlined,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Nama produk wajib diisi';
                        }
                        if (v.trim().length < 2) return 'Minimal 2 karakter';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // ── SKU ──────────────────────────────────────────────
                    TextInput(
                      label: 'SKU / Barcode',
                      hintText: 'Masukkan SKU',
                      controller: _skuController,
                      prefixIcon: Icons.qr_code_outlined,
                    ),
                    const SizedBox(height: 16),

                    // ── Kategori (dropdown) ──────────────────────────────
                    _isLoadingCategories
                        ? Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              border: Border.all(color: cs.outlineVariant),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.gold),
                                ),
                                SizedBox(width: 10),
                                Text('Memuat kategori...'),
                              ],
                            ),
                          )
                        : SearchableDropdown<int>(
                            label: 'Kategori (Opsional)',
                            hintText: 'Pilih kategori',
                            value: _selectedCategoryId,
                            prefixIcon: Icons.category_outlined,
                            items: _categoryItems,
                            onChanged: (v) => setState(() => _selectedCategoryId = v),
                          ),
                    const SizedBox(height: 16),

                    // ── Stok & Harga ─────────────────────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextInput(
                            label: 'Jumlah Stok *',
                            hintText: 'Masukkan jumlah',
                            keyboardType: TextInputType.number,
                            controller: _stockController,
                            prefixIcon: Icons.numbers_outlined,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Stok wajib diisi';
                              }
                              if (int.tryParse(v.trim()) == null) {
                                return 'Angka tidak valid';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextInput(
                            label: 'Harga Jual *',
                            hintText: 'Masukkan harga',
                            keyboardType: TextInputType.number,
                            controller: _priceController,
                            prefixIcon: Icons.attach_money_outlined,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Harga wajib diisi';
                              }
                              final n = double.tryParse(v.trim());
                              if (n == null || n < 0) {
                                return 'Harga tidak valid';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Deskripsi ────────────────────────────────────────
                    TextInput(
                      label: 'Deskripsi (Opsional)',
                      hintText: 'Tambahkan deskripsi produk',
                      controller: _descriptionController,
                      maxLines: 4,
                      prefixIcon: Icons.description_outlined,
                    ),
                    const SizedBox(height: 32),

                    // ── Simpan ───────────────────────────────────────────
                    CustomButton(
                      text: 'Simpan Perubahan',
                      size: ButtonSize.large,
                      isLoading: _isSaving,
                      onPressed: _isSaving ? null : _saveChanges,
                      fullWidth: true,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
