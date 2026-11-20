import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/models/access.dart';
import 'package:gg_store_cashier/core/models/monthly_recap.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/services/accounting_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import '../widgets/finance_widgets.dart';
import 'reports_pages.dart' show defaultReportLocation;

import 'package:gg_store_cashier/core/services/error_handler.dart';
/// Who may open the recap: branch managers (their branch), owner and accountant.
const recapPermissions = ['reports.view_location', 'reports.view_all', 'accounting.view'];

bool canReadRecap(UserAccess access) => recapPermissions.any(access.can);

// Row colours from the shop's old spreadsheet, kept as small markers for familiarity.
const _sheetBlue = Color(0xFF3B82F6);
const _sheetRed = Color(0xFFEF4444);
const _sheetYellow = Color(0xFFFFCC00);
const _sheetGreen = Color(0xFF22C55E);
const _sheetCyan = Color(0xFF22D3EE);

/// Rekap Bulanan: the monthly recap the shop kept in a spreadsheet, built from the system's records.
///   - Rekap omset (everyone who may open it): sales, how they were paid, store cash spending,
///     refunds and discounts, and the net takings.
///   - Alokasi uang (owner, accountant): where the net takings went.
///   - Per kategori: net sales, cost and gross profit per category.
class MonthlyRecapPage extends ConsumerStatefulWidget {
  const MonthlyRecapPage({super.key});

  @override
  ConsumerState<MonthlyRecapPage> createState() => _MonthlyRecapPageState();
}

class _MonthlyRecapPageState extends ConsumerState<MonthlyRecapPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int? _locationId;
  bool _locationChosen = false;
  MonthlyRecap? _data;
  bool _loading = true;
  String? _error;

  Set<int>? get _scope => scopeFor(ref.read(currentAccessProvider), recapPermissions);

  String get _monthParam => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!_locationChosen) {
      _locationId = defaultReportLocation(ref.read(currentAccessProvider), _scope);
      _locationChosen = true;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AccountingService.monthlyRecap(locationId: _locationId, month: _monthParam);
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = ErrorHandler.describe(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    ref.watch(currentAccessProvider);
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('Rekap Bulanan', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: cs.surface,
        elevation: 0,
        actions: [IconButton(tooltip: 'Muat ulang', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: Column(children: [
        Container(
          color: cs.surface,
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FinanceLocationChips(
              scope: _scope,
              value: _locationId,
              allLabel: _scope == null ? 'Semua lokasi' : null,
              onChanged: (id) {
                setState(() => _locationId = id);
                _load();
              },
            ),
            MonthStepper(
              month: _month,
              onChanged: (m) {
                setState(() => _month = m);
                _load();
              },
            ),
          ]),
        ),
        Expanded(
          child: AsyncBody(
            loading: _loading,
            error: _error,
            onRetry: _load,
            builder: () {
              final d = _data!;
              final o = d.omset;
              final a = d.allocation;
              return RefreshIndicator(
                color: AppTheme.gold,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    if (isCurrent)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('Bulan berjalan: angka sampai hari ini', style: TextStyle(color: cs.onSurfaceVariant)),
                      ),
                    const _Heading('Rekap omset'),
                    _SheetCard(month: _month, rows: [
                      _Row('Total omset sistem', o.gross, hint: '${o.transactions} transaksi, sebelum diskon'),
                      _Row('Total cash', o.cash, kind: _Kind.sub, hint: 'Tunai diterima, dikurangi kembalian'),
                      _Row('Total QRIS + debit', o.qrisDebit, kind: _Kind.sub),
                      _Row('Total transfer', o.transfer, kind: _Kind.sub),
                      _Row('E-wallet / online', o.ewallet, kind: _Kind.sub),
                      _Row('Pengeluaran', o.expenses, kind: _Kind.minus, hint: 'Biaya yang dibayar dari kas toko'),
                      for (final l in o.expenseLines) _Row('${l.name} (${l.count}×)', l.amount, kind: _Kind.sub),
                      _Row('Refund', o.refund, kind: _Kind.minus, hint: 'Uang dikembalikan ke pelanggan (retur)'),
                      _Row('Komplimen', o.discounts, kind: _Kind.minus, hint: 'Diskon dan voucher'),
                      _Row('Omset bersih', o.net, kind: _Kind.result, hint: 'Omset sistem − pengeluaran − refund − komplimen'),
                    ]),
                    if (a != null) ...[
                      const _Heading('Alokasi uang'),
                      _SheetCard(month: _month, rows: [
                        _Row('Omset bersih', a.netRevenue),
                        _Row('Operasional', a.operational, kind: _Kind.minus, color: _sheetBlue, hint: 'Biaya yang dibayar dari bank, per kategori'),
                        for (final l in a.operationalLines) _Row('${l.name} (${l.count}×)', l.amount, kind: _Kind.sub),
                        _Row('Pembelian stok', a.stockPurchases, kind: _Kind.minus, color: _sheetRed),
                        _Row('Barang (dibayar saat diterima)', a.stockGoods, kind: _Kind.sub),
                        _Row('Top up deposit pulsa', a.stockPulsa, kind: _Kind.sub),
                        _Row('Pembayaran hutang', a.debtPayments, kind: _Kind.minus, color: _sheetYellow, hint: 'Pelunasan penerimaan barang sebelumnya'),
                        _Row('Aset', a.assets, kind: _Kind.minus, color: _sheetGreen, hint: 'Masuk ke akun aset tetap lewat jurnal'),
                        _Row('Sisa uang', a.remaining, kind: _Kind.result, hint: 'Omset bersih − operasional − stok − hutang − aset'),
                        _Row('Sisa uang pulsa', a.pulsaBalance, color: _sheetCyan, hint: 'Saldo deposit pulsa di akhir bulan'),
                      ]),
                    ],
                    const _Heading('Per kategori'),
                    if (d.categories.isEmpty)
                      Text('Belum ada penjualan bulan ini', style: TextStyle(color: cs.onSurfaceVariant))
                    else ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('Omset di sini sudah dikurangi diskon dan refund barang kategori itu.',
                            style: TextStyle(color: cs.onSurfaceVariant)),
                      ),
                      for (final c in d.categories) _CategoryCard(category: c),
                      _OmsetSteps(omset: o, categoryTotal: d.categories.fold<double>(0, (s, c) => s + c.revenue)),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

enum _Kind { plain, minus, sub, result }

class _Row {
  final String label;
  final double value;
  final _Kind kind;
  final Color? color;
  final String? hint;
  const _Row(this.label, this.value, {this.kind = _Kind.plain, this.color, this.hint});
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
        child: Semantics(
          header: true,
          child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        ),
      );
}

/// The spreadsheet look on a phone: month line, black "Keterangan | Angka" bar, one figure per row.
class _SheetCard extends StatelessWidget {
  final DateTime month;
  final List<_Row> rows;
  const _SheetCard({required this.month, required this.rows});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ink = cs.onSurface;
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ink, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Text('Bulan', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
            Text(monthLabel(month), style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
          ]),
        ),
        Container(
          color: AppTheme.background,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: const Row(children: [
            Text('KETERANGAN', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            Spacer(),
            Text('ANGKA', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          ]),
        ),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
          _SheetRow(row: rows[i]),
        ],
      ]),
    );
  }
}

class _SheetRow extends StatelessWidget {
  final _Row row;
  const _SheetRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final result = row.kind == _Kind.result;
    final sub = row.kind == _Kind.sub;
    // On the yellow result row the text is always black (black on yellow ≈ 14:1).
    final fg = result ? Colors.black : (sub ? cs.onSurfaceVariant : cs.onSurface);
    final weight = result ? FontWeight.w800 : (sub ? FontWeight.w500 : FontWeight.w700);
    return Container(
      color: result ? _sheetYellow : (sub ? cs.surfaceContainerLow : null),
      padding: EdgeInsets.fromLTRB(sub ? 32 : 12, 9, 12, 9),
      child: Semantics(
        label: '${row.kind == _Kind.minus ? 'dikurangi ' : ''}${row.label}, ${rp(row.value)}',
        excludeSemantics: true,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (row.color != null)
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(top: 3, right: 8),
              decoration: BoxDecoration(
                color: row.color,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: Colors.black26),
              ),
            ),
          if (row.kind == _Kind.minus)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text('−', style: TextStyle(color: fg, fontWeight: FontWeight.w800)),
            ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(row.label, style: TextStyle(color: fg, fontWeight: weight)),
              if (row.hint != null)
                Text(row.hint!, style: text.labelSmall?.copyWith(color: result ? Colors.black87 : cs.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(width: 12),
          Text(
            rp(row.value),
            style: TextStyle(
              color: row.value < 0 && !result ? AppTheme.destructive : fg,
              fontWeight: weight,
              fontSize: result ? 15 : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ]),
      ),
    );
  }
}

/// How the totals relate, so they do not look contradictory:
/// omset sistem → (− komplimen − refund) → total per kategori → (− pengeluaran) → omset bersih.
/// Discounts and refunds belong to items, so the category figures already exclude them; store
/// spending belongs to no category, so only omset bersih takes it off.
class _OmsetSteps extends StatelessWidget {
  final RecapOmset omset;
  final double categoryTotal;
  const _OmsetSteps({required this.omset, required this.categoryTotal});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget step(String label, double value, {bool strong = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: strong ? _sheetYellow : cs.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: strong ? Colors.black : cs.outlineVariant, width: strong ? 1.5 : 1),
          ),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: strong ? Colors.black : null))),
            Text(rp(value), style: TextStyle(fontWeight: FontWeight.w800, color: strong ? Colors.black : null)),
          ]),
        );
    Widget arrow(String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(Icons.arrow_downward_rounded, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 12))),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Kenapa angkanya berbeda?', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        step('Total omset sistem', omset.gross),
        arrow('− komplimen ${rp(omset.discounts)}  − refund ${rp(omset.refund)}'),
        step('Total per kategori', categoryTotal),
        arrow('− pengeluaran kas toko ${rp(omset.expenses)}'),
        step('Omset bersih', omset.net, strong: true),
      ]),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final RecapCategory category;
  const _CategoryCard({required this.category});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = category;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800))),
          Text('${c.qty.toStringAsFixed(0)} terjual', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        MoneyRow('Omset', c.revenue),
        MoneyRow('Harga pokok', -c.cost),
        MoneyRow('Laba kotor', c.grossProfit, bold: true, color: c.grossProfit < 0 ? AppTheme.destructive : null),
      ]),
    );
  }
}
