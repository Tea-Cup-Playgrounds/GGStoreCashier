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

import 'package:gg_store_cashier/core/services/error_handler.dart';
/// Common entries the accountant makes by hand: (label, memo, [(account code, side)]).
const _templates = <(String, String, List<(String, bool)>)>[
  ('Setor kas ke bank', 'Setoran tunai ke bank', [('1-1200', true), ('1-1100', false)]),
  ('Pencairan QRIS', 'Pencairan QRIS / e-wallet', [('1-1200', true), ('1-1300', false)]),
  ('Pencairan EDC', 'Pencairan EDC (kartu)', [('1-1200', true), ('1-1310', false)]),
  ('Setoran modal', 'Setoran modal pemilik', [('1-1200', true), ('3-1000', false)]),
];

class _Line {
  String? accountCode;
  final debit = TextEditingController();
  final credit = TextEditingController();
  final memo = TextEditingController();
  bool autoFilled = false;

  double get debitValue => RupiahInputFormatter.parseRupiahAsDouble(debit.text) ?? 0;
  double get creditValue => RupiahInputFormatter.parseRupiahAsDouble(credit.text) ?? 0;

  void dispose() {
    debit.dispose();
    credit.dispose();
    memo.dispose();
  }
}

/// Jurnal manual: entries that have no document of their own (cash deposits, settlements, PPN,
/// owner drawings, corrections). Must balance; can be voided later from the journal list.
class ManualJournalPage extends ConsumerStatefulWidget {
  const ManualJournalPage({super.key});

  @override
  ConsumerState<ManualJournalPage> createState() => _ManualJournalPageState();
}

class _ManualJournalPageState extends ConsumerState<ManualJournalPage> {
  final _formKey = GlobalKey<FormState>();
  final _memo = TextEditingController();
  final List<_Line> _lines = [_Line(), _Line()];
  DateTime _date = DateTime.now();
  int? _locationId;
  bool _locationChosen = false;
  List<LedgerAccount> _accounts = [];
  bool _saving = false;

  Set<int>? get _scope => scopeFor(ref.read(currentAccessProvider), const ['accounting.post_manual']);

  @override
  void initState() {
    super.initState();
    AccountingService.accounts().then((a) {
      if (mounted) setState(() => _accounts = a.where((x) => x.isPostable && x.isActive).toList());
    }).catchError((Object e) => SnackBarService.error(ErrorHandler.describe(e)));
  }

  @override
  void dispose() {
    _memo.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  // Controllers of removed lines are disposed after the frame that stops using them.
  void _disposeLater(List<_Line> lines) => WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final l in lines) {
          l.dispose();
        }
      });

  int get _debitCents => _lines.fold(0, (s, l) => s + (l.debitValue * 100).round());
  int get _creditCents => _lines.fold(0, (s, l) => s + (l.creditValue * 100).round());
  bool get _balanced => _debitCents > 0 && _debitCents == _creditCents;

  void _applyTemplate((String, String, List<(String, bool)>) t) {
    final known = _accounts.map((a) => a.code).toSet();
    if (!t.$3.every((x) => known.contains(x.$1))) {
      SnackBarService.error('Akun untuk "${t.$1}" tidak ada di Bagan Akun');
      return;
    }
    final old = List.of(_lines);
    setState(() {
      _lines
        ..clear()
        ..addAll(t.$3.map((x) => _Line()..accountCode = x.$1));
      _memo.text = t.$2;
    });
    _disposeLater(old);
  }

  // With two lines, the amount typed on one side is copied to the other line's opposite side.
  void _mirror(int index, bool debitSide) {
    if (_lines.length != 2) return;
    final from = _lines[index];
    final other = _lines[1 - index];
    final target = debitSide ? other.credit : other.debit;
    final source = debitSide ? from.debit : from.credit;
    if (target.text.isEmpty || other.autoFilled) {
      target.text = source.text;
      (debitSide ? other.debit : other.credit).clear();
      other.autoFilled = true;
    }
  }

  Future<void> _post() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lines.any((l) => l.accountCode == null)) {
      SnackBarService.error('Pilih akun di setiap baris');
      return;
    }
    if (_lines.any((l) => (l.debitValue > 0) == (l.creditValue > 0))) {
      SnackBarService.error('Setiap baris berisi debit atau kredit saja');
      return;
    }
    if (!_balanced) {
      SnackBarService.error('Debit dan kredit belum seimbang');
      return;
    }
    setState(() => _saving = true);
    try {
      final message = await AccountingService.postManualJournal(
        date: ymd(_date),
        locationId: _locationId,
        memo: _memo.text.trim(),
        lines: _lines
            .map((l) => ManualJournalLine(accountCode: l.accountCode, debit: l.debitValue, credit: l.creditValue, memo: l.memo.text))
            .toList(),
      );
      SnackBarService.success(message);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      SnackBarService.error(ErrorHandler.describe(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAccount(_Line line) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AccountPicker(accounts: _accounts, selected: line.accountCode),
    );
    if (picked != null) setState(() => line.accountCode = picked);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scope = _scope;
    if (!_locationChosen) {
      _locationId = scope == null ? null : (scope.isEmpty ? null : scope.first);
      _locationChosen = true;
    }
    final diff = (_debitCents - _creditCents) / 100;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(title: const Text('Jurnal Manual', style: TextStyle(fontWeight: FontWeight.w600)), backgroundColor: cs.surface, elevation: 0),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final t in _templates) ActionChip(avatar: const Icon(Icons.bolt_rounded, size: 16), label: Text(t.$1), onPressed: () => _applyTemplate(t)),
            ]),
            const SizedBox(height: 12),
            DateField(label: 'Tanggal', value: _date, onChanged: (d) => setState(() => _date = d)),
            const SizedBox(height: 12),
            FinanceLocationField(scope: scope, value: _locationId, onChanged: (v) => setState(() => _locationId = v)),
            const SizedBox(height: 12),
            TextInput(
              label: 'Keterangan *',
              hintText: 'mis. Setoran tunai BR01 ke bank',
              controller: _memo,
              prefixIcon: Icons.notes,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Isi keterangan jurnal' : null,
            ),
            const SizedBox(height: 16),
            for (final (i, line) in _lines.indexed)
              SectionCard(
                key: ObjectKey(line),
                title: 'Baris ${i + 1}',
                trailing: IconButton(
                  tooltip: 'Hapus baris',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _lines.length <= 2
                      ? null
                      : () {
                          final removed = _lines[i];
                          setState(() => _lines.removeAt(i));
                          _disposeLater([removed]);
                        },
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                    onPressed: _accounts.isEmpty ? null : () => _pickAccount(line),
                    icon: const Icon(Icons.account_tree_outlined),
                    label: Text(
                      line.accountCode == null
                          ? (_accounts.isEmpty ? 'Memuat akun...' : 'Pilih akun')
                          : _accounts.where((a) => a.code == line.accountCode).firstOrNull?.label ?? line.accountCode!,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextInput(
                        label: 'Debit',
                        controller: line.debit,
                        keyboardType: TextInputType.number,
                        inputFormatters: [RupiahInputFormatter()],
                        onChanged: (_) => setState(() {
                          line.autoFilled = false;
                          if (line.debit.text.isNotEmpty) line.credit.clear();
                          _mirror(i, true);
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextInput(
                        label: 'Kredit',
                        controller: line.credit,
                        keyboardType: TextInputType.number,
                        inputFormatters: [RupiahInputFormatter()],
                        onChanged: (_) => setState(() {
                          line.autoFilled = false;
                          if (line.credit.text.isNotEmpty) line.debit.clear();
                          _mirror(i, false);
                        }),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  TextInput(label: 'Keterangan baris (opsional)', controller: line.memo),
                ]),
              ),
            TextButton.icon(
              onPressed: () => setState(() => _lines.add(_Line())),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Tambah baris'),
            ),
            const SizedBox(height: 8),
            SectionCard(
              child: Column(children: [
                MoneyRow('Total debit', _debitCents / 100),
                MoneyRow('Total kredit', _creditCents / 100),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _balanced
                      ? const StatusBadge('Seimbang', color: AppTheme.success)
                      : StatusBadge(diff == 0 ? 'Isi jumlahnya' : 'Selisih ${rp(diff.abs())}', color: AppTheme.destructive),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            CustomButton(text: 'Posting Jurnal', isLoading: _saving, onPressed: _saving || !_balanced ? null : _post, fullWidth: true),
          ],
        ),
      ),
    );
  }
}

/// Searchable list of postable accounts; pops the chosen code.
class _AccountPicker extends StatefulWidget {
  final List<LedgerAccount> accounts;
  final String? selected;
  const _AccountPicker({required this.accounts, this.selected});

  @override
  State<_AccountPicker> createState() => _AccountPickerState();
}

class _AccountPickerState extends State<_AccountPicker> {
  String _query = '';

  static const _typeLabels = {'asset': 'Aset', 'liability': 'Kewajiban', 'equity': 'Ekuitas', 'income': 'Pendapatan', 'expense': 'Beban'};

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final shown = widget.accounts.where((a) => q.isEmpty || a.label.toLowerCase().contains(q)).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari kode atau nama akun', border: OutlineInputBorder()),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (context, i) {
              final a = shown[i];
              return ListTile(
                dense: true,
                title: Text(a.label),
                subtitle: Text(_typeLabels[a.type] ?? a.type),
                trailing: a.code == widget.selected ? const Icon(Icons.check, color: AppTheme.gold) : null,
                onTap: () => Navigator.pop(context, a.code),
              );
            },
          ),
        ),
      ]),
    );
  }
}
