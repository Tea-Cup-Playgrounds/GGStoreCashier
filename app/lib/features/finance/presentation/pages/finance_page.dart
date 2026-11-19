import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/models/access.dart';
import 'package:gg_store_cashier/core/models/accounting.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/services/accounting_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/features/warehouse/presentation/widgets/status_badge.dart';
import 'package:gg_store_cashier/shared/widgets/menu_list.dart';
import '../widgets/finance_widgets.dart';
import 'expenses_page.dart';
import 'journals_page.dart';
import 'manual_journal_page.dart';
import 'monthly_recap_page.dart';
import 'periods_page.dart';
import 'pulsa_deposit_page.dart';
import 'reports_pages.dart';

/// Laba Rugi and Neraca: the books (accounting.view) or a location's own reports (branch managers).
const statementPermissions = ['accounting.view', 'reports.view_location'];

bool canReadStatements(UserAccess access) => statementPermissions.any(access.can);

/// Whether the Finance tab is shown: users who record expenses / pulsa top-ups, read their branch's
/// reports or read the books.
bool canUseFinance(UserAccess access) => access.can('expenses.manage') || canReadStatements(access) || canReadRecap(access);

/// Keuangan: this month at a glance and the accounting inputs the user may make.
///   - Branch admins (expenses.manage, reports.view_location at their branch): Biaya and Deposit
///     Pulsa, and the Laba Rugi and Neraca of their branch.
///   - Owner / accountant (every location): the same for every branch and head office, plus the
///     books: journals, manual journals and closing periods.
/// Opening balances, the chart of accounts and account mappings stay in the web back office.
class FinancePage extends ConsumerStatefulWidget {
  const FinancePage({super.key});

  @override
  ConsumerState<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends ConsumerState<FinancePage> {
  ExpenseList? _expenses;
  PulsaDeposit? _deposit;
  ProfitLoss? _profit;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// The location the summary is about: the user's branch, or null (every location) for head office.
  int? _summaryLocation(UserAccess access, List<String> permissions) {
    final scope = scopeFor(access, permissions);
    if (scope == null) return null;
    final home = access.defaultLocationId;
    return scope.contains(home) ? home : (scope.isEmpty ? null : scope.first);
  }

  Future<void> _load() async {
    final access = ref.read(currentAccessProvider);
    if (!canUseFinance(access)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (from, to) = monthRange(DateTime.now());
      const viewPerms = ['expenses.manage', 'accounting.view'];
      final location = _summaryLocation(access, viewPerms);
      final results = await Future.wait<Object?>([
        AccountingService.expenses(locationId: location, from: from, to: to),
        AccountingService.pulsaDeposit(locationId: location, from: from, to: to),
        canReadStatements(access)
            ? AccountingService.profitLoss(locationId: _summaryLocation(access, statementPermissions), from: from, to: to)
            : Future<ProfitLoss?>.value(null),
      ]);
      if (!mounted) return;
      setState(() {
        _expenses = results[0] as ExpenseList;
        _deposit = results[1] as PulsaDeposit;
        _profit = results[2] as ProfitLoss?;
      });
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
    final access = ref.watch(currentAccessProvider);
    final location = _summaryLocation(access, const ['expenses.manage', 'accounting.view']);
    final locationName = location == null
        ? 'Semua lokasi'
        : (ref.watch(financeLocationsProvider).valueOrNull ?? const []).where((l) => l.id == location).firstOrNull?.label ?? 'Cabang';

    if (!canUseFinance(access)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Keuangan')),
        body: const Center(child: Text('Anda tidak memiliki akses ke menu keuangan')),
      );
    }

    final canBooks = access.can('accounting.view');
    final canStatements = canReadStatements(access);
    final canRecap = canReadRecap(access);
    final canExpenses = access.can('expenses.manage') || canBooks;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Keuangan', style: TextStyle(fontWeight: FontWeight.w600)),
          Text('${access.roleLabel} · $locationName', style: Theme.of(context).textTheme.bodySmall),
        ]),
        backgroundColor: cs.surface,
        elevation: 0,
        actions: [IconButton(tooltip: 'Muat ulang', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: AppTheme.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            SectionCard(
              title: monthLabel(DateTime.now()),
              trailing: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : null,
              child: _error != null
                  ? Text(_error!, style: const TextStyle(color: AppTheme.destructive))
                  : Column(children: [
                      if (_profit != null) ...[
                        MoneyRow('Pendapatan', _profit!.totalIncome),
                        MoneyRow('Laba bersih', _profit!.netProfit, bold: true, color: _profit!.netProfit < 0 ? AppTheme.destructive : AppTheme.gold),
                        const Divider(),
                      ],
                      if (_expenses != null) MoneyRow('Biaya bulan ini', _expenses!.total),
                      if (_deposit != null)
                        MoneyRow('Saldo deposit pulsa', _deposit!.balance, color: _deposit!.balance < 0 ? AppTheme.destructive : null),
                    ]),
            ),
            const MenuGroupLabel('Input'),
            if (canExpenses)
              MenuTile(
                icon: Icons.receipt_long_outlined,
                title: 'Biaya',
                subtitle: 'Catat sewa, gaji, listrik, perlengkapan; batalkan yang salah',
                onTap: () => _open(const ExpensesPage()),
              ),
            if (canExpenses)
              MenuTile(
                icon: Icons.sim_card_outlined,
                title: 'Deposit Pulsa',
                subtitle: 'Saldo, pemakaian per bulan, top up',
                onTap: () => _open(const PulsaDepositPage()),
              ),
            if (access.can('accounting.post_manual'))
              MenuTile(
                icon: Icons.edit_note_rounded,
                title: 'Jurnal Manual',
                subtitle: 'Setoran kas ke bank, pencairan QRIS/EDC, PPN, koreksi',
                onTap: () => _open(const ManualJournalPage()),
              ),
            if (canStatements || canRecap) const MenuGroupLabel('Laporan'),
            if (canRecap)
              MenuTile(
                icon: Icons.summarize_outlined,
                title: 'Rekap Bulanan',
                subtitle: canBooks ? 'Omset, pengeluaran dan alokasi uang per bulan' : 'Omset dan pengeluaran cabang Anda per bulan',
                onTap: () => _open(const MonthlyRecapPage()),
              ),
            if (canStatements) ...[
              MenuTile(
                icon: Icons.trending_up_rounded,
                title: 'Laba Rugi',
                subtitle: canBooks ? 'Pendapatan, harga pokok, beban, laba bersih' : 'Laba rugi cabang Anda',
                onTap: () => _open(const ProfitLossPage()),
              ),
              MenuTile(
                icon: Icons.account_balance_outlined,
                title: 'Neraca',
                subtitle: canBooks ? 'Aset, kewajiban dan ekuitas per tanggal' : 'Neraca cabang Anda',
                onTap: () => _open(const BalanceSheetPage()),
              ),
            ],
            if (canBooks) ...[
              const MenuGroupLabel('Akuntansi'),
              MenuTile(
                icon: Icons.menu_book_outlined,
                title: 'Jurnal',
                subtitle: 'Semua jurnal otomatis dan manual',
                onTap: () => _open(const JournalsPage()),
              ),
              MenuTile(
                icon: Icons.lock_clock_outlined,
                title: 'Periode',
                subtitle: access.can('accounting.close_period') ? 'Tutup dan buka kembali bulan' : 'Status tutup buku per bulan',
                onTap: () => _open(const PeriodsPage()),
              ),
              const SizedBox(height: 8),
              Text('Saldo awal, bagan akun, pemetaan akun, neraca saldo dan buku besar ada di back office web.',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}
