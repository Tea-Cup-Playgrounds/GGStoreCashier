import 'package:flutter/material.dart';
import 'package:gg_store_cashier/core/helper/imei_validator.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/services/catalog_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';

/// Picks in-stock units of one variant at a location. Scanning (or typing) an IMEI and pressing
/// enter ticks the matching unit. Returns the selected unit ids, or null when dismissed.
class UnitPickerSheet extends StatefulWidget {
  final int locationId;
  final int variantId;
  final String title;
  final Set<String> initiallySelected;

  const UnitPickerSheet({
    super.key,
    required this.locationId,
    required this.variantId,
    required this.title,
    this.initiallySelected = const {},
  });

  static Future<Set<String>?> show(BuildContext context,
          {required int locationId, required int variantId, required String title, Set<String> selected = const {}}) =>
      showModalBottomSheet<Set<String>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => UnitPickerSheet(
            locationId: locationId, variantId: variantId, title: title, initiallySelected: selected),
      );

  @override
  State<UnitPickerSheet> createState() => _UnitPickerSheetState();
}

class _UnitPickerSheetState extends State<UnitPickerSheet> {
  final _scan = TextEditingController();
  final _scanFocus = FocusNode();
  late final Set<String> _selected = {...widget.initiallySelected};
  List<ProductUnit> _units = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scan.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final units = await CatalogService.getUnits(
          locationId: widget.locationId, variantId: widget.variantId, status: 'in_stock');
      if (mounted) setState(() => _units = units);
    } catch (e) {
      SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onScan(String value) {
    final code = ImeiValidator.normalize(value);
    _scan.clear();
    _scanFocus.requestFocus();
    if (code.isEmpty) return;
    final match = _units.where((u) => u.imei1 == code || u.imei2 == code || u.serialNumber == code);
    if (match.isEmpty) {
      SnackBarService.error('$code tidak tersedia di lokasi ini');
      return;
    }
    setState(() => _selected.add(match.first.id));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _scan,
              focusNode: _scanFocus,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: _onScan,
              decoration: const InputDecoration(
                hintText: 'Scan IMEI / serial untuk memilih',
                prefixIcon: Icon(Icons.qr_code_scanner_rounded),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Text('${_selected.length} dari ${_units.length} dipilih', style: Theme.of(context).textTheme.labelMedium),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _selected.length == _units.length
                    ? _selected.clear()
                    : _selected.addAll(_units.map((u) => u.id))),
                child: Text(_selected.length == _units.length ? 'Kosongkan' : 'Pilih semua'),
              ),
            ]),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.gold))
                  : _units.isEmpty
                      ? Center(child: Text('Tidak ada unit tersedia', style: TextStyle(color: cs.onSurfaceVariant)))
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: _units.length,
                          itemBuilder: (context, i) {
                            final u = _units[i];
                            return CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _selected.contains(u.id),
                              activeColor: AppTheme.gold,
                              title: Text(u.identifier, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text([if (u.imei2 != null) u.imei2!, conditionLabel(u.conditionGrade)].join(' · ')),
                              onChanged: (v) => setState(() => v == true ? _selected.add(u.id) : _selected.remove(u.id)),
                            );
                          },
                        ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context, _selected),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.gold, foregroundColor: Colors.black),
              child: Text('Gunakan ${_selected.length} unit'),
            ),
          ],
        ),
      ),
    );
  }
}
