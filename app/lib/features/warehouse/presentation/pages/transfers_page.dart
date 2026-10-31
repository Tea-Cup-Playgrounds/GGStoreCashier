import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:gg_store_cashier/core/models/access.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/models/warehouse.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/services/warehouse_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import '../widgets/status_badge.dart';
import 'transfer_detail_page.dart';
import 'transfer_form_page.dart';

/// Transfers leaving (Keluar) or arriving at (Masuk) one location.
class TransfersPage extends ConsumerStatefulWidget {
  final Location location;
  const TransfersPage({super.key, required this.location});

  @override
  ConsumerState<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends ConsumerState<TransfersPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)..addListener(_onTab);
  List<StockTransfer> _transfers = [];
  bool _loading = true;
  String? _error;

  String get _direction => _tabs.index == 0 ? 'out' : 'in';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _onTab() {
    if (!_tabs.indexIsChanging) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final transfers = await WarehouseService.getTransfers(locationId: widget.location.id, direction: _direction);
      if (mounted) setState(() => _transfers = transfers);
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
    final canCreate = access.can('transfers.create', widget.location.id);

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Transfer Stok', style: TextStyle(fontWeight: FontWeight.w600)),
          Text(widget.location.label, style: Theme.of(context).textTheme.bodySmall),
        ]),
        backgroundColor: cs.surface,
        elevation: 0,
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppTheme.gold,
          indicatorColor: AppTheme.gold,
          unselectedLabelColor: cs.onSurfaceVariant,
          tabs: const [Tab(text: 'Keluar'), Tab(text: 'Masuk')],
        ),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _open(TransferFormPage(from: widget.location)),
              backgroundColor: AppTheme.gold,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('Transfer Baru'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.gold))
          : _error != null
              ? Center(child: Text(_error!))
              : _transfers.isEmpty
                  ? Center(child: Text('Belum ada transfer', style: TextStyle(color: cs.onSurfaceVariant)))
                  : RefreshIndicator(
                      color: AppTheme.gold,
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                        itemCount: _transfers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final t = _transfers[i];
                          final other = _direction == 'out' ? 'Ke ${t.toCode} · ${t.toName}' : 'Dari ${t.fromCode} · ${t.fromName}';
                          return Material(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: cs.outlineVariant, width: 0.8),
                              ),
                              onTap: () => _open(TransferDetailPage(transferId: t.id)),
                              title: Text(other, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text([
                                t.number,
                                '${t.qtyTotal} pcs',
                                if (t.createdAt != null) DateFormat('dd-MM-yy').format(t.createdAt!.toLocal()),
                              ].join(' · ')),
                              trailing: StatusBadge(
                                t.resolvedAt != null && t.status == 'partially_received' ? 'Selesai (selisih)' : transferStatusLabel(t.status),
                                color: StatusBadge.colorFor(t.resolvedAt != null ? 'received' : t.status),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
