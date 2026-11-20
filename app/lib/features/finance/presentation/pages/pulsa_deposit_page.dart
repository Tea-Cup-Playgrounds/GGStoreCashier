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
import 'journals_page.dart';

import 'package:gg_store_cashier/core/services/error_handler.dart';
/// Deposit Pulsa: money paid in advance to the pulsa / digital provider. Top-ups add to it; every
/// pulsa sale uses it at the item's harga modal.
class PulsaDepositPage extends ConsumerStatefulWidget {
  const PulsaDepositPage({super.key});

  @override
  ConsumerState<PulsaDepositPage> createState() => _PulsaDepositPageState();
}

class _PulsaDepositPageState extends ConsumerState<PulsaDepositPage> {
  int _year = DateTime.now().year;
  int? _locationId;
  bool _locationChosen = false;
  PulsaDeposit? _data;
  bool _loading = true;
  String? _error;

  Set<int>? get _viewScope => scopeFor(ref.read(currentAccessProvider), const ['expenses.manage', 'accounting.view']);
  Set<int>? get _manageScope => scopeFor(ref.read(currentAccessProvider), const ['expenses.manage']);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!_locationChosen) {
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
      final now = DateTime.now();
      final to = _year == now.year ? ymd(now) : '$_year-12-31';
      final data = await AccountingService.pulsaDeposit(locationId: _locationId, from: '$_year-01-01', to: to);
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = ErrorHandler.describe(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _topUp() async {
    final saved = await PulsaTopUpSheet.show(context, scope: _manageScope, locationId: _locationId);
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    ref.watch(currentAccessProvider);
    final manage = _manageScope;
    final canTopUp = manage == null || manage.isNotEmpty;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(title: const Text('Deposit Pulsa', style: TextStyle(fontWeight: FontWeight.w600)), backgroundColor: cs.surface, elevation: 0),
      floatingActionButton: canTopUp
          ? FloatingActionButton.extended(
              onPressed: _topUp,
              backgroundColor: AppTheme.gold,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add_card_rounded),
              label: const Text('Top Up'),
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
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: () {
                setState(() => _year -= 1);
                _load();
              }),
              Text('Tahun $_year', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: _year >= DateTime.now().year
                    ? null
                    : () {
                        setState(() => _year += 1);
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
              final toppedUp = d.topUps.where((t) => !t.isVoid).fold<double>(0, (s, t) => s + t.amount);
              final used = d.usage.fold<double>(0, (s, u) => s + u.used);
              return RefreshIndicator(
                color: AppTheme.gold,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    SectionCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Saldo deposit sekarang', style: TextStyle(color: cs.onSurfaceVariant)),
                        Text(rp(d.balance),
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: d.balance < 0 ? AppTheme.destructive : AppTheme.gold)),
                        if (d.balance < 0) const Text('Minus: catat top up yang belum masuk', style: TextStyle(color: AppTheme.destructive)),
                        const Divider(height: 20),
                        MoneyRow('Top up tahun $_year', toppedUp),
                        MoneyRow('Terpakai tahun $_year', used),
                      ]),
                    ),
                    SectionCard(
                      title: 'Pemakaian per bulan',
                      child: d.usage.isEmpty
                          ? Text('Belum ada penjualan pulsa dengan harga modal', style: TextStyle(color: cs.onSurfaceVariant))
                          : Column(children: [
                              for (final u in d.usage) MoneyRow(yearMonthLabel(u.month), u.used, sub: '${u.sales} transaksi'),
                            ]),
                    ),
                    SectionCard(
                      title: 'Top up',
                      child: d.topUps.isEmpty
                          ? Text('Belum ada top up', style: TextStyle(color: cs.onSurfaceVariant))
                          : Column(children: [
                              for (final t in d.topUps)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: Text('${dayLabel(t.date)} · ${t.locationCode ?? 'Pusat'}'),
                                  subtitle: Text(t.number),
                                  trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                                    Text(rp(t.amount), style: TextStyle(fontWeight: FontWeight.w700, decoration: t.isVoid ? TextDecoration.lineThrough : null)),
                                    if (t.isVoid) const StatusBadge('Dibatalkan', color: AppTheme.destructive),
                                  ]),
                                  // Journals are for users who read the books (branch staff see the list only).
                                  onTap: !ref.read(currentAccessProvider).can('accounting.view')
                                      ? null
                                      : () async {
                                          final changed = await JournalDetailSheet.show(context, journalId: t.entryId);
                                          if (changed == true) _load();
                                        },
                                ),
                            ]),
                    ),
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

/// Top-up of the pulsa deposit. Pops true when saved.
class PulsaTopUpSheet extends ConsumerStatefulWidget {
  final Set<int>? scope;
  final int? locationId;
  const PulsaTopUpSheet({super.key, required this.scope, this.locationId});

  static Future<bool?> show(BuildContext context, {required Set<int>? scope, int? locationId}) => showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => PulsaTopUpSheet(scope: scope, locationId: locationId),
      );

  @override
  ConsumerState<PulsaTopUpSheet> createState() => _PulsaTopUpSheetState();
}

class _PulsaTopUpSheetState extends ConsumerState<PulsaTopUpSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late int? _locationId = widget.scope == null || (widget.locationId != null && widget.scope!.contains(widget.locationId))
      ? widget.locationId
      : (widget.scope!.isEmpty ? null : widget.scope!.first);
  DateTime _date = DateTime.now();
  String _paidFrom = 'bank';
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final message = await AccountingService.topUpPulsa(
        locationId: _locationId,
        date: ymd(_date),
        amount: RupiahInputFormatter.parseRupiahAsDouble(_amount.text)!,
        paidFrom: _paidFrom,
        note: _note.text.trim(),
      );
      SnackBarService.success(message);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      SnackBarService.error(ErrorHandler.describe(e));
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
              Text('Top Up Deposit Pulsa', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const Text('Uang yang dikirim ke penyedia pulsa; tiap penjualan pulsa memakai saldo ini.'),
              const SizedBox(height: 16),
              DateField(label: 'Tanggal', value: _date, onChanged: (d) => setState(() => _date = d)),
              const SizedBox(height: 12),
              FinanceLocationField(scope: widget.scope, value: _locationId, onChanged: (v) => setState(() => _locationId = v), label: 'Lokasi yang memakai deposit'),
              const SizedBox(height: 12),
              TextInput(
                label: 'Jumlah *',
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                prefixIcon: Icons.payments_outlined,
                validator: (v) {
                  final n = RupiahInputFormatter.parseRupiahAsDouble(v ?? '');
                  return n == null || n <= 0 ? 'Isi jumlah top up' : null;
                },
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'bank', label: Text('Dari Bank'), icon: Icon(Icons.account_balance_outlined)),
                  ButtonSegment(value: 'cash', label: Text('Dari Kas'), icon: Icon(Icons.payments_outlined)),
                ],
                selected: {_paidFrom},
                onSelectionChanged: (s) => setState(() => _paidFrom = s.first),
              ),
              const SizedBox(height: 12),
              TextInput(label: 'Catatan (opsional)', hintText: 'mis. Transfer ke server pulsa', controller: _note, prefixIcon: Icons.notes),
              const SizedBox(height: 16),
              CustomButton(text: 'Simpan Top Up', isLoading: _saving, onPressed: _saving ? null : _save, fullWidth: true),
            ],
          ),
        ),
      ),
    );
  }
}
