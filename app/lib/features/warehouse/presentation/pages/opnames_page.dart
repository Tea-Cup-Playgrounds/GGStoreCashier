import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:gg_store_cashier/core/models/access.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/models/warehouse.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/services/warehouse_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import '../widgets/status_badge.dart';
import 'opname_detail_page.dart';

/// Stock counts (stok opname) at one location.
class OpnamesPage extends ConsumerStatefulWidget {
  final Location location;
  const OpnamesPage({super.key, required this.location});

  @override
  ConsumerState<OpnamesPage> createState() => _OpnamesPageState();
}

class _OpnamesPageState extends ConsumerState<OpnamesPage> {
  List<StockOpname> _opnames = [];
  bool _loading = true;
  String? _error;
  bool _starting = false;

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
      final opnames = await WarehouseService.getOpnames(locationId: widget.location.id);
      if (mounted) setState(() => _opnames = opnames);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(String id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OpnameDetailPage(opnameId: id)));
    _load();
  }

  Future<void> _start() async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mulai Stok Opname'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Stok sistem di ${widget.location.label} dicatat sekarang sebagai pembanding. '
              'Penjualan selama penghitungan tetap tercatat.'),
          const SizedBox(height: 12),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Catatan (opsional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mulai')),
        ],
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (ok != true) return;
    setState(() => _starting = true);
    try {
      final opname = await WarehouseService.startOpname(locationId: widget.location.id, note: text);
      await _open(opname.id);
    } catch (e) {
      SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final access = ref.watch(accessProvider).valueOrNull ?? UserAccess.empty;
    final canStart = access.can('stock.opname', widget.location.id) && !_opnames.any((o) => o.isCounting);

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Stok Opname', style: TextStyle(fontWeight: FontWeight.w600)),
          Text(widget.location.label, style: Theme.of(context).textTheme.bodySmall),
        ]),
        backgroundColor: cs.surface,
        elevation: 0,
      ),
      floatingActionButton: canStart
          ? FloatingActionButton.extended(
              onPressed: _starting ? null : _start,
              backgroundColor: AppTheme.gold,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Mulai Opname'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.gold))
          : _error != null
              ? Center(child: Text(_error!))
              : _opnames.isEmpty
                  ? Center(child: Text('Belum ada stok opname', style: TextStyle(color: cs.onSurfaceVariant)))
                  : RefreshIndicator(
                      color: AppTheme.gold,
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                        itemCount: _opnames.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final o = _opnames[i];
                          return Material(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: cs.outlineVariant, width: 0.8),
                              ),
                              onTap: () => _open(o.id),
                              title: Text(o.number, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text([
                                '${o.itemCount} barang',
                                if (o.createdAt != null) DateFormat('dd-MM-yy').format(o.createdAt!.toLocal()),
                                if (o.note != null && o.note!.isNotEmpty) o.note!,
                              ].join(' · ')),
                              trailing: StatusBadge(opnameStatusLabel(o.status), color: StatusBadge.colorFor(o.status)),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
