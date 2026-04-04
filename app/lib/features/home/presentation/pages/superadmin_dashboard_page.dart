// ignore_for_file: library_private_types_in_public_api
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/connectivity_monitor.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/helper/currency_formatter.dart';
import '../../../../core/helper/date_formatter.dart';
import '../../../../core/provider/auth_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/live_clock.dart';

const _palette = [
  Color(0xFFD4AF37), Color(0xFF6366F1), Color(0xFF10B981),
  Color(0xFFF59E0B), Color(0xFFEF4444), Color(0xFF8B5CF6),
  Color(0xFF06B6D4), Color(0xFFF97316),
];

const _periods = [
  _Period('7 Days', 7), _Period('14 Days', 14),
  _Period('30 Days', 30), _Period('90 Days', 90),
];

class _Period {
  final String label;
  final int days;
  const _Period(this.label, this.days);
}

// ─────────────────────────────────────────────────────────────────────────────

class SuperAdminDashboardPage extends ConsumerStatefulWidget {
  const SuperAdminDashboardPage({super.key});
  @override
  ConsumerState<SuperAdminDashboardPage> createState() => _DashState();
}

class _DashState extends ConsumerState<SuperAdminDashboardPage> {
  bool _loading = true;
  bool _isDataStale = false;
  String? _error;
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _trend = [], _branch = [], _cat = [], _top = [];
  int _trendDays = 30, _catDays = 30;
  String _branchDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

  StreamSubscription<ConnectivityStatus>? _connectivitySub;
  ConnectivityStatus? _lastConnectivity;

  @override
  void initState() {
    super.initState();
    _load();
    LocationService.requestPermission();
    _connectivitySub = ConnectivityMonitor.instance.statusStream.listen((status) {
      if (_lastConnectivity == ConnectivityStatus.offline &&
          status == ConnectivityStatus.online) {
        _load();
      }
      _lastConnectivity = status;
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await Future.wait([
        AnalyticsService.getSummary(),
        AnalyticsService.getRevenueTrend(_trendDays),
        AnalyticsService.getBranchRevenue(_branchDate),
        AnalyticsService.getCategorySales(_catDays),
        AnalyticsService.getTopProducts(30),
      ]);
      if (mounted) setState(() {
        _summary = r[0] as Map<String, dynamic>;
        _trend   = r[1] as List<Map<String, dynamic>>;
        _branch  = r[2] as List<Map<String, dynamic>>;
        _cat     = r[3] as List<Map<String, dynamic>>;
        _top     = r[4] as List<Map<String, dynamic>>;
        _isDataStale = false;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        if (_summary != null) {
          // We have previous data — show it as stale instead of error
          setState(() { _isDataStale = true; _loading = false; });
        } else {
          setState(() { _error = e.toString(); _loading = false; });
        }
      }
    }
  }

  Future<void> _reloadTrend() async {
    final d = await AnalyticsService.getRevenueTrend(_trendDays, forceRefresh: true);
    if (mounted) setState(() => _trend = d);
  }

  Future<void> _reloadBranch() async {
    final d = await AnalyticsService.getBranchRevenue(_branchDate, forceRefresh: true);
    if (mounted) setState(() => _branch = d);
  }

  Future<void> _reloadCat() async {
    final d = await AnalyticsService.getCategorySales(_catDays, forceRefresh: true);
    if (mounted) setState(() => _cat = d);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.gold));
    }
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, size: 56, color: AppTheme.destructive),
          const SizedBox(height: 16),
          Text('Failed to load analytics', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(_error!, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 24),
          ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ]),
      ));
    }

    // RefreshIndicator directly on CustomScrollView — no PullToRefresh wrapper
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.gold,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildHeader(user?.name ?? 'SuperAdmin'),
                  const SizedBox(height: 20),
                  _buildKpiGrid(),
                  const SizedBox(height: 24),
                  _buildCard(
                    title: 'Revenue Trend',
                    subtitle: 'Daily revenue — all branches',
                    trailing: _periodDrop(_trendDays, (v) {
                      setState(() => _trendDays = v);
                      _reloadTrend();
                    }),
                    child: SizedBox(
                      height: 220,
                      child: _trend.isEmpty
                          ? _emptyState('No revenue data for this period')
                          : _TrendChart(data: _trend),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildCard(
                    title: 'Branch Revenue',
                    subtitle: 'Revenue per branch on selected date',
                    trailing: _datePick(),
                    child: SizedBox(
                      height: 240,
                      child: _branch.isEmpty
                          ? _emptyState('No branch data')
                          : _BranchChart(data: _branch),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildCard(
                    title: 'Sales by Category',
                    subtitle: 'Most purchased categories',
                    trailing: _periodDrop(_catDays, (v) {
                      setState(() => _catDays = v);
                      _reloadCat();
                    }),
                    child: _cat.isEmpty
                        ? SizedBox(height: 160, child: _emptyState('No category data'))
                        : _PieChart(data: _cat),
                  ),
                  const SizedBox(height: 24),
                  _buildCard(
                    title: 'Top Products',
                    subtitle: 'Best sellers — last 30 days',
                    child: _top.isEmpty
                        ? SizedBox(height: 160, child: _emptyState('No product data'))
                        : _TopChart(data: _top),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String name) {
    return Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Analytics Dashboard',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
        Text('Welcome back, $name',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
      ])),
      const LiveClock(),
      const SizedBox(width: 4),
      if (_isDataStale)
        const Tooltip(
          message: 'Data mungkin tidak terbaru',
          child: Icon(Icons.cloud_off, size: 14, color: Colors.orange),
        ),
      IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh all'),
    ]);
  }

  Widget _buildKpiGrid() {
    if (_summary == null) return const SizedBox.shrink();
    final today = Map<String, dynamic>.from(_summary!['today'] as Map);
    final month = Map<String, dynamic>.from(_summary!['month'] as Map);
    final all   = Map<String, dynamic>.from(_summary!['allTime'] as Map);
    final act   = _summary!['activeBranchesToday'];

    final items = [
      _KpiData("Today's Revenue",  CurrencyFormatter.formatToCompactRupiah(_d(today['revenue'])),  Icons.today,                 _palette[0]),
      _KpiData("Today's Tx",       '${today['transactions']}',                                      Icons.receipt_outlined,      _palette[1]),
      _KpiData("Month Revenue",    CurrencyFormatter.formatToCompactRupiah(_d(month['revenue'])),   Icons.calendar_month,        _palette[2]),
      _KpiData("Active Branches",  '$act',                                                           Icons.store_outlined,        _palette[3]),
      _KpiData("All-time Revenue", CurrencyFormatter.formatToCompactRupiah(_d(all['revenue'])),     Icons.bar_chart,             _palette[5]),
      _KpiData("All-time Tx",      '${all['transactions']}',                                         Icons.shopping_bag_outlined, _palette[6]),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.65,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _KpiCard(data: items[i]),
    );
  }

  Widget _buildCard({
    required String title,
    required String subtitle,
    required Widget child,
    Widget? trailing,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(0.55))),
            ])),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
          ]),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _emptyState(String msg) => Center(
    child: Text(msg, style: const TextStyle(color: AppTheme.mutedForeground)),
  );

  Widget _periodDrop(int val, ValueChanged<int> cb) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: val, isDense: true, dropdownColor: cs.surface,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface),
          items: _periods.map((p) => DropdownMenuItem(value: p.days, child: Text(p.label))).toList(),
          onChanged: (v) { if (v != null) cb(v); },
        ),
      ),
    );
  }

  Widget _datePick() {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () async {
        final p = await showDatePicker(
          context: context,
          initialDate: DateTime.tryParse(_branchDate) ?? DateTime.now(),
          firstDate: DateTime(2024),
          lastDate: DateTime.now(),
        );
        if (p != null) {
          setState(() => _branchDate = DateFormat('yyyy-MM-dd').format(p));
          _reloadBranch();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.calendar_today_outlined, size: 14, color: cs.onSurface.withOpacity(0.7)),
          const SizedBox(width: 6),
          Text(DateFormatter.format(_branchDate), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface)),
        ]),
      ),
    );
  }

  static double _d(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }
}

// ── KPI card ──────────────────────────────────────────────────────────────────
class _KpiData {
  final String label, value;
  final IconData icon;
  final Color color;
  const _KpiData(this.label, this.value, this.icon, this.color);
}

class _KpiCard extends StatelessWidget {
  final _KpiData data;
  const _KpiCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: data.color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(data.icon, color: data.color, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(data.value,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold, color: data.color),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(data.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.55)),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        )),
      ]),
    );
  }
}

// ── Revenue trend line chart ──────────────────────────────────────────────────
double _n(dynamic v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0.0;
}

class _TrendChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _TrendChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final spots = data.asMap().entries.map((e) =>
        FlSpot(e.key.toDouble(), _n(e.value['revenue']))
    ).toList();

    final maxY = spots.isEmpty ? 1.0
        : spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);

    return LineChart(LineChartData(
      minY: 0,
      maxY: maxY == 0 ? 1 : maxY * 1.25,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true, drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: Colors.grey.withOpacity(0.15), strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 56,
          getTitlesWidget: (v, _) => Text(
            CurrencyFormatter.formatToCompactRupiah(v),
            style: const TextStyle(fontSize: 9, color: AppTheme.mutedForeground),
          ),
        )),
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 22,
          interval: data.length <= 7 ? 1 : (data.length / 5).ceilToDouble(),
          getTitlesWidget: (v, _) {
            final idx = v.toInt();
            if (idx < 0 || idx >= data.length) return const SizedBox.shrink();
            final raw = data[idx]['date']?.toString() ?? '';
            final label = DateFormatter.formatAxis(raw);
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(label, style: const TextStyle(fontSize: 9, color: AppTheme.mutedForeground)),
            );
          },
        )),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [LineChartBarData(
        spots: spots,
        isCurved: true,
        color: _palette[0],
        barWidth: 2.5,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: true, color: _palette[0].withOpacity(0.1)),
      )],
      lineTouchData: LineTouchData(touchTooltipData: LineTouchTooltipData(
        getTooltipItems: (ts) => ts.map((s) => LineTooltipItem(
          CurrencyFormatter.formatToCompactRupiah(s.y),
          const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
        )).toList(),
      )),
    ));
  }
}

// ── Branch bar chart ──────────────────────────────────────────────────────────
class _BranchChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _BranchChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final maxY = data.isEmpty ? 1.0
        : data.map((e) => _n(e['revenue']))
              .fold(0.0, (a, b) => a > b ? a : b);

    return BarChart(BarChartData(      maxY: maxY == 0 ? 1 : maxY * 1.3,
      gridData: FlGridData(
        show: true, drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: Colors.grey.withOpacity(0.15), strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 36,
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= data.length) return const SizedBox.shrink();
            final name = data[i]['branch_name']?.toString() ?? '';
            final short = name.length > 9 ? '${name.substring(0, 8)}…' : name;
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(short,
                  style: const TextStyle(fontSize: 9, color: AppTheme.mutedForeground),
                  textAlign: TextAlign.center),
            );
          },
        )),
        leftTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 56,
          getTitlesWidget: (v, _) => Text(
            CurrencyFormatter.formatToCompactRupiah(v),
            style: const TextStyle(fontSize: 9, color: AppTheme.mutedForeground),
          ),
        )),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      barGroups: data.asMap().entries.map((e) {
        final rev = _n(e.value['revenue']);
        final color = _palette[e.key % _palette.length];
        return BarChartGroupData(x: e.key, barRods: [
          BarChartRodData(
            toY: rev,
            color: color,
            width: 20,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true, toY: maxY * 1.3, color: color.withOpacity(0.07)),
          ),
        ]);
      }).toList(),
      barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(
        getTooltipItem: (group, _, rod, __) => BarTooltipItem(
          '${data[group.x]['branch_name']}\n${CurrencyFormatter.formatToCompactRupiah(rod.toY)}',
          const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      )),
    ));
  }
}

// ── Category pie chart ────────────────────────────────────────────────────────
class _PieChart extends StatefulWidget {
  final List<Map<String, dynamic>> data;
  const _PieChart({required this.data});
  @override
  State<_PieChart> createState() => _PieChartState();
}

class _PieChartState extends State<_PieChart> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final total = widget.data.fold(0.0, (s, e) => s + _n(e['total_qty']));

    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 200,
        child: PieChart(PieChartData(          pieTouchData: PieTouchData(touchCallback: (_, r) {
            setState(() => _touched = r?.touchedSection?.touchedSectionIndex ?? -1);
          }),
          sectionsSpace: 2,
          centerSpaceRadius: 36,
          sections: widget.data.asMap().entries.map((e) {
            final qty = _n(e.value['total_qty']);
            final pct = total > 0 ? qty / total * 100 : 0.0;
            final isTouched = e.key == _touched;
            final color = _palette[e.key % _palette.length];
            return PieChartSectionData(
              value: qty,
              color: color,
              radius: isTouched ? 72 : 60,
              title: '${pct.toStringAsFixed(1)}%',
              titleStyle: TextStyle(
                  fontSize: isTouched ? 13 : 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            );
          }).toList(),
        )),
      ),
      const SizedBox(height: 16),
      // Legend — 2-column grid, max 4 rows = 8 items
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 4.5, mainAxisSpacing: 4, crossAxisSpacing: 4,
        ),
        itemCount: widget.data.length > 8 ? 8 : widget.data.length,
        itemBuilder: (_, i) {
          final color = _palette[i % _palette.length];
          return Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Expanded(child: Text(
              widget.data[i]['category_name']?.toString() ?? 'Unknown',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            )),
          ]);
        },
      ),
    ]);
  }
}

// ── Top products progress bars ────────────────────────────────────────────────
class _TopChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _TopChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final maxQty = data.isEmpty ? 1.0
        : data.map((e) => _n(e['total_qty']))
              .fold(0.0, (a, b) => a > b ? a : b);
    final top = data.take(8).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: top.asMap().entries.map((e) {
        final qty = _n(e.value['total_qty']);
        final pct = maxQty > 0 ? qty / maxQty : 0.0;
        final color = _palette[e.key % _palette.length];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(
                e.value['name']?.toString() ?? '',
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1, overflow: TextOverflow.ellipsis,
              )),
              const SizedBox(width: 8),
              Text('${qty.toInt()} sold',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                backgroundColor: color.withOpacity(0.12),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ]),
        );
      }).toList(),
    );
  }
}
