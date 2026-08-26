import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/superadmin_dashboard.dart';
import '../services/socket_service.dart';
import '../services/cache_manager.dart';

// ─────────────────────────────────────────────────────────────────────────────
// High-frequency state — driven by socket event `dashboard:live-update`
// ─────────────────────────────────────────────────────────────────────────────

class HighFreqState {
  final SalesKpi? sales;
  final BranchStatus? branches;
  final List<LiveTransaction> recentTransactions;
  final StockCounts? stock;
  final DateTime? lastUpdateTime;

  const HighFreqState({
    this.sales,
    this.branches,
    this.recentTransactions = const [],
    this.stock,
    this.lastUpdateTime,
  });

  HighFreqState copyWith({
    SalesKpi? sales,
    BranchStatus? branches,
    List<LiveTransaction>? recentTransactions,
    StockCounts? stock,
    DateTime? lastUpdateTime,
  }) =>
      HighFreqState(
        sales: sales ?? this.sales,
        branches: branches ?? this.branches,
        recentTransactions: recentTransactions ?? this.recentTransactions,
        stock: stock ?? this.stock,
        lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
      );

  /// Seed initial values from an HTTP load.
  HighFreqState seedFromHttp(HighFreqDashboard data) => HighFreqState(
        sales: data.sales,
        branches: data.branches,
        recentTransactions: data.recentTransactions,
        stock: data.stock,
        lastUpdateTime: DateTime.now(),
      );

  /// Apply a socket delta: update KPIs, prepend new transaction (cap at 20).
  HighFreqState applySocketDelta(Map<String, dynamic> payload) {
    try {
      final salesMap = payload['sales'] as Map?;
      final newSales = salesMap != null ? SalesKpi.fromJson(Map<String, dynamic>.from(salesMap)) : sales;

      final activeBranches = payload['activeBranches'];
      final newBranches = (branches != null && activeBranches != null)
          ? BranchStatus(
              total: branches!.total,
              active: activeBranches as int,
              offline: branches!.total - (activeBranches),
            )
          : branches;

      final stockMap = payload['stock'] as Map?;
      final newStock = stockMap != null ? StockCounts.fromJson(Map<String, dynamic>.from(stockMap)) : stock;

      final txMap = payload['newTransaction'] as Map?;
      List<LiveTransaction> newTxList = List.of(recentTransactions);
      if (txMap != null) {
        final newTx = LiveTransaction.fromJson(Map<String, dynamic>.from(txMap));
        // Prepend, keep max 20
        newTxList.insert(0, newTx);
        if (newTxList.length > 20) newTxList = newTxList.sublist(0, 20);
      }

      return copyWith(
        sales: newSales,
        branches: newBranches,
        stock: newStock,
        recentTransactions: newTxList,
        lastUpdateTime: DateTime.now(),
      );
    } catch (e) {
      dev.log('HighFreqState.applySocketDelta error: $e');
      return copyWith(lastUpdateTime: DateTime.now());
    }
  }
}

class HighFreqNotifier extends StateNotifier<HighFreqState> {
  HighFreqNotifier() : super(const HighFreqState()) {
    SocketService.on('dashboard:live-update', _handleLiveUpdate);
    // Also react to individual transaction events as a fallback
    SocketService.on('transaction-created', _handleTransactionCreated);
    SocketService.on('payment-completed', _handlePaymentCompleted);
  }

  void _handleLiveUpdate(dynamic data) {
    if (!mounted) return;
    try {
      final map = data is Map<String, dynamic> ? data : Map<String, dynamic>.from(data as Map);
      state = state.applySocketDelta(map);
      // Bust the high-freq HTTP cache so the next seedFromHttp call fetches fresh data
      CacheManager.invalidate('sadmin:high_freq');
    } catch (e) {
      dev.log('HighFreqNotifier._handleLiveUpdate error: $e');
    }
  }

  /// Fallback: when transaction-created fires without a full dashboard:live-update
  /// (e.g. on branch-scoped events that don't include the delta payload),
  /// at minimum prepend the new transaction and bust the cache.
  void _handleTransactionCreated(dynamic data) {
    if (!mounted) return;
    try {
      final map = data is Map<String, dynamic> ? data : Map<String, dynamic>.from(data as Map);
      // Build a minimal delta that only adds the new transaction row
      final delta = <String, dynamic>{'newTransaction': map};
      state = state.applySocketDelta(delta);
      CacheManager.invalidate('sadmin:high_freq');
    } catch (e) {
      dev.log('HighFreqNotifier._handleTransactionCreated error: $e');
    }
  }

  void _handlePaymentCompleted(dynamic data) {
    if (!mounted) return;
    // payment-completed doesn't carry full KPI deltas, but busting the cache
    // ensures the next explicit refresh fetches current numbers.
    CacheManager.invalidate('sadmin:high_freq');
  }

  void seedFromHttp(HighFreqDashboard data) {
    if (!mounted) return;
    state = state.seedFromHttp(data);
  }

  @override
  void dispose() {
    SocketService.off('dashboard:live-update', _handleLiveUpdate);
    SocketService.off('transaction-created', _handleTransactionCreated);
    SocketService.off('payment-completed', _handlePaymentCompleted);
    super.dispose();
  }
}

final highFreqProvider = StateNotifierProvider<HighFreqNotifier, HighFreqState>(
  (ref) => HighFreqNotifier(),
);

// ─────────────────────────────────────────────────────────────────────────────
// Low-frequency trigger — just a counter to signal when to reload
// ─────────────────────────────────────────────────────────────────────────────

class LowFreqTrigger extends StateNotifier<int> {
  LowFreqTrigger() : super(0);
  void refresh() => state = state + 1;
}

final lowFreqTriggerProvider = StateNotifierProvider<LowFreqTrigger, int>(
  (ref) => LowFreqTrigger(),
);
