import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/helper/currency_formatter.dart';
import '../../../../core/provider/auth_provider.dart';
import '../../../../core/provider/realtime_provider.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/services/admin_dashboard_service.dart';
import '../../../../core/services/connectivity_monitor.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/animated_number.dart';
import '../../../../shared/widgets/chart_rerender.dart';
import '../../../../shared/widgets/live_clock.dart';

// ── palette (mirrors superadmin) ─────────────────────────────────────────────
const _kPalette = [
  Color(0xFFD4AF37),
  Color(0xFF6366F1),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
  Color(0xFF8B5CF6),
];

class AdminDashboardPage extends ConsumerStatefulWidget {
  const AdminDashboardPage({super.key});
  @override
  ConsumerState<AdminDashboardPage> createState() => _AdminDashState();
}

class _AdminDashState extends ConsumerState<AdminDashboardPage> {
  bool _loading = true;
  bool _stale = false;
  AdminDashboardData? _data;
  String _trendType = 'hourly';

  ProviderSubscription<RealtimeTransactionState>? _txSub;
  StreamSubscription<ConnectivityStatus>? _connectSub;
  ConnectivityStatus? _lastConn;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // Periodic fallback: re-fetch every 30 s so numbers stay live even
    // when the socket is silent (ngrok reconnect, firewall, etc.)
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _load(force: true);
    });
    _connectSub = ConnectivityMonitor.instance.statusStream.listen((s) {
      if (_lastConn == ConnectivityStatus.offline && s == ConnectivityStatus.online) _load();
      _lastConn = s;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to live transactions store — triggers reload every 500 ms
    // automatically via the store's internal poll timer. We only need to
    // re-fetch fresh aggregate numbers (totals, trend) when a new payment lands.
    _txSub ??= ref.listenManual(realtimeTransactionProvider, (prev, next) {
      if (next.lastUpdateTime != prev?.lastUpdateTime) _load(force: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _txSub?.close();
    _connectSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    // Only show the full loading spinner on the very first load
    if (_data == null) setState(() => _loading = true);
    try {
      final d = await AdminDashboardService.get(trendType: _trendType, forceRefresh: force);
      if (mounted) {
        setState(() {
          _data = d;
          _stale = AdminDashboardService.lastFetchWasStale;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeTrend(String t) {
    setState(() => _trendType = t);
    _load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => _load(force: true),
        color: AppTheme.gold,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              sliver: SliverList(
                  delegate: SliverChildListDelegate([
                _buildHeader(user?.name ?? 'Admin'),
                const SizedBox(height: 16),
                if (_loading && _data == null)
                  const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator(color: AppTheme.gold, strokeWidth: 2)))
                else if (_data != null) ...[
                  _OmsetCard(data: _data!),
                  const SizedBox(height: 12),
                  _KasCard(data: _data!),
                  const SizedBox(height: 20),
                  _TrendSection(
                    data: _data!,
                    trendType: _trendType,
                    onChangeTrend: _changeTrend,
                  ),
                  const SizedBox(height: 20),
                  _QuickShortcuts(isKaryawan: user?.isEmployee ?? false),
                ],
              ])),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String name) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_greet(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.55))),
        Text(name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        if (_data != null)
          Text(_data!.branchName, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.gold)),
      ])),
      if (_stale)
        const Tooltip(
            message: 'Data mungkin tidak terbaru', child: Icon(Icons.cloud_off, size: 14, color: Colors.orange)),
      const SizedBox(width: 4),
      const LiveClock(),
      const SizedBox(width: 4),
      IconButton(
        icon: const Icon(Icons.refresh, size: 20),
        color: AppTheme.mutedForeground,
        onPressed: () => _load(force: true),
      ),
    ]);
  }

  String _greet() {
    final h = DateTime.now().hour;
    if (h < 10) return 'Selamat Pagi';
    if (h < 15) return 'Selamat Siang';
    if (h < 18) return 'Selamat Sore';
    return 'Selamat Malam';
  }
}

// ── Omset card ────────────────────────────────────────────────────────────────

class _OmsetCard extends StatelessWidget {
  final AdminDashboardData data;
  const _OmsetCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = data.targetPendapatan > 0 ? (data.todayRevenue / data.targetPendapatan).clamp(0.0, 1.0) : 0.0;
    final overTarget = data.targetPendapatan > 0 && data.todayRevenue >= data.targetPendapatan;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.storefront_outlined, size: 16, color: AppTheme.gold),
          const SizedBox(width: 6),
          Text('Omset Hari Ini', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.gold)),
          const Spacer(),
          if (overTarget)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.check_circle_outline, size: 12, color: AppTheme.success),
                const SizedBox(width: 4),
                Text('Target tercapai!',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppTheme.success, fontWeight: FontWeight.bold)),
              ]),
            ),
        ]),
        const SizedBox(height: 6),
        // Revenue | Target side-by-side
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Flexible(
              child: AnimatedNumber(
            value: CurrencyFormatter.formatToRupiah(data.todayRevenue),
            style:
                Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: AppTheme.gold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )),
          if (data.targetPendapatan > 0) ...[
            Text(' | ',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.35))),
            Flexible(
                child: Text(
              CurrencyFormatter.formatToRupiah(data.targetPendapatan),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.5)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )),
          ],
        ]),
        if (data.targetPendapatan > 0) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: AppTheme.gold.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(overTarget ? AppTheme.success : AppTheme.gold),
            ),
          ),
          const SizedBox(height: 4),
          Text('${(pct * 100).toStringAsFixed(1)}% dari target',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.5))),
        ],
        const SizedBox(height: 6),
        Text('${data.todayTxCount} transaksi hari ini',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.55))),
      ]),
    );
  }
}

// ── Status Kas card ───────────────────────────────────────────────────────────

class _KasCard extends StatelessWidget {
  final AdminDashboardData data;
  const _KasCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = data.cashTotal + data.digitalTotal;
    final cashPct = total > 0 ? data.cashTotal / total : 0.5;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.account_balance_wallet_outlined, size: 16, color: AppTheme.mutedForeground),
          const SizedBox(width: 6),
          Text('Status Kas', style: Theme.of(context).textTheme.bodySmall),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: _KasTile(
            label: 'Tunai',
            icon: Icons.payments_outlined,
            amount: data.cashTotal,
            color: _kPalette[2],
          )),
          const SizedBox(width: 12),
          Expanded(
              child: _KasTile(
            label: 'Digital',
            icon: Icons.contactless_outlined,
            amount: data.digitalTotal,
            color: _kPalette[1],
          )),
        ]),
        const SizedBox(height: 10),
        // Split bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(children: [
            Flexible(
              flex: (cashPct * 100).round().clamp(1, 99),
              child: Container(height: 6, color: _kPalette[2]),
            ),
            Flexible(
              flex: ((1 - cashPct) * 100).round().clamp(1, 99),
              child: Container(height: 6, color: _kPalette[1]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _KasTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final double amount;
  final Color color;
  const _KasTile({required this.label, required this.icon, required this.amount, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 6),
        AnimatedNumber(
          value: CurrencyFormatter.formatToCompactRupiah(amount),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: color),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.55))),
      ]),
    );
  }
}

// ── Trend section ─────────────────────────────────────────────────────────────

class _TrendSection extends StatelessWidget {
  final AdminDashboardData data;
  final String trendType;
  final ValueChanged<String> onChangeTrend;
  const _TrendSection({required this.data, required this.trendType, required this.onChangeTrend});

  static const _options = [('Jam', 'hourly'), ('Harian', 'daily'), ('Mingguan', 'weekly'), ('Bulanan', 'monthly')];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Penjualan', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          Text('Tren pendapatan cabang',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.5))),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: trendType,
              isDense: true,
              dropdownColor: cs.surface,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface),
              items: _options.map((o) => DropdownMenuItem(value: o.$2, child: Text(o.$1))).toList(),
              onChanged: (v) {
                if (v != null) onChangeTrend(v);
              },
            ),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      ChartRerender(child: _AdminTrendChart(points: data.trend)),
    ]);
  }
}

class _AdminTrendChart extends StatelessWidget {
  final List<AdminTrendPoint> points;
  const _AdminTrendChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (points.isEmpty) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Center(child: Text('Belum ada data untuk periode ini', style: Theme.of(context).textTheme.bodySmall)),
      );
    }

    final spots = points.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.revenue)).toList();
    final maxY = spots.map((s) => s.y).fold(0.0, (a, b) => a > b ? a : b);

    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(4, 14, 14, 4),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: LineChart(LineChartData(
        minY: 0,
        maxY: maxY == 0 ? 1 : maxY * 1.3,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: cs.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
              sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 54,
            getTitlesWidget: (v, _) => Text(
              CurrencyFormatter.formatToCompactRupiah(v),
              style: const TextStyle(fontSize: 9, color: AppTheme.mutedForeground),
            ),
          )),
          bottomTitles: AxisTitles(
              sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval: points.length <= 8 ? 1 : (points.length / 5).ceilToDouble(),
            getTitlesWidget: (v, _) {
              final idx = v.toInt();
              if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(points[idx].label, style: const TextStyle(fontSize: 9, color: AppTheme.mutedForeground)),
              );
            },
          )),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: _kPalette[0],
            barWidth: 2.5,
            dotData: FlDotData(
              show: points.length <= 24,
              getDotPainter: (_, __, ___, ____) =>
                  FlDotCirclePainter(radius: 3, color: _kPalette[0], strokeWidth: 1.5, strokeColor: Colors.white),
            ),
            belowBarData: BarAreaData(show: true, color: _kPalette[0].withValues(alpha: 0.09)),
          )
        ],
        lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (ts) => ts.map((s) {
            final idx = s.x.toInt().clamp(0, points.length - 1);
            return LineTooltipItem(
              '${points[idx].label}\n${CurrencyFormatter.formatToCompactRupiah(s.y)}',
              const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
            );
          }).toList(),
        )),
      )),
    );
  }
}

// ── Quick shortcuts ───────────────────────────────────────────────────────────

class _QuickShortcuts extends StatelessWidget {
  final bool isKaryawan;
  const _QuickShortcuts({required this.isKaryawan});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = [
      if (!isKaryawan)
        _ShortcutItem(Icons.add_box_outlined, 'Tambah Produk', () => context.push(AppRouter.inventoryAddItem)),
      if (!isKaryawan) _ShortcutItem(Icons.category_outlined, 'Kategori', () => context.push(AppRouter.categoryForm)),
      if (!isKaryawan) _ShortcutItem(Icons.people_outlined, 'Pengguna', () => context.push(AppRouter.userManagement)),
      _ShortcutItem(Icons.bluetooth, 'Perangkat', () => context.push(AppRouter.deviceManager)),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Pintasan', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.9,
        children: items
            .map((item) => GestureDetector(
                  onTap: item.onTap,
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(item.icon, size: 26, color: AppTheme.gold),
                      const SizedBox(height: 6),
                      Text(item.label,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ))
            .toList(),
      ),
    ]);
  }
}

class _ShortcutItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ShortcutItem(this.icon, this.label, this.onTap);
}
