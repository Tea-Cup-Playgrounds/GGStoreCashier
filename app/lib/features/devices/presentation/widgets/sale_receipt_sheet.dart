import 'package:material_ui/material_ui.dart';

import '../../../../core/services/api_client.dart';
import '../../../../core/services/sales_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/receipt_printer.dart';
import '../../domain/receipt.dart';
import '../../domain/receipt_config.dart';
import '../../domain/receipt_layout.dart';
import 'receipt_preview.dart';

import 'package:gg_store_cashier/core/services/error_handler.dart';
/// A sale's receipt on screen (to show the customer or check it) with a print button.
class SaleReceiptSheet extends StatefulWidget {
  /// The receipt, or null while [saleId] is being loaded.
  final ReceiptData? receipt;
  final String? saleId;

  /// Reprints are marked "SALINAN".
  final bool reprint;

  const SaleReceiptSheet._({this.receipt, this.saleId, this.reprint = false});

  /// A receipt already at hand (the sale just made).
  static Future<void> showReceipt(BuildContext context, ReceiptData receipt) => _show(context, SaleReceiptSheet._(receipt: receipt));

  /// A past sale, loaded from the server; printing it prints a copy.
  static Future<void> showSale(BuildContext context, String saleId) =>
      _show(context, SaleReceiptSheet._(saleId: saleId, reprint: true));

  static Future<void> _show(BuildContext context, Widget sheet) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => FractionallySizedBox(heightFactor: 0.9, child: sheet),
      );

  @override
  State<SaleReceiptSheet> createState() => _SaleReceiptSheetState();
}

class _SaleReceiptSheetState extends State<SaleReceiptSheet> {
  ReceiptData? _receipt;
  ReceiptConfig _config = const ReceiptConfig();
  PrinterSettings? _printer;
  String? _loadError;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _receipt = widget.receipt;
    _load();
  }

  Future<void> _load() async {
    final config = await ReceiptConfig.load();
    final printer = await PrinterSettings.load();
    if (mounted) {
      setState(() {
        _config = config;
        _printer = printer;
      });
    }
    if (_receipt == null && widget.saleId != null) {
      try {
        final sale = await SalesService.getSale(widget.saleId!);
        if (mounted) setState(() => _receipt = ReceiptData.fromSale(sale.json));
      } on ApiException catch (e) {
        if (mounted) setState(() => _loadError = e.message);
      }
    }
  }

  Future<void> _print() async {
    final receipt = _receipt;
    if (receipt == null) return;
    setState(() => _printing = true);
    try {
      await ReceiptPrinter.printReceipt(widget.reprint ? receipt.asCopy() : receipt);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Struk dikirim ke printer')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is PrinterException ? e.message : ErrorHandler.describeAs('Gagal mencetak', e)),
          backgroundColor: AppTheme.destructive,
        ));
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    return Column(
      children: [
        Expanded(
          child: receipt == null
              ? Center(
                  child: _loadError != null
                      ? Padding(padding: const EdgeInsets.all(24), child: Text(_loadError!, textAlign: TextAlign.center))
                      : const CircularProgressIndicator(),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ReceiptPreview(
                    rows: ReceiptLayout.build(widget.reprint ? receipt.asCopy() : receipt, _config),
                    charsPerLine: _config.charsPerLine,
                  ),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: receipt == null || _printing || !(_printer?.isConfigured ?? false) ? null : _print,
                icon: _printing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.print_outlined),
                label: Text((_printer?.isConfigured ?? true)
                    ? (widget.reprint ? 'Cetak ulang' : 'Cetak')
                    : 'Printer belum diatur (Pengaturan → Printer Struk)'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
