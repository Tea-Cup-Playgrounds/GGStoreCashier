import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:gg_store_cashier/core/config/api_config.dart';
import 'package:gg_store_cashier/core/provider/auth_provider.dart';
import 'package:gg_store_cashier/core/services/auth_service.dart';
import 'package:gg_store_cashier/core/helper/rupiah_input_formatter.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import 'package:gg_store_cashier/shared/widgets/custom_button.dart';
import 'package:gg_store_cashier/shared/widgets/text_input.dart';
import 'package:gg_store_cashier/shared/widgets/searchable_dropdown.dart';
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
        headers: {'Authorization': 'Bearer $token', ...ApiConfig.defaultHeaders},
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
    FocusScope.of(context).unfocus();
    
    if (!_formKey.currentState!.validate()) {
      debugPrint('[AddProduct] form validation failed');
      return;
    }

    if (_selectedBranchId == null) {
      SnackBarService.error('Please select a branch');
      return;
    }

    debugPrint('[AddProduct] submitting form...');
    debugPrint('[AddProduct] name: ${_productNameController.text.trim()}');
    debugPrint('[AddProduct] branch_id: $_selectedBranchId');
    debugPrint('[AddProduct] category_id: $_selectedCategoryId');
    debugPrint('[AddProduct] has image: ${_productImage != null}');
    if (_productImage != null) {
      debugPrint('[AddProduct] image path: ${_productImage!.path}');
      debugPrint('[AddProduct] image exists: ${await _productImage!.exists()}');
      debugPrint('[AddProduct] image size: ${await _productImage!.length()} bytes');
    }

    setState(() => _isLoading = true);

    try {
      final token = await AuthService.getToken();
      debugPrint('[AddProduct] token present: ${token != null}');
      debugPrint('[AddProduct] API URL: ${ApiConfig.apiUrl}');

      final dio = Dio(BaseOptions(
        baseUrl: ApiConfig.apiUrl,
        headers: {'Authorization': 'Bearer $token', ...ApiConfig.defaultHeaders},
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
      ));

      // Add logging interceptor
      dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        requestHeader: true,
        error: true,
        logPrint: (o) => debugPrint('[AddProduct][DIO] $o'),
      ));

      // Prepare form data
      final formData = FormData.fromMap({
        'name': _productNameController.text.trim(),
        'barcode': _barcodeController.text.trim(),
        'category_id': _selectedCategoryId,
        'sell_price': RupiahInputFormatter.parseRupiahAsDouble(_priceController.text) ?? 0,
        'stock': int.parse(_stockController.text.trim()),
        'branch_id': _selectedBranchId,
      });

      // Add image if selected
      if (_productImage != null) {
        final filename = _productImage!.path.split('/').last;
        final ext = filename.split('.').last.toLowerCase();
        final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';

        debugPrint('[AddProduct] attaching image: $filename, mime: $mimeType');
        formData.files.add(MapEntry(
          'product_image',
          await MultipartFile.fromFile(
            _productImage!.path,
            filename: filename,
            contentType: http_parser.MediaType.parse(mimeType),
          ),
        ));
      }

      debugPrint('[AddProduct] sending POST /api/products');
      final response = await dio.post('/api/products', data: formData);
      debugPrint('[AddProduct] response status: ${response.statusCode}');
      debugPrint('[AddProduct] response data: ${response.data}');

      if (response.statusCode == 201) {
        if (mounted) {
          SnackBarService.success('Product added successfully');
          context.pop();
        }
      }
    } catch (e) {
      debugPrint('[AddProduct] ERROR: $e');
      if (e is DioException) {
        debugPrint('[AddProduct] DioException type: ${e.type}');
        debugPrint('[AddProduct] DioException message: ${e.message}');
        debugPrint('[AddProduct] response status: ${e.response?.statusCode}');
        debugPrint('[AddProduct] response data: ${e.response?.data}');
      }
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
              padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 24),
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

                    // Branch Dropdown — only visible to superadmin
                    if (isSuperAdmin) ...[
                      SearchableDropdown<int>(
                        label: 'Branch',
                        hintText: 'Select branch',
                        value: _selectedBranchId,
                        items: _branches.map((branch) {
                          return DropdownItem<int>(
                            value: branch['id'],
                            label: branch['name'],
                            icon: Icons.store,
                          );
                        }).toList(),
                        onChanged: (value) => setState(() => _selectedBranchId = value),
                        enabled: true,
                        prefixIcon: Icons.store,
                        validator: (value) {
                          if (value == null) return 'Please select a branch';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Category Dropdown
                    SearchableDropdown<int>(
                      label: 'Category (Optional)',
                      hintText: 'Select category',
                      value: _selectedCategoryId,
                      items: _categories.map((category) {
                        return DropdownItem<int>(
                          value: category['id'],
                          label: category['name'],
                          icon: Icons.category,
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => _selectedCategoryId = value),
                      prefixIcon: Icons.category,
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
                            hintText: "Rp0",
                            controller: _priceController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [RupiahInputFormatter()],
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Price is required';
                              }
                              final price = RupiahInputFormatter.parseRupiahAsDouble(value);
                              if (price == null || price <= 0) {
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
