import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/helper/currency_formatter.dart';
import '../../../../core/models/business_overview.dart';
import '../../../../core/provider/auth_provider.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/connectivity_monitor.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/theme/app_theme.dart';

/// Owner home: "how is the business doing, and does anything need me?"
///
/// Reading order follows the owner's questions: today (with a fair comparison), this month,
/// what needs action, then performance over one period that every chart below shares.
class SuperAdminDashboardPage extends ConsumerStatefulWidget {
  const SuperAdminDashboardPage({super.key});

  @override
  ConsumerState<SuperAdminDashboardPage> createState() => _SuperAdminDashboardPageState();
}

class _SuperAdminDashboardPageState extends ConsumerState<SuperAdminDashboardPage> {
  static const _periods = [7, 30, 90];

  int _days = 7;
  OverviewResult? _result;
  bool _refreshing = false;
  bool _failed = false;

  StreamSubscription<ConnectivityStatus>? _connectivitySub;
  ConnectivityStatus? _lastConnectivity;

  @override
  void initState() {
    super.initState();
    _load();
    LocationService.requestPermission();
    // Back online after an outage: replace the cached copy with fresh numbers.
    _connectivitySub = ConnectivityMonitor.instance.statusStream.listen((status) {
      if (_lastConnectivity == ConnectivityStatus.offline && status == ConnectivityStatus.online) {
        _load(force: true);
      }
      _lastConnectivity = status;
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _refreshing = true;
      _failed = false;
    });
    try {
      final result = await AnalyticsService.getOverview(_days, forceRefresh: force);
      if (!mounted) return;
      setState(() => _result = result);
    } catch (_) {
      if (!mounted) return;
      if (_result == null) {
        setState(() => _failed = true);
      } else {
        // Keep what is on screen; say so instead of replacing it with an error page.
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Gagal memperbarui. Data yang tampil adalah data terakhir.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _selectPeriod(int days) {
    if (days == _days) return;
    setState(() => _days = days);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(authProvider).user?.name ?? 'Owner';
    final result = _result;

    if (result == null) {
      return SafeArea(child: _failed ? _ErrorState(onRetry: () => _load(force: true)) : const _DashboardSkeleton());
    }

    final data = result.data;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => _load(force: true),
        color: AppTheme.gold,
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 840;
          final gap = wide ? 20.0 : 16.0;
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 12, wide ? 24 : 16, 100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Header(
                            name: name,
                            fetchedAt: result.fetchedAt,
                            refreshing: _refreshing,
                            onRefresh: () => _load(force: true),
                          ),
                          if (result.stale) ...[
                            const SizedBox(height: 12),
                            _StaleBanner(fetchedAt: result.fetchedAt, onRetry: () => _load(force: true)),
                          ],
                          SizedBox(height: gap),
                          _pair(
                            wide,
                            gap,
                            _TodayCard(today: data.today, activeBranches: data.activeBranchesToday, branchCount: data.branches.length),
                            _MonthCard(month: data.month),
                            flex: (3, 2),
                          ),
                          SizedBox(height: gap),
                          _AttentionCard(attention: data.attention),
                          SizedBox(height: gap + 8),
                          _PeriodHeader(
                            days: _days,
                            periods: _periods,
                            from: data.period.from,
                            to: data.period.to,
                            onChanged: _selectPeriod,
                          ),
                          const SizedBox(height: 12),
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 150),
                            // The numbers below belong to the previous period until the new ones arrive.
                            opacity: _refreshing && data.period.days != _days ? 0.45 : 1,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              _TrendCard(period: data.period),
                              SizedBox(height: gap),
                              _pair(wide, gap, _BranchCard(branches: data.branches, days: data.period.days),
                                  _CategoryCard(categories: data.categories, days: data.period.days)),
                              SizedBox(height: gap),
                              _ProductCard(products: data.products, days: data.period.days),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  /// Side by side on wide screens, stacked on phones.
  Widget _pair(bool wide, double gap, Widget a, Widget b, {(int, int) flex = (1, 1)}) {
    if (!wide) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, SizedBox(height: gap), b]);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(flex: flex.$1, child: a),
        SizedBox(width: gap),
        Expanded(flex: flex.$2, child: b),
      ]),
    );
  }
}

// ── tokens ────────────────────────────────────────────────────────────────────

class _Tokens {
  final Color card, border, muted, text, accentText, track;
  const _Tokens(this.card, this.border, this.muted, this.text, this.accentText, this.track);

  factory _Tokens.of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? const _Tokens(AppTheme.card, AppTheme.border, AppTheme.mutedForeground, AppTheme.foreground, AppTheme.goldLight,
            Color(0xFF262626))
        : const _Tokens(AppTheme.lightCard, AppTheme.lightBorder, AppTheme.lightMutedForeground, AppTheme.lightForeground,
            Color(0xFF7A6200), Color(0xFFEFEBE3));
  }
}

// ── formatting ────────────────────────────────────────────────────────────────

const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
const _monthsLong = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
];
const _weekdays = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];

final _count = NumberFormat.decimalPattern('id_ID');
String _time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}.${t.minute.toString().padLeft(2, '0')}';
String _longDate(DateTime d) => '${_weekdays[d.weekday - 1]}, ${d.day} ${_monthsLong[d.month - 1]} ${d.year}';
String _shortDate(DateTime d) => '${d.day} ${_monthsShort[d.month - 1]}';
String _rupiah(num v) => CurrencyFormatter.formatToRupiah(v);
String _compact(num v) => CurrencyFormatter.formatToCompactRupiah(v);

String _range(DateTime? from, DateTime? to) {
  if (from == null || to == null) return '';
  if (from.year != to.year) return '${_shortDate(from)} ${from.year} – ${_shortDate(to)} ${to.year}';
  if (from.month == to.month) return '${from.day}–${to.day} ${_monthsShort[to.month - 1]} ${to.year}';
  return '${_shortDate(from)} – ${_shortDate(to)} ${to.year}';
}

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 10) return 'Selamat pagi';
  if (hour < 15) return 'Selamat siang';
  if (hour < 18) return 'Selamat sore';
  return 'Selamat malam';
}

// ── building blocks ───────────────────────────────────────────────────────────

class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: child,
    );
  }
}

class _PanelTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _PanelTitle(this.title, {this.subtitle});

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final text = Theme.of(context).textTheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: text.bodySmall?.copyWith(color: t.muted)),
          ],
        ]),
      ),
    ]);
  }
}

/// Direction + percentage + what it is compared with. Never colour alone: the arrow and the
/// sign carry the meaning for colour-blind users and screen readers.
class _Delta extends StatelessWidget {
  final double? change;
  final String comparedWith;
  const _Delta({required this.change, required this.comparedWith});

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final text = Theme.of(context).textTheme.bodySmall;
    final c = change;
    if (c == null) {
      return Text('Belum ada pembanding $comparedWith', style: text?.copyWith(color: t.muted));
    }
    final flat = c.abs() < 0.005;
    final up = c > 0;
    final color = flat ? t.muted : (up ? AppTheme.success : AppTheme.destructive);
    final pct = (c.abs() * 100).toStringAsFixed(c.abs() < 0.1 ? 1 : 0).replaceAll('.', ',');
    final label = flat ? 'Sama' : '${up ? '+' : '−'}$pct%';
    final spoken = flat ? 'sama' : '${up ? 'naik' : 'turun'} $pct persen';
    return Semantics(
      label: '$spoken $comparedWith',
      excludeSemantics: true,
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 2, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(flat ? Icons.remove : (up ? Icons.arrow_upward : Icons.arrow_downward), size: 13, color: color),
            const SizedBox(width: 2),
            Text(label, style: text?.copyWith(color: color, fontWeight: FontWeight.w700)),
          ]),
        ),
        Text(comparedWith, style: text?.copyWith(color: t.muted)),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: text.labelSmall?.copyWith(color: t.muted)),
      const SizedBox(height: 2),
      Text(value,
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
    ]);
  }
}

class _ShareBar extends StatelessWidget {
  final double value;
  const _ShareBar(this.value);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1).toDouble(),
        minHeight: 6,
        backgroundColor: _Tokens.of(context).track,
        valueColor: const AlwaysStoppedAnimation(AppTheme.gold),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyNote(this.icon, this.message);

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(children: [
        Icon(icon, color: t.muted, size: 28),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: t.muted)),
      ]),
    );
  }
}

// ── header & status ───────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String name;
  final DateTime fetchedAt;
  final bool refreshing;
  final VoidCallback onRefresh;
  const _Header({required this.name, required this.fetchedAt, required this.refreshing, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final text = Theme.of(context).textTheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_greeting()}, $name', style: text.bodyMedium?.copyWith(color: t.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Semantics(
            header: true,
            child: Text('Ringkasan bisnis', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 2),
          Text('${_longDate(DateTime.now())} · semua cabang', style: text.bodySmall?.copyWith(color: t.muted)),
        ]),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        SizedBox(
          width: 48,
          height: 48,
          child: refreshing
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.gold),
                )
              : IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh), tooltip: 'Muat ulang'),
        ),
        Text('Diperbarui ${_time(fetchedAt)}', style: text.labelSmall?.copyWith(color: t.muted)),
      ]),
    ]);
  }
}

class _StaleBanner extends StatelessWidget {
  final DateTime fetchedAt;
  final VoidCallback onRetry;
  const _StaleBanner({required this.fetchedAt, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sameDay = DateUtils.isSameDay(fetchedAt, DateTime.now());
    final when = sameDay ? 'pukul ${_time(fetchedAt)}' : '${_shortDate(fetchedAt)} pukul ${_time(fetchedAt)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.cloud_off_outlined, color: AppTheme.warning, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Tidak terhubung ke server. Menampilkan data $when.', style: text.bodySmall),
        ),
        TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
      ]),
    );
  }
}

// ── today & month ─────────────────────────────────────────────────────────────

class _TodayCard extends StatelessWidget {
  final Totals today;
  final int activeBranches;
  final int branchCount;
  const _TodayCard({required this.today, required this.activeBranches, required this.branchCount});

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final text = Theme.of(context).textTheme;
    final noSales = today.transactions == 0;
    return _Panel(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('Pendapatan hari ini', style: text.labelLarge?.copyWith(color: t.muted)),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _rupiah(today.revenue),
            style: text.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: t.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (noSales)
          Text('Belum ada penjualan hari ini', style: text.bodySmall?.copyWith(color: t.muted))
        else
          _Delta(change: today.revenueChange, comparedWith: 'vs kemarin di jam yang sama'),
        const SizedBox(height: 16),
        Divider(height: 1, color: t.border),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _Stat('Transaksi', _count.format(today.transactions))),
          Expanded(child: _Stat('Rata-rata', noSales ? '—' : _compact(today.averageTicket))),
          Expanded(child: _Stat('Cabang aktif', '$activeBranches dari $branchCount')),
        ]),
      ]),
    );
  }
}

class _MonthCard extends StatelessWidget {
  final Totals month;
  const _MonthCard({required this.month});

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    return _Panel(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('Bulan ini · ${_monthsLong[now.month - 1]}', style: text.labelLarge?.copyWith(color: t.muted)),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _rupiah(month.revenue),
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
        const SizedBox(height: 8),
        _Delta(change: month.revenueChange, comparedWith: 'vs tanggal 1–${now.day} bulan lalu'),
        const SizedBox(height: 16),
        Divider(height: 1, color: t.border),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _Stat('Transaksi', _count.format(month.transactions))),
          Expanded(child: _Stat('Rata-rata', month.transactions == 0 ? '—' : _compact(month.averageTicket))),
        ]),
      ]),
    );
  }
}

// ── needs attention ───────────────────────────────────────────────────────────

class _Issue {
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String? route;
  const _Issue(this.icon, this.color, this.title, this.detail, {this.route});
}

class _AttentionCard extends StatelessWidget {
  final Attention attention;
  const _AttentionCard({required this.attention});

  List<_Issue> get _issues {
    final a = attention;
    return [
      if (a.cashDifferenceCount > 0)
        _Issue(Icons.account_balance_wallet_outlined, AppTheme.destructive,
            'Selisih kas di ${a.cashDifferenceCount} shift hari ini', 'Total selisih ${_rupiah(a.cashDifferenceTotal)}'),
      if (a.outOfStock > 0)
        _Issue(Icons.remove_shopping_cart_outlined, AppTheme.destructive, '${_count.format(a.outOfStock)} produk habis',
            'Stok 0 di cabang; pelanggan tidak bisa membeli', route: AppRouter.inventory),
      if (a.overdueShifts > 0)
        _Issue(Icons.schedule, AppTheme.warning, '${a.overdueShifts} shift terbuka lebih dari 12 jam',
            'Kemungkinan lupa ditutup; kas shift belum dihitung'),
      if (a.lowStock > 0)
        _Issue(Icons.inventory_2_outlined, AppTheme.warning, '${_count.format(a.lowStock)} produk stok menipis',
            'Di bawah batas pemesanan ulang', route: AppRouter.inventory),
      if (a.voidedToday > 0)
        _Issue(Icons.block, AppTheme.warning, '${a.voidedToday} penjualan dibatalkan hari ini', 'Periksa alasan pembatalan'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final text = Theme.of(context).textTheme;
    final issues = _issues;

    if (issues.isEmpty) {
      return _Panel(
        child: Row(children: [
          const Icon(Icons.check_circle_outline, color: AppTheme.success),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tidak ada yang perlu ditindaklanjuti', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text('Kas, stok dan shift semua cabang aman.', style: text.bodySmall?.copyWith(color: t.muted)),
            ]),
          ),
        ]),
      );
    }

    return _Panel(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _PanelTitle('Perlu perhatian', subtitle: '${issues.length} hal untuk ditindaklanjuti'),
        const SizedBox(height: 8),
        for (final issue in issues) _IssueRow(issue),
      ]),
    );
  }
}

class _IssueRow extends StatelessWidget {
  final _Issue issue;
  const _IssueRow(this.issue);

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final text = Theme.of(context).textTheme;
    final route = issue.route;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: route == null ? null : () => context.go(route),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: issue.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(issue.icon, color: issue.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(issue.title, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(issue.detail, style: text.bodySmall?.copyWith(color: t.muted)),
              ]),
            ),
            if (route != null) Icon(Icons.chevron_right, color: t.muted),
          ]),
        ),
      ),
    );
  }
}

// ── performance over a period ─────────────────────────────────────────────────

class _PeriodHeader extends StatelessWidget {
  final int days;
  final List<int> periods;
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<int> onChanged;
  const _PeriodHeader({required this.days, required this.periods, this.from, this.to, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final text = Theme.of(context).textTheme;
    final title = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(header: true, child: Text('Performa', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
      Text('$days hari terakhir · ${_range(from, to)}', style: text.bodySmall?.copyWith(color: t.muted)),
    ]);
    final selector = SegmentedButton<int>(
      segments: [for (final d in periods) ButtonSegment(value: d, label: Text('$d hari'))],
      selected: {days},
      showSelectedIcon: false,
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.standard,
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppTheme.gold.withValues(alpha: 0.18) : null,
        ),
      ),
    );
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 520) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [title, const SizedBox(height: 12), selector]);
      }
      return Row(children: [Expanded(child: title), selector]);
    });
  }
}

class _TrendCard extends StatelessWidget {
  final PeriodSummary period;
  const _TrendCard({required this.period});

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final text = Theme.of(context).textTheme;
    final hasSales = period.daily.any((d) => d.revenue > 0);
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Pendapatan', style: text.labelLarge?.copyWith(color: t.muted)),
        const SizedBox(height: 4),
        Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 12, runSpacing: 4, children: [
          Text(_rupiah(period.revenue),
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${_count.format(period.transactions)} transaksi', style: text.bodySmall?.copyWith(color: t.muted)),
          ),
        ]),
        const SizedBox(height: 6),
        _Delta(change: period.revenueChange, comparedWith: 'vs ${period.days} hari sebelumnya'),
        const SizedBox(height: 20),
        SizedBox(
          height: 200,
          child: hasSales
              ? _TrendChart(daily: period.daily)
              : const _EmptyNote(Icons.show_chart, 'Belum ada penjualan di periode ini'),
        ),
      ]),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<DailyRevenue> daily;
  const _TrendChart({required this.daily});

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final maxRevenue = daily.map((d) => d.revenue).fold<double>(0, math.max);
    final yInterval = _niceInterval(maxRevenue / 3);
    final maxY = (maxRevenue / yInterval).ceil() * yInterval;
    final labelEvery = math.max(1, (daily.length / 6).ceil());
    final axisStyle = TextStyle(fontSize: 11, color: t.muted);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY <= 0 ? 1 : maxY,
        minX: 0,
        maxX: (daily.length - 1).toDouble(),
        clipData: const FlClipData.all(),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) => FlLine(color: t.border, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              interval: yInterval,
              getTitlesWidget: (v, meta) => v == meta.max && v != 0
                  ? const SizedBox.shrink()
                  : SideTitleWidget(axisSide: meta.axisSide, child: Text(_compact(v).replaceFirst('Rp', ''), style: axisStyle)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                final fromEnd = daily.length - 1 - i;
                if (i < 0 || i >= daily.length || v != i || fromEnd % labelEvery != 0) return const SizedBox.shrink();
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  fitInside: SideTitleFitInsideData.fromTitleMeta(meta, distanceFromEdge: 0),
                  child: Text(_shortDate(daily[i].date), style: axisStyle),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => const Color(0xFF1F1F1F),
            getTooltipItems: (spots) => spots.map((s) {
              final d = daily[s.x.round()];
              return LineTooltipItem(
                '${_weekdays[d.date.weekday - 1]}, ${_shortDate(d.date)}\n',
                const TextStyle(color: Color(0xFFBDBDBD), fontSize: 11),
                children: [
                  TextSpan(
                    text: _rupiah(d.revenue),
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: '\n${_count.format(d.transactions)} transaksi',
                    style: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 11),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < daily.length; i++) FlSpot(i.toDouble(), daily[i].revenue)],
            isCurved: true,
            preventCurveOverShooting: true,
            color: AppTheme.gold,
            barWidth: 2.5,
            dotData: FlDotData(show: daily.length <= 7),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppTheme.gold.withValues(alpha: 0.25), AppTheme.gold.withValues(alpha: 0)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 1, 2 or 5 times a power of ten, so axis labels read as round numbers.
  static double _niceInterval(double raw) {
    if (raw <= 0) return 1;
    final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final step = raw / magnitude;
    final nice = step <= 1 ? 1 : (step <= 2 ? 2 : (step <= 5 ? 5 : 10));
    return nice * magnitude;
  }
}

class _BranchCard extends StatelessWidget {
  final List<BranchPerformance> branches;
  final int days;
  const _BranchCard({required this.branches, required this.days});

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final text = Theme.of(context).textTheme;
    final total = branches.fold<double>(0, (s, b) => s + b.revenue);
    final top = branches.fold<double>(0, (m, b) => math.max(m, b.revenue));

    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const _PanelTitle('Cabang', subtitle: 'Diurutkan dari pendapatan tertinggi'),
        const SizedBox(height: 12),
        if (branches.isEmpty)
          const _EmptyNote(Icons.storefront_outlined, 'Belum ada cabang aktif')
        else
          for (final b in branches)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Flexible(
                    child: Text(b.name,
                        style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (b.code.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(b.code, style: text.labelSmall?.copyWith(color: t.muted)),
                  ],
                  if (b.openShifts > 0) ...[const SizedBox(width: 8), const _OpenShiftBadge()],
                  const Spacer(),
                  const SizedBox(width: 8),
                  Text(b.revenue > 0 ? _compact(b.revenue) : '—',
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
                ]),
                const SizedBox(height: 6),
                _ShareBar(top > 0 ? b.revenue / top : 0),
                const SizedBox(height: 4),
                Text(
                  b.revenue > 0
                      ? '${_count.format(b.transactions)} transaksi · ${(b.revenue / total * 100).round()}% dari total'
                      : 'Belum ada penjualan dalam $days hari',
                  style: text.labelSmall?.copyWith(color: t.muted),
                ),
              ]),
            ),
      ]),
    );
  }
}

class _OpenShiftBadge extends StatelessWidget {
  const _OpenShiftBadge();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'shift sedang buka',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text('Buka',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.success, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final List<RankedItem> categories;
  final int days;
  const _CategoryCard({required this.categories, required this.days});

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final text = Theme.of(context).textTheme;
    final total = categories.fold<double>(0, (s, c) => s + c.revenue);

    // Five named rows at most; the rest add up to "Lainnya" so the shares still total 100%.
    final rows = categories.take(5).toList();
    if (categories.length > 5) {
      final rest = categories.skip(5);
      rows.add(RankedItem('Lainnya', rest.fold(0, (s, c) => s + c.revenue), rest.fold(0, (s, c) => s + c.qty)));
    }

    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const _PanelTitle('Kategori', subtitle: 'Bagian dari pendapatan'),
        const SizedBox(height: 12),
        if (total <= 0)
          const _EmptyNote(Icons.category_outlined, 'Belum ada penjualan di periode ini')
        else
          for (final c in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Text(c.name,
                        style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Text('${(c.revenue / total * 100).round()}%',
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
                ]),
                const SizedBox(height: 6),
                _ShareBar(c.revenue / total),
                const SizedBox(height: 4),
                Text('${_compact(c.revenue)} · ${_count.format(c.qty)} item',
                    style: text.labelSmall?.copyWith(color: t.muted)),
              ]),
            ),
      ]),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final List<RankedItem> products;
  final int days;
  const _ProductCard({required this.products, required this.days});

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final text = Theme.of(context).textTheme;
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const _PanelTitle('Produk terlaris', subtitle: 'Berdasarkan jumlah terjual, semua cabang'),
        const SizedBox(height: 8),
        if (products.isEmpty)
          const _EmptyNote(Icons.shopping_bag_outlined, 'Belum ada produk terjual di periode ini')
        else
          for (var i = 0; i < products.length; i++) ...[
            if (i > 0) Divider(height: 1, color: t.border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                SizedBox(
                  width: 28,
                  child: Text('${i + 1}',
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: i == 0 ? t.accentText : t.muted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ),
                Expanded(
                  child: Text(products[i].name,
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${_count.format(products[i].qty)} terjual',
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
                  Text(_compact(products[i].revenue), style: text.labelSmall?.copyWith(color: t.muted)),
                ]),
              ]),
            ),
          ],
      ]),
    );
  }
}

// ── loading & error ───────────────────────────────────────────────────────────

/// Mirrors the real layout so the page does not jump when data arrives.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF1A1A1A) : const Color(0xFFEDEAE3);
    final highlight = dark ? const Color(0xFF262626) : const Color(0xFFF7F5F0);
    Widget block(double height, {double? width, double radius = 16}) => Align(
          alignment: Alignment.centerLeft,
          child: Container(
            height: height,
            width: width ?? double.infinity,
            decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(radius)),
          ),
        );
    return Semantics(
      label: 'Memuat ringkasan bisnis',
      child: Shimmer.fromColors(
        baseColor: base,
        highlightColor: highlight,
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            block(14, width: 160, radius: 6),
            const SizedBox(height: 8),
            block(26, width: 220, radius: 6),
            const SizedBox(height: 20),
            block(190),
            const SizedBox(height: 16),
            block(150),
            const SizedBox(height: 16),
            block(120),
            const SizedBox(height: 24),
            block(22, width: 140, radius: 6),
            const SizedBox(height: 12),
            block(300),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off_outlined, size: 48, color: t.muted),
          const SizedBox(height: 16),
          Text('Ringkasan belum bisa dimuat', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Periksa koneksi internet dan pastikan server berjalan, lalu coba lagi.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: t.muted),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Coba lagi')),
        ]),
      ),
    );
  }
}
