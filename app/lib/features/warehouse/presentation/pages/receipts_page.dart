import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:gg_store_cashier/core/helper/currency_formatter.dart';
import 'package:gg_store_cashier/core/models/access.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/models/warehouse.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/services/warehouse_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import '../widgets/status_badge.dart';
import 'receipt_detail_page.dart';
import 'receipt_form_page.dart';

/// Goods receipts (penerimaan barang) at one location.
class ReceiptsPage extends ConsumerStatefulWidget {
  final Location location;
  const ReceiptsPage({super.key, required this.location});

  @override
  ConsumerState<ReceiptsPage> createState() => _ReceiptsPageState();
}

class _ReceiptsPageState extends ConsumerState<ReceiptsPage> {
  List<GoodsReceipt> _receipts = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all'; // all | draft | unpaid

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final receipts = await WarehouseService.getReceipts(
        locationId: widget.location.id,
        status: _filter == 'draft' ? 'draft' : null,
      );
      if (mounted) {
        setState(() => _receipts = _filter == 'unpaid'
            ? receipts.where((r) => r.paymentStatus == 'unpaid' || r.paymentStatus == 'partial').toList()
            : receipts);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final access = ref.watch(accessProvider).valueOrNull ?? UserAccess.empty;
    final canCreate = access.can('purchases.manage', widget.location.id);

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Penerimaan Barang', style: TextStyle(fontWeight: FontWeight.w600)),
          Text(widget.location.label, style: Theme.of(context).textTheme.bodySmall),
        ]),
        backgroundColor: cs.surface,
        elevation: 0,
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _open(ReceiptFormPage(location: widget.location)),
              backgroundColor: AppTheme.gold,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Penerimaan Baru'),
            )
          : null,
      body: Column(
        children: [
          Container(
            color: cs.surface,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Wrap(spacing: 8, children: [
              for (final f in const [('all', 'Semua'), ('draft', 'Draf'), ('unpaid', 'Belum lunas')])
                ChoiceChip(
                  label: Text(f.$2),
                  selected: _filter == f.$1,
                  selectedColor: AppTheme.gold.withValues(alpha: 0.15),
                  onSelected: (_) {
                    setState(() => _filter = f.$1);
                    _load();
                  },
                ),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.gold))
                : _error != null
                    ? Center(child: Text(_error!))
                    : _receipts.isEmpty
                        ? Center(child: Text('Belum ada penerimaan barang', style: TextStyle(color: cs.onSurfaceVariant)))
                        : RefreshIndicator(
                            color: AppTheme.gold,
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                              itemCount: _receipts.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, i) => _ReceiptTile(
                                receipt: _receipts[i],
                                onTap: () => _open(ReceiptDetailPage(receiptId: _receipts[i].id)),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptTile extends StatelessWidget {
  final GoodsReceipt receipt;
  final VoidCallback onTap;
  const _ReceiptTile({required this.receipt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = receipt.isDraft ? 'draft' : receipt.paymentStatus ?? 'posted';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant, width: 0.8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(receipt.supplierName, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      receipt.number,
                      if (receipt.invoiceNo != null) 'Faktur ${receipt.invoiceNo}',
                      '${receipt.itemQty} pcs',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  StatusBadge(receipt.isDraft ? 'Draf' : receiptPaymentLabel(receipt.paymentStatus),
                      color: StatusBadge.colorFor(status)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(CurrencyFormatter.formatToRupiah(receipt.grandTotal),
                    style: const TextStyle(color: AppTheme.gold, fontWeight: FontWeight.w700)),
                if (receipt.createdAt != null)
                  Text(DateFormat('dd-MM-yy').format(receipt.createdAt!.toLocal()), style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
