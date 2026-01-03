import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import 'package:gg_store_cashier/shared/widgets/custom_button.dart';
import 'package:gg_store_cashier/shared/widgets/image_input.dart';
import 'package:gg_store_cashier/shared/widgets/text_input.dart';
import '../../../../core/theme/app_theme.dart';
// import '../../../../shared/widgets/bottom_navigation.dart'; // Halaman Detail biasanya tidak memiliki BottomNav

class InventoryDetailPage extends StatefulWidget {
  final String productId;
  final bool image;
  const InventoryDetailPage(
      {super.key, required this.productId, this.image = false});

  @override
  State<InventoryDetailPage> createState() => _InventoryDetailPageState();
}

class _InventoryDetailPageState extends State<InventoryDetailPage> {
  final Map<String, dynamic> product = {
    "id": 1,
    "productName": "Signature Watch",
    "category": 'Accessories',
    "sku": "WAT-001",
    "price": "299,99",
    "stock": "29",
    "description": "Premium stainless steel watch with gold accents",
  };

  File? _pickedImage;
  final _imageKey = GlobalKey<ImageInputState>();
  late TextEditingController _productNameController;
  late TextEditingController _skuController;
  late TextEditingController _categoryController;
  late TextEditingController _stockController;
  late TextEditingController _priceController;
  late TextEditingController _descriptionController;
  String? imageUrl = "https://picsum.photos/seed/picsum/200/300";

  @override
  void initState() {
    super.initState();

    _productNameController =
        TextEditingController(text: product["productName"]);
    _skuController = TextEditingController(text: product["sku"]);
    _categoryController = TextEditingController(text: product["category"]);
    _stockController = TextEditingController(text: product["stock"]);
    _priceController = TextEditingController(text: product["price"]);
    _descriptionController =
        TextEditingController(text: product["description"]);
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
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        // Tombol kembali otomatis
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.foreground),
          onPressed: () => Navigator.of(context).pop(),
        ),
        // Judul dan Subtitle Kustom
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit Item',
              style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.foreground,
                  ),
            ),
            Text(
              widget
                  .productId, // Menggunakan productId (WAT-001) sebagai subtitle
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: AppTheme.mutedForeground,
                  ),
            ),
          ],
        ),
        backgroundColor: AppTheme.background,
        elevation: 0,
        actions: [
          // Tombol Hapus (Warna Destructive)
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppTheme.destructive),
            onPressed: () {
              // TODO: Aksi Hapus Item
            },
          ),
          const SizedBox(width: 8.0),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Gambar Produk
            // const Icon(Icons.photo_album_rounded),
            widget.image
                ? ImageInput(
                    file: _pickedImage,
                    onChanged: (file) {
                      setState(() => _pickedImage = file);
                    },
                  )
                : ImageInput(
                    file: _pickedImage,
                    imageUrl: imageUrl,
                    onChanged: (file) {
                      setState(() => _pickedImage = file);
                    },
                  ),
            // 2. Form Input
            // Product Name
            const SizedBox(height: 32),
            TextInput(
              label: 'Product Name',
              hintText: "Masukkan nama product",
              controller: _productNameController,
            ),
            const SizedBox(
              height: 16.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextInput(
                    label: 'SKU',
                    hintText: "Masukkan SKU",
                    controller: _skuController,
                  ),
                ),
                const SizedBox(
                  width: 16.0,
                ),
                Expanded(
                  child: TextInput(
                    label: 'Category',
                    hintText: "Masukkan Category",
                    controller: _categoryController,
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 16.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextInput(
                    label: 'Stock Quantity',
                    hintText: "Masukkan Quatity",
                    controller: _stockController,
                  ),
                ),
                const SizedBox(
                  width: 16.0,
                ),
                Expanded(
                  child: TextInput(
                    label: 'Price',
                    hintText: "Masukkan Price",
                    controller: _priceController,
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 16.0,
            ),
            TextInput(
              label: 'Description',
              hintText: "Masukkan Description",
              controller: _descriptionController,
              maxLines: 5,
            ),
            const SizedBox(
              height: 32,
            ),
            // Tombol Save (Contoh Aksi)
            CustomButton(
              text: "Saves Changes",
              size: ButtonSize.large,
              onPressed: () {
                SnackBarService.success("Saves changed!");
              },
              fullWidth: true,
            )
          ],
        ),
      ),
      // Halaman detail tidak menggunakan BottomNavigation
      // bottomNavigationBar: const BottomNavigation(),
    );
  }

  // Helper Widget untuk Label Form
  Widget _buildLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium!.copyWith(
              color: AppTheme.foreground,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }

  // Helper Widget untuk TextFormField
  Widget _buildTextField(
    BuildContext context, {
    required String initialValue,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
  }) {
    // Menggunakan TextFormField untuk mendapatkan styling dari ThemeData
    return TextFormField(
      initialValue: initialValue,
      maxLines: maxLines,
      keyboardType: keyboardType,
      readOnly: readOnly,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}
