import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:gg_store_cashier/core/helper/rupiah_input_formatter.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/services/catalog_service.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import 'package:gg_store_cashier/shared/widgets/custom_button.dart';
import 'package:gg_store_cashier/shared/widgets/text_input.dart';

/// Adds or removes stock of a non-serialized variant at one location. Returns true when saved.
class StockAdjustSheet extends StatefulWidget {
  final Location location;
  final String variantLabel;
  final int variantId;
  final int currentQty;

  const StockAdjustSheet({
    super.key,
    required this.location,
    required this.variantLabel,
    required this.variantId,
    required this.currentQty,
  });

  static Future<bool?> show(BuildContext context,
          {required Location location, required String variantLabel, required int variantId, required int currentQty}) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => StockAdjustSheet(
            location: location, variantLabel: variantLabel, variantId: variantId, currentQty: currentQty),
      );

  @override
  State<StockAdjustSheet> createState() => _StockAdjustSheetState();
}

class _StockAdjustSheetState extends State<StockAdjustSheet> {
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController();
  final _costController = TextEditingController();
  final _noteController = TextEditingController();
  bool _incoming = true;
  bool _saving = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final qty = int.parse(_qtyController.text.trim());
    setState(() => _saving = true);
    try {
      final newQty = await CatalogService.adjustStock(
        locationId: widget.location.id,
        variantId: widget.variantId,
        qtyChange: _incoming ? qty : -qty,
        unitCost: _incoming ? RupiahInputFormatter.parseRupiahAsDouble(_costController.text) : null,
        note: _noteController.text.trim(),
      );
      SnackBarService.success('Stok sekarang $newQty');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _costController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sesuaikan Stok', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('${widget.variantLabel} · ${widget.location.label} · stok saat ini ${widget.currentQty}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Tambah'), icon: Icon(Icons.add_rounded)),
                ButtonSegment(value: false, label: Text('Kurangi'), icon: Icon(Icons.remove_rounded)),
              ],
              selected: {_incoming},
              onSelectionChanged: (s) => setState(() => _incoming = s.first),
            ),
            const SizedBox(height: 16),
            TextInput(
              label: 'Jumlah *',
              hintText: '0',
              controller: _qtyController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              prefixIcon: Icons.numbers_outlined,
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                if (n == null || n <= 0) return 'Masukkan jumlah lebih dari 0';
                if (!_incoming && n > widget.currentQty) return 'Melebihi stok (${widget.currentQty})';
                return null;
              },
            ),
            if (_incoming) ...[
              const SizedBox(height: 12),
              TextInput(
                label: 'Harga pokok per unit (opsional)',
                hintText: 'Rp0',
                controller: _costController,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                prefixIcon: Icons.payments_outlined,
              ),
            ],
            const SizedBox(height: 12),
            TextInput(
              label: 'Alasan *',
              hintText: 'Contoh: stok awal, barang rusak, salah hitung',
              controller: _noteController,
              prefixIcon: Icons.edit_note_outlined,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Alasan wajib diisi' : null,
            ),
            const SizedBox(height: 20),
            CustomButton(text: 'Simpan', isLoading: _saving, onPressed: _saving ? null : _save, fullWidth: true),
          ],
        ),
      ),
    );
  }
}
