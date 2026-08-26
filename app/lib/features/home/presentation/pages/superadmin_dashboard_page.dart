import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../core/models/superadmin_dashboard.dart';
import '../../../../core/provider/auth_provider.dart';
import '../../../../core/provider/realtime_store_provider.dart';
import '../../../../core/provider/superadmin_dashboard_provider.dart';
import '../../../../core/services/superadmin_dashboard_service.dart';
import '../../../../core/services/connectivity_monitor.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/helper/currency_formatter.dart';
import '../../../../shared/widgets/chart_rerender.dart';
import '../../../../shared/widgets/live_clock.dart';
import '../../../../shared/widgets/animated_number.dart';

part 'superadmin_dashboard_widgets.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _palette = [
  Color(0xFFD4AF37),
  Color(0xFF6366F1),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
  Color(0xFF8B5CF6),
  Color(0xFF06B6D4),
  Color(0xFFF97316),
  Color(0xFFEC4899),
  Color(0xFF14B8A6),
];

// ── Page ──────────────────────────────────────────────────────────────────────
class SuperAdminDashboardPage extends ConsumerStatefulWidget {
  const SuperAdminDashboardPage({super.key});
  @override
  ConsumerState<SuperAdminDashboardPage> createState() => _DashState();
}

class _DashState extends ConsumerState<SuperAdminDashboardPage> {
  // State
  bool _highFreqLoading = true;
  bool _lowFreqLoading = true;
  String? _highFreqError;
  bool _lowFreqStale = false;
  LowFreqDashboard? _lowFreq;
  String _trendType = 'hourly';

  // Bottom segment toggle: 0 = Transaksi, 1 = Stok
  int _segmentIndex = 0;
  // Top-selling toggle: 0 = Products, 1 = Categories
  int _topSellingIndex = 0;

  Timer? _lowFreqTimer;
  Timer? _highFreqTimer;
  StreamSubscription<ConnectivityStatus>? _connectSub;
  ConnectivityStatus? _lastConnectivity;

  @override
  void initState() {
    super.initState();
    _loadHighFreq();
    _loadLowFreq();
    _startLowFreqTimer();
    _startHighFreqTimer();

    _connectSub = ConnectivityMonitor.instance.statusStream.listen((status) {
      if (_lastConnectivity == ConnectivityStatus.offline && status == ConnectivityStatus.online) {
        _loadHighFreq();
        _loadLowFreq();
      }
      _lastConnectivity = status;
    });
  }

  void _startLowFreqTimer() {
    _lowFreqTimer?.cancel();
    _lowFreqTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      _loadLowFreq(force: true);
    });
  }

  /// Periodic fallback: re-fetch high-freq data every 30 s in case the socket
  /// is silent (e.g. behind ngrok, firewall, or reconnecting).
  void _startHighFreqTimer() {
    _highFreqTimer?.cancel();
    _highFreqTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadHighFreq(force: true);
    });
  }

  Future<void> _loadHighFreq({bool force = false}) async {
    setState(() {
      _highFreqLoading = true;
      _highFreqError = null;
    });
    try {
      final data = await SuperadminDashboardService.getHighFreq(forceRefresh: force);
      if (mounted) {
        ref.read(highFreqProvider.notifier).seedFromHttp(data);
        // Seed the live transaction SQLite store from the HTTP response so the
        // feed is populated immediately on first open (no waiting for a socket event)
        ref.read(liveTransactionStoreProvider.notifier).seedFromHttp(data.recentTransactions);
        setState(() => _highFreqLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _highFreqError = e.toString();
          _highFreqLoading = false;
        });
      }
    }
  }

  Future<void> _loadLowFreq({bool force = false}) async {
    // For background refreshes (timer / trend change) we don't set loading=true
    // so the existing data stays visible without a flicker. Only show the
    // loading spinner on the very first load (when _lowFreq is null).
    if (_lowFreq == null) {
      setState(() {
        _lowFreqLoading = true;
        _lowFreqStale = false;
      });
    }
    try {
      final data = await SuperadminDashboardService.getLowFreq(trendType: _trendType, forceRefresh: force);
      if (mounted) {
        setState(() {
          _lowFreq = data;
          _lowFreqStale = SuperadminDashboardService.lastLowFreqWasStale;
          _lowFreqLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lowFreqStale = _lowFreq != null;
          _lowFreqLoading = false;
        });
      }
    }
  }

  Future<void> _onPullRefresh() async {
    await Future.wait([_loadHighFreq(force: true), _loadLowFreq(force: true)]);
  }

  // Separate flag for when only the trend is reloading (tab switch)
  bool _trendLoading = false;

  void _changeTrend(String type) {
    setState(() {
      _trendType = type;
      _trendLoading = true;
    });
    _loadLowFreq(force: true).then((_) {
      if (mounted) setState(() => _trendLoading = false);
    });
  }

  @override
  void dispose() {
    _lowFreqTimer?.cancel();
    _highFreqTimer?.cancel();
    _connectSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hf = ref.watch(highFreqProvider);
    final user = ref.watch(authProvider).user;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _onPullRefresh,
        color: AppTheme.gold,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              sliver: SliverList(
                  delegate: SliverChildListDelegate([
                _buildHeader(user?.name ?? 'SuperAdmin'),
                const SizedBox(height: 16),
                // ── High-frequency cards row ──────────────────────────────────
                _buildHighFreqCards(hf),
                const SizedBox(height: 20),
                // ── Leaderboard ───────────────────────────────────────────────
                const _SectionTitle(title: 'Leaderboard Cabang', subtitle: 'Pendapatan hari ini vs kemarin'),
                const SizedBox(height: 10),
                _buildLeaderboard(),
                const SizedBox(height: 20),
                // ── Sales trend ───────────────────────────────────────────────
                _SectionTitle(
                    title: 'Tren Penjualan', subtitle: 'Berdasarkan periode yang dipilih', trailing: _trendPicker()),
                const SizedBox(height: 10),
                _buildTrend(),
                const SizedBox(height: 20),
                // ── Top selling ───────────────────────────────────────────────
                _SectionTitle(
                  title: 'Paling Laku',
                  subtitle: 'Penjualan terbaik hari ini',
                  trailing: _TogglePill(
                    options: const ['Produk', 'Kategori'],
                    selected: _topSellingIndex,
                    onChanged: (i) => setState(() => _topSellingIndex = i),
                  ),
                ),
                const SizedBox(height: 10),
                _buildTopSelling(),
                const SizedBox(height: 20),
                // ── Bottom segment ────────────────────────────────────────────
                _TogglePill(
                  options: const ['Transaksi', 'Stok'],
                  selected: _segmentIndex,
                  onChanged: (i) => setState(() => _segmentIndex = i),
                  wide: true,
                ),
                const SizedBox(height: 12),
                _buildBottomSegment(hf),
              ])),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(String name) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Dashboard Superadmin',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            if (_lowFreqStale) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade800.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.amber, width: 0.5),
                ),
                child: const Text('Perlu Update',
                    style: TextStyle(fontSize: 8, color: Colors.amber, fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
          Text('Selamat datang, $name',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.55))),
        ]),
      ),
      const LiveClock(),
      const SizedBox(width: 4),
      IconButton(
        icon: const Icon(Icons.refresh, size: 20),
        onPressed: _onPullRefresh,
        tooltip: 'Perbarui semua',
        color: AppTheme.mutedForeground,
      ),
    ]);
  }

  // ── High-frequency cards ──────────────────────────────────────────────────
  Widget _buildHighFreqCards(HighFreqState hf) {
    if (_highFreqLoading && hf.sales == null) {
      return const SizedBox(
          height: 140, child: Center(child: CircularProgressIndicator(color: AppTheme.gold, strokeWidth: 2)));
    }
    if (_highFreqError != null && hf.sales == null) {
      return _ErrorTile(message: _highFreqError!, onRetry: _loadHighFreq);
    }
    final sales = hf.sales!;
    final branches = hf.branches;
    return Column(children: [
      // Card 1 — Total Sales Today
      _SalesTodayCard(sales: sales),
      const SizedBox(height: 10),
      Row(children: [
        // Card 2 — Active branches
        Expanded(child: _BranchCard(branches: branches)),
        const SizedBox(width: 10),
        // Card 3 — Total tx + AOV
        Expanded(child: _TxAovCard(sales: sales)),
      ]),
    ]);
  }

  // ── Leaderboard ───────────────────────────────────────────────────────────
  Widget _buildLeaderboard() {
    if (_lowFreqLoading && _lowFreq == null) {
      return const SizedBox(
          height: 160, child: Center(child: CircularProgressIndicator(color: AppTheme.gold, strokeWidth: 2)));
    }
    if (_lowFreq == null) return const SizedBox.shrink();
    return ChartRerender(child: _LeaderboardChart(entries: _lowFreq!.leaderboard));
  }

  // ── Trend chart ───────────────────────────────────────────────────────────
  Widget _buildTrend() {
    if (_lowFreqLoading && _lowFreq == null) {
      return const SizedBox(
          height: 220, child: Center(child: CircularProgressIndicator(color: AppTheme.gold, strokeWidth: 2)));
    }
    if (_lowFreq == null) return const SizedBox.shrink();
    return Stack(
      children: [
        ChartRerender(child: _TrendChart(points: _lowFreq!.trend, trendType: _trendType)),
        if (_trendLoading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: CircularProgressIndicator(color: AppTheme.gold, strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }

  // ── Top selling ───────────────────────────────────────────────────────────
  Widget _buildTopSelling() {
    if (_lowFreqLoading && _lowFreq == null) {
      return const SizedBox(
          height: 200, child: Center(child: CircularProgressIndicator(color: AppTheme.gold, strokeWidth: 2)));
    }
    if (_lowFreq == null) return const SizedBox.shrink();
    final items = _topSellingIndex == 0 ? _lowFreq!.topProducts : _lowFreq!.topCategories;
    return ChartRerender(child: _TopSellingChart(items: items));
  }

  // ── Bottom segment ────────────────────────────────────────────────────────
  Widget _buildBottomSegment(HighFreqState hf) {
    if (_segmentIndex == 0) {
      // Live transaction feed — driven by SQLite store, 500 ms poll
      final liveTxs = ref.watch(liveTransactionStoreProvider);
      return _LiveTransactionFeed(
        transactions: liveTxs,
        isLoading: _highFreqLoading && liveTxs.isEmpty,
      );
    } else {
      return _StockSegment(stock: hf.stock, isLoading: _highFreqLoading && hf.stock == null);
    }
  }

  Widget _trendPicker() {
    final cs = Theme.of(context).colorScheme;
    const options = [
      ('Jam', 'hourly'),
      ('Harian', 'daily'),
      ('Mingguan', 'weekly'),
      ('Bulanan', 'monthly'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _trendType,
          isDense: true,
          dropdownColor: cs.surface,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface),
          items: options.map((o) => DropdownMenuItem(value: o.$2, child: Text(o.$1))).toList(),
          onChanged: (v) {
            if (v != null) _changeTrend(v);
          },
        ),
      ),
    );
  }
}
