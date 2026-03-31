class DashboardStats {
  final double todayRevenue;
  final int todayTransactions;
  final int monthlyTransactions;
  final double monthlyRevenue;
  final int lowStockCount;
  final int outOfStockCount;
  final List<RecentTransaction> recentTransactions;

  const DashboardStats({
    required this.todayRevenue,
    required this.todayTransactions,
    required this.monthlyTransactions,
    required this.monthlyRevenue,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.recentTransactions,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>;
    final txList = json['recentTransactions'] as List? ?? [];
    return DashboardStats(
      todayRevenue: _toDouble(stats['todayRevenue']),
      todayTransactions: _toInt(stats['todayTransactions']),
      monthlyTransactions: _toInt(stats['monthlyTransactions']),
      monthlyRevenue: _toDouble(stats['monthlyRevenue']),
      lowStockCount: _toInt(stats['lowStockCount']),
      outOfStockCount: _toInt(stats['outOfStockCount']),
      recentTransactions: txList.map((e) => RecentTransaction.fromJson(e)).toList(),
    );
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }
}

class RecentTransaction {
  final int id;
  final double finalAmount;
  final String paymentStatus;
  final String? paymentMethod;
  final int itemCount;
  final String? userName;
  final String? branchName;
  final DateTime createdAt;

  const RecentTransaction({
    required this.id,
    required this.finalAmount,
    required this.paymentStatus,
    this.paymentMethod,
    required this.itemCount,
    this.userName,
    this.branchName,
    required this.createdAt,
  });

  factory RecentTransaction.fromJson(Map<String, dynamic> json) {
    return RecentTransaction(
      id: DashboardStats._toInt(json['id']),
      finalAmount: DashboardStats._toDouble(json['final_amount']),
      paymentStatus: json['payment_status']?.toString() ?? 'paid',
      paymentMethod: json['payment_method']?.toString(),
      itemCount: DashboardStats._toInt(json['item_count']),
      userName: json['user_name']?.toString(),
      branchName: json['branch_name']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  /// Human-readable relative time
  String get relativeTime {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays}d ago';
  }
}
