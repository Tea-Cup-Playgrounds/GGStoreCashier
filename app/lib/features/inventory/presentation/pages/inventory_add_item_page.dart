import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import 'package:gg_store_cashier/shared/widgets/custom_button.dart';
import 'package:gg_store_cashier/shared/widgets/text_input.dart';
import 'package:go_router/go_router.dart';
import 'package:gg_store_cashier/shared/widgets/image_input.dart';

class InventoryAddItemPage extends StatefulWidget {
  const InventoryAddItemPage({super.key});

  @override
  State<InventoryAddItemPage> createState() => _InventoryAddItemState();
}

class _InventoryAddItemState extends State<InventoryAddItemPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _productNameController = TextEditingController();
  final TextEditingController _skuController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _stockController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  File? _productImage;
  // final _imageKey = GlobalKey<ImageInputState>();

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
            onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back)),
        title: const Text(
          "Tambah Product",
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ImageInput(
                  file: _productImage,
                  label: "",
                  onChanged: (img) => setState(() => _productImage = img),
                ),
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
                  height: 16,
                ),
                CustomButton(
                  text: "Tambah",
                  size: ButtonSize.large,
                  onPressed: () {
                    SnackBarService.success("Item successfully added");
                  },
                  fullWidth: true,
                )
              ],
            )),
      ),
    );
  }
}
