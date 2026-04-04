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
  File? _pickedImage;
  String? _imageUrl;
  bool _isLoading = true;
  bool _isSaving = false;
  Product? _currentProduct;

  List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId;

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

    _loadCategories().then((_) {
      if (!widget.isNewItem) {
        _loadProductData();
      } else {
        setState(() => _isLoading = false);
      }
    });
  }

  Future<void> _loadCategories() async {
    try {
      final token = await AuthService.getToken();
      final dio = Dio(BaseOptions(
        baseUrl: ApiConfig.apiUrl,
        headers: {'Authorization': 'Bearer $token', ...ApiConfig.defaultHeaders},
      ));
      final response = await dio.get('/api/categories');
      setState(() {
        _categories = List<Map<String, dynamic>>.from(response.data['categories']);
      });
    } catch (_) {
      // Non-fatal: dropdown will be empty
    }
  }

  Future<void> _loadProductData() async {
    try {
      setState(() => _isLoading = true);

      final product =
          await ProductService.getProductDetail(int.parse(widget.productId));

      setState(() {
        _currentProduct = product;
        _productNameController.text = product.name;
        _skuController.text = product.barcode ?? '';
        _selectedCategoryId = product.categoryId;
        _stockController.text = product.stock.toString();
        _priceController.text = product.sellPrice.toString();
        _descriptionController.text = product.description ?? '';
        _imageUrl = ProductService.getProductImageUrl(product.image);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      SnackBarService.error("Gagal memuat detail produk: $e");
      Navigator.of(context).pop();
    }
  }

  Future<void> _saveChanges() async {
    if (_currentProduct == null) return;

    setState(() => _isSaving = true);
    try {
      final updatedProduct = _currentProduct!.copyWith(
        categoryId: _selectedCategoryId,
      );
      await ProductService.updateProduct(
        product: updatedProduct,
        name: _productNameController.text.trim(),
        barcode: _skuController.text.trim(),
        stock: int.tryParse(_stockController.text.trim()) ?? 0,
        sellPrice: double.tryParse(_priceController.text.trim()) ?? 0.0,
        description: _descriptionController.text.trim(),
        imageFile: _pickedImage,
      );

      SnackBarService.success("Berhasil disimpan!");
      Navigator.pop(context, true);
    } catch (e) {
      SnackBarService.error("Gagal: $e");
    } finally {
      setState(() => _isSaving = false);
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
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isNewItem ? 'Add Item' : 'Edit Item',
              style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        actions: [
          if (!widget.isNewItem)
            IconButton(
              icon:
                  const Icon(Icons.delete_outline, color: AppTheme.destructive),
              onPressed: () {
                // TODO: Implementasi Delete
              },
            ),
          const SizedBox(width: 8.0),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.gold))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ImageInput(
                    file: _pickedImage,
                    imageUrl: _imageUrl,
                    onChanged: (file) {
                      setState(() => _pickedImage = file);
                    },
                  ),
                  const SizedBox(height: 32),
                  TextInput(
                    label: 'Product Name',
                    hintText: "Masukkan nama product",
                    controller: _productNameController,
                  ),
                  const SizedBox(height: 16.0),
                  Row(
                    children: [
                      Expanded(
                        child: TextInput(
                          label: 'SKU',
                          hintText: "Masukkan SKU",
                          controller: _skuController,
                        ),
                      ),
                      const SizedBox(width: 16.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Category',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<int>(
                              value: _selectedCategoryId,
                              decoration: InputDecoration(
                                hintText: 'Pilih Category',
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 14),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: AppTheme.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: AppTheme.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: AppTheme.gold),
                                ),
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surface,
                              ),
                              items: _categories
                                  .map((cat) => DropdownMenuItem<int>(
                                        value: cat['id'] as int,
                                        child: Text(cat['name'] as String),
                                      ))
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _selectedCategoryId = val),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16.0),
                  Row(
                    children: [
                      Expanded(
                        child: TextInput(
                          label: 'Stock Quantity',
                          hintText: "Masukkan Quantity",
                          keyboardType: TextInputType.number,
                          controller: _stockController,
                        ),
                      ),
                      const SizedBox(width: 16.0),
                      Expanded(
                        child: TextInput(
                          label: 'Price',
                          hintText: "Masukkan Price",
                          keyboardType: TextInputType.number,
                          controller: _priceController,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16.0),
                  TextInput(
                    label: 'Description',
                    hintText: "Masukkan Description",
                    controller: _descriptionController,
                    maxLines: 5,
                  ),
                  const SizedBox(height: 30),
                  CustomButton(
                    text: _isSaving ? "Saving..." : "Save Changes",
                    size: ButtonSize.large,
                    onPressed: _isSaving ? null : _saveChanges,
                    fullWidth: true,
                  )
                ],
              ),
            ),
    );
  }
}
