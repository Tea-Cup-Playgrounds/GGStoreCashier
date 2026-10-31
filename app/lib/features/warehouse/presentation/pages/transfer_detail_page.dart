import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:gg_store_cashier/core/helper/imei_validator.dart';
import 'package:gg_store_cashier/core/models/access.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/models/warehouse.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/services/warehouse_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import 'package:gg_store_cashier/shared/widgets/custom_button.dart';
import '../widgets/status_badge.dart';
import 'transfer_form_page.dart';

class TransferDetailPage extends ConsumerStatefulWidget {
  final String transferId;
  const TransferDetailPage({super.key, required this.transferId});

  @override
  ConsumerState<TransferDetailPage> createState() => _TransferDetailPageState();
}

class _TransferDetailPageState extends ConsumerState<TransferDetailPage> {
  StockTransfer? _transfer;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await WarehouseService.getTransfer(widget.transferId);
      if (mounted) setState(() => _transfer = t);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _run(Future<StockTransfer?> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      final updated = await action();
      SnackBarService.success(success);
      if (mounted && updated != null) setState(() => _transfer = updated);
    } catch (e) {
      SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lanjutkan')),
          ],
        ),
      ) ==
      true;

  Future<void> _send() async {
    final t = _transfer!;
    if (!await _confirm('Kirim Transfer', 'Stok di ${t.fromCode} akan dikurangi dan barang tercatat dalam pengiriman ke ${t.toCode}.')) return;
    await _run(() => WarehouseService.sendTransfer(t.id), 'Transfer dikirim');
  }

  Future<void> _cancel() async {
    if (!await _confirm('Batalkan Draf', 'Batalkan transfer ${_transfer!.number}?')) return;
    await _run(() async {
      await WarehouseService.cancelTransfer(_transfer!.id);
      await _load();
      return null;
    }, 'Transfer dibatalkan');
  }

  Future<void> _edit() async {
    final t = _transfer!;
    final from = Location(id: t.fromLocationId, code: t.fromCode, name: t.fromName ?? '', type: 'branch');
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => TransferFormPage(from: from, transfer: t)));
    if (saved == true) _load();
  }

  Future<void> _receive() async {
    final updated = await ReceiveTransferSheet.show(context, transfer: _transfer!);
    if (updated != null && mounted) setState(() => _transfer = updated);
  }

  Future<void> _resolve() async {
    final t = _transfer!;
    final note = TextEditingController();
    String action = 'return';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Selesaikan Selisih'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t.outstanding} barang masih dalam pengiriman.'),
            RadioGroup<String>(
              groupValue: action,
              onChanged: (v) => setLocal(() => action = v ?? 'return'),
              child: Column(children: [
                RadioListTile<String>(contentPadding: EdgeInsets.zero, value: 'return', title: Text('Kembalikan ke stok ${t.fromCode}')),
                const RadioListTile<String>(contentPadding: EdgeInsets.zero, value: 'write_off', title: Text('Hapus sebagai hilang')),
              ]),
            ),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Alasan *')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            TextButton(onPressed: () => Navigator.pop(ctx, note.text.trim().isNotEmpty), child: const Text('Simpan')),
          ],
        ),
      ),
    );
    final reason = note.text.trim();
    note.dispose();
    if (ok != true) return;
    await _run(() => WarehouseService.resolveTransfer(t.id, action: action, note: reason), 'Selisih diselesaikan');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = _transfer;
    final access = ref.watch(accessProvider).valueOrNull ?? UserAccess.empty;
    final fmt = DateFormat('dd-MM-yy HH:mm');

    Widget? action;
    if (t != null) {
      if (t.status == 'draft' && access.can('transfers.send', t.fromLocationId)) {
        action = CustomButton(text: 'Kirim', icon: Icons.local_shipping_outlined, isLoading: _busy, onPressed: _busy ? null : _send, fullWidth: true);
      } else if (t.status == 'sent' && access.can('transfers.receive', t.toLocationId)) {
        action = CustomButton(text: 'Terima Barang', icon: Icons.move_to_inbox_outlined, isLoading: _busy, onPressed: _busy ? null : _receive, fullWidth: true);
      } else if (t.outstanding > 0 && access.can('stock.adjust', t.fromLocationId)) {
        action = CustomButton(
            text: 'Selesaikan Selisih', variant: ButtonVariant.outline, isLoading: _busy, onPressed: _busy ? null : _resolve, fullWidth: true);
      }
    }

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: Text(t?.number ?? 'Transfer', style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: cs.surface,
        elevation: 0,
        actions: [
          if (t != null && t.status == 'draft' && access.can('transfers.create', t.fromLocationId)) ...[
            IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit', onPressed: _busy ? null : _edit),
            IconButton(icon: const Icon(Icons.block, color: AppTheme.destructive), tooltip: 'Batalkan', onPressed: _busy ? null : _cancel),
          ],
        ],
      ),
      bottomNavigationBar: action == null ? null : SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: action)),
      body: t == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator(color: AppTheme.gold))
          : RefreshIndicator(
              color: AppTheme.gold,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SectionCard(
                    title: '${t.fromCode} → ${t.toCode}',
                    trailing: StatusBadge(transferStatusLabel(t.status), color: StatusBadge.colorFor(t.status)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${t.fromName} → ${t.toName}', style: Theme.of(context).textTheme.bodySmall),
                      if (t.sentAt != null) Text('Dikirim ${fmt.format(t.sentAt!.toLocal())} · ${t.sentByName ?? ''}', style: Theme.of(context).textTheme.bodySmall),
                      if (t.receivedAt != null)
                        Text('Diterima ${fmt.format(t.receivedAt!.toLocal())} · ${t.receivedByName ?? ''}', style: Theme.of(context).textTheme.bodySmall),
                      if (t.note != null && t.note!.isNotEmpty) Text('Catatan: ${t.note}', style: Theme.of(context).textTheme.bodySmall),
                      if (t.receiveNote != null && t.receiveNote!.isNotEmpty)
                        Text('Catatan penerimaan: ${t.receiveNote}', style: Theme.of(context).textTheme.bodySmall),
                      if (t.outstanding > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('${t.outstanding} barang masih dalam pengiriman',
                              style: const TextStyle(color: AppTheme.destructive, fontWeight: FontWeight.w600)),
                        ),
                    ]),
                  ),
                  SectionCard(
                    title: 'Barang',
                    child: Column(children: [
                      for (final item in t.items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                              Text(item.qtyReceived == null ? '${item.qtySent}' : '${item.qtyReceived}/${item.qtySent}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: item.qtyReceived != null && item.qtyReceived! < item.qtySent ? AppTheme.destructive : null,
                                  )),
                            ]),
                            if (item.qtyResolved > 0)
                              Text('${item.qtyResolved} diselesaikan (kembali / hilang)', style: Theme.of(context).textTheme.bodySmall),
                            if (item.isSerialized)
                              Wrap(spacing: 6, runSpacing: 4, children: [
                                for (final u in item.units)
                                  Chip(
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    avatar: Icon(
                                      switch (u.outcome) {
                                        'received' => Icons.check_circle,
                                        'returned' => Icons.undo,
                                        'written_off' => Icons.cancel,
                                        _ => Icons.local_shipping_outlined,
                                      },
                                      size: 16,
                                      color: switch (u.outcome) {
                                        'received' => AppTheme.success,
                                        'written_off' => AppTheme.destructive,
                                        _ => cs.onSurfaceVariant,
                                      },
                                    ),
                                    label: Text(u.identifier, style: Theme.of(context).textTheme.labelSmall),
                                  ),
                              ]),
                          ]),
                        ),
                    ]),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Confirms what arrived. Quantity items default to the sent quantity; serialized units are
/// ticked by default, and scanning an IMEI ticks it. Returns the updated transfer.
class ReceiveTransferSheet extends StatefulWidget {
  final StockTransfer transfer;
  const ReceiveTransferSheet({super.key, required this.transfer});

  static Future<StockTransfer?> show(BuildContext context, {required StockTransfer transfer}) => showModalBottomSheet<StockTransfer>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ReceiveTransferSheet(transfer: transfer),
      );

  @override
  State<ReceiveTransferSheet> createState() => _ReceiveTransferSheetState();
}

class _ReceiveTransferSheetState extends State<ReceiveTransferSheet> {
  late final Map<String, TextEditingController> _qty = {
    for (final i in widget.transfer.items.where((i) => !i.isSerialized)) i.id: TextEditingController(text: i.qtySent.toString()),
  };
  late final Set<String> _arrived = {
    for (final i in widget.transfer.items.where((i) => i.isSerialized)) ...i.units.map((u) => u.unitId),
  };
  final _scan = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    _scan.dispose();
    _note.dispose();
    super.dispose();
  }

  void _onScan(String value) {
    final code = ImeiValidator.normalize(value);
    _scan.clear();
    if (code.isEmpty) return;
    for (final item in widget.transfer.items) {
      for (final u in item.units) {
        if (u.matches(code)) {
          setState(() => _arrived.add(u.unitId));
          return;
        }
      }
    }
    SnackBarService.error('$code tidak ada di transfer ini');
  }

  Future<void> _save() async {
    final qty = <String, int>{};
    for (final item in widget.transfer.items.where((i) => !i.isSerialized)) {
      final n = int.tryParse(_qty[item.id]!.text.trim());
      if (n == null || n < 0 || n > item.qtySent) {
        SnackBarService.error('Jumlah "${item.name}" harus 0–${item.qtySent}');
        return;
      }
      qty[item.id] = n;
    }
    final missing = [
      for (final item in widget.transfer.items.where((i) => i.isSerialized))
        for (final u in item.units)
          if (!_arrived.contains(u.unitId)) u.unitId,
    ];
    setState(() => _saving = true);
    try {
      final updated = await WarehouseService.receiveTransfer(widget.transfer.id,
          qtyReceived: qty, missingUnitIds: missing, note: _note.text.trim());
      SnackBarService.success(updated.status == 'received' ? 'Diterima lengkap' : 'Diterima sebagian — selisih dicatat');
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final serialized = widget.transfer.items.where((i) => i.isSerialized).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Terima ${widget.transfer.number}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(controller: scrollController, children: [
              for (final item in widget.transfer.items.where((i) => !i.isSerialized))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.name),
                  subtitle: Text('Dikirim ${item.qtySent}'),
                  trailing: SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _qty[item.id],
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Diterima', isDense: true),
                    ),
                  ),
                ),
              if (serialized.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _scan,
                  keyboardType: TextInputType.number,
                  onSubmitted: _onScan,
                  decoration: const InputDecoration(hintText: 'Scan IMEI untuk menandai diterima', prefixIcon: Icon(Icons.qr_code_scanner_rounded), isDense: true),
                ),
                for (final item in serialized) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  for (final u in item.units)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeColor: AppTheme.gold,
                      value: _arrived.contains(u.unitId),
                      title: Text(u.identifier),
                      onChanged: (v) => setState(() => v == true ? _arrived.add(u.unitId) : _arrived.remove(u.unitId)),
                    ),
                ],
              ],
              const SizedBox(height: 8),
              TextField(controller: _note, decoration: const InputDecoration(labelText: 'Catatan penerimaan (mis. dus rusak)')),
            ]),
          ),
          const SizedBox(height: 8),
          CustomButton(text: 'Konfirmasi Penerimaan', isLoading: _saving, onPressed: _saving ? null : _save, fullWidth: true),
        ]),
      ),
    );
  }
}
