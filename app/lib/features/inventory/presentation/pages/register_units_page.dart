import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:gg_store_cashier/core/helper/imei_validator.dart';
import 'package:gg_store_cashier/core/helper/rupiah_input_formatter.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/services/catalog_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import 'package:gg_store_cashier/shared/widgets/custom_button.dart';
import 'package:gg_store_cashier/shared/widgets/text_input.dart';

/// Registers several serialized units at once (opening stock / correction). Pops with the
/// number of units registered.
///
/// Scanner-friendly: pressing enter (which keyboard-mode scanners send) moves to the next
/// IMEI field and adds a new row after the last one. At a warehouse IMEIs may be left empty
/// and filled in later.
class RegisterUnitsPage extends StatefulWidget {
  final CatalogProduct product;
  final ProductVariant variant;
  final Location location;

  const RegisterUnitsPage({super.key, required this.product, required this.variant, required this.location});

  @override
  State<RegisterUnitsPage> createState() => _RegisterUnitsPageState();
}

class _UnitRow {
  final first = TextEditingController();
  final second = TextEditingController();
  final firstFocus = FocusNode();
  final secondFocus = FocusNode();

  void dispose() {
    first.dispose();
    second.dispose();
    firstFocus.dispose();
    secondFocus.dispose();
  }
}

class _RegisterUnitsPageState extends State<RegisterUnitsPage> {
  final _formKey = GlobalKey<FormState>();
  final _rows = <_UnitRow>[_UnitRow()];
  final _cost = TextEditingController();
  final _note = TextEditingController();
  final _blankCount = TextEditingController(text: '1');
  String _grade = 'new';
  bool _saving = false;

  bool get _usesImei => widget.product.serialType != SerialType.serial;
  bool get _dual => widget.product.serialType == SerialType.imeiDual;
  bool get _idsOptional => widget.location.isWarehouse;

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _cost.dispose();
    _note.dispose();
    _blankCount.dispose();
    super.dispose();
  }

  // Controllers are disposed after the frame that removes their fields.
  void _removeRow(int index) {
    final row = _rows[index];
    setState(() => _rows.removeAt(index));
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
  }

  void _addRow({bool focus = true}) {
    final row = _UnitRow();
    setState(() => _rows.add(row));
    if (focus) WidgetsBinding.instance.addPostFrameCallback((_) => row.firstFocus.requestFocus());
  }

  void _onSubmittedFirst(int index) {
    final row = _rows[index];
    if (_dual) {
      row.secondFocus.requestFocus();
    } else if (index == _rows.length - 1) {
      _addRow();
    } else {
      _rows[index + 1].firstFocus.requestFocus();
    }
  }

  void _onSubmittedSecond(int index) {
    if (index == _rows.length - 1) {
      _addRow();
    } else {
      _rows[index + 1].firstFocus.requestFocus();
    }
  }

  /// Every identifier entered across all rows, for duplicate checks inside the batch.
  List<String> get _allIds => [
        for (final r in _rows) ...[ImeiValidator.normalize(r.first.text), if (_dual) ImeiValidator.normalize(r.second.text)]
      ].where((v) => v.isNotEmpty).toList();

  String? _validateId(String? value, String label, {String? other}) {
    final v = ImeiValidator.normalize(value ?? '');
    final error = _usesImei
        ? ImeiValidator.validate(v, required: !_idsOptional, label: label)
        : (v.isEmpty && !_idsOptional ? '$label wajib diisi' : null);
    if (error != null) return error;
    if (v.isEmpty) return null;
    if (other != null && v == ImeiValidator.normalize(other)) return 'IMEI 1 dan 2 tidak boleh sama';
    if (_allIds.where((id) => id == v).length > 1) return 'Duplikat di daftar ini';
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    // A trailing empty row (left by the scanner flow) is ignored.
    while (_rows.length > 1 && _rows.last.first.text.trim().isEmpty && _rows.last.second.text.trim().isEmpty) {
      _removeRow(_rows.length - 1);
    }
    // Validate after the trimmed rows are gone from the tree.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_formKey.currentState!.validate()) return;

    final cost = RupiahInputFormatter.parseRupiahAsDouble(_cost.text) ?? 0;
    final units = <Map<String, dynamic>>[];
    final withIds = _rows.where((r) => r.first.text.trim().isNotEmpty || r.second.text.trim().isNotEmpty);
    for (final r in withIds) {
      final first = ImeiValidator.normalize(r.first.text);
      final second = ImeiValidator.normalize(r.second.text);
      units.add({
        if (_usesImei) 'imei1': first.isEmpty ? null : first else 'serial_number': first.isEmpty ? null : first,
        if (_dual) 'imei2': second.isEmpty ? null : second,
        'unit_cost': cost,
        'condition_grade': _grade,
      });
    }
    if (_idsOptional && units.isEmpty) {
      final blank = int.tryParse(_blankCount.text.trim()) ?? 0;
      for (var i = 0; i < blank; i++) {
        units.add({'unit_cost': cost, 'condition_grade': _grade});
      }
    }
    if (units.isEmpty) {
      SnackBarService.error('Isi minimal satu unit');
      return;
    }

    setState(() => _saving = true);
    try {
      final count = await CatalogService.registerUnits(
        locationId: widget.location.id,
        variantId: widget.variant.id,
        units: units,
        note: _note.text.trim(),
      );
      SnackBarService.success('$count unit didaftarkan');
      if (mounted) Navigator.of(context).pop(count);
    } catch (e) {
      SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final firstLabel = _usesImei ? (_dual ? 'IMEI 1' : 'IMEI') : 'Nomor seri';

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('Daftarkan Unit', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: cs.surface,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 24),
          children: [
            Text(widget.product.variantLabel(widget.variant),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            Text(widget.location.label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            if (_idsOptional) ...[
              const SizedBox(height: 8),
              Text('Di gudang, IMEI boleh dikosongkan dan diisi nanti sebelum unit dijual.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.warning)),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: TextInput(
                  label: 'Harga pokok per unit',
                  hintText: 'Rp0',
                  controller: _cost,
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  prefixIcon: Icons.payments_outlined,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'new', label: Text('Baru')),
                ButtonSegment(value: 'A', label: Text('Bekas A')),
                ButtonSegment(value: 'B', label: Text('B')),
                ButtonSegment(value: 'C', label: Text('C')),
              ],
              selected: {_grade},
              onSelectionChanged: (s) => setState(() => _grade = s.first),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Text('Unit (${_rows.length})', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(onPressed: _addRow, icon: const Icon(Icons.add_rounded), label: const Text('Tambah baris')),
            ]),
            for (var i = 0; i < _rows.length; i++)
              Container(
                key: ObjectKey(_rows[i]),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant, width: 0.8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 14, right: 8),
                      child: Text('${i + 1}', style: Theme.of(context).textTheme.labelLarge),
                    ),
                    Expanded(
                      child: Column(children: [
                        TextFormField(
                          controller: _rows[i].first,
                          focusNode: _rows[i].firstFocus,
                          autofocus: i == 0,
                          keyboardType: _usesImei ? TextInputType.number : TextInputType.text,
                          inputFormatters: _usesImei ? [FilteringTextInputFormatter.digitsOnly] : null,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) => _onSubmittedFirst(i),
                          decoration: InputDecoration(labelText: firstLabel, isDense: true),
                          validator: (v) => _validateId(v, firstLabel, other: _dual ? _rows[i].second.text : null),
                        ),
                        if (_dual) ...[
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _rows[i].second,
                            focusNode: _rows[i].secondFocus,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) => _onSubmittedSecond(i),
                            decoration: const InputDecoration(labelText: 'IMEI 2', isDense: true),
                            validator: (v) => _validateId(v, 'IMEI 2', other: _rows[i].first.text),
                          ),
                        ],
                      ]),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _rows.length == 1 ? null : () => _removeRow(i),
                    ),
                  ],
                ),
              ),
            if (_idsOptional) ...[
              const SizedBox(height: 4),
              TextInput(
                label: 'Atau: jumlah unit tanpa IMEI',
                hintText: 'Dipakai bila semua baris di atas kosong',
                controller: _blankCount,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                prefixIcon: Icons.numbers_outlined,
              ),
            ],
            const SizedBox(height: 12),
            TextInput(
              label: 'Catatan (opsional)',
              hintText: 'Contoh: stok awal, pindahan dari sistem lama',
              controller: _note,
              prefixIcon: Icons.edit_note_outlined,
            ),
            const SizedBox(height: 24),
            CustomButton(
              text: 'Simpan Unit',
              size: ButtonSize.large,
              isLoading: _saving,
              onPressed: _saving ? null : _submit,
              fullWidth: true,
            ),
          ],
        ),
      ),
    );
  }
}
