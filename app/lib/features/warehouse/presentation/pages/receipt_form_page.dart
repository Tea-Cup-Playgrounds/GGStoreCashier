import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:intl/intl.dart';
import 'package:gg_store_cashier/core/helper/currency_formatter.dart';
import 'package:gg_store_cashier/core/helper/imei_validator.dart';
import 'package:gg_store_cashier/core/helper/rupiah_input_formatter.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/models/warehouse.dart';
import 'package:gg_store_cashier/core/services/warehouse_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/features/inventory/presentation/widgets/variant_picker_sheet.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import 'package:gg_store_cashier/shared/widgets/custom_button.dart';
import 'package:gg_store_cashier/shared/widgets/searchable_dropdown.dart';
import 'package:gg_store_cashier/shared/widgets/text_input.dart';
import 'receipt_detail_page.dart';

const _ppnRate = 11.0;

String _rupiahText(double value) => RupiahInputFormatter()
    .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: value.round().toString()))
    .text;

class _UnitDraft {
  final first = TextEditingController();
  final second = TextEditingController();
  final firstFocus = FocusNode();
  final secondFocus = FocusNode();

  _UnitDraft([ReceiptUnit? unit]) {
    first.text = unit?.imei1 ?? unit?.serialNumber ?? '';
    second.text = unit?.imei2 ?? '';
  }

  void dispose() {
    first.dispose();
    second.dispose();
    firstFocus.dispose();
    secondFocus.dispose();
  }
}

class _LineDraft {
  final int variantId;
  final String name;
  final bool isSerialized;
  final SerialType? serialType;
  final qty = TextEditingController(text: '1');
  final cost = TextEditingController();
  bool ppn;
  final units = <_UnitDraft>[];

  _LineDraft({required this.variantId, required this.name, required this.isSerialized, this.serialType, this.ppn = false}) {
    if (isSerialized) units.add(_UnitDraft());
  }

  factory _LineDraft.fromItem(ReceiptItem item) {
    final line = _LineDraft(
      variantId: item.variantId,
      name: item.name,
      isSerialized: item.isSerialized,
      serialType: item.serialType,
      ppn: item.taxRate > 0,
    );
    line.qty.text = item.qty.toString();
    line.cost.text = _rupiahText(item.unitCost);
    if (item.isSerialized) {
      line.units.first.dispose();
      line.units
        ..clear()
        ..addAll(item.units.map(_UnitDraft.new));
      if (line.units.isEmpty) line.units.add(_UnitDraft());
    }
    return line;
  }

  bool get usesImei => serialType != SerialType.serial;
  bool get dual => serialType == SerialType.imeiDual;

  int get quantity => isSerialized ? units.length : (int.tryParse(qty.text.trim()) ?? 0);
  double get unitCost => RupiahInputFormatter.parseRupiahAsDouble(cost.text) ?? 0;
  double get subtotal => quantity * unitCost;
  double get tax => ppn ? (subtotal * _ppnRate / 100 * 100).roundToDouble() / 100 : 0;

  Map<String, dynamic> toJson() => {
        'variant_id': variantId,
        'qty': quantity,
        'unit_cost': unitCost,
        'tax_rate': ppn ? _ppnRate : 0,
        if (isSerialized)
          'units': units.map((u) {
            final a = ImeiValidator.normalize(u.first.text);
            final b = ImeiValidator.normalize(u.second.text);
            return usesImei
                ? {'imei1': a.isEmpty ? null : a, 'imei2': b.isEmpty ? null : b}
                : {'serial_number': a.isEmpty ? null : a};
          }).toList(),
      };

  void dispose() {
    qty.dispose();
    cost.dispose();
    for (final u in units) {
      u.dispose();
    }
  }
}

/// Create a draft goods receipt at [location], or edit [receipt] (draft only).
/// Saving opens the receipt; it is posted from there.
class ReceiptFormPage extends StatefulWidget {
  final Location location;
  final GoodsReceipt? receipt;

  const ReceiptFormPage({super.key, required this.location, this.receipt});

  @override
  State<ReceiptFormPage> createState() => _ReceiptFormPageState();
}

class _ReceiptFormPageState extends State<ReceiptFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _invoiceNo = TextEditingController();
  final _note = TextEditingController();
  final _lines = <_LineDraft>[];
  List<Supplier> _suppliers = [];
  int? _supplierId;
  DateTime? _invoiceDate;
  DateTime? _dueDate;
  bool _saving = false;

  bool get _idsOptional => widget.location.isWarehouse;

  @override
  void initState() {
    super.initState();
    final r = widget.receipt;
    if (r != null) {
      _supplierId = r.supplierId;
      _invoiceNo.text = r.invoiceNo ?? '';
      _note.text = r.note ?? '';
      _invoiceDate = r.invoiceDate != null ? DateTime.tryParse(r.invoiceDate!) : null;
      _dueDate = r.dueDate != null ? DateTime.tryParse(r.dueDate!) : null;
      _lines.addAll(r.items.map(_LineDraft.fromItem));
    }
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    try {
      final suppliers = await WarehouseService.getSuppliers();
      if (mounted) setState(() => _suppliers = suppliers);
    } catch (e) {
      SnackBarService.error('Gagal memuat supplier: $e');
    }
  }

  @override
  void dispose() {
    _invoiceNo.dispose();
    _note.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _addLine() async {
    final picked = await VariantPickerSheet.show(context, locationId: widget.location.id);
    if (picked == null) return;
    if (_lines.any((l) => l.variantId == picked.variant.id)) {
      SnackBarService.error('Barang ini sudah ada di daftar');
      return;
    }
    setState(() => _lines.add(_LineDraft(
          variantId: picked.variant.id,
          name: picked.label,
          isSerialized: picked.product.isSerialized,
          serialType: picked.product.serialType,
        )));
  }

  void _removeLine(int index) {
    final line = _lines[index];
    setState(() => _lines.removeAt(index));
    WidgetsBinding.instance.addPostFrameCallback((_) => line.dispose());
  }

  void _addUnit(_LineDraft line) {
    final unit = _UnitDraft();
    setState(() => line.units.add(unit));
    WidgetsBinding.instance.addPostFrameCallback((_) => unit.firstFocus.requestFocus());
  }

  void _removeUnit(_LineDraft line, int index) {
    final unit = line.units[index];
    setState(() => line.units.removeAt(index));
    WidgetsBinding.instance.addPostFrameCallback((_) => unit.dispose());
  }

  Future<void> _pickDate(bool due) async {
    final initial = (due ? _dueDate : _invoiceDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => due ? _dueDate = picked : _invoiceDate = picked);
  }

  String? _validateId(_LineDraft line, String? value, String label) {
    final v = ImeiValidator.normalize(value ?? '');
    if (line.usesImei) return ImeiValidator.validate(v, required: !_idsOptional, label: label);
    return v.isEmpty && !_idsOptional ? '$label wajib diisi' : null;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_supplierId == null) {
      SnackBarService.error('Pilih supplier');
      return;
    }
    if (_lines.isEmpty) {
      SnackBarService.error('Tambahkan minimal satu barang');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final dateFormat = DateFormat('yyyy-MM-dd');
    final data = {
      if (widget.receipt == null) 'location_id': widget.location.id,
      'supplier_id': _supplierId,
      'invoice_no': _invoiceNo.text.trim(),
      'invoice_date': _invoiceDate != null ? dateFormat.format(_invoiceDate!) : null,
      'due_date': _dueDate != null ? dateFormat.format(_dueDate!) : null,
      'note': _note.text.trim(),
      'items': _lines.map((l) => l.toJson()).toList(),
    };
    setState(() => _saving = true);
    try {
      final saved = await WarehouseService.saveReceipt(data, id: widget.receipt?.id);
      SnackBarService.success('Draf disimpan — periksa lalu posting untuk menambah stok');
      if (!mounted) return;
      if (widget.receipt == null) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ReceiptDetailPage(receiptId: saved.id)));
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtotal = _lines.fold<double>(0, (s, l) => s + l.subtotal);
    final tax = _lines.fold<double>(0, (s, l) => s + l.tax);
    final dateFormat = DateFormat('dd-MM-yyyy');

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: Text(widget.receipt == null ? 'Penerimaan Baru' : 'Edit ${widget.receipt!.number}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: cs.surface,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 24),
          children: [
            Text(widget.location.label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            SearchableDropdown<int>(
              key: ValueKey('supplier-${_suppliers.length}'),
              label: 'Supplier *',
              hintText: 'Pilih supplier',
              value: _supplierId,
              prefixIcon: Icons.business_outlined,
              items: _suppliers.map((s) => DropdownItem<int>(value: s.id, label: '${s.name} (${s.code})')).toList(),
              onChanged: (v) => setState(() => _supplierId = v),
            ),
            const SizedBox(height: 12),
            TextInput(label: 'No. faktur supplier', controller: _invoiceNo, prefixIcon: Icons.receipt_long_outlined),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(false),
                  icon: const Icon(Icons.event_outlined),
                  label: Text(_invoiceDate == null ? 'Tgl faktur' : dateFormat.format(_invoiceDate!)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(true),
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text(_dueDate == null ? 'Jatuh tempo' : dateFormat.format(_dueDate!)),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              Text('Barang (${_lines.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(onPressed: _addLine, icon: const Icon(Icons.add_rounded), label: const Text('Tambah barang')),
            ]),
            if (_idsOptional)
              Text('Di gudang, IMEI boleh dikosongkan dan diisi nanti sebelum unit dijual.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            for (var i = 0; i < _lines.length; i++) _buildLine(_lines[i], i),
            const SizedBox(height: 8),
            TextInput(label: 'Catatan', controller: _note, maxLines: 2, prefixIcon: Icons.notes),
            const SizedBox(height: 16),
            _TotalRow('Subtotal', subtotal),
            _TotalRow('PPN', tax),
            _TotalRow('Total', subtotal + tax, bold: true),
            const SizedBox(height: 20),
            CustomButton(
              text: 'Simpan Draf',
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

  Widget _buildLine(_LineDraft line, int index) {
    final cs = Theme.of(context).colorScheme;
    final firstLabel = line.usesImei ? (line.dual ? 'IMEI 1' : 'IMEI') : 'Nomor seri';
    return Container(
      key: ObjectKey(line),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text(line.name, style: const TextStyle(fontWeight: FontWeight.w700))),
            IconButton(icon: const Icon(Icons.delete_outline, color: AppTheme.destructive), onPressed: () => _removeLine(index)),
          ]),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  if (!line.isSerialized) ...[
                    SizedBox(
                      width: 90,
                      child: TextFormField(
                        controller: line.qty,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Jumlah', isDense: true),
                        onChanged: (_) => setState(() {}),
                        validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? 'Isi > 0' : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: TextFormField(
                      controller: line.cost,
                      keyboardType: TextInputType.number,
                      inputFormatters: [RupiahInputFormatter()],
                      decoration: const InputDecoration(labelText: 'Harga beli / unit (tanpa PPN)', isDense: true),
                      onChanged: (_) => setState(() {}),
                      validator: (v) => RupiahInputFormatter.parseRupiahAsDouble(v ?? '') == null ? 'Wajib diisi' : null,
                    ),
                  ),
                ]),
                Row(children: [
                  Checkbox(
                    value: line.ppn,
                    activeColor: AppTheme.gold,
                    onChanged: (v) => setState(() => line.ppn = v ?? false),
                  ),
                  const Text('PPN 11%'),
                  const Spacer(),
                  Text(CurrencyFormatter.formatToRupiah(line.subtotal + line.tax),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
                if (line.isSerialized) ...[
                  Row(children: [
                    Text('Unit (${line.units.length})', style: Theme.of(context).textTheme.labelLarge),
                    const Spacer(),
                    TextButton.icon(onPressed: () => _addUnit(line), icon: const Icon(Icons.add_rounded), label: const Text('Unit')),
                  ]),
                  for (var u = 0; u < line.units.length; u++)
                    Padding(
                      key: ObjectKey(line.units[u]),
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(children: [
                              TextFormField(
                                controller: line.units[u].first,
                                focusNode: line.units[u].firstFocus,
                                keyboardType: line.usesImei ? TextInputType.number : TextInputType.text,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(labelText: '${u + 1}. $firstLabel', isDense: true),
                                validator: (v) => _validateId(line, v, firstLabel),
                                onFieldSubmitted: (_) {
                                  if (line.dual) {
                                    line.units[u].secondFocus.requestFocus();
                                  } else if (u == line.units.length - 1) {
                                    _addUnit(line);
                                  }
                                },
                              ),
                              if (line.dual)
                                TextFormField(
                                  controller: line.units[u].second,
                                  focusNode: line.units[u].secondFocus,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(labelText: 'IMEI 2', isDense: true),
                                  validator: (v) => _validateId(line, v, 'IMEI 2'),
                                  onFieldSubmitted: (_) {
                                    if (u == line.units.length - 1) _addUnit(line);
                                  },
                                ),
                            ]),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: line.units.length == 1 ? null : () => _removeUnit(line, u),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final double value;
  final bool bold;
  const _TotalRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.gold) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Text(label, style: style),
        const Spacer(),
        Text(CurrencyFormatter.formatToRupiah(value), style: style),
      ]),
    );
  }
}
