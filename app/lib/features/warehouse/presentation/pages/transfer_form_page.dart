import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/models/warehouse.dart';
import 'package:gg_store_cashier/core/services/catalog_service.dart';
import 'package:gg_store_cashier/core/services/warehouse_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/features/inventory/presentation/widgets/variant_picker_sheet.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import 'package:gg_store_cashier/shared/widgets/custom_button.dart';
import 'package:gg_store_cashier/shared/widgets/text_input.dart';
import '../widgets/unit_picker_sheet.dart';
import 'transfer_detail_page.dart';

class _Line {
  final int variantId;
  final String name;
  final bool isSerialized;
  /// On-hand at the source when picked; null when editing a draft (the server re-checks on send).
  final int? available;
  final TextEditingController qty;
  Set<String> unitIds;

  _Line({required this.variantId, required this.name, required this.isSerialized, this.available, int qty = 1, Set<String>? unitIds})
      : qty = TextEditingController(text: qty.toString()),
        unitIds = unitIds ?? {};

  Map<String, dynamic> toJson() => isSerialized
      ? {'variant_id': variantId, 'unit_ids': unitIds.toList()}
      : {'variant_id': variantId, 'qty': int.tryParse(qty.text.trim()) ?? 0};
}

/// Create a draft transfer out of [from], or edit [transfer] (draft only).
class TransferFormPage extends StatefulWidget {
  final Location from;
  final StockTransfer? transfer;

  const TransferFormPage({super.key, required this.from, this.transfer});

  @override
  State<TransferFormPage> createState() => _TransferFormPageState();
}

class _TransferFormPageState extends State<TransferFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _note = TextEditingController();
  final _lines = <_Line>[];
  List<Location> _destinations = [];
  int? _toId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.transfer;
    if (t != null) {
      _toId = t.toLocationId;
      _note.text = t.note ?? '';
      _lines.addAll(t.items.map((i) => _Line(
            variantId: i.variantId,
            name: i.name,
            isSerialized: i.isSerialized,
            qty: i.qtySent,
            unitIds: i.units.map((u) => u.unitId).toSet(),
          )));
    }
    _loadDestinations();
  }

  Future<void> _loadDestinations() async {
    try {
      final all = await CatalogService.getLocations(destinations: true);
      if (mounted) setState(() => _destinations = all.where((l) => l.id != widget.from.id && l.isActive).toList());
    } catch (e) {
      SnackBarService.error('Gagal memuat lokasi tujuan: $e');
    }
  }

  @override
  void dispose() {
    _note.dispose();
    for (final l in _lines) {
      l.qty.dispose();
    }
    super.dispose();
  }

  Future<void> _addLine() async {
    final picked = await VariantPickerSheet.show(context, locationId: widget.from.id, onlyInStock: true);
    if (picked == null || !mounted) return;
    if (_lines.any((l) => l.variantId == picked.variant.id)) {
      SnackBarService.error('Barang ini sudah ada di daftar');
      return;
    }
    final line = _Line(
      variantId: picked.variant.id,
      name: picked.label,
      isSerialized: picked.product.isSerialized,
      available: picked.variant.onHand ?? 0,
    );
    if (line.isSerialized) {
      final units = await UnitPickerSheet.show(context, locationId: widget.from.id, variantId: line.variantId, title: line.name);
      if (units == null || units.isEmpty) return;
      line.unitIds = units;
    }
    setState(() => _lines.add(line));
  }

  Future<void> _editUnits(_Line line) async {
    final units = await UnitPickerSheet.show(context,
        locationId: widget.from.id, variantId: line.variantId, title: line.name, selected: line.unitIds);
    if (units != null && units.isNotEmpty) setState(() => line.unitIds = units);
  }

  void _removeLine(int index) {
    final line = _lines[index];
    setState(() => _lines.removeAt(index));
    WidgetsBinding.instance.addPostFrameCallback((_) => line.qty.dispose());
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_toId == null) {
      SnackBarService.error('Pilih lokasi tujuan');
      return;
    }
    if (_lines.isEmpty) {
      SnackBarService.error('Tambahkan minimal satu barang');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final saved = await WarehouseService.saveTransfer(
        id: widget.transfer?.id,
        fromLocationId: widget.from.id,
        toLocationId: _toId!,
        note: _note.text.trim(),
        items: _lines.map((l) => l.toJson()).toList(),
      );
      SnackBarService.success('Draf transfer disimpan — kirim untuk memindahkan stok');
      if (!mounted) return;
      if (widget.transfer == null) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => TransferDetailPage(transferId: saved.id)));
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
    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: Text(widget.transfer == null ? 'Transfer Baru' : 'Edit ${widget.transfer!.number}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: cs.surface,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 24),
          children: [
            Row(children: [
              const Icon(Icons.outbox_outlined, size: 18),
              const SizedBox(width: 6),
              Text('Dari ${widget.from.label}', style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _toId,
              decoration: const InputDecoration(labelText: 'Tujuan *', prefixIcon: Icon(Icons.move_to_inbox_outlined)),
              items: _destinations
                  .map((l) => DropdownMenuItem(value: l.id, child: Text(l.label)))
                  .toList(),
              onChanged: (v) => setState(() => _toId = v),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Text('Barang (${_lines.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(onPressed: _addLine, icon: const Icon(Icons.add_rounded), label: const Text('Tambah barang')),
            ]),
            for (var i = 0; i < _lines.length; i++)
              Container(
                key: ObjectKey(_lines[i]),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant, width: 0.8),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_lines[i].name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(_lines[i].available == null ? 'Draf' : 'Tersedia ${_lines[i].available}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  if (_lines[i].isSerialized)
                    TextButton.icon(
                      onPressed: () => _editUnits(_lines[i]),
                      icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                      label: Text('${_lines[i].unitIds.length} unit'),
                    )
                  else
                    SizedBox(
                      width: 80,
                      child: TextFormField(
                        controller: _lines[i].qty,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Jumlah', isDense: true),
                        validator: (v) {
                          final n = int.tryParse(v ?? '') ?? 0;
                          if (n <= 0) return '> 0';
                          final max = _lines[i].available;
                          if (max != null && n > max) return 'Maks $max';
                          return null;
                        },
                      ),
                    ),
                  IconButton(icon: const Icon(Icons.delete_outline, color: AppTheme.destructive), onPressed: () => _removeLine(i)),
                ]),
              ),
            const SizedBox(height: 8),
            TextInput(label: 'Catatan', controller: _note, maxLines: 2, prefixIcon: Icons.notes),
            const SizedBox(height: 20),
            CustomButton(text: 'Simpan Draf', size: ButtonSize.large, isLoading: _saving, onPressed: _saving ? null : _save, fullWidth: true),
          ],
        ),
      ),
    );
  }
}
