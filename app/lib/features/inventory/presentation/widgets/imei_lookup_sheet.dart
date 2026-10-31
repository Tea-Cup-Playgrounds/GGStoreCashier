import 'package:flutter/material.dart';
import 'package:gg_store_cashier/core/helper/currency_formatter.dart';
import 'package:gg_store_cashier/core/helper/imei_validator.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/services/catalog_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';

/// Finds a unit by IMEI or serial number across every location the user may view.
/// Barcode scanners in keyboard mode type straight into the field.
class ImeiLookupSheet extends StatefulWidget {
  const ImeiLookupSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const ImeiLookupSheet(),
      );

  @override
  State<ImeiLookupSheet> createState() => _ImeiLookupSheetState();
}

class _ImeiLookupSheetState extends State<ImeiLookupSheet> {
  final _controller = TextEditingController();
  List<ProductUnit>? _results;
  bool _loading = false;
  String? _error;

  Future<void> _search() async {
    final query = ImeiValidator.normalize(_controller.text);
    if (query.length < 4) {
      setState(() => _error = 'Masukkan minimal 4 digit');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final units = await CatalogService.getUnits(search: query);
      if (mounted) setState(() => _results = units);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Cek IMEI / Serial', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Ketik atau scan IMEI / nomor seri',
              prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
              errorText: _error,
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _loading ? null : _search),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: AppTheme.gold)),
            )
          else if (_results != null && _results!.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Unit tidak ditemukan di lokasi yang dapat Anda akses',
                  textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
            )
          else if (_results != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _results!.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final u = _results![i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.smartphone_rounded, color: u.status == 'in_stock' ? AppTheme.success : cs.onSurfaceVariant),
                    title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      u.identifier,
                      if (u.imei2 != null) u.imei2!,
                      '${unitStatusLabel(u.status)} · ${u.locationName ?? '-'}',
                      conditionLabel(u.conditionGrade),
                    ].join('\n')),
                    isThreeLine: true,
                    trailing: Text(CurrencyFormatter.formatToRupiah(u.sellPrice),
                        style: const TextStyle(color: AppTheme.gold, fontWeight: FontWeight.w700)),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
