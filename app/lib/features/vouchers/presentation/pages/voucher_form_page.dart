import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import '../../../../core/models/voucher.dart';
import '../../../../core/services/voucher_service.dart';
import '../../../../core/services/product_service.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../shared/widgets/text_input.dart' as w;
import '../../../../shared/widgets/searchable_dropdown.dart';
import '../../../../shared/utils/snackbar_service.dart';
import 'package:go_router/go_router.dart';

class VoucherFormPage extends StatefulWidget {
  /// Pass an existing voucher to edit, or null to create.
  final Voucher? voucher;

  const VoucherFormPage({super.key, this.voucher});

  @override
  State<VoucherFormPage> createState() => _VoucherFormPageState();
}

class _VoucherFormPageState extends State<VoucherFormPage> {
  final _formKey     = GlobalKey<FormState>();
  final _codeCtrl    = TextEditingController();
  final _descCtrl    = TextEditingController();
  final _valueCtrl   = TextEditingController();
  final _fromCtrl    = TextEditingController();
  final _toCtrl      = TextEditingController();

  String  _discountType = 'percent';
  bool    _isActive     = true;
  bool    _isSaving     = false;

  // target
  String? _targetType;
  int?    _selectedTargetId;

  List<DropdownItem<int>> _targetItems    = [];
  bool    _isLoadingTargets = false;
  String? _targetLoadError;

  bool get _isEditing => widget.voucher != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final v = widget.voucher!;
      _codeCtrl.text  = v.code;
      _descCtrl.text  = v.description ?? '';
      _discountType   = v.discountType;
      _valueCtrl.text = v.discountValue
          .toStringAsFixed(v.discountType == 'percent' ? 0 : 2);
      _fromCtrl.text  = v.validFrom ?? '';
      _toCtrl.text    = v.validTo   ?? '';
      _isActive       = v.isActive;
      _targetType     = v.targetType;
      _selectedTargetId = v.targetId;
      if (v.targetType != null) _loadTargets(v.targetType!);
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _descCtrl.dispose();
    _valueCtrl.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTargets(String type) async {
    setState(() {
      _isLoadingTargets = true;
      _targetLoadError  = null;
      _targetItems      = [];
    });

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

      List<DropdownItem<int>> items;

      if (type == 'categories') {
        final res  = await dio.get('/api/categories');
        final list = res.data['categories'] as List;
        items = list
            .map((e) => DropdownItem<int>(
                  value: e['id'] as int,
                  label: e['name'].toString(),
                  icon: Icons.category_outlined,
                ))
            .toList();
      } else {
        final products = await ProductService.getProducts();
        items = products
            .map((p) => DropdownItem<int>(
                  value: int.parse(p.id),
                  label: p.name,
                  icon: Icons.inventory_2_outlined,
                ))
            .toList();
      }

      if (mounted) {
        setState(() {
          _targetItems      = items;
          _isLoadingTargets = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _targetLoadError  = e.toString();
          _isLoadingTargets = false;
        });
      }
    }
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      ctrl.text = picked.toIso8601String().substring(0, 10);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (_targetType != null && _selectedTargetId == null) {
      SnackBarService.error('Please select a target item');
      return;
    }

    setState(() => _isSaving = true);

    final data = {
      'code':           _codeCtrl.text.trim().toUpperCase(),
      'description':    _descCtrl.text.trim().isEmpty
                            ? null
                            : _descCtrl.text.trim(),
      'discount_type':  _discountType,
      'discount_value': double.parse(_valueCtrl.text.trim()),
      'target_type':    _targetType,
      'target_id':      _selectedTargetId,
      'valid_from':     _fromCtrl.text.trim().isEmpty ? null : _fromCtrl.text.trim(),
      'valid_to':       _toCtrl.text.trim().isEmpty   ? null : _toCtrl.text.trim(),
      'is_active':      _isActive ? 1 : 0,
    };

    try {
      if (_isEditing) {
        await VoucherService.update(widget.voucher!.id, data);
        SnackBarService.success('Voucher updated');
      } else {
        await VoucherService.create(data);
        SnackBarService.success('Voucher created');
      }
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        String msg = e.toString();
        if (e is DioException && e.response?.data?['error'] != null) {
          msg = e.response!.data['error'];
        }
        SnackBarService.error(msg);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(
          _isEditing ? 'Edit Voucher' : 'New Voucher',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: cs.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Voucher Code ───────────────────────────────────────────────
              w.TextInput(
                label: 'Voucher Code *',
                hintText: 'e.g. SUMMER20',
                controller: _codeCtrl,
                prefixIcon: Icons.local_offer_outlined,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_\-]')),
                  LengthLimitingTextInputFormatter(50),
                ],
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Voucher code is required'
                    : null,
              ),
              const SizedBox(height: 16),

              // ── Description ────────────────────────────────────────────────
              w.TextInput(
                label: 'Description',
                hintText: 'e.g. Summer sale discount',
                controller: _descCtrl,
                prefixIcon: Icons.notes_outlined,
              ),
              const SizedBox(height: 16),

              // ── Discount Type + Value ──────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SearchableDropdown<String>(
                      label: 'Discount Type *',
                      hintText: 'Select type',
                      value: _discountType,
                      prefixIcon: Icons.percent,
                      items: [
                        DropdownItem(
                            value: 'percent',
                            label: 'Percent (%)',
                            icon: Icons.percent),
                        DropdownItem(
                            value: 'fixed',
                            label: 'Fixed (Rp)',
                            icon: Icons.money),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _discountType = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: w.TextInput(
                      label: 'Value *',
                      hintText: _discountType == 'percent' ? '1–100' : 'Amount',
                      controller: _valueCtrl,
                      prefixIcon: Icons.money,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        final n = double.tryParse(v.trim());
                        if (n == null || n <= 0) return 'Must be > 0';
                        if (_discountType == 'percent' && n > 100) {
                          return 'Max 100%';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Applies To (target type) ───────────────────────────────────
              SearchableDropdown<String>(
                label: 'Applies To',
                hintText: 'All products (no restriction)',
                value: _targetType,
                prefixIcon: Icons.filter_alt_outlined,
                items: [
                  DropdownItem(
                      value: 'categories',
                      label: 'Specific Category',
                      icon: Icons.category_outlined),
                  DropdownItem(
                      value: 'product',
                      label: 'Specific Product',
                      icon: Icons.inventory_2_outlined),
                ],
                onChanged: (v) {
                  setState(() {
                    _targetType       = v;
                    _selectedTargetId = null;
                    _targetItems      = [];
                    _targetLoadError  = null;
                  });
                  if (v != null) _loadTargets(v);
                },
              ),
              const SizedBox(height: 16),

              // ── Target Item picker ─────────────────────────────────────────
              if (_targetType != null) ...[
                _buildTargetPicker(cs),
                const SizedBox(height: 16),
              ],

              // ── Valid From / To ────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: w.TextInput(
                      label: 'Valid From',
                      hintText: 'YYYY-MM-DD',
                      controller: _fromCtrl,
                      prefixIcon: Icons.calendar_today_outlined,
                      readOnly: true,
                      onTap: () => _pickDate(_fromCtrl),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: w.TextInput(
                      label: 'Valid To',
                      hintText: 'YYYY-MM-DD',
                      controller: _toCtrl,
                      prefixIcon: Icons.event_outlined,
                      readOnly: true,
                      onTap: () => _pickDate(_toCtrl),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ── Active toggle ──────────────────────────────────────────────
              SwitchListTile.adaptive(
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
                title: const Text('Active'),
                subtitle: Text(_isActive
                    ? 'Voucher can be used at checkout'
                    : 'Voucher is disabled'),
                contentPadding: EdgeInsets.zero,
                activeColor: AppTheme.gold,
              ),
              const SizedBox(height: 24),

              // ── Submit ─────────────────────────────────────────────────────
              CustomButton(
                text: _isEditing ? 'Save Changes' : 'Create Voucher',
                icon: _isEditing ? Icons.save_outlined : Icons.add,
                size: ButtonSize.large,
                fullWidth: true,
                isLoading: _isSaving,
                onPressed: _isSaving ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Target item picker ─────────────────────────────────────────────────────
  Widget _buildTargetPicker(ColorScheme cs) {
    final label = _targetType == 'categories' ? 'Category' : 'Product';

    if (_isLoadingTargets) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.gold),
            ),
            SizedBox(width: 12),
            Text('Loading options...'),
          ],
        ),
      );
    }

    if (_targetLoadError != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.destructive.withOpacity(0.08),
          border: Border.all(color: AppTheme.destructive.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline,
                color: AppTheme.destructive, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Failed to load $label options',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.destructive)),
            ),
            TextButton(
              onPressed: () => _loadTargets(_targetType!),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return SearchableDropdown<int>(
      label: 'Select $label *',
      hintText: 'Search and select a $label',
      value: _selectedTargetId,
      prefixIcon: _targetType == 'categories'
          ? Icons.category_outlined
          : Icons.inventory_2_outlined,
      items: _targetItems,
      onChanged: (v) => setState(() => _selectedTargetId = v),
      validator: (v) =>
          v == null ? 'Please select a $label' : null,
    );
  }
}
