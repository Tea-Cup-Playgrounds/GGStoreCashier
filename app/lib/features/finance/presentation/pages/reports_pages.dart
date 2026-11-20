import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/models/access.dart';
import 'package:gg_store_cashier/core/models/accounting.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/services/accounting_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/features/warehouse/presentation/widgets/status_badge.dart';
import '../widgets/finance_widgets.dart';
import 'finance_page.dart';

import 'package:gg_store_cashier/core/services/error_handler.dart';
/// Laba Rugi for a month or the year to date, per location or for the whole company.
class ProfitLossPage extends ConsumerStatefulWidget {
  const ProfitLossPage({super.key});

  @override
  ConsumerState<ProfitLossPage> createState() => _ProfitLossPageState();
}

class _ProfitLossPageState extends ConsumerState<ProfitLossPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _yearToDate = false;
  int? _locationId;
  bool _locationChosen = false;
  ProfitLoss? _data;
  bool _loading = true;
  String? _error;

  Set<int>? get _scope => scopeFor(ref.read(currentAccessProvider), statementPermissions);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  (String, String) get _range {
    if (!_yearToDate) return monthRange(_month);
    final (_, to) = monthRange(_month);
    return ('${_month.year}-01-01', to);
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
      final (from, to) = _range;
      final data = await AccountingService.profitLoss(locationId: _locationId, from: from, to: to);
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
    final (from, to) = _range;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(title: const Text('Laba Rugi', style: TextStyle(fontWeight: FontWeight.w600)), backgroundColor: cs.surface, elevation: 0),
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
            Row(children: [
              MonthStepper(month: _month, onChanged: (m) {
                setState(() => _month = m);
                _load();
              }),
              const Spacer(),
              FilterChip(
                label: const Text('Awal tahun s/d bulan ini'),
                selected: _yearToDate,
                selectedColor: AppTheme.gold.withValues(alpha: 0.15),
                onSelected: (v) {
                  setState(() => _yearToDate = v);
                  _load();
                },
              ),
            ]),
          ]),
        ),
        Expanded(
          child: AsyncBody(
            loading: _loading,
            error: _error,
            onRetry: _load,
            builder: () {
              final d = _data!;
              final cogs = d.expense.where((r) => (r.code ?? '').startsWith('5-')).toList();
              final operating = d.expense.where((r) => !(r.code ?? '').startsWith('5-')).toList();
              return RefreshIndicator(
                color: AppTheme.gold,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Text('${dayLabel(from)} – ${dayLabel(to)}', style: TextStyle(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    SectionCard(
                      child: Column(children: [
                        MoneyRow('Pendapatan', d.totalIncome),
                        MoneyRow('Harga pokok penjualan', -d.costOfGoods),
                        const Divider(),
                        MoneyRow('Laba kotor', d.grossProfit, bold: true),
                        MoneyRow('Beban operasional', -d.operatingExpense),
                        const Divider(),
                        MoneyRow('Laba bersih', d.netProfit, bold: true, color: d.netProfit < 0 ? AppTheme.destructive : AppTheme.gold),
                      ]),
                    ),
                    _RowsCard(title: 'Pendapatan', rows: d.income),
                    _RowsCard(title: 'Harga pokok', rows: cogs),
                    _RowsCard(title: 'Beban operasional', rows: operating),
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

/// Neraca at the end of a chosen day: assets = liabilities + equity, with this year's and earlier
/// years' profit worked out from the income and expense accounts.
class BalanceSheetPage extends ConsumerStatefulWidget {
  const BalanceSheetPage({super.key});

  @override
  ConsumerState<BalanceSheetPage> createState() => _BalanceSheetPageState();
}

class _BalanceSheetPageState extends ConsumerState<BalanceSheetPage> {
  DateTime _date = DateTime.now();
  int? _locationId;
  bool _locationChosen = false;
  BalanceSheet? _data;
  bool _loading = true;
  String? _error;

  Set<int>? get _scope => scopeFor(ref.read(currentAccessProvider), statementPermissions);

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
      final data = await AccountingService.balanceSheet(locationId: _locationId, to: ymd(_date));
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

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(title: const Text('Neraca', style: TextStyle(fontWeight: FontWeight.w600)), backgroundColor: cs.surface, elevation: 0),
      body: Column(children: [
        Container(
          color: cs.surface,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FinanceLocationChips(
              scope: _scope,
              value: _locationId,
              allLabel: _scope == null ? 'Semua lokasi' : null,
              onChanged: (id) {
                setState(() => _locationId = id);
                _load();
              },
            ),
            const SizedBox(height: 8),
            DateField(label: 'Per tanggal', value: _date, onChanged: (d) {
              setState(() => _date = d);
              _load();
            }),
          ]),
        ),
        Expanded(
          child: AsyncBody(
            loading: _loading,
            error: _error,
            onRetry: _load,
            builder: () {
              final d = _data!;
              return RefreshIndicator(
                color: AppTheme.gold,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: d.balanced
                          ? const StatusBadge('Seimbang: aset = kewajiban + ekuitas', color: AppTheme.success)
                          : StatusBadge('Tidak seimbang, selisih ${rp(d.difference)}', color: AppTheme.destructive),
                    ),
                    const SizedBox(height: 8),
                    _RowsCard(title: 'Aset', rows: d.assets, total: d.totalAssets),
                    _RowsCard(title: 'Kewajiban', rows: d.liabilities, total: d.totalLiabilities),
                    _RowsCard(title: 'Ekuitas', rows: d.equity, total: d.totalEquity),
                    SectionCard(child: MoneyRow('Total kewajiban dan ekuitas', d.totalLiabilities + d.totalEquity, bold: true)),
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

/// Where a report starts: every location for head office, else the user's own branch.
int? defaultReportLocation(UserAccess access, Set<int>? scope) {
  if (scope == null) return null;
  final home = access.defaultLocationId;
  return scope.contains(home) ? home : (scope.isEmpty ? null : scope.first);
}

class _RowsCard extends StatelessWidget {
  final String title;
  final List<ReportRow> rows;
  final double? total;
  const _RowsCard({required this.title, required this.rows, this.total});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SectionCard(
      title: title,
      trailing: total == null ? null : Text(rp(total!), style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.gold)),
      child: rows.isEmpty
          ? Text('Tidak ada saldo', style: TextStyle(color: cs.onSurfaceVariant))
          : Column(children: [
              for (final r in rows) MoneyRow(r.code == null ? r.name : '${r.code} ${r.name}', r.balance, sub: r.computed ? 'dihitung dari laba rugi' : null),
            ]),
    );
  }
}
