import 'dart:io';
import 'package:flutter/material.dart';
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

  late TextEditingController _productNameController;
  late TextEditingController _skuController;
  late TextEditingController _categoryController;
  late TextEditingController _stockController;
  late TextEditingController _priceController;
  late TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _productNameController = TextEditingController();
    _skuController = TextEditingController();
    _categoryController = TextEditingController();
    _stockController = TextEditingController();
    _priceController = TextEditingController();
    _descriptionController = TextEditingController();

    if (!widget.isNewItem) {
      _loadProductData();
    } else {
      setState(() => _isLoading = false);
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
        _categoryController.text = product.category ?? '';
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
      await ProductService.updateProduct(
        product: _currentProduct!,
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
    _categoryController.dispose();
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
                        child: TextInput(
                          label: 'Category',
                          hintText: "Masukkan Category",
                          controller: _categoryController,
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
