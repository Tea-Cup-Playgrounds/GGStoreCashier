import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/helper/rupiah_input_formatter.dart';
import 'package:gg_store_cashier/core/models/accounting.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/services/accounting_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/features/warehouse/presentation/widgets/status_badge.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import 'package:gg_store_cashier/shared/widgets/custom_button.dart';
import 'package:gg_store_cashier/shared/widgets/text_input.dart';
import '../widgets/finance_widgets.dart';

/// Biaya: operating costs (rent, salaries, electricity, supplies...). Each one is journaled at once
/// (Dr expense account, Cr Kas / Bank); a mistake is corrected by voiding it.
class ExpensesPage extends ConsumerStatefulWidget {
  const ExpensesPage({super.key});

  @override
  ConsumerState<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends ConsumerState<ExpensesPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int? _locationId;
  bool _locationChosen = false;
  ExpenseList? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Set<int>? get _viewScope => scopeFor(ref.read(currentAccessProvider), const ['expenses.manage', 'accounting.view']);
  Set<int>? get _manageScope => scopeFor(ref.read(currentAccessProvider), const ['expenses.manage']);

  Future<void> _load() async {
    if (!_locationChosen) {
      // Branch staff start at their branch; head office sees every location.
      final scope = _viewScope;
      final home = ref.read(currentAccessProvider).defaultLocationId;
      _locationId = scope == null ? null : (scope.contains(home) ? home : (scope.isEmpty ? null : scope.first));
      _locationChosen = true;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (from, to) = monthRange(_month);
      final data = await AccountingService.expenses(locationId: _locationId, from: from, to: to);
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final saved = await ExpenseFormSheet.show(context, scope: _manageScope, locationId: _locationId);
    if (saved == true) _load();
  }

  Future<void> _open(Expense expense) async {
    final changed = await ExpenseDetailSheet.show(context, expenseId: expense.id, manageScope: _manageScope);
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    ref.watch(currentAccessProvider);
    final manage = _manageScope;
    final canCreate = manage == null || manage.isNotEmpty;
    final data = _data;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(title: const Text('Biaya', style: TextStyle(fontWeight: FontWeight.w600)), backgroundColor: cs.surface, elevation: 0),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _create,
              backgroundColor: AppTheme.gold,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Catat Biaya'),
            )
          : null,
      body: Column(children: [
        Container(
          color: cs.surface,
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FinanceLocationChips(
              scope: _viewScope,
              value: _locationId,
              allLabel: _viewScope == null ? 'Semua lokasi' : null,
              onChanged: (id) {
                setState(() => _locationId = id);
                _load();
              },
            ),
            MonthStepper(month: _month, onChanged: (m) {
              setState(() => _month = m);
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
              final d = data!;
              return RefreshIndicator(
                color: AppTheme.gold,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    SectionCard(
                      title: 'Total biaya ${monthLabel(_month)}',
                      trailing: Text(rp(d.total), style: const TextStyle(color: AppTheme.gold, fontWeight: FontWeight.w800)),
                      child: d.byCategory.isEmpty
                          ? Text('Belum ada biaya', style: TextStyle(color: cs.onSurfaceVariant))
                          : Column(children: [for (final (category, amount) in d.byCategory) MoneyRow(category, amount)]),
                    ),
                    for (final x in d.expenses) _ExpenseTile(expense: x, onTap: () => _open(x)),
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

class _ExpenseTile extends StatelessWidget {
  final Expense expense;
  final VoidCallback onTap;
  const _ExpenseTile({required this.expense, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final x = expense;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant, width: 0.8),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(x.accountName, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                if ((x.payee ?? x.note) != null)
                  Text([x.payee, x.note].whereType<String>().join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text('${dayLabel(x.date)} · ${x.locationCode ?? 'Pusat'} · ${x.paidFromLabel} · ${x.number}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                if (x.isVoid) ...[const SizedBox(height: 4), const StatusBadge('Dibatalkan', color: AppTheme.destructive)],
              ]),
            ),
            Text(rp(x.amount),
                style: TextStyle(
                  color: x.isVoid ? cs.onSurfaceVariant : AppTheme.gold,
                  fontWeight: FontWeight.w700,
                  decoration: x.isVoid ? TextDecoration.lineThrough : null,
                )),
          ]),
        ),
      ),
    );
  }
}

/// Records an expense. Pops true when saved.
class ExpenseFormSheet extends ConsumerStatefulWidget {
  final Set<int>? scope;
  final int? locationId;
  const ExpenseFormSheet({super.key, required this.scope, this.locationId});

  static Future<bool?> show(BuildContext context, {required Set<int>? scope, int? locationId}) => showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ExpenseFormSheet(scope: scope, locationId: locationId),
      );

  @override
  ConsumerState<ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends ConsumerState<ExpenseFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _payee = TextEditingController();
  final _note = TextEditingController();
  late int? _locationId = widget.scope == null || (widget.locationId != null && widget.scope!.contains(widget.locationId))
      ? widget.locationId
      : (widget.scope!.isEmpty ? null : widget.scope!.first);
  DateTime _date = DateTime.now();
  String _paidFrom = 'cash';
  String? _accountCode;
  List<ExpenseCategory> _categories = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    AccountingService.expenseCategories().then((c) {
      if (mounted) setState(() => _categories = c);
    }).catchError((Object e) => SnackBarService.error(e.toString()));
  }

  @override
  void dispose() {
    _amount.dispose();
    _payee.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final expense = await AccountingService.createExpense(
        locationId: _locationId,
        date: ymd(_date),
        accountCode: _accountCode!,
        amount: RupiahInputFormatter.parseRupiahAsDouble(_amount.text)!,
        paidFrom: _paidFrom,
        payee: _payee.text.trim(),
        note: _note.text.trim(),
      );
      SnackBarService.success('Biaya ${expense.number} dicatat');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Catat Biaya', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const Text('Langsung dijurnal: beban di debit, Kas atau Bank di kredit.'),
              const SizedBox(height: 16),
              DateField(label: 'Tanggal', value: _date, onChanged: (d) => setState(() => _date = d)),
              const SizedBox(height: 12),
              FinanceLocationField(scope: widget.scope, value: _locationId, onChanged: (v) => setState(() => _locationId = v)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _accountCode,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Kategori *', prefixIcon: Icon(Icons.category_outlined), border: OutlineInputBorder()),
                hint: Text(_categories.isEmpty ? 'Memuat kategori...' : 'Pilih kategori'),
                items: [for (final c in _categories) DropdownMenuItem(value: c.code, child: Text(c.label, overflow: TextOverflow.ellipsis))],
                validator: (v) => v == null ? 'Pilih kategori' : null,
                onChanged: (v) => setState(() => _accountCode = v),
              ),
              const SizedBox(height: 12),
              TextInput(
                label: 'Jumlah *',
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                prefixIcon: Icons.payments_outlined,
                validator: (v) {
                  final n = RupiahInputFormatter.parseRupiahAsDouble(v ?? '');
                  return n == null || n <= 0 ? 'Isi jumlah biaya' : null;
                },
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'cash', label: Text('Dari Kas'), icon: Icon(Icons.payments_outlined)),
                  ButtonSegment(value: 'bank', label: Text('Dari Bank'), icon: Icon(Icons.account_balance_outlined)),
                ],
                selected: {_paidFrom},
                onSelectionChanged: (s) => setState(() => _paidFrom = s.first),
              ),
              const SizedBox(height: 12),
              TextInput(label: 'Dibayar ke (opsional)', hintText: 'mis. PLN, pemilik ruko', controller: _payee, prefixIcon: Icons.person_outline),
              const SizedBox(height: 12),
              TextInput(label: 'Catatan (opsional)', hintText: 'mis. Listrik bulan Oktober', controller: _note, prefixIcon: Icons.notes),
              const SizedBox(height: 16),
              CustomButton(text: 'Simpan Biaya', isLoading: _saving, onPressed: _saving ? null : _save, fullWidth: true),
            ],
          ),
        ),
      ),
    );
  }
}

/// One expense with its journal number; posted ones can be voided. Pops true when voided.
class ExpenseDetailSheet extends StatefulWidget {
  final String expenseId;
  final Set<int>? manageScope;
  const ExpenseDetailSheet({super.key, required this.expenseId, required this.manageScope});

  static Future<bool?> show(BuildContext context, {required String expenseId, required Set<int>? manageScope}) => showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ExpenseDetailSheet(expenseId: expenseId, manageScope: manageScope),
      );

  @override
  State<ExpenseDetailSheet> createState() => _ExpenseDetailSheetState();
}

class _ExpenseDetailSheetState extends State<ExpenseDetailSheet> {
  Expense? _expense;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AccountingService.expense(widget.expenseId).then((x) {
      if (mounted) setState(() => _expense = x);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e.toString());
    });
  }

  bool get _canVoid {
    final x = _expense;
    if (x == null || x.isVoid) return false;
    final scope = widget.manageScope;
    return scope == null || (x.locationId != null && scope.contains(x.locationId));
  }

  Future<void> _void() async {
    final reason = await askReason(context, title: 'Batalkan biaya?', message: 'Jurnal pembalik dibuat dengan tanggal hari ini. Biaya tetap terlihat sebagai dibatalkan.');
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      await AccountingService.voidExpense(widget.expenseId, reason);
      SnackBarService.success('Biaya dibatalkan');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final x = _expense;
    final cs = Theme.of(context).colorScheme;
    Widget row(String label, String? value) => value == null || value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 110, child: Text(label, style: TextStyle(color: cs.onSurfaceVariant))),
              Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: _error != null
          ? Text(_error!)
          : x == null
              ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator(color: AppTheme.gold)))
              : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text(x.number, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
                    StatusBadge(x.isVoid ? 'Dibatalkan' : 'Tercatat', color: x.isVoid ? AppTheme.destructive : AppTheme.success),
                  ]),
                  const SizedBox(height: 8),
                  Text(rp(x.amount), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.gold)),
                  const SizedBox(height: 12),
                  row('Kategori', '${x.accountCode} ${x.accountName}'),
                  row('Tanggal', dayLabel(x.date)),
                  row('Lokasi', x.locationCode ?? 'Pusat'),
                  row('Dibayar dari', x.paidFromLabel),
                  row('Dibayar ke', x.payee),
                  row('Catatan', x.note),
                  row('Jurnal', x.journalNumber),
                  row('Dicatat oleh', x.createdByName),
                  if (x.isVoid) row('Alasan batal', '${x.voidReason ?? '-'}${x.voidedByName != null ? ' (${x.voidedByName})' : ''}'),
                  if (_canVoid) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppTheme.destructive, side: const BorderSide(color: AppTheme.destructive)),
                      onPressed: _busy ? null : _void,
                      icon: const Icon(Icons.undo_rounded),
                      label: const Text('Batalkan biaya'),
                    ),
                  ],
                ]),
    );
  }
}
