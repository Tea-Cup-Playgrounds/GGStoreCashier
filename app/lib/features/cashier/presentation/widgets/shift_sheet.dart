import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gg_store_cashier/core/helper/currency_formatter.dart';
import 'package:gg_store_cashier/core/helper/rupiah_input_formatter.dart';
import 'package:gg_store_cashier/core/models/sales.dart';
import 'package:gg_store_cashier/core/services/sales_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import 'package:gg_store_cashier/shared/widgets/custom_button.dart';
import 'package:gg_store_cashier/shared/widgets/text_input.dart';

/// Opens a shift (no [session]) or shows the open one with its totals and closes it after the
/// cash is counted. Pops with the open session, or null once closed.
class ShiftSheet extends StatefulWidget {
  final int locationId;
  final CashSession? session;

  const ShiftSheet({super.key, required this.locationId, this.session});

  /// Returns (changed, session): changed is false when the sheet was dismissed.
  static Future<(bool, CashSession?)> show(BuildContext context, {required int locationId, CashSession? session}) async {
    final result = await showModalBottomSheet<(bool, CashSession?)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ShiftSheet(locationId: locationId, session: session),
    );
    return result ?? (false, session);
  }

  @override
  State<ShiftSheet> createState() => _ShiftSheetState();
}

class _ShiftSheetState extends State<ShiftSheet> {
  final _cash = TextEditingController();
  final _note = TextEditingController();
  CashSession? _session;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    if (_session != null) _refresh();
  }

  @override
  void dispose() {
    _cash.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final s = await SalesService.getShift(_session!.id);
      if (mounted) setState(() => _session = s);
    } catch (e) {
      SnackBarService.error(e.toString());
    }
  }

  Future<void> _open() async {
    setState(() => _busy = true);
    try {
      final s = await SalesService.openShift(
        locationId: widget.locationId,
        openingCash: RupiahInputFormatter.parseRupiahAsDouble(_cash.text) ?? 0,
      );
      SnackBarService.success('Shift dibuka');
      if (mounted) Navigator.pop(context, (true, s));
    } catch (e) {
      SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    final counted = RupiahInputFormatter.parseRupiahAsDouble(_cash.text);
    if (counted == null) {
      SnackBarService.error('Isi jumlah uang tunai di laci');
      return;
    }
    setState(() => _busy = true);
    try {
      final (closed, message) = await SalesService.closeShift(_session!.id, countedCash: counted, note: _note.text.trim());
      if ((closed.difference ?? 0) == 0) {
        SnackBarService.success(message);
      } else {
        SnackBarService.show(message, backgroundColor: AppTheme.warning, duration: const Duration(seconds: 4));
      }
      if (mounted) Navigator.pop(context, (true, null));
    } catch (e) {
      SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s == null ? 'Buka Shift' : 'Shift Berjalan', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (s == null) ...[
              const Text('Shift bersifat opsional. Dengan shift, kas di laci dicocokkan saat tutup.'),
              const SizedBox(height: 12),
              TextInput(
                label: 'Modal awal (uang di laci)',
                hintText: 'Rp0',
                controller: _cash,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                prefixIcon: Icons.point_of_sale_outlined,
              ),
              const SizedBox(height: 16),
              CustomButton(text: 'Buka Shift', isLoading: _busy, onPressed: _busy ? null : _open, fullWidth: true),
            ] else ...[
              if (s.openedAt != null) Text('Dibuka ${DateFormat('dd-MM-yy HH:mm').format(s.openedAt!.toLocal())}'),
              const SizedBox(height: 8),
              _row('Modal awal', s.openingCash),
              _row('Penjualan (${s.salesCount})', s.salesTotal),
              for (final m in s.byMethod) _row('  ${m.name}', m.amount),
              const Divider(),
              _row('Kas seharusnya', s.expectedCash, bold: true),
              const SizedBox(height: 12),
              TextInput(
                label: 'Uang tunai dihitung *',
                hintText: 'Rp0',
                controller: _cash,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                prefixIcon: Icons.payments_outlined,
              ),
              const SizedBox(height: 8),
              TextInput(label: 'Catatan', controller: _note, prefixIcon: Icons.notes),
              const SizedBox(height: 16),
              CustomButton(text: 'Tutup Shift', isLoading: _busy, onPressed: _busy ? null : _close, fullWidth: true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, double value, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Text(label, style: style), const Spacer(), Text(CurrencyFormatter.formatToRupiah(value), style: style)]),
    );
  }
}
