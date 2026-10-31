import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/helper/imei_validator.dart';
import 'package:gg_store_cashier/core/helper/rupiah_input_formatter.dart';
import 'package:gg_store_cashier/core/models/access.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/services/catalog_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import 'package:gg_store_cashier/shared/widgets/custom_button.dart';
import 'package:gg_store_cashier/shared/widgets/text_input.dart';

/// Edit a unit's IMEI/serial, condition, price and notes, or take it out of stock.
/// Returns true when something changed.
class UnitEditSheet extends ConsumerStatefulWidget {
  final ProductUnit unit;
  final CatalogProduct product;
  final Location location;

  const UnitEditSheet({super.key, required this.unit, required this.product, required this.location});

  static Future<bool?> show(BuildContext context,
          {required ProductUnit unit, required CatalogProduct product, required Location location}) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => UnitEditSheet(unit: unit, product: product, location: location),
      );

  @override
  ConsumerState<UnitEditSheet> createState() => _UnitEditSheetState();
}

class _UnitEditSheetState extends ConsumerState<UnitEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _imei1;
  late final TextEditingController _imei2;
  late final TextEditingController _serial;
  late final TextEditingController _price;
  late final TextEditingController _notes;
  late String _grade;
  bool _saving = false;

  bool get _usesImei => widget.product.serialType != SerialType.serial;
  bool get _dual => widget.product.serialType == SerialType.imeiDual;
  bool get _editable => ['in_stock', 'reserved', 'defective'].contains(widget.unit.status);

  @override
  void initState() {
    super.initState();
    final u = widget.unit;
    _imei1 = TextEditingController(text: u.imei1 ?? '');
    _imei2 = TextEditingController(text: u.imei2 ?? '');
    _serial = TextEditingController(text: u.serialNumber ?? '');
    _notes = TextEditingController(text: u.notes ?? '');
    _price = TextEditingController();
    _grade = u.conditionGrade;
  }

  @override
  void dispose() {
    for (final c in [_imei1, _imei2, _serial, _price, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _orNull(TextEditingController c) {
    final v = ImeiValidator.normalize(c.text);
    return v.isEmpty ? null : v;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await CatalogService.updateUnit(widget.unit.id, {
        if (_usesImei) 'imei1': _orNull(_imei1),
        if (_dual) 'imei2': _orNull(_imei2),
        if (!_usesImei) 'serial_number': _orNull(_serial),
        'condition_grade': _grade,
        if (_price.text.trim().isNotEmpty) 'sell_price': RupiahInputFormatter.parseRupiahAsDouble(_price.text),
        'notes': _notes.text.trim(),
      });
      SnackBarService.success('Unit diperbarui');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _writeOff(String status) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(status == 'defective' ? 'Tandai Rusak' : 'Hapus dari Stok'),
        content: TextField(
          controller: reason,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Alasan *', hintText: 'Contoh: LCD pecah, hilang'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, reason.text.trim().isNotEmpty),
            style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
            child: const Text('Konfirmasi'),
          ),
        ],
      ),
    );
    final note = reason.text.trim();
    reason.dispose();
    if (confirmed != true) return;
    try {
      await CatalogService.writeOffUnit(widget.unit.id, status: status, note: note);
      SnackBarService.success(status == 'defective' ? 'Unit ditandai rusak' : 'Unit dihapus dari stok');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      SnackBarService.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final access = ref.watch(accessProvider).valueOrNull ?? UserAccess.empty;
    final canEdit = _editable && access.can('units.register', widget.location.id);
    final canWriteOff = widget.unit.status == 'in_stock' && access.can('stock.adjust', widget.location.id);
    final idRequired = !widget.location.isWarehouse && widget.unit.hasIdentifier;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Detail Unit', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              Text('${unitStatusLabel(widget.unit.status)} · ${widget.location.label}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
              if (_usesImei) ...[
                TextInput(
                  label: _dual ? 'IMEI 1' : 'IMEI',
                  controller: _imei1,
                  readOnly: !canEdit,
                  keyboardType: TextInputType.number,
                  prefixIcon: Icons.qr_code_2_rounded,
                  validator: (v) => ImeiValidator.validate(v, required: idRequired, label: _dual ? 'IMEI 1' : 'IMEI'),
                ),
                if (_dual) ...[
                  const SizedBox(height: 12),
                  TextInput(
                    label: 'IMEI 2',
                    controller: _imei2,
                    readOnly: !canEdit,
                    keyboardType: TextInputType.number,
                    prefixIcon: Icons.qr_code_2_rounded,
                    validator: (v) {
                      final error = ImeiValidator.validate(v, required: idRequired, label: 'IMEI 2');
                      if (error != null) return error;
                      final a = ImeiValidator.normalize(_imei1.text);
                      return a.isNotEmpty && a == ImeiValidator.normalize(v ?? '') ? 'IMEI 1 dan 2 tidak boleh sama' : null;
                    },
                  ),
                ],
              ] else
                TextInput(
                  label: 'Nomor seri',
                  controller: _serial,
                  readOnly: !canEdit,
                  prefixIcon: Icons.confirmation_number_outlined,
                  validator: (v) => idRequired && (v == null || v.trim().isEmpty) ? 'Nomor seri wajib diisi' : null,
                ),
              const SizedBox(height: 12),
              Text('Kondisi', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'new', label: Text('Baru')),
                  ButtonSegment(value: 'A', label: Text('A')),
                  ButtonSegment(value: 'B', label: Text('B')),
                  ButtonSegment(value: 'C', label: Text('C')),
                ],
                selected: {_grade},
                onSelectionChanged: canEdit ? (s) => setState(() => _grade = s.first) : null,
              ),
              const SizedBox(height: 12),
              TextInput(
                label: 'Harga jual khusus unit (opsional)',
                hintText: 'Kosongkan untuk harga varian',
                controller: _price,
                readOnly: !canEdit,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                prefixIcon: Icons.sell_outlined,
              ),
              const SizedBox(height: 12),
              TextInput(label: 'Catatan', controller: _notes, readOnly: !canEdit, maxLines: 2, prefixIcon: Icons.notes),
              const SizedBox(height: 20),
              if (canEdit)
                CustomButton(text: 'Simpan', isLoading: _saving, onPressed: _saving ? null : _save, fullWidth: true),
              if (canWriteOff) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _writeOff('defective'),
                      icon: const Icon(Icons.build_circle_outlined),
                      label: const Text('Tandai rusak'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _writeOff('written_off'),
                      style: OutlinedButton.styleFrom(foregroundColor: AppTheme.destructive),
                      icon: const Icon(Icons.remove_circle_outline),
                      label: const Text('Hapus dari stok'),
                    ),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
