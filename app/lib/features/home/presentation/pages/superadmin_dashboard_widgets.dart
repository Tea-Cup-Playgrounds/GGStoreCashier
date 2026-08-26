part of 'superadmin_dashboard_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

double _n(dynamic v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0.0;
}

String _pct(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}%';

Widget _buildCard({required BuildContext context, required Widget child, double? height}) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    height: height,
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: cs.outlineVariant),
    ),
    child: child,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Section title row
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const _SectionTitle({required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        if (subtitle != null)
          Text(subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.5))),
      ])),
      if (trailing != null) trailing!,
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Toggle pill (segmented button replacement)
// ─────────────────────────────────────────────────────────────────────────────

class _TogglePill extends StatelessWidget {
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;
  final bool wide;
  const _TogglePill({
    required this.options,
    required this.selected,
    required this.onChanged,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: wide ? double.infinity : null,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min, children: [
        for (int i = 0; i < options.length; i++)
          Expanded(
            flex: wide ? 1 : 0,
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: i == selected ? AppTheme.gold : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  options[i],
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: i == selected ? FontWeight.w600 : FontWeight.normal,
                        color: i == selected ? Colors.white : cs.onSurface.withValues(alpha: 0.7),
                      ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error tile
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorTile extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorTile({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 32, color: AppTheme.destructive),
        const SizedBox(height: 8),
        Text('Gagal memuat data', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        Text(message,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Coba Lagi'),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card 1: Total Sales Today
// ─────────────────────────────────────────────────────────────────────────────

class _SalesTodayCard extends StatelessWidget {
  final SalesKpi sales;
  const _SalesTodayCard({required this.sales});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.monetization_on_outlined, size: 16, color: AppTheme.gold),
          const SizedBox(width: 6),
          Text('Total Penjualan Hari Ini',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
        const SizedBox(height: 6),
        AnimatedNumber(
          value: CurrencyFormatter.formatToRupiah(sales.todayRevenue),
          style:
              Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: AppTheme.gold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        // vs yesterday and last week inline
        Row(children: [
          _DeltaBadge(label: 'vs Kemarin', value: sales.vsYesterday),
          const SizedBox(width: 16),
          _DeltaBadge(label: 'vs Minggu Lalu', value: sales.vsLastWeek),
        ]),
      ]),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  final String label;
  final double value;
  const _DeltaBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final up = value >= 0;
    final color = up ? AppTheme.success : AppTheme.destructive;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(up ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: color),
      const SizedBox(width: 3),
      Text(_pct(value),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.bold)),
      const SizedBox(width: 4),
      Text(label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card 2: Active branches
// ─────────────────────────────────────────────────────────────────────────────

class _BranchCard extends StatelessWidget {
  final BranchStatus? branches;
  const _BranchCard({required this.branches});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final b = branches;
    return _buildCard(
        context: context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              const Icon(Icons.store_outlined, size: 16, color: AppTheme.mutedForeground),
              const SizedBox(width: 6),
              Text('Cabang Aktif', style: Theme.of(context).textTheme.bodySmall),
            ]),
            const SizedBox(height: 8),
            AnimatedNumber(
              value: b != null ? '${b.active}/${b.total}' : '—',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface),
            ),
            const SizedBox(height: 4),
            if (b != null && b.offline > 0)
              Text('${b.offline} offline (tdk ada penjualan)',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.destructive),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)
            else
              Text('Semua cabang aktif',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.success), maxLines: 1),
          ],
        ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card 3: Total transactions + AOV
// ─────────────────────────────────────────────────────────────────────────────

class _TxAovCard extends StatelessWidget {
  final SalesKpi sales;
  const _TxAovCard({required this.sales});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final aov = CurrencyFormatter.formatToCompactRupiah(sales.avgOrderValue);
    return _buildCard(
        context: context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              const Icon(Icons.receipt_outlined, size: 16, color: AppTheme.mutedForeground),
              const SizedBox(width: 6),
              Text('Transaksi', style: Theme.of(context).textTheme.bodySmall),
            ]),
            const SizedBox(height: 8),
            // XXX | RpYYrb
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              AnimatedNumber(
                value: '${sales.todayTxCount}',
                style:
                    Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface),
              ),
              Text(' | ',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.4))),
              Flexible(
                  child: AnimatedNumber(
                value: aov,
                style:
                    Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: _palette[1]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )),
            ]),
            const SizedBox(height: 4),
            Text('Rata-rata per transaksi',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.5)),
                maxLines: 1),
          ],
        ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Leaderboard — horizontal scrollable grouped bar chart
// ─────────────────────────────────────────────────────────────────────────────

class _LeaderboardChart extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  const _LeaderboardChart({required this.entries});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (entries.isEmpty) {
      return _buildCard(
          context: context,
          height: 180,
          child:
              Center(child: Text('Belum ada data penjualan hari ini', style: Theme.of(context).textTheme.bodySmall)));
    }

    final maxVal = entries.fold(
        0.0, (m, e) => e.todayRevenue > m ? e.todayRevenue : (e.yesterdayRevenue > m ? e.yesterdayRevenue : m));
    if (maxVal == 0) {
      return _buildCard(
          context: context,
          height: 180,
          child:
              Center(child: Text('Belum ada data penjualan hari ini', style: Theme.of(context).textTheme.bodySmall)));
    }

    // Chart width: 80px per branch, min 300
    final chartWidth = (entries.length * 80.0).clamp(300.0, double.infinity);

    return _buildCard(
        context: context,
        child: SizedBox(
          height: 200,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: chartWidth,
              child: BarChart(BarChartData(
                maxY: maxVal * 1.35,
                groupsSpace: 12,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: cs.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= entries.length) return const SizedBox.shrink();
                      final name = entries[i].branchName;
                      final short = name.length > 9 ? '${name.substring(0, 8)}…' : name;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(short,
                            style: const TextStyle(fontSize: 9, color: AppTheme.mutedForeground),
                            textAlign: TextAlign.center),
                      );
                    },
                  )),
                ),
                barGroups: entries.asMap().entries.map((e) {
                  final idx = e.key;
                  final entry = e.value;
                  final color = _palette[idx % _palette.length];
                  return BarChartGroupData(
                      x: idx,
                      barRods: [
                        // Yesterday bar — very low opacity background
                        BarChartRodData(
                          toY: entry.yesterdayRevenue,
                          color: color.withValues(alpha: 0.15),
                          width: 22,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                        // Today bar — solid
                        BarChartRodData(
                          toY: entry.todayRevenue,
                          color: color,
                          width: 22,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          rodStackItems: [],
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxVal * 1.35,
                            color: color.withValues(alpha: 0.04),
                          ),
                        ),
                      ],
                      barsSpace: 3);
                }).toList(),
                barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final entry = entries[group.x];
                    final label = rodIndex == 0 ? 'Kemarin' : 'Hari Ini';
                    return BarTooltipItem(
                      '${entry.branchName}\n$label: ${CurrencyFormatter.formatToCompactRupiah(rod.toY)}',
                      const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                    );
                  },
                )),
              )),
            ),
          ),
        ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sales Trend line chart
// ─────────────────────────────────────────────────────────────────────────────

class _TrendChart extends StatelessWidget {
  final List<TrendPoint> points;
  final String trendType;
  const _TrendChart({required this.points, required this.trendType});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return _buildCard(
          context: context,
          height: 200,
          child: Center(child: Text('Belum ada data untuk periode ini', style: Theme.of(context).textTheme.bodySmall)));
    }

    final spots = points.asMap().entries.map((e) => FlSpot(e.key.toDouble(), _n(e.value.revenue))).toList();
    final maxY = spots.map((s) => s.y).fold(0.0, (a, b) => a > b ? a : b);

    return _buildCard(
        context: context,
        child: SizedBox(
          height: 210,
          child: LineChart(LineChartData(
            minY: 0,
            maxY: maxY == 0 ? 1 : maxY * 1.3,
            clipData: const FlClipData.all(),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.withValues(alpha: 0.12), strokeWidth: 1),
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
                interval: points.length <= 8 ? 1 : (points.length / 6).ceilToDouble(),
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child:
                        Text(points[idx].label, style: const TextStyle(fontSize: 9, color: AppTheme.mutedForeground)),
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
                color: _palette[0],
                barWidth: 2.5,
                dotData: FlDotData(
                  show: points.length <= 24,
                  getDotPainter: (_, __, ___, ____) =>
                      FlDotCirclePainter(radius: 3, color: _palette[0], strokeWidth: 1.5, strokeColor: Colors.white),
                ),
                belowBarData: BarAreaData(show: true, color: _palette[0].withValues(alpha: 0.09)),
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
        ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top Selling — horizontal bar chart (max 10)
// ─────────────────────────────────────────────────────────────────────────────

class _TopSellingChart extends StatelessWidget {
  final List<TopItem> items;
  const _TopSellingChart({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _buildCard(
          context: context,
          height: 120,
          child:
              Center(child: Text('Belum ada data penjualan hari ini', style: Theme.of(context).textTheme.bodySmall)));
    }
    final top = items.take(10).toList();
    final maxQty = top.fold(0, (m, e) => e.totalQty > m ? e.totalQty : m).toDouble();

    return _buildCard(
        context: context,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: top.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final pct = maxQty > 0 ? item.totalQty / maxQty : 0.0;
            final color = _palette[i % _palette.length];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                      child: Text(item.name,
                          style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  Text('${item.totalQty} terjual',
                      style:
                          Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 4),
                LayoutBuilder(builder: (ctx, constraints) {
                  return Stack(children: [
                    Container(
                      height: 8,
                      width: constraints.maxWidth,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Container(
                      height: 8,
                      width: constraints.maxWidth * pct,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ]);
                }),
              ]),
            );
          }).toList(),
        ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live Transaction Feed (max 20, animated on new entry)
// ─────────────────────────────────────────────────────────────────────────────

class _LiveTransactionFeed extends StatelessWidget {
  final List<LiveTransaction> transactions;
  final bool isLoading;
  const _LiveTransactionFeed({required this.transactions, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
          height: 160, child: Center(child: CircularProgressIndicator(color: AppTheme.gold, strokeWidth: 2)));
    }
    if (transactions.isEmpty) {
      return _buildCard(
          context: context,
          height: 100,
          child: Center(child: Text('Belum ada transaksi hari ini', style: Theme.of(context).textTheme.bodySmall)));
    }
    return _buildCard(
        context: context,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row
            Row(children: [
              Expanded(
                  child: Text('Feed Transaksi Live',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text('Live',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: AppTheme.success, fontWeight: FontWeight.bold)),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            ...transactions.map((tx) => _TxFeedRow(tx: tx, key: ValueKey(tx.id))),
          ],
        ));
  }
}

class _TxFeedRow extends StatefulWidget {
  final LiveTransaction tx;
  const _TxFeedRow({required this.tx, super.key});

  @override
  State<_TxFeedRow> createState() => _TxFeedRowState();
}

class _TxFeedRowState extends State<_TxFeedRow> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tx = widget.tx;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            // Branch initial avatar
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _palette[(tx.id % _palette.length)].withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                  child: Text(
                (tx.branchName?.isNotEmpty == true) ? tx.branchName![0].toUpperCase() : '?',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: _palette[tx.id % _palette.length],
                ),
              )),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(tx.branchName ?? 'Cabang',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                Text(CurrencyFormatter.formatToRupiah(tx.finalAmount),
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: AppTheme.gold, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                Expanded(
                    child: Text('${tx.itemCount} item · ${tx.paymentMethod ?? 'cash'}',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: cs.onSurface.withValues(alpha: 0.5)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                Text(tx.relativeTime,
                    style:
                        Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.4))),
              ]),
            ])),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stock segment — counters + clickable rows for modal
// ─────────────────────────────────────────────────────────────────────────────

class _StockSegment extends StatelessWidget {
  final StockCounts? stock;
  final bool isLoading;
  const _StockSegment({required this.stock, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    if (isLoading || stock == null) {
      return const SizedBox(
          height: 120, child: Center(child: CircularProgressIndicator(color: AppTheme.gold, strokeWidth: 2)));
    }
    return _buildCard(
        context: context,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                  child: Text('Status Stok Live',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text('Live',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: AppTheme.success, fontWeight: FontWeight.bold)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                  child: _StockCountTile(
                count: stock!.lowCount,
                label: 'Stok Kritis',
                icon: Icons.warning_amber_rounded,
                color: AppTheme.warning,
                type: 'low',
              )),
              const SizedBox(width: 12),
              Expanded(
                  child: _StockCountTile(
                count: stock!.outCount,
                label: 'Habis',
                icon: Icons.remove_shopping_cart_outlined,
                color: AppTheme.destructive,
                type: 'out',
              )),
            ]),
          ],
        ));
  }
}

class _StockCountTile extends StatefulWidget {
  final int count;
  final String label;
  final IconData icon;
  final Color color;
  final String type;
  const _StockCountTile({
    required this.count,
    required this.label,
    required this.icon,
    required this.color,
    required this.type,
  });

  @override
  State<_StockCountTile> createState() => _StockCountTileState();
}

class _StockCountTileState extends State<_StockCountTile> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  }

  @override
  void didUpdateWidget(_StockCountTile old) {
    super.didUpdateWidget(old);
    if (old.count != widget.count) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _showModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _StockDetailModal(type: widget.type),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _showModal,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) {
          final glow = _pulse.value > 0 && _pulse.value < 1;
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.08 + (_pulse.value * 0.08)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: widget.color.withValues(alpha: glow ? 0.5 : 0.2)),
            ),
            child: child,
          );
        },
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(widget.icon, size: 20, color: widget.color),
          const SizedBox(height: 8),
          AnimatedNumber(
            value: '${widget.count}',
            style:
                Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: widget.color),
          ),
          const SizedBox(height: 2),
          Text(widget.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: widget.color.withValues(alpha: 0.8))),
          const SizedBox(height: 4),
          Text('Ketuk untuk detail',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4))),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stock detail bottom sheet modal
// ─────────────────────────────────────────────────────────────────────────────

class _StockDetailModal extends StatefulWidget {
  final String type; // 'low' | 'out'
  const _StockDetailModal({required this.type});

  @override
  State<_StockDetailModal> createState() => _StockDetailModalState();
}

class _StockDetailModalState extends State<_StockDetailModal> {
  bool _loading = true;
  List<Map<String, dynamic>> _products = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await SuperadminDashboardService.getStockDetail(widget.type);
    if (mounted) {
      setState(() {
        _products = data;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = widget.type == 'out' ? 'Produk Stok Habis' : 'Produk Stok Kritis';
    final color = widget.type == 'out' ? AppTheme.destructive : AppTheme.warning;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(children: [
              Icon(widget.type == 'out' ? Icons.remove_shopping_cart_outlined : Icons.warning_amber_rounded,
                  color: color, size: 20),
              const SizedBox(width: 8),
              Text(title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: color)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.gold, strokeWidth: 2))
                : _products.isEmpty
                    ? Center(child: Text('Tidak ada produk $title', style: Theme.of(context).textTheme.bodySmall))
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _products.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final p = _products[i];
                          final stock = p['stock'] as int? ?? 0;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(children: [
                              Expanded(
                                  child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p['name']?.toString() ?? '',
                                      style:
                                          Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 2),
                                  Text('${p['category_name'] ?? '-'} · ${p['branch_name'] ?? '-'}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ],
                              )),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('Stok: $stock',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                              ),
                            ]),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}
