import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/helper/screen_type_utils.dart';
import '../../../../core/constants/screen_breakpoints.dart';
import '../../../../core/provider/auth_provider.dart';
import '../../../../core/provider/realtime_provider.dart';
import '../../../../core/models/dashboard_stats.dart';
import '../../../../core/services/dashboard_service.dart';
import '../../../../core/helper/currency_formatter.dart';
import '../widgets/stat_card.dart';
import '../widgets/quick_action_card.dart';
import '../widgets/transaction_item.dart';
import '../../../../shared/widgets/pull_to_refresh.dart';
import '../../../../shared/widgets/live_clock.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/services/connectivity_monitor.dart';
import '../../../../core/services/error_handler.dart';
import '../../../../shared/widgets/error_page.dart';
import 'superadmin_dashboard_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late List<Animation<Offset>> _slideAnimations;
  late List<Animation<double>> _fadeAnimations;

  DashboardStats? _stats;
  bool _isLoading = true;
  String? _error;
  bool _isDataStale = false;

  ProviderSubscription<RealtimeTransactionState>? _txSub;
  ProviderSubscription<RealtimeProductState>? _productSub;
  ProviderSubscription<AsyncValue<ConnectivityStatus>>? _connectivitySub;
  ConnectivityStatus? _lastConnectivityStatus;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadDashboard();
    // Request location permission silently on load for timezone awareness
    LocationService.requestPermission();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _txSub ??= ref.listenManual(realtimeTransactionProvider, (prev, next) {
      if (next.lastUpdateTime != prev?.lastUpdateTime) _loadDashboard();
    });
    _productSub ??= ref.listenManual(realtimeProductProvider, (prev, next) {
      if (next.lastUpdateTime != prev?.lastUpdateTime) _loadDashboard();
    });
    _connectivitySub ??= ref.listenManual(connectivityProvider, (previous, next) {
      if (previous?.valueOrNull == ConnectivityStatus.offline &&
          next.valueOrNull == ConnectivityStatus.online) {
        if (mounted) _loadDashboard();
      }
    });
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _slideAnimations = List.generate(6, (index) {
      return Tween<Offset>(
        begin: const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Interval(
          index * 0.1,
          0.6 + (index * 0.1),
          curve: Curves.easeOutCubic,
        ),
      ));
    });

    _fadeAnimations = List.generate(6, (index) {
      return Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Interval(
          index * 0.1,
          0.6 + (index * 0.1),
          curve: Curves.easeOut,
        ),
      ));
    });
  }

  Future<void> _loadDashboard({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final stats = await DashboardService.getStats(forceRefresh: forceRefresh);
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoading = false;
          _isDataStale = DashboardService.lastFetchWasStale;
        });
        _animationController.forward(from: 0);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _txSub?.close();
    _productSub?.close();
    _connectivitySub?.close();
    _animationController.dispose();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Selamat Pagi';
    if (hour < 18) return 'Selamat Siang';
    return 'Selamat Malam';
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    // SuperAdmin gets the full analytics dashboard
    if (user?.isSuperAdmin == true) {
      return const SuperAdminDashboardPage();
    }

    final isKaryawan = user?.isEmployee ?? false;

    final screenType = getScreenType(context);
    final orientation = getOrientation(context);
    final horizontalPadding =
        Breakpoints.getHorizontalPadding(screenType, orientation);
    final statsColumns =
        Breakpoints.getGridColumns(screenType, orientation);
    final quickActionsColumns = screenType == ScreenType.tablet
        ? (orientation == OrientationType.landscape ? 5 : 4)
        : 3;

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                    maxWidth: Breakpoints.maxContentWidth),
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.gold))
                    : _error != null
                        ? _buildError()
                        : _buildContent(
                            screenType,
                            orientation,
                            horizontalPadding,
                            statsColumns,
                            quickActionsColumns,
                            isKaryawan,
                            user?.name ?? 'User',
                            _isDataStale,
                          ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    final isOffline = ConnectivityMonitor.instance.currentStatus == ConnectivityStatus.offline;
    if (isOffline && !_isDataStale) {
      return ErrorPage(
        error: AppError(
          type: AppErrorType.offline,
          userMessage: ErrorHandler.messageFor(AppErrorType.offline),
        ),
        onRetry: _loadDashboard,
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline,
              size: 48, color: AppTheme.destructive),
          const SizedBox(height: 16),
          const Text('Gagal memuat dashboard'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba Lagi'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.gold),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    ScreenType screenType,
    OrientationType orientation,
    double horizontalPadding,
    int statsColumns,
    int quickActionsColumns,
    bool isKaryawan,
    String userName,
    bool isDataStale,
  ) {
    final stats = _stats!;

    return PullToRefresh(
      onRefresh: () => _loadDashboard(forceRefresh: true),
      child: SingleChildScrollView(
      padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          SlideTransition(
            position: _slideAnimations[0],
            child: FadeTransition(
              opacity: _fadeAnimations[0],
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.gold.withOpacity(0.05),
                      Colors.transparent,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getGreeting(),
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(
                                color: AppTheme.mutedForeground,
                                fontSize: screenType == ScreenType.tablet
                                    ? 18
                                    : null,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          userName,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: screenType == ScreenType.tablet
                                    ? 36
                                    : null,
                              ),
                        ),
                        if (isDataStale) ...[
                          const SizedBox(height: 4),
                          Tooltip(
                            message: 'Data mungkin tidak terbaru',
                            child: const Icon(
                              Icons.cloud_off,
                              size: 14,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        const LiveClock(),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _loadDashboard,
                          icon: const Icon(Icons.refresh,
                              color: AppTheme.mutedForeground),
                          tooltip: 'Refresh',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Stats Grid
          SlideTransition(
            position: _slideAnimations[1],
            child: FadeTransition(
              opacity: _fadeAnimations[1],
              child: GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: statsColumns,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  mainAxisExtent:
                      screenType == ScreenType.tablet ? 160 : 140,
                ),
                children: [
                  StatCard(
                    icon: Icons.attach_money,
                    label: 'Pendapatan Hari Ini',
                    value: CurrencyFormatter.formatToCompactRupiah(
                        stats.todayRevenue),
                    isHighlighted: true,
                  ),
                  StatCard(
                    icon: Icons.receipt_long_outlined,
                    label: 'Transaksi Hari Ini',
                    value: stats.todayTransactions.toString(),
                  ),
                  StatCard(
                    icon: Icons.shopping_bag_outlined,
                    label: 'Transaksi Bulan Ini',
                    value: stats.monthlyTransactions.toString(),
                  ),
                  StatCard(
                    icon: Icons.inventory_2_outlined,
                    label: 'Stok Kritis',
                    value: (stats.lowStockCount + stats.outOfStockCount)
                        .toString(),
                    isPositive: stats.lowStockCount + stats.outOfStockCount == 0,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Quick Actions
          SlideTransition(
            position: _slideAnimations[2],
            child: FadeTransition(
              opacity: _fadeAnimations[2],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aksi Cepat',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize:
                              screenType == ScreenType.tablet ? 26 : null,
                        ),
                  ),
                  const SizedBox(height: 16),
                  GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: quickActionsColumns,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      mainAxisExtent:
                          screenType == ScreenType.tablet ? 150 : 130,
                    ),
                    children: [
                      QuickActionCard(
                        icon: Icons.shopping_cart_outlined,
                        label: 'Transaksi Baru',
                        onTap: () => context.go(AppRouter.cashier),
                      ),
                      QuickActionCard(
                        icon: Icons.local_offer_outlined,
                        label: 'Pasang Kupon',
                        onTap: () => context.go(AppRouter.cashier),
                      ),
                      QuickActionCard(
                        icon: Icons.inventory_2_outlined,
                        label: 'Cek Stok',
                        onTap: () => context.go(AppRouter.inventory),
                      ),
                      QuickActionCard(
                        icon: Icons.bluetooth,
                        label: 'Kontrol Perangkat',
                        onTap: () => context.go(AppRouter.cashier),
                      ),
                      if (!isKaryawan)
                        QuickActionCard(
                          icon: Icons.add,
                          label: 'Tambah Stok',
                          onTap: () => context.go(AppRouter.inventory),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Recent Transactions
          SlideTransition(
            position: _slideAnimations[3],
            child: FadeTransition(
              opacity: _fadeAnimations[3],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Transaksi Terbaru',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: screenType == ScreenType.tablet
                                  ? 26
                                  : null,
                            ),
                      ),
                      TextButton(
                        onPressed: () {},
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Lihat Semua',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(color: AppTheme.gold),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right,
                                size: 16, color: AppTheme.gold),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (stats.recentTransactions.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'Belum ada transaksi hari ini',
                          style: TextStyle(color: AppTheme.mutedForeground),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: stats.recentTransactions.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final tx = stats.recentTransactions[index];
                        return SlideTransition(
                          position: _slideAnimations[4],
                          child: FadeTransition(
                            opacity: _fadeAnimations[4],
                            child: TransactionItem(
                              id: tx.id.toString(),
                              time: tx.relativeTime,
                              items: tx.itemCount,
                              total: tx.finalAmount,
                              paymentMethod:
                                  tx.paymentMethod ?? 'cash',
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 100),
        ],
      ),
    ), // SingleChildScrollView
    ); // PullToRefresh
  }
}
