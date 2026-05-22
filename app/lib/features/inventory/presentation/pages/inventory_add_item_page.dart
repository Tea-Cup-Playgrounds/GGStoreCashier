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
      final branchesResponse = await dio.get('/api/branches');
      final categoriesResponse = await dio.get('/api/categories');

      if (mounted) {
        setState(() {
          _branches = List<Map<String, dynamic>>.from(
              branchesResponse.data['branches'].map((b) => {'id': b['id'], 'name': b['name']}));
          _categories = List<Map<String, dynamic>>.from(
              categoriesResponse.data['categories'].map((c) => {'id': c['id'], 'name': c['name']}));
          final user = ref.read(authProvider).user;
          if (user != null && user.role != 'superadmin' && user.branchId != null) {
            _selectedBranchId = user.branchId;
          }
          _isLoadingData = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingData = false);
        SnackBarService.error('Gagal memuat data: ${e.toString()}');
      }
    }
  }

  Future<void> _submitForm() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (_selectedBranchId == null) {
      SnackBarService.error('Pilih cabang terlebih dahulu');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final token = await AuthService.getToken();
      final dio = Dio(BaseOptions(
        baseUrl: ApiConfig.apiUrl,
        headers: {'Authorization': 'Bearer $token', ...ApiConfig.defaultHeaders},
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
      ));

      final formData = FormData.fromMap({
        'name': _productNameController.text.trim(),
        if (_barcodeController.text.trim().isNotEmpty) 'barcode': _barcodeController.text.trim(),
        'category_id': _selectedCategoryId,
        'sell_price': RupiahInputFormatter.parseRupiahAsDouble(_priceController.text) ?? 0,
        'stock': int.parse(_stockController.text.trim()),
        'branch_id': _selectedBranchId,
      });

      if (_productImage != null) {
        final filename = _productImage!.path.split('/').last;
        final ext = filename.split('.').last.toLowerCase();
        final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';
        formData.files.add(MapEntry(
          'product_image',
          await MultipartFile.fromFile(_productImage!.path,
              filename: filename, contentType: http_parser.MediaType.parse(mimeType)),
        ));
      }

      final response = await dio.post('/api/products', data: formData);

      if (response.statusCode == 201 && mounted) {
        SnackBarService.success('Produk berhasil ditambahkan');
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Gagal menambahkan produk';
        if (e is DioException && e.response?.data != null) {
          errorMessage = e.response!.data['error'] ?? errorMessage;
        }
        SnackBarService.error(errorMessage);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
        leading: IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back)),
        title: const Text('Tambah Produk', style: TextStyle(fontWeight: FontWeight.w600)),
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
                    ImageInput(
                        file: _productImage,
                        label: 'Gambar Produk',
                        onChanged: (img) => setState(() => _productImage = img)),
                    const SizedBox(height: 24),
                    TextInput(
                      label: 'Nama Produk',
                      hintText: 'Masukkan nama produk',
                      controller: _productNameController,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Nama produk wajib diisi' : null,
                    ),
                    const SizedBox(height: 16),
                    TextInput(
                        label: 'Barcode (Opsional)',
                        hintText: 'Kosongkan untuk generate otomatis',
                        controller: _barcodeController),
                    const SizedBox(height: 16),
                    SearchableDropdown<int>(
                      label: 'Cabang',
                      hintText: 'Pilih cabang',
                      value: _selectedBranchId,
                      items: _branches
                          .where((b) => b['id'] != 0)
                          .map((b) => DropdownItem<int>(value: b['id'], label: b['name'], icon: Icons.store))
                          .toList(),
                      onChanged: isSuperAdmin ? (v) => setState(() => _selectedBranchId = v) : (v) {},
                      enabled: isSuperAdmin,
                      prefixIcon: Icons.store,
                      validator: (v) => v == null ? 'Pilih cabang terlebih dahulu' : null,
                    ),
                    const SizedBox(height: 16),
                    SearchableDropdown<int>(
                      label: 'Kategori (Opsional)',
                      hintText: 'Pilih kategori',
                      value: _selectedCategoryId,
                      items: _categories
                          .map((c) => DropdownItem<int>(value: c['id'], label: c['name'], icon: Icons.category))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedCategoryId = v),
                      prefixIcon: Icons.category,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextInput(
                            label: 'Jumlah Stok',
                            hintText: 'Masukkan jumlah',
                            controller: _stockController,
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Stok wajib diisi';
                              if (int.tryParse(v) == null) return 'Angka tidak valid';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextInput(
                            label: 'Harga Jual',
                            hintText: 'Rp0',
                            controller: _priceController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [RupiahInputFormatter()],
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Harga wajib diisi';
                              final price = RupiahInputFormatter.parseRupiahAsDouble(v);
                              if (price == null || price <= 0) return 'Harga tidak valid';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    CustomButton(
                        text: 'Tambah Produk',
                        size: ButtonSize.large,
                        onPressed: _isLoading ? null : _submitForm,
                        isLoading: _isLoading,
                        fullWidth: true),
                  ],
                ),
              ),
            ),
    );
  }
}
