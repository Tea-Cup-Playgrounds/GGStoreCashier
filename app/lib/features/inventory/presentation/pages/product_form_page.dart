import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:gg_store_cashier/core/helper/rupiah_input_formatter.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/services/catalog_service.dart';
import 'package:gg_store_cashier/core/services/product_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import 'package:gg_store_cashier/shared/widgets/custom_button.dart';
import 'package:gg_store_cashier/shared/widgets/image_input.dart';
import 'package:gg_store_cashier/shared/widgets/searchable_dropdown.dart';
import 'package:gg_store_cashier/shared/widgets/text_input.dart';

String _rupiahText(double value) => RupiahInputFormatter()
    .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: value.round().toString()))
    .text;

class _VariantDraft {
  final int? id; // null = new variant
  final TextEditingController name;
  final TextEditingController sku;
  final TextEditingController barcode;
  final TextEditingController price;

  _VariantDraft({this.id, String? name, String? sku, String? barcode, double? price})
      : name = TextEditingController(text: name ?? ''),
        sku = TextEditingController(text: sku ?? ''),
        barcode = TextEditingController(text: barcode ?? ''),
        price = TextEditingController(text: price != null ? _rupiahText(price) : '');

  factory _VariantDraft.from(ProductVariant v) =>
      _VariantDraft(id: v.id, name: v.name, sku: v.sku, barcode: v.barcode, price: v.basePrice);

  Map<String, dynamic> toJson() => {
        'name': name.text.trim().isEmpty ? null : name.text.trim(),
        if (sku.text.trim().isNotEmpty) 'sku': sku.text.trim(),
        'barcode': barcode.text.trim().isEmpty ? null : barcode.text.trim(),
        'base_price': RupiahInputFormatter.parseRupiahAsDouble(price.text) ?? 0,
      };

  void dispose() {
    name.dispose();
    sku.dispose();
    barcode.dispose();
    price.dispose();
  }
}

/// Create a catalog product (no [product]) or edit one. Stock is added afterwards from the
/// product page. Pops with true when saved.
class ProductFormPage extends StatefulWidget {
  final CatalogProduct? product;

  const ProductFormPage({super.key, this.product});

  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends State<ProductFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _warranty = TextEditingController(text: '0');
  final _variants = <_VariantDraft>[];
  final _removedVariantIds = <int>[];

  File? _image;
  String _kind = 'goods';
  bool _serialized = false;
  SerialType _serialType = SerialType.imei;
  int? _brandId;
  int? _categoryId;
  List<Brand> _brands = [];
  List<({int id, String name})> _categories = [];
  bool _loadingRefs = true;
  bool _saving = false;

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _name.text = p.name;
      _description.text = p.description ?? '';
      _warranty.text = p.warrantyMonths.toString();
      _kind = p.kind;
      _serialized = p.isSerialized;
      _serialType = p.serialType ?? SerialType.imei;
      _brandId = p.brandId;
      _categoryId = p.categoryId;
      _variants.addAll(p.variants.where((v) => v.isActive).map(_VariantDraft.from));
    }
    if (_variants.isEmpty) _variants.add(_VariantDraft());
    _loadRefs();
  }

  Future<void> _loadRefs() async {
    try {
      final results = await Future.wait([CatalogService.getBrands(), CatalogService.getCategories()]);
      if (mounted) {
        setState(() {
          _brands = results[0] as List<Brand>;
          _categories = results[1] as List<({int id, String name})>;
        });
      }
    } catch (e) {
      SnackBarService.error('Gagal memuat merek/kategori: $e');
    } finally {
      if (mounted) setState(() => _loadingRefs = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _warranty.dispose();
    for (final v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  Future<void> _addBrand() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Merek Baru'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Contoh: Samsung'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Simpan')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try {
      final brand = await CatalogService.createBrand(name);
      if (mounted) {
        setState(() {
          _brands = [..._brands, brand]..sort((a, b) => a.name.compareTo(b.name));
          _brandId = brand.id;
        });
      }
    } catch (e) {
      SnackBarService.error(e.toString());
    }
  }

  void _removeVariant(int index) {
    final draft = _variants[index];
    setState(() {
      _variants.removeAt(index);
      if (draft.id != null) _removedVariantIds.add(draft.id!);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => draft.dispose());
  }

  Map<String, dynamic> get _fields => {
        'name': _name.text.trim(),
        'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
        'brand_id': _brandId,
        'category_id': _categoryId,
        'kind': _kind,
        'is_serialized': _kind == 'goods' && _serialized,
        if (_kind == 'goods' && _serialized) 'serial_type': serialTypeToApi(_serialType),
        'warranty_months': int.tryParse(_warranty.text.trim()) ?? 0,
      };

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      int productId;
      if (_isEdit) {
        productId = widget.product!.id;
        await CatalogService.updateProduct(productId, _fields);
        final originals = {for (final v in widget.product!.variants) v.id: v};
        for (final draft in _variants) {
          final json = draft.toJson();
          if (draft.id == null) {
            await CatalogService.addVariant(productId, json);
            continue;
          }
          final original = originals[draft.id]!;
          final changed = json['name'] != original.name ||
              (json['sku'] != null && json['sku'] != original.sku) ||
              json['barcode'] != original.barcode ||
              json['base_price'] != original.basePrice;
          if (changed) await CatalogService.updateVariant(draft.id!, json);
        }
        for (final id in _removedVariantIds) {
          await CatalogService.deleteVariant(id);
        }
      } else {
        final created = await CatalogService.createProduct(_fields, _variants.map((v) => v.toJson()).toList());
        productId = created.id;
      }
      if (_image != null) await CatalogService.uploadProductImage(productId, _image!);

      SnackBarService.success(_isEdit ? 'Produk diperbarui' : 'Produk ditambahkan');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final existingImage = widget.product?.image;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Produk' : 'Tambah Produk', style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: cs.surface,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 24),
          children: [
            ImageInput(
              file: _image,
              imageUrl: existingImage != null && existingImage.isNotEmpty
                  ? ProductService.getProductImageUrl(existingImage)
                  : null,
              label: 'Gambar Produk',
              onChanged: (f) => setState(() => _image = f),
            ),
            const SizedBox(height: 20),
            TextInput(
              label: 'Nama Produk *',
              hintText: 'Contoh: Samsung Galaxy A55 5G',
              controller: _name,
              prefixIcon: Icons.inventory_2_outlined,
              validator: (v) => (v == null || v.trim().length < 2) ? 'Nama produk minimal 2 karakter' : null,
            ),
            const SizedBox(height: 16),
            if (_loadingRefs)
              const LinearProgressIndicator(color: AppTheme.gold)
            else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: SearchableDropdown<int>(
                      // Autocomplete only reads its initial value once; rebuild it when a
                      // brand is created and selected from the dialog.
                      key: ValueKey('brand-$_brandId-${_brands.length}'),
                      label: 'Merek (opsional)',
                      hintText: 'Pilih merek',
                      value: _brandId,
                      prefixIcon: Icons.sell_outlined,
                      items: _brands.map((b) => DropdownItem<int>(value: b.id, label: b.name)).toList(),
                      onChanged: (v) => setState(() => _brandId = v),
                    ),
                  ),
                  IconButton(tooltip: 'Merek baru', icon: const Icon(Icons.add_circle_outline), onPressed: _addBrand),
                ],
              ),
              const SizedBox(height: 16),
              SearchableDropdown<int>(
                label: 'Kategori (opsional)',
                hintText: 'Pilih kategori',
                value: _categoryId,
                prefixIcon: Icons.category_outlined,
                items: _categories.map((c) => DropdownItem<int>(value: c.id, label: c.name)).toList(),
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ],
            const SizedBox(height: 16),
            Text('Jenis', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'goods', label: Text('Barang'), icon: Icon(Icons.inventory_2_outlined)),
                ButtonSegment(value: 'service', label: Text('Jasa'), icon: Icon(Icons.build_outlined)),
                ButtonSegment(value: 'digital', label: Text('Digital'), icon: Icon(Icons.bolt_outlined)),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            if (_kind == 'goods') ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Lacak per unit (IMEI / nomor seri)'),
                subtitle: const Text('Untuk HP, tablet, laptop. Tidak dapat diubah setelah ada stok.'),
                value: _serialized,
                activeThumbColor: AppTheme.gold,
                onChanged: (v) => setState(() => _serialized = v),
              ),
              if (_serialized)
                DropdownButtonFormField<SerialType>(
                  initialValue: _serialType,
                  decoration: const InputDecoration(labelText: 'Jenis identitas unit'),
                  items: SerialType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(serialTypeLabel(t))))
                      .toList(),
                  onChanged: (v) => setState(() => _serialType = v ?? SerialType.imei),
                ),
            ],
            const SizedBox(height: 16),
            TextInput(
              label: 'Garansi (bulan)',
              controller: _warranty,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              prefixIcon: Icons.verified_user_outlined,
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                return n == null || n > 120 ? 'Isi 0–120' : null;
              },
            ),
            const SizedBox(height: 16),
            TextInput(
              label: 'Deskripsi (opsional)',
              controller: _description,
              maxLines: 3,
              prefixIcon: Icons.description_outlined,
            ),
            const SizedBox(height: 24),
            Row(children: [
              Text('Varian', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _variants.add(_VariantDraft())),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Tambah varian'),
              ),
            ]),
            Text('Contoh varian: 8/256 Hitam. Kosongkan nama bila hanya satu varian. SKU dibuat otomatis bila kosong.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            for (var i = 0; i < _variants.length; i++)
              _VariantEditor(
                key: ObjectKey(_variants[i]),
                draft: _variants[i],
                index: i,
                requireName: _variants.length > 1,
                onRemove: _variants.length == 1 ? null : () => _removeVariant(i),
              ),
            const SizedBox(height: 24),
            CustomButton(
              text: _isEdit ? 'Simpan Perubahan' : 'Tambah Produk',
              size: ButtonSize.large,
              isLoading: _saving,
              onPressed: _saving ? null : _save,
              fullWidth: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _VariantEditor extends StatelessWidget {
  final _VariantDraft draft;
  final int index;
  final bool requireName;
  final VoidCallback? onRemove;

  const _VariantEditor({super.key, required this.draft, required this.index, required this.requireName, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant, width: 0.8),
      ),
      child: Column(
        children: [
          Row(children: [
            Text('Varian ${index + 1}', style: Theme.of(context).textTheme.labelLarge),
            const Spacer(),
            if (onRemove != null)
              IconButton(icon: const Icon(Icons.delete_outline, color: AppTheme.destructive), onPressed: onRemove),
          ]),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(children: [
              TextFormField(
                controller: draft.name,
                decoration: InputDecoration(labelText: requireName ? 'Nama varian *' : 'Nama varian (opsional)', isDense: true),
                validator: (v) => requireName && (v == null || v.trim().isEmpty) ? 'Nama varian wajib diisi' : null,
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: draft.sku,
                    decoration: const InputDecoration(labelText: 'SKU', hintText: 'Otomatis', isDense: true),
                    validator: (v) {
                      final s = v?.trim() ?? '';
                      if (s.isEmpty) return null;
                      return RegExp(r'^[A-Za-z0-9\-_.]{2,50}$').hasMatch(s) ? null : 'Huruf, angka, - _ .';
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: draft.barcode,
                    decoration: const InputDecoration(labelText: 'Barcode', isDense: true),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              TextFormField(
                controller: draft.price,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                decoration: const InputDecoration(labelText: 'Harga jual dasar *', hintText: 'Rp0', isDense: true),
                validator: (v) => RupiahInputFormatter.parseRupiahAsDouble(v ?? '') == null ? 'Harga wajib diisi' : null,
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
