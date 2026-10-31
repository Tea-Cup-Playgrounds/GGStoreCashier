import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gg_store_cashier/core/helper/currency_formatter.dart';
import 'package:gg_store_cashier/core/helper/rupiah_input_formatter.dart';
import 'package:gg_store_cashier/core/models/sales.dart';
import 'package:gg_store_cashier/core/services/sales_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/shared/widgets/custom_button.dart';

/// What the cashier confirmed in [PaymentSheet].
class PaymentSheetResult {
  final List<PaymentEntry> payments;
  final CustomerChoice? customer;
  const PaymentSheetResult({required this.payments, this.customer});
}

String _rupiahText(double value) => RupiahInputFormatter()
    .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: value.round().toString()))
    .text;

class _PaymentRow {
  PaymentMethod method;
  final amount = TextEditingController();
  final reference = TextEditingController();
  _PaymentRow(this.method);

  double get value => RupiahInputFormatter.parseRupiahAsDouble(amount.text) ?? 0;

  void dispose() {
    amount.dispose();
    reference.dispose();
  }
}

/// Checkout: one or more payment methods (split payment), change from cash, and the customer
/// (required when the cart has IMEI items). Offline only cash is offered.
class PaymentSheet extends StatefulWidget {
  final double total;
  final List<PaymentMethod> methods;
  final bool requireCustomer;
  final bool offline;

  const PaymentSheet({super.key, required this.total, required this.methods, this.requireCustomer = false, this.offline = false});

  static Future<PaymentSheetResult?> show(BuildContext context,
          {required double total, required List<PaymentMethod> methods, bool requireCustomer = false, bool offline = false}) =>
      showModalBottomSheet<PaymentSheetResult>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => PaymentSheet(total: total, methods: methods, requireCustomer: requireCustomer, offline: offline),
      );

  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<PaymentSheet> {
  final _rows = <_PaymentRow>[];
  final _customerSearch = TextEditingController();
  final _newName = TextEditingController();
  final _newPhone = TextEditingController();
  Timer? _debounce;
  List<Customer> _found = [];
  Customer? _customer;
  bool _newCustomer = false;
  bool _showCustomer = false;

  List<PaymentMethod> get _available => widget.offline ? widget.methods.where((m) => m.isCash).toList() : widget.methods;

  @override
  void initState() {
    super.initState();
    _showCustomer = widget.requireCustomer;
    final cash = _available.where((m) => m.isCash);
    final first = _PaymentRow(cash.isNotEmpty ? cash.first : _available.first);
    first.amount.text = _rupiahText(widget.total);
    _rows.add(first);
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _debounce?.cancel();
    _customerSearch.dispose();
    _newName.dispose();
    _newPhone.dispose();
    super.dispose();
  }

  double get _paid => _rows.fold(0, (s, r) => s + r.value);
  double get _nonCash => _rows.where((r) => !r.method.isCash).fold(0, (s, r) => s + r.value);
  double get _change => (_paid - widget.total).clamp(0, double.infinity).toDouble();

  String? get _problem {
    if (_paid < widget.total) return 'Kurang ${CurrencyFormatter.formatToRupiah(widget.total - _paid)}';
    if (_nonCash > widget.total) return 'Pembayaran non-tunai melebihi total';
    if (_rows.any((r) => r.method.requiresReference && r.reference.text.trim().isEmpty)) return 'Isi nomor referensi';
    if (widget.requireCustomer && _customerChoice == null) return 'Pelanggan wajib diisi untuk HP / barang ber-IMEI';
    return null;
  }

  CustomerChoice? get _customerChoice {
    if (_newCustomer) {
      final name = _newName.text.trim();
      return name.length >= 2 ? CustomerChoice.newCustomer(name: name, phone: _newPhone.text.trim()) : null;
    }
    return _customer == null ? null : CustomerChoice.existing(_customer!);
  }

  void _searchCustomers(String value) {
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _found = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final found = await SalesService.searchCustomers(value.trim());
        if (mounted) setState(() => _found = found);
      } catch (_) {
        if (mounted) setState(() => _found = []);
      }
    });
  }

  void _setAmount(_PaymentRow row, double amount) => setState(() => row.amount.text = _rupiahText(amount));

  /// Quick cash: exact amount and the next round notes above it.
  List<double> get _quickCash {
    final remaining = widget.total - _rows.where((r) => !r.method.isCash).fold<double>(0, (s, r) => s + r.value);
    if (remaining <= 0) return const [];
    final options = <double>{remaining};
    for (final note in [10000.0, 20000.0, 50000.0, 100000.0]) {
      options.add((remaining / note).ceil() * note);
    }
    return options.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final problem = _problem;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Flexible(
                child: Text('Pembayaran',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerRight,
                  fit: BoxFit.scaleDown,
                  child: Text(CurrencyFormatter.formatToRupiah(widget.total),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppTheme.gold, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
            if (widget.offline)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Offline: hanya pembayaran tunai', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.warning)),
              ),
            const SizedBox(height: 12),

            // ── customer ──
            if (!_showCustomer)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showCustomer = true),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Tambah pelanggan (opsional)'),
                ),
              )
            else
              _buildCustomer(cs),
            const SizedBox(height: 12),

            // ── payments ──
            for (final row in _rows) _buildRow(row),
            if (_rows.length < _available.length)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    final unused = _available.where((m) => !_rows.any((r) => r.method.id == m.id));
                    _rows.add(_PaymentRow(unused.first));
                  }),
                  icon: const Icon(Icons.call_split_rounded),
                  label: const Text('Tambah metode (split bayar)'),
                ),
              ),
            const Divider(height: 24),
            _summaryRow('Dibayar', _paid),
            if (_change > 0) _summaryRow('Kembalian', _change, color: AppTheme.success, bold: true),
            if (problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(problem, style: const TextStyle(color: AppTheme.destructive, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 16),
            CustomButton(
              text: 'Bayar',
              size: ButtonSize.large,
              icon: Icons.check_rounded,
              fullWidth: true,
              onPressed: problem != null
                  ? null
                  : () => Navigator.pop(
                        context,
                        PaymentSheetResult(
                          payments: _rows
                              .where((r) => r.value > 0)
                              .map((r) => PaymentEntry(method: r.method, amount: r.value, reference: r.reference.text.trim()))
                              .toList(),
                          customer: _customerChoice,
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomer(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(widget.requireCustomer ? 'Pelanggan *' : 'Pelanggan',
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => setState(() {
              _newCustomer = !_newCustomer;
              _customer = null;
            }),
            child: Text(_newCustomer ? 'Cari yang sudah ada' : 'Pelanggan baru'),
          ),
        ]),
        if (_newCustomer) ...[
          TextField(controller: _newName, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Nama', isDense: true)),
          const SizedBox(height: 8),
          TextField(
            controller: _newPhone,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'No. HP', isDense: true),
          ),
        ] else if (_customer != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person, color: AppTheme.gold),
            title: Text(_customer!.name),
            subtitle: _customer!.phone == null ? null : Text(_customer!.phone!),
            trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _customer = null)),
          )
        else ...[
          TextField(
            controller: _customerSearch,
            keyboardType: TextInputType.text,
            onChanged: _searchCustomers,
            decoration: const InputDecoration(hintText: 'Cari no. HP atau nama (min. 3 huruf)', prefixIcon: Icon(Icons.search), isDense: true),
          ),
          for (final c in _found.take(5))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(c.name),
              subtitle: c.phone == null ? null : Text(c.phone!),
              onTap: () => setState(() {
                _customer = c;
                _found = [];
              }),
            ),
        ],
      ]),
    );
  }

  Widget _buildRow(_PaymentRow row) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            flex: 5,
            child: DropdownButtonFormField<int>(
              initialValue: row.method.id,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Metode', isDense: true),
              items: _available
                  .where((m) => m.id == row.method.id || !_rows.any((r) => r.method.id == m.id))
                  .map((m) => DropdownMenuItem(value: m.id, child: Text(m.name)))
                  .toList(),
              onChanged: (id) => setState(() => row.method = _available.firstWhere((m) => m.id == id)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: TextField(
              controller: row.amount,
              keyboardType: TextInputType.number,
              inputFormatters: [RupiahInputFormatter()],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Jumlah', isDense: true),
            ),
          ),
          if (_rows.length > 1)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() {
                _rows.remove(row);
                WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
              }),
            ),
        ]),
        if (row.method.requiresReference)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextField(
              controller: row.reference,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'No. referensi / approval', isDense: true),
            ),
          ),
        if (row.method.isCash)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final amount in _quickCash)
                ActionChip(
                  label: Text(amount == _quickCash.first ? 'Uang pas' : CurrencyFormatter.formatToCompactRupiah(amount)),
                  onPressed: () => _setAmount(row, amount),
                ),
            ]),
          ),
      ]),
    );
  }

  Widget _summaryRow(String label, double value, {Color? color, bool bold = false}) {
    final style = TextStyle(color: color, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: bold ? 16 : 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Text(label, style: style), const Spacer(), Text(CurrencyFormatter.formatToRupiah(value), style: style)]),
    );
  }
}
