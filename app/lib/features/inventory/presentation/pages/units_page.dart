import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/helper/currency_formatter.dart';
import 'package:gg_store_cashier/core/models/access.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/services/catalog_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import '../widgets/unit_edit_sheet.dart';
import 'register_units_page.dart';

/// Serialized units of one variant at one location.
class UnitsPage extends ConsumerStatefulWidget {
  final CatalogProduct product;
  final ProductVariant variant;
  final Location location;

  const UnitsPage({super.key, required this.product, required this.variant, required this.location});

  @override
  ConsumerState<UnitsPage> createState() => _UnitsPageState();
}

class _UnitsPageState extends ConsumerState<UnitsPage> {
  List<ProductUnit> _units = [];
  bool _loading = true;
  String? _error;
  bool _onlyInStock = true;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final units = await CatalogService.getUnits(
        locationId: widget.location.id,
        variantId: widget.variant.id,
        status: _onlyInStock ? 'in_stock' : null,
      );
      if (mounted) setState(() => _units = units);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    final count = await Navigator.of(context).push<int>(MaterialPageRoute(
      builder: (_) => RegisterUnitsPage(product: widget.product, variant: widget.variant, location: widget.location),
    ));
    if (count != null && count > 0) _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final access = ref.watch(accessProvider).valueOrNull ?? UserAccess.empty;
    final canRegister = access.can('units.register', widget.location.id);
    final q = _search.text.trim();
    final visible = q.isEmpty
        ? _units
        : _units
            .where((u) => [u.imei1, u.imei2, u.serialNumber].any((id) => id != null && id.contains(q)))
            .toList();
    final missingIds = _units.where((u) => !u.hasIdentifier).length;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.product.variantLabel(widget.variant),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            Text(widget.location.label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        backgroundColor: cs.surface,
        elevation: 0,
      ),
      floatingActionButton: canRegister
          ? FloatingActionButton.extended(
              onPressed: _register,
              backgroundColor: AppTheme.gold,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Daftarkan Unit'),
            )
          : null,
      body: Column(
        children: [
          Container(
            color: cs.surface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Cari IMEI / serial',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('Hanya tersedia'),
                      selected: _onlyInStock,
                      onSelected: (v) {
                        setState(() => _onlyInStock = v);
                        _load();
                      },
                    ),
                    const Spacer(),
                    Text('${_units.length} unit', style: Theme.of(context).textTheme.labelMedium),
                  ],
                ),
                if (missingIds > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [
                      const Icon(Icons.warning_amber_rounded, size: 16, color: AppTheme.warning),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('$missingIds unit belum memiliki IMEI/serial dan belum bisa dijual',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.warning)),
                      ),
                    ]),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.gold))
                : _error != null
                    ? Center(child: Text(_error!))
                    : visible.isEmpty
                        ? Center(
                            child: Text(_units.isEmpty ? 'Belum ada unit di lokasi ini' : 'Unit tidak ditemukan',
                                style: TextStyle(color: cs.onSurfaceVariant)))
                        : RefreshIndicator(
                            color: AppTheme.gold,
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                              itemCount: visible.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, i) => _UnitTile(
                                unit: visible[i],
                                onTap: () async {
                                  final changed = await UnitEditSheet.show(context,
                                      unit: visible[i], product: widget.product, location: widget.location);
                                  if (changed == true) _load();
                                },
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _UnitTile extends StatelessWidget {
  final ProductUnit unit;
  final VoidCallback onTap;
  const _UnitTile({required this.unit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = switch (unit.status) {
      'in_stock' => AppTheme.success,
      'defective' || 'written_off' => AppTheme.destructive,
      _ => cs.onSurfaceVariant,
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: unit.hasIdentifier ? cs.outlineVariant : AppTheme.warning, width: 0.8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(unit.identifier,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: unit.hasIdentifier ? null : AppTheme.warning,
                          )),
                  if (unit.imei2 != null)
                    Text(unit.imei2!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text('${unitStatusLabel(unit.status)} · ${conditionLabel(unit.conditionGrade)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: statusColor, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(CurrencyFormatter.formatToRupiah(unit.sellPrice),
                    style: const TextStyle(color: AppTheme.gold, fontWeight: FontWeight.w700)),
                if (unit.unitCost != null)
                  Text('HPP ${CurrencyFormatter.formatToCompactRupiah(unit.unitCost!)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
