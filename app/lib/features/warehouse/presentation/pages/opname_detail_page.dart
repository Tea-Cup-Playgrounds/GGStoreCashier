import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/helper/imei_validator.dart';
import 'package:gg_store_cashier/core/models/access.dart';
import 'package:gg_store_cashier/core/models/warehouse.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/services/warehouse_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import 'package:gg_store_cashier/shared/widgets/custom_button.dart';
import '../widgets/status_badge.dart';

/// Counting screen: enter counted quantities for accessories, scan IMEIs for phones, then approve.
class OpnameDetailPage extends ConsumerStatefulWidget {
  final String opnameId;
  const OpnameDetailPage({super.key, required this.opnameId});

  @override
  ConsumerState<OpnameDetailPage> createState() => _OpnameDetailPageState();
}

class _OpnameDetailPageState extends ConsumerState<OpnameDetailPage> {
  StockOpname? _opname;
  String? _error;
  bool _busy = false;
  final _scan = TextEditingController();
  final _scanFocus = FocusNode();
  final _search = TextEditingController();
  final _counts = <int, TextEditingController>{};
  final _dirty = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scan.dispose();
    _scanFocus.dispose();
    _search.dispose();
    for (final c in _counts.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply(StockOpname opname) {
    for (final item in opname.items.where((i) => !i.isSerialized)) {
      if (_dirty.contains(item.variantId)) continue;
      final controller = _counts.putIfAbsent(item.variantId, TextEditingController.new);
      controller.text = item.countedQty?.toString() ?? '';
    }
    setState(() => _opname = opname);
  }

  Future<void> _load() async {
    try {
      _apply(await WarehouseService.getOpname(widget.opnameId));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _saveCounts() async {
    if (_dirty.isEmpty) return;
    final counts = <int, int?>{
      for (final id in _dirty) id: _counts[id]!.text.trim().isEmpty ? null : int.tryParse(_counts[id]!.text.trim()),
    };
    setState(() => _busy = true);
    try {
      final updated = await WarehouseService.saveCounts(widget.opnameId, counts);
      _dirty.clear();
      _apply(updated);
      SnackBarService.success('Hitungan disimpan');
    } catch (e) {
      SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onScan(String value) async {
    final code = ImeiValidator.normalize(value);
    _scan.clear();
    _scanFocus.requestFocus();
    if (code.isEmpty) return;
    try {
      final result = await WarehouseService.scanOpname(widget.opnameId, code);
      if (result.result == 'found') {
        SnackBarService.success(result.message);
      } else if (result.result == 'already') {
        SnackBarService.show(result.message, backgroundColor: AppTheme.warning);
      } else {
        SnackBarService.error(result.message);
      }
      await _load();
    } catch (e) {
      SnackBarService.error(e.toString());
    }
  }

  Future<void> _approve() async {
    if (_dirty.isNotEmpty) await _saveCounts();
    final o = _opname!;
    final qtyItems = o.items.where((i) => !i.isSerialized);
    final uncounted = qtyItems.where((i) => i.countedQty == null).length;
    final variances = qtyItems.where((i) => (i.variance ?? 0) != 0).length;
    final missingUnits = o.items.where((i) => i.isSerialized).fold<int>(0, (s, i) => s + i.units.where((u) => !u.found && u.status == 'in_stock').length);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Setujui Stok Opname'),
        content: Text([
          '$variances barang akan disesuaikan.',
          if (missingUnits > 0) '$missingUnits unit ber-IMEI tidak ditemukan dan akan dihapus dari stok.',
          if (uncounted > 0) '$uncounted barang belum dihitung dan tidak diubah.',
          'Tindakan ini tidak dapat dibatalkan.',
        ].join('\n\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Setujui')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final summary = await WarehouseService.approveOpname(o.id);
      SnackBarService.success('Disetujui: ${summary['adjusted']} barang disesuaikan, ${summary['unitsWrittenOff']} unit dihapus');
      await _load();
    } catch (e) {
      SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan Stok Opname'),
        content: const Text('Hitungan dibuang dan stok tidak diubah.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Kembali')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
            child: const Text('Batalkan'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await WarehouseService.cancelOpname(_opname!.id);
      SnackBarService.success('Stok opname dibatalkan');
      await _load();
    } catch (e) {
      SnackBarService.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final o = _opname;
    final access = ref.watch(accessProvider).valueOrNull ?? UserAccess.empty;
    final canCount = o != null && o.isCounting && access.can('stock.opname', o.locationId);
    final q = _search.text.trim().toLowerCase();
    final items = o == null
        ? <OpnameItem>[]
        : o.items
            .where((i) => q.isEmpty || i.name.toLowerCase().contains(q) || (i.sku ?? '').toLowerCase().contains(q) || (i.barcode ?? '') == q)
            .toList();

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: Text(o?.number ?? 'Stok Opname', style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: cs.surface,
        elevation: 0,
        actions: [
          if (canCount) IconButton(icon: const Icon(Icons.block, color: AppTheme.destructive), tooltip: 'Batalkan', onPressed: _cancel),
        ],
      ),
      bottomNavigationBar: canCount
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  Expanded(
                    child: CustomButton(
                      text: _dirty.isEmpty ? 'Tersimpan' : 'Simpan (${_dirty.length})',
                      variant: ButtonVariant.outline,
                      onPressed: _busy || _dirty.isEmpty ? null : _saveCounts,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: CustomButton(text: 'Setujui', isLoading: _busy, onPressed: _busy ? null : _approve)),
                ]),
              ),
            )
          : null,
      body: o == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator(color: AppTheme.gold))
          : Column(
              children: [
                Container(
                  color: cs.surface,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: Text('${o.locationCode} · ${o.locationName}', style: Theme.of(context).textTheme.bodySmall)),
                      StatusBadge(opnameStatusLabel(o.status), color: StatusBadge.colorFor(o.status)),
                    ]),
                    if (canCount) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _scan,
                        focusNode: _scanFocus,
                        keyboardType: TextInputType.number,
                        onSubmitted: _onScan,
                        decoration: const InputDecoration(
                          hintText: 'Scan IMEI / serial unit yang ada di rak',
                          prefixIcon: Icon(Icons.qr_code_scanner_rounded),
                          isDense: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(hintText: 'Cari barang', prefixIcon: Icon(Icons.search), isDense: true),
                    ),
                  ]),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      for (final item in items) _buildItem(item, canCount),
                      if (o.extras.isNotEmpty)
                        SectionCard(
                          title: 'Temuan di luar daftar (${o.extras.length})',
                          child: Column(children: [
                            for (final e in o.extras)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.help_outline, color: AppTheme.warning),
                                title: Text(e.identifier),
                                subtitle: Text(e.unitId == null
                                    ? 'Belum terdaftar'
                                    : '${e.unitName ?? ''} · tercatat di ${e.unitLocationCode ?? 'luar stok'} (${e.unitStatus ?? ''})'),
                              ),
                          ]),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildItem(OpnameItem item, bool canCount) {
    final cs = Theme.of(context).colorScheme;
    final variance = item.isSerialized ? item.variance : (_countedValue(item) == null ? null : _countedValue(item)! - item.systemQty);
    final varianceColor = variance == null || variance == 0 ? cs.onSurfaceVariant : (variance > 0 ? AppTheme.success : AppTheme.destructive);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant, width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('Sistem ${item.systemQty}${item.sku != null ? ' · ${item.sku}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          if (item.isSerialized)
            Text('${item.countedQty ?? 0}/${item.systemQty} ditemukan', style: const TextStyle(fontWeight: FontWeight.w700))
          else
            SizedBox(
              width: 80,
              child: TextField(
                controller: _counts[item.variantId],
                enabled: canCount,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Hitung', isDense: true),
                onChanged: (_) => setState(() => _dirty.add(item.variantId)),
              ),
            ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(variance == null ? '–' : '${variance > 0 ? '+' : ''}$variance',
                textAlign: TextAlign.end, style: TextStyle(color: varianceColor, fontWeight: FontWeight.w700)),
          ),
        ]),
        if (item.isSerialized && item.units.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              for (final u in item.units)
                InputChip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  avatar: Icon(u.found ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 16, color: u.found ? AppTheme.success : cs.onSurfaceVariant),
                  label: Text(u.identifier, style: Theme.of(context).textTheme.labelSmall),
                  // Tapping a found unit undoes the scan.
                  onPressed: canCount && u.found
                      ? () async {
                          try {
                            await WarehouseService.unscanOpname(widget.opnameId, u.unitId);
                            await _load();
                          } catch (e) {
                            SnackBarService.error(e.toString());
                          }
                        }
                      : null,
                ),
            ]),
          ),
      ]),
    );
  }

  int? _countedValue(OpnameItem item) {
    final text = _counts[item.variantId]?.text.trim() ?? '';
    return text.isEmpty ? null : int.tryParse(text);
  }
}
