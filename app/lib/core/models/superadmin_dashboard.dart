/// Models for the new superadmin dashboard (v2).
/// Low-frequency data: macro KPIs, leaderboard, trend, top items.
/// High-frequency data: three live cards, recent 20 transactions, stock counts.
library;

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

double _d(dynamic v) {
  if (v == null) return 0.0;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

int _i(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  return int.tryParse(v.toString()) ?? 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sales KPI
// ─────────────────────────────────────────────────────────────────────────────

class SalesKpi {
  final double todayRevenue;
  final int todayTxCount;
  final double avgOrderValue;
  final double vsYesterday; // signed percentage
  final double vsLastWeek; // signed percentage

  const SalesKpi({
    required this.todayRevenue,
    required this.todayTxCount,
    required this.avgOrderValue,
    required this.vsYesterday,
    required this.vsLastWeek,
  });

  factory SalesKpi.fromJson(Map<String, dynamic> j) => SalesKpi(
        todayRevenue: _d(j['todayRevenue']),
        todayTxCount: _i(j['todayTxCount']),
        avgOrderValue: _d(j['avgOrderValue']),
        vsYesterday: _d(j['vsYesterday']),
        vsLastWeek: _d(j['vsLastWeek']),
      );

  SalesKpi copyWith({
    double? todayRevenue,
    int? todayTxCount,
    double? avgOrderValue,
    double? vsYesterday,
    double? vsLastWeek,
  }) =>
      SalesKpi(
        todayRevenue: todayRevenue ?? this.todayRevenue,
        todayTxCount: todayTxCount ?? this.todayTxCount,
        avgOrderValue: avgOrderValue ?? this.avgOrderValue,
        vsYesterday: vsYesterday ?? this.vsYesterday,
        vsLastWeek: vsLastWeek ?? this.vsLastWeek,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Branch status
// ─────────────────────────────────────────────────────────────────────────────

class BranchStatus {
  final int total;
  final int active;
  final int offline;

  const BranchStatus({
    required this.total,
    required this.active,
    required this.offline,
  });

  factory BranchStatus.fromJson(Map<String, dynamic> j) => BranchStatus(
        total: _i(j['total']),
        active: _i(j['active']),
        offline: _i(j['offline']),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Leaderboard entry
// ─────────────────────────────────────────────────────────────────────────────

class LeaderboardEntry {
  final int branchId;
  final String branchName;
  final double todayRevenue;
  final double yesterdayRevenue;
  final int todayTx;

  const LeaderboardEntry({
    required this.branchId,
    required this.branchName,
    required this.todayRevenue,
    required this.yesterdayRevenue,
    required this.todayTx,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> j) => LeaderboardEntry(
        branchId: _i(j['branch_id']),
        branchName: j['branch_name']?.toString() ?? '',
        todayRevenue: _d(j['today_revenue']),
        yesterdayRevenue: _d(j['yesterday_revenue']),
        todayTx: _i(j['today_tx']),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sales trend point
// ─────────────────────────────────────────────────────────────────────────────

class TrendPoint {
  final String labelKey;
  final String label;
  final double revenue;
  final int txCount;

  const TrendPoint({
    required this.labelKey,
    required this.label,
    required this.revenue,
    required this.txCount,
  });

  factory TrendPoint.fromJson(Map<String, dynamic> j) => TrendPoint(
        labelKey: j['label_key']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        revenue: _d(j['revenue']),
        txCount: _i(j['tx_count']),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Top item (product or category)
// ─────────────────────────────────────────────────────────────────────────────

class TopItem {
  final String id;
  final String name;
  final int totalQty;
  final double totalRevenue;

  const TopItem({
    required this.id,
    required this.name,
    required this.totalQty,
    required this.totalRevenue,
  });

  factory TopItem.fromProductJson(Map<String, dynamic> j) => TopItem(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        totalQty: _i(j['total_qty']),
        totalRevenue: _d(j['total_revenue']),
      );

  factory TopItem.fromCategoryJson(Map<String, dynamic> j) => TopItem(
        id: j['category_id']?.toString() ?? '',
        name: j['category_name']?.toString() ?? '',
        totalQty: _i(j['total_qty']),
        totalRevenue: _d(j['total_revenue']),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Stock counts
// ─────────────────────────────────────────────────────────────────────────────

class StockCounts {
  final int lowCount;
  final int outCount;

  const StockCounts({required this.lowCount, required this.outCount});

  factory StockCounts.fromJson(Map<String, dynamic> j) =>
      StockCounts(lowCount: _i(j['lowCount']), outCount: _i(j['outCount']));
}

// ─────────────────────────────────────────────────────────────────────────────
// Live transaction (feed entry)
// ─────────────────────────────────────────────────────────────────────────────

class LiveTransaction {
  final int id;
  final double finalAmount;
  final String paymentStatus;
  final String? paymentMethod;
  final int itemCount;
  final String? userName;
  final String? branchName;
  final DateTime createdAt;

  const LiveTransaction({
    required this.id,
    required this.finalAmount,
    required this.paymentStatus,
    this.paymentMethod,
    required this.itemCount,
    this.userName,
    this.branchName,
    required this.createdAt,
  });

  factory LiveTransaction.fromJson(Map<String, dynamic> j) => LiveTransaction(
        id: _i(j['id']),
        finalAmount: _d(j['final_amount']),
        paymentStatus: j['payment_status']?.toString() ?? 'paid',
        paymentMethod: j['payment_method']?.toString(),
        itemCount: _i(j['item_count']),
        userName: j['user_name']?.toString(),
        branchName: j['branch_name']?.toString(),
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
      );

  String get relativeTime {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    return '${diff.inDays}hari lalu';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Low-frequency dashboard payload
// ─────────────────────────────────────────────────────────────────────────────

class LowFreqDashboard {
  final SalesKpi sales;
  final BranchStatus branches;
  final List<LeaderboardEntry> leaderboard;
  final String trendType;
  final List<TrendPoint> trend;
  final List<TopItem> topProducts;
  final List<TopItem> topCategories;

  const LowFreqDashboard({
    required this.sales,
    required this.branches,
    required this.leaderboard,
    required this.trendType,
    required this.trend,
    required this.topProducts,
    required this.topCategories,
  });

  factory LowFreqDashboard.fromJson(Map<String, dynamic> j) {
    final trendBlock = j['trend'] as Map<String, dynamic>? ?? {};
    return LowFreqDashboard(
      sales: SalesKpi.fromJson(Map<String, dynamic>.from(j['sales'] as Map? ?? {})),
      branches: BranchStatus.fromJson(Map<String, dynamic>.from(j['branches'] as Map? ?? {})),
      leaderboard: ((j['leaderboard'] as List?) ?? [])
          .map((e) => LeaderboardEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      trendType: trendBlock['type']?.toString() ?? 'hourly',
      trend: ((trendBlock['data'] as List?) ?? [])
          .map((e) => TrendPoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      topProducts: ((j['topProducts'] as List?) ?? [])
          .map((e) => TopItem.fromProductJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      topCategories: ((j['topCategories'] as List?) ?? [])
          .map((e) => TopItem.fromCategoryJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// High-frequency dashboard payload
// ─────────────────────────────────────────────────────────────────────────────

class HighFreqDashboard {
  final SalesKpi sales;
  final BranchStatus branches;
  final List<LiveTransaction> recentTransactions;
  final StockCounts stock;

  const HighFreqDashboard({
    required this.sales,
    required this.branches,
    required this.recentTransactions,
    required this.stock,
  });

  factory HighFreqDashboard.fromJson(Map<String, dynamic> j) => HighFreqDashboard(
        sales: SalesKpi.fromJson(Map<String, dynamic>.from(j['sales'] as Map? ?? {})),
        branches: BranchStatus.fromJson(Map<String, dynamic>.from(j['branches'] as Map? ?? {})),
        recentTransactions: ((j['recentTransactions'] as List?) ?? [])
            .map((e) => LiveTransaction.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        stock: StockCounts.fromJson(Map<String, dynamic>.from(j['stock'] as Map? ?? {})),
      );
}
