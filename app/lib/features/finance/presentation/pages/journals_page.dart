import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gg_store_cashier/core/models/accounting.dart';
import 'package:gg_store_cashier/core/models/catalog.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/services/accounting_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/features/warehouse/presentation/widgets/status_badge.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import '../widgets/finance_widgets.dart';
import 'manual_journal_page.dart';

/// Jurnal: every entry, automatic and manual. Entries are never edited; a mistake is corrected by a
/// reversing entry.
class JournalsPage extends ConsumerStatefulWidget {
  const JournalsPage({super.key});

  @override
  ConsumerState<JournalsPage> createState() => _JournalsPageState();
}

class _JournalsPageState extends ConsumerState<JournalsPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int? _locationId;
  String? _sourceType;
  List<JournalSummary> _journals = [];
  bool _loading = true;
  String? _error;

  Set<int>? get _scope => scopeFor(ref.read(currentAccessProvider), const ['accounting.view']);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (from, to) = monthRange(_month);
      final journals = await AccountingService.journals(locationId: _locationId, from: from, to: to, sourceType: _sourceType);
      if (mounted) setState(() => _journals = journals);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newManual() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ManualJournalPage()));
    if (saved == true) _load();
  }

  Future<void> _pickSource() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => ListView(shrinkWrap: true, children: [
        ListTile(title: const Text('Semua sumber'), trailing: _sourceType == null ? const Icon(Icons.check) : null, onTap: () => Navigator.pop(ctx, '')),
        for (final e in journalSourceLabels.entries)
          ListTile(title: Text(e.value), trailing: _sourceType == e.key ? const Icon(Icons.check) : null, onTap: () => Navigator.pop(ctx, e.key)),
      ]),
    );
    if (picked == null) return;
    setState(() => _sourceType = picked.isEmpty ? null : picked);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final access = ref.watch(currentAccessProvider);

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(title: const Text('Jurnal', style: TextStyle(fontWeight: FontWeight.w600)), backgroundColor: cs.surface, elevation: 0),
      floatingActionButton: access.can('accounting.post_manual')
          ? FloatingActionButton.extended(
              onPressed: _newManual,
              backgroundColor: AppTheme.gold,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Jurnal Manual'),
            )
          : null,
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
              ActionChip(
                avatar: const Icon(Icons.filter_list_rounded, size: 16),
                label: Text(_sourceType == null ? 'Semua sumber' : journalSourceLabel(_sourceType!)),
                onPressed: _pickSource,
              ),
            ]),
          ]),
        ),
        Expanded(
          child: AsyncBody(
            loading: _loading,
            error: _error,
            onRetry: _load,
            builder: () => _journals.isEmpty
                ? Center(child: Text('Tidak ada jurnal', style: TextStyle(color: cs.onSurfaceVariant)))
                : RefreshIndicator(
                    color: AppTheme.gold,
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                      itemCount: _journals.length + (_journals.length >= 300 ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        if (i == _journals.length) {
                          return Text('Menampilkan 300 jurnal terbaru; persempit dengan lokasi atau sumber.',
                              textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant));
                        }
                        final j = _journals[i];
                        return _JournalTile(
                          journal: j,
                          onTap: () async {
                            final changed = await JournalDetailSheet.show(context, journalId: j.id);
                            if (changed == true) _load();
                          },
                        );
                      },
                    ),
                  ),
          ),
        ),
      ]),
    );
  }
}

class _JournalTile extends StatelessWidget {
  final JournalSummary journal;
  final VoidCallback onTap;
  const _JournalTile({required this.journal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final j = journal;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant, width: 0.8)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(j.memo ?? journalSourceLabel(j.sourceType), maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('${dayLabel(j.entryDate)} · ${j.locationCode ?? 'Pusat'} · ${journalSourceLabel(j.sourceType)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              Text(j.number, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontFamily: 'monospace')),
              if (j.isVoid || j.isReversal) ...[
                const SizedBox(height: 4),
                StatusBadge(j.isVoid ? 'Dibatalkan' : 'Pembalik', color: j.isVoid ? AppTheme.destructive : AppTheme.warning),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          Text(rp(j.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

/// One journal entry with its lines. Manual journals, opening balances and pulsa top-ups can be
/// voided here (the rest through their own documents). Pops true when voided.
class JournalDetailSheet extends ConsumerStatefulWidget {
  final String journalId;
  const JournalDetailSheet({super.key, required this.journalId});

  static Future<bool?> show(BuildContext context, {required String journalId}) => showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (_, controller) => PrimaryScrollController(controller: controller, child: JournalDetailSheet(journalId: journalId)),
        ),
      );

  @override
  ConsumerState<JournalDetailSheet> createState() => _JournalDetailSheetState();
}

class _JournalDetailSheetState extends ConsumerState<JournalDetailSheet> {
  Journal? _journal;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AccountingService.journal(widget.journalId).then((j) {
      if (mounted) setState(() => _journal = j);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e.toString());
    });
  }

  Future<void> _void() async {
    final reason = await askReason(context, title: 'Batalkan jurnal?', message: 'Jurnal pembalik dibuat dengan tanggal hari ini.', confirm: 'Batalkan jurnal');
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      await AccountingService.voidJournal(widget.journalId, reason);
      SnackBarService.success('Jurnal dibatalkan');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      SnackBarService.error(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final access = ref.watch(currentAccessProvider);
    final locations = ref.watch(financeLocationsProvider).valueOrNull ?? const <Location>[];
    String locationCode(int? id) => id == null ? 'Pusat' : (locations.where((l) => l.id == id).firstOrNull?.code ?? '#$id');
    final j = _journal;
    if (_error != null) return Padding(padding: const EdgeInsets.all(16), child: Text(_error!));
    if (j == null) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator(color: AppTheme.gold)));
    final s = j.summary;
    final canVoid = journalsVoidableHere.contains(s.sourceType) && !s.isVoid && !s.isReversal && access.can('accounting.post_manual', s.locationId);
    final multiLocation = j.lines.map((l) => l.locationId).toSet().length > 1;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Row(children: [
          Expanded(child: Text(s.number, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontFamily: 'monospace'))),
          if (s.isVoid) const StatusBadge('Dibatalkan', color: AppTheme.destructive),
          if (s.isReversal) const StatusBadge('Pembalik', color: AppTheme.warning),
        ]),
        const SizedBox(height: 4),
        Text('${dayLabel(s.entryDate)} · ${s.locationCode ?? 'Pusat'} · ${journalSourceLabel(s.sourceType)}', style: TextStyle(color: cs.onSurfaceVariant)),
        if (s.memo != null) ...[const SizedBox(height: 8), Text(s.memo!, style: const TextStyle(fontWeight: FontWeight.w600))],
        if (j.createdByName != null) Text('Oleh ${j.createdByName}', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 12),
        for (final l in j.lines)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 0.6))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Padding(
                  // Credits are indented, as on paper.
                  padding: EdgeInsets.only(left: l.credit > 0 ? 24 : 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${l.accountCode} ${l.accountName}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (multiLocation || l.memo != null)
                      Text([if (multiLocation) locationCode(l.locationId), if (l.memo != null) l.memo!].join(' · '),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
              ),
              SizedBox(width: 96, child: Text(l.debit > 0 ? rp(l.debit) : '', textAlign: TextAlign.right)),
              SizedBox(width: 96, child: Text(l.credit > 0 ? rp(l.credit) : '', textAlign: TextAlign.right)),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w800))),
            SizedBox(width: 96, child: Text(rp(j.totalDebit), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
            SizedBox(width: 96, child: Text(rp(j.totalCredit), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
          ]),
        ),
        Row(children: [
          const Expanded(child: SizedBox()),
          SizedBox(width: 96, child: Text('Debit', textAlign: TextAlign.right, style: Theme.of(context).textTheme.labelSmall)),
          SizedBox(width: 96, child: Text('Kredit', textAlign: TextAlign.right, style: Theme.of(context).textTheme.labelSmall)),
        ]),
        if (canVoid) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.destructive, side: const BorderSide(color: AppTheme.destructive)),
            onPressed: _busy ? null : _void,
            icon: const Icon(Icons.undo_rounded),
            label: const Text('Batalkan jurnal'),
          ),
        ] else if (!journalsVoidableHere.contains(s.sourceType) && !s.isVoid && !s.isReversal) ...[
          const SizedBox(height: 12),
          Text('Jurnal otomatis dibatalkan lewat dokumennya (penjualan, biaya, penerimaan...).',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ],
    );
  }
}
