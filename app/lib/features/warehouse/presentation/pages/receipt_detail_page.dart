import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:gg_store_cashier/core/helper/currency_formatter.dart';
import 'package:gg_store_cashier/core/helper/rupiah_input_formatter.dart';
import 'package:gg_store_cashier/core/models/access.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/models/warehouse.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/services/warehouse_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import 'package:gg_store_cashier/shared/widgets/custom_button.dart';
import 'package:gg_store_cashier/shared/widgets/text_input.dart';
import '../widgets/status_badge.dart';
import 'receipt_form_page.dart';

class ReceiptDetailPage extends ConsumerStatefulWidget {
  final String receiptId;
  const ReceiptDetailPage({super.key, required this.receiptId});

  @override
  ConsumerState<ReceiptDetailPage> createState() => _ReceiptDetailPageState();
}

class _ReceiptDetailPageState extends ConsumerState<ReceiptDetailPage> {
  GoodsReceipt? _receipt;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final receipt = await WarehouseService.getReceipt(widget.receiptId);
      if (mounted) setState(() => _receipt = receipt);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<bool> _confirm(String title, String message, {String action = 'Lanjutkan', bool danger = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: danger ? TextButton.styleFrom(foregroundColor: AppTheme.destructive) : null,
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _post() async {
    final r = _receipt!;
    final ok = await _confirm(
      'Posting Penerimaan',
      'Stok ${r.locationCode ?? ''} akan bertambah sesuai daftar barang. Setelah diposting, penerimaan tidak dapat diubah.',
      action: 'Posting',
    );
    if (!ok) return;
    await _run(() async {
      final posted = await WarehouseService.postReceipt(r.id);
      SnackBarService.success('Diposting — stok bertambah');
      if (mounted) setState(() => _receipt = posted);
    });
  }

  Future<void> _delete() async {
    if (!await _confirm('Hapus Draf', 'Hapus draf ${_receipt!.number}?', action: 'Hapus', danger: true)) return;
    await _run(() async {
      await WarehouseService.deleteReceipt(_receipt!.id);
      SnackBarService.success('Draf dihapus');
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  Future<void> _edit() async {
    final r = _receipt!;
    final location = Location(id: r.locationId, code: r.locationCode, name: r.locationName ?? '', type: r.locationType ?? 'branch');
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ReceiptFormPage(location: location, receipt: r)),
    );
    if (saved == true) _load();
  }

  Future<void> _pay() async {
    final paid = await SupplierPaymentSheet.show(context, receipt: _receipt!);
    if (paid == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = _receipt;
    final access = ref.watch(accessProvider).valueOrNull ?? UserAccess.empty;
    final canManage = r != null && access.can('purchases.manage', r.locationId);

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: Text(r?.number ?? 'Penerimaan Barang', style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: cs.surface,
        elevation: 0,
        actions: [
          if (r != null && r.isDraft && canManage) ...[
            IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit', onPressed: _busy ? null : _edit),
            IconButton(icon: const Icon(Icons.delete_outline, color: AppTheme.destructive), tooltip: 'Hapus', onPressed: _busy ? null : _delete),
          ],
        ],
      ),
      bottomNavigationBar: r == null || !canManage
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: r.isDraft
                    ? CustomButton(text: 'Posting ke Stok', icon: Icons.inventory_rounded, isLoading: _busy, onPressed: _busy ? null : _post, fullWidth: true)
                    : r.outstanding > 0
                        ? CustomButton(text: 'Catat Pembayaran', icon: Icons.payments_outlined, onPressed: _pay, fullWidth: true)
                        : const SizedBox.shrink(),
              ),
            ),
      body: r == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator(color: AppTheme.gold))
          : RefreshIndicator(
              color: AppTheme.gold,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SectionCard(
                    title: r.supplierName,
                    trailing: StatusBadge(r.isDraft ? 'Draf' : receiptPaymentLabel(r.paymentStatus),
                        color: StatusBadge.colorFor(r.isDraft ? 'draft' : r.paymentStatus ?? 'posted')),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _Info('Lokasi', '${r.locationCode ?? ''} · ${r.locationName ?? ''}'),
                      if (r.invoiceNo != null && r.invoiceNo!.isNotEmpty) _Info('No. faktur', r.invoiceNo!),
                      if (r.invoiceDate != null) _Info('Tgl faktur', r.invoiceDate!),
                      if (r.dueDate != null) _Info('Jatuh tempo', r.dueDate!),
                      if (r.postedAt != null)
                        _Info('Diposting', '${DateFormat('dd-MM-yy HH:mm').format(r.postedAt!.toLocal())} · ${r.postedByName ?? ''}'),
                      if (r.note != null && r.note!.isNotEmpty) _Info('Catatan', r.note!),
                    ]),
                  ),
                  SectionCard(
                    title: 'Barang',
                    child: Column(children: [
                      for (final item in r.items) _ItemRow(item: item),
                      const Divider(),
                      _Total('Subtotal', r.subtotal),
                      _Total('PPN', r.taxTotal),
                      _Total('Total', r.grandTotal, bold: true),
                      if (!r.isDraft) ...[
                        _Total('Dibayar', r.paidTotal),
                        _Total('Sisa', r.outstanding, color: r.outstanding > 0 ? AppTheme.destructive : AppTheme.success),
                      ],
                    ]),
                  ),
                  if (r.payments.isNotEmpty)
                    SectionCard(
                      title: 'Pembayaran',
                      child: Column(children: [
                        for (final p in r.payments)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.payments_outlined, color: AppTheme.success),
                            title: Text(CurrencyFormatter.formatToRupiah(p.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text([p.paidAt, paymentMethodLabel(p.method), if (p.reference != null) p.reference, p.createdByName]
                                .whereType<String>()
                                .join(' · ')),
                          ),
                      ]),
                    ),
                ],
              ),
            ),
    );
  }
}

class _Info extends StatelessWidget {
  final String label;
  final String value;
  const _Info(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 100,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Expanded(child: Text(value, style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final ReceiptItem item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(CurrencyFormatter.formatToRupiah(item.lineTotal), style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        Text(
          '${item.qty} × ${CurrencyFormatter.formatToRupiah(item.unitCost)}${item.taxRate > 0 ? ' + PPN ${item.taxRate.toStringAsFixed(0)}%' : ''}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        if (item.isSerialized)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              for (final u in item.units)
                Chip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: Text(u.imei1 ?? u.serialNumber ?? 'Tanpa IMEI',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: u.imei1 == null && u.serialNumber == null ? AppTheme.warning : null,
                          )),
                ),
            ]),
          ),
      ]),
    );
  }
}

class _Total extends StatelessWidget {
  final String label;
  final double value;
  final bool bold;
  final Color? color;
  const _Total(this.label, this.value, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color ?? (bold ? AppTheme.gold : null));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Text(label, style: style), const Spacer(), Text(CurrencyFormatter.formatToRupiah(value), style: style)]),
    );
  }
}

/// Records a payment against a posted receipt. Returns true when saved.
class SupplierPaymentSheet extends StatefulWidget {
  final GoodsReceipt receipt;
  const SupplierPaymentSheet({super.key, required this.receipt});

  static Future<bool?> show(BuildContext context, {required GoodsReceipt receipt}) => showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => SupplierPaymentSheet(receipt: receipt),
      );

  @override
  State<SupplierPaymentSheet> createState() => _SupplierPaymentSheetState();
}

class _SupplierPaymentSheetState extends State<SupplierPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: RupiahInputFormatter()
        .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: widget.receipt.outstanding.round().toString()))
        .text,
  );
  final _reference = TextEditingController();
  String _method = 'transfer';
  DateTime _paidAt = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final left = await WarehouseService.paySupplier(
        receiptId: widget.receipt.id,
        amount: RupiahInputFormatter.parseRupiahAsDouble(_amount.text)!,
        method: _method,
        reference: _reference.text.trim(),
        paidAt: DateFormat('yyyy-MM-dd').format(_paidAt),
      );
      SnackBarService.success(left > 0 ? 'Pembayaran dicatat, sisa ${CurrencyFormatter.formatToRupiah(left)}' : 'Tagihan lunas');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pembayaran ke ${widget.receipt.supplierName}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            Text('Sisa tagihan ${CurrencyFormatter.formatToRupiah(widget.receipt.outstanding)}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextInput(
              label: 'Jumlah *',
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [RupiahInputFormatter()],
              prefixIcon: Icons.payments_outlined,
              validator: (v) {
                final n = RupiahInputFormatter.parseRupiahAsDouble(v ?? '');
                if (n == null || n <= 0) return 'Isi jumlah pembayaran';
                if (n > widget.receipt.outstanding) return 'Melebihi sisa tagihan';
                return null;
              },
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'transfer', label: Text('Transfer')),
                ButtonSegment(value: 'cash', label: Text('Tunai')),
                ButtonSegment(value: 'giro', label: Text('Giro')),
                ButtonSegment(value: 'other', label: Text('Lain')),
              ],
              selected: {_method},
              onSelectionChanged: (s) => setState(() => _method = s.first),
            ),
            const SizedBox(height: 12),
            TextInput(label: 'Referensi (no. transfer / giro)', controller: _reference, prefixIcon: Icons.tag),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(context: context, initialDate: _paidAt, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (picked != null) setState(() => _paidAt = picked);
              },
              icon: const Icon(Icons.event_outlined),
              label: Text('Tanggal bayar: ${DateFormat('dd-MM-yyyy').format(_paidAt)}'),
            ),
            const SizedBox(height: 16),
            CustomButton(text: 'Simpan Pembayaran', isLoading: _saving, onPressed: _saving ? null : _save, fullWidth: true),
          ],
        ),
      ),
    );
  }
}
