import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:gg_store_cashier/core/models/accounting.dart';
import 'package:gg_store_cashier/core/provider/access_provider.dart';
import 'package:gg_store_cashier/core/services/accounting_service.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';
import 'package:gg_store_cashier/features/warehouse/presentation/widgets/status_badge.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import '../widgets/finance_widgets.dart';

import 'package:gg_store_cashier/core/services/error_handler.dart';
/// Periode: a closed month accepts no new journals dated in it. Late automatic postings (e.g. an
/// offline sale uploaded after closing) are booked on today instead.
class PeriodsPage extends ConsumerStatefulWidget {
  const PeriodsPage({super.key});

  @override
  ConsumerState<PeriodsPage> createState() => _PeriodsPageState();
}

class _PeriodsPageState extends ConsumerState<PeriodsPage> {
  List<AccountingPeriod> _periods = [];
  bool _loading = true;
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final periods = await AccountingService.periods();
      if (mounted) setState(() => _periods = periods);
    } catch (e) {
      if (mounted) setState(() => _error = ErrorHandler.describe(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The last 18 months, newest first, with their stored status (none stored = open).
  List<AccountingPeriod> get _months {
    final now = DateTime.now();
    return [
      for (var i = 0; i < 18; i++)
        () {
          final d = DateTime(now.year, now.month - i);
          return _periods.where((p) => p.year == d.year && p.month == d.month).firstOrNull ??
              AccountingPeriod(year: d.year, month: d.month, status: 'open');
        }(),
    ];
  }

  Future<void> _toggle(AccountingPeriod p) async {
    final close = !p.isClosed;
    final label = monthLabelOf(p.year, p.month);
    final ok = await confirmAction(
      context,
      title: close ? 'Tutup $label?' : 'Buka kembali $label?',
      message: close
          ? 'Jurnal, biaya dan dokumen bertanggal di bulan ini tidak bisa dicatat lagi. Penjualan yang terlambat masuk dibukukan pada tanggal hari ini.'
          : 'Bulan ini bisa menerima jurnal lagi. Laporan bulan ini bisa berubah.',
      confirm: close ? 'Tutup periode' : 'Buka kembali',
    );
    if (!ok) return;
    setState(() => _busy = '${p.year}-${p.month}');
    try {
      SnackBarService.success(await AccountingService.setPeriod(p.year, p.month, close: close));
      await _load();
    } catch (e) {
      SnackBarService.error(ErrorHandler.describe(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canClose = ref.watch(currentAccessProvider).can('accounting.close_period');
    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(title: const Text('Periode Akuntansi', style: TextStyle(fontWeight: FontWeight.w600)), backgroundColor: cs.surface, elevation: 0),
      body: AsyncBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        builder: () => RefreshIndicator(
          color: AppTheme.gold,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Text('Tutup bulan setelah semua transaksinya dicatat dan dicek, biasanya awal bulan berikutnya.',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              for (final p in _months)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant, width: 0.8)),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(monthLabelOf(p.year, p.month), style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Row(children: [
                          StatusBadge(p.isClosed ? 'Ditutup' : 'Terbuka', color: p.isClosed ? AppTheme.destructive : AppTheme.success),
                          if (p.isClosed && p.closedAt != null) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '${DateFormat('dd-MM-yy HH:mm').format(p.closedAt!.toLocal())}${p.closedByName != null ? ' · ${p.closedByName}' : ''}',
                                style: Theme.of(context).textTheme.labelSmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ]),
                      ]),
                    ),
                    if (canClose)
                      _busy == '${p.year}-${p.month}'
                          ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                          : TextButton(onPressed: _busy != null ? null : () => _toggle(p), child: Text(p.isClosed ? 'Buka kembali' : 'Tutup')),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
