import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:gg_store_cashier/core/config/api_config.dart';
import 'package:gg_store_cashier/core/provider/auth_provider.dart';
import 'package:gg_store_cashier/core/services/auth_service.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import 'package:gg_store_cashier/shared/widgets/custom_button.dart';
import 'package:gg_store_cashier/shared/widgets/text_input.dart';
import 'package:go_router/go_router.dart';
import 'package:gg_store_cashier/shared/widgets/image_input.dart';

class InventoryAddItemPage extends ConsumerStatefulWidget {
  const InventoryAddItemPage({super.key});

  @override
  ConsumerState<InventoryAddItemPage> createState() => _InventoryAddItemState();
}

class _InventoryAddItemState extends ConsumerState<InventoryAddItemPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _productNameController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _stockController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  
  File? _productImage;
  bool _isLoading = false;
  bool _isLoadingData = true;
  
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _categories = [];
  int? _selectedBranchId;
  int? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoadingData = true);
    
    try {
      final token = await AuthService.getToken();
      final dio = Dio(BaseOptions(
        baseUrl: ApiConfig.apiUrl,
        headers: {'Authorization': 'Bearer $token'},
      ));

      // Load branches
      final branchesResponse = await dio.get('/api/branches');
      final categoriesResponse = await dio.get('/api/categories');

      setState(() {
        _branches = List<Map<String, dynamic>>.from(
          branchesResponse.data['branches'].map((b) => {
            'id': b['id'],
            'name': b['name'],
          })
        );
        
        _categories = List<Map<String, dynamic>>.from(
          categoriesResponse.data['categories'].map((c) => {
            'id': c['id'],
            'name': c['name'],
          })
        );

        // Set default branch for admin/karyawan
        final user = ref.read(authProvider).user;
        if (user != null && user.role != 'superadmin' && user.branchId != null) {
          _selectedBranchId = user.branchId;
        }
        
        _isLoadingData = false;
      });
    } catch (e) {
      setState(() => _isLoadingData = false);
      if (mounted) {
        SnackBarService.error('Failed to load data: ${e.toString()}');
      }
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedBranchId == null) {
      SnackBarService.error('Please select a branch');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final token = await AuthService.getToken();
      final dio = Dio(BaseOptions(
        baseUrl: ApiConfig.apiUrl,
        headers: {'Authorization': 'Bearer $token'},
      ));

      // Prepare form data
      final formData = FormData.fromMap({
        'name': _productNameController.text.trim(),
        'barcode': _barcodeController.text.trim(),
        'category_id': _selectedCategoryId,
        'sell_price': double.parse(_priceController.text.trim()),
        'stock': int.parse(_stockController.text.trim()),
        'branch_id': _selectedBranchId,
      });

      // Add image if selected
      if (_productImage != null) {
        formData.files.add(MapEntry(
          'product_image',
          await MultipartFile.fromFile(
            _productImage!.path,
            filename: _productImage!.path.split('/').last,
          ),
        ));
      }

      final response = await dio.post('/api/products', data: formData);

      if (response.statusCode == 201) {
        if (mounted) {
          SnackBarService.success('Product added successfully');
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Failed to add product';
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
  void dispose() {
    _productNameController.dispose();
    _barcodeController.dispose();
    _stockController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isSuperAdmin = user?.role == 'superadmin';

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text(
          "Add Product",
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product Image
                    ImageInput(
                      file: _productImage,
                      label: "Product Image",
                      onChanged: (img) => setState(() => _productImage = img),
                    ),
                    const SizedBox(height: 24),

                    // Product Name
                    TextInput(
                      label: 'Product Name',
                      hintText: "Enter product name",
                      controller: _productNameController,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Product name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Barcode (optional - will be auto-generated if empty)
                    TextInput(
                      label: 'Barcode (Optional)',
                      hintText: "Leave empty for auto-generate",
                      controller: _barcodeController,
                    ),
                    const SizedBox(height: 16),

                    // Branch Dropdown (disabled for admin/karyawan)
                    DropdownButtonFormField<int>(
                      value: _selectedBranchId,
                      decoration: const InputDecoration(
                        labelText: 'Branch',
                        hintText: 'Select branch',
                      ),
                      items: _branches.map((branch) {
                        return DropdownMenuItem<int>(
                          value: branch['id'],
                          child: Text(branch['name']),
                        );
                      }).toList(),
                      onChanged: isSuperAdmin
                          ? (value) => setState(() => _selectedBranchId = value)
                          : null, // Disabled for non-superadmin
                      validator: (value) {
                        if (value == null) {
                          return 'Please select a branch';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Category Dropdown
                    DropdownButtonFormField<int>(
                      value: _selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'Category (Optional)',
                        hintText: 'Select category',
                      ),
                      items: _categories.map((category) {
                        return DropdownMenuItem<int>(
                          value: category['id'],
                          child: Text(category['name']),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => _selectedCategoryId = value),
                    ),
                    const SizedBox(height: 16),

                    // Stock and Price Row
                    Row(
                      children: [
                        Expanded(
                          child: TextInput(
                            label: 'Stock Quantity',
                            hintText: "Enter quantity",
                            controller: _stockController,
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Stock is required';
                              }
                              if (int.tryParse(value) == null) {
                                return 'Invalid number';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextInput(
                            label: 'Sell Price',
                            hintText: "Enter price",
                            controller: _priceController,
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Price is required';
                              }
                              if (double.tryParse(value) == null) {
                                return 'Invalid price';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Submit Button
                    CustomButton(
                      text: "Add Product",
                      size: ButtonSize.large,
                      onPressed: _isLoading ? null : _submitForm,
                      isLoading: _isLoading,
                      fullWidth: true,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
