/// GET /api/analytics/overview: the owner's home screen.
///
/// Parsing is defensive because cached copies come back from Hive as Map<dynamic, dynamic>.
class BusinessOverview {
  final DateTime? generatedAt;
  final Totals today;
  final Totals month;
  final PeriodSummary period;
  final List<BranchPerformance> branches;
  final int activeBranchesToday;
  final List<RankedItem> categories;
  final List<RankedItem> products;
  final Attention attention;

  const BusinessOverview({
    required this.generatedAt,
    required this.today,
    required this.month,
    required this.period,
    required this.branches,
    required this.activeBranchesToday,
    required this.categories,
    required this.products,
    required this.attention,
  });

  factory BusinessOverview.fromJson(Map<String, dynamic> json) => BusinessOverview(
        generatedAt: DateTime.tryParse(json['generated_at']?.toString() ?? ''),
        today: Totals.fromJson(_map(json['today'])),
        month: Totals.fromJson(_map(json['month'])),
        period: PeriodSummary.fromJson(_map(json['period'])),
        branches: _list(json['branches']).map(BranchPerformance.fromJson).toList(),
        activeBranchesToday: _int(json['active_branches_today']),
        categories: _list(json['categories']).map(RankedItem.fromJson).toList(),
        products: _list(json['products']).map(RankedItem.fromJson).toList(),
        attention: Attention.fromJson(_map(json['attention'])),
      );
}

/// Revenue and sale count, with the same measure for the comparison span ([previous]).
class Totals {
  final double revenue;
  final int transactions;
  final double previousRevenue;
  final int previousTransactions;

  const Totals(this.revenue, this.transactions, this.previousRevenue, this.previousTransactions);

  factory Totals.fromJson(Map<String, dynamic> json) {
    final previous = _map(json['previous']);
    return Totals(
      _double(json['revenue']),
      _int(json['transactions']),
      _double(previous['revenue']),
      _int(previous['transactions']),
    );
  }

  double get averageTicket => transactions == 0 ? 0 : revenue / transactions;

  /// Change against the comparison span as a fraction (0.12 = +12%); null when there is nothing to compare.
  double? get revenueChange => previousRevenue <= 0 ? null : (revenue - previousRevenue) / previousRevenue;
}

class PeriodSummary extends Totals {
  final int days;
  final DateTime? from;
  final DateTime? to;
  final List<DailyRevenue> daily;

  PeriodSummary({
    required this.days,
    required this.from,
    required this.to,
    required this.daily,
    required double revenue,
    required int transactions,
    required double previousRevenue,
    required int previousTransactions,
  }) : super(revenue, transactions, previousRevenue, previousTransactions);

  factory PeriodSummary.fromJson(Map<String, dynamic> json) {
    final totals = Totals.fromJson(json);
    return PeriodSummary(
      days: _int(json['days']),
      from: DateTime.tryParse(json['from']?.toString() ?? ''),
      to: DateTime.tryParse(json['to']?.toString() ?? ''),
      daily: _list(json['daily']).map(DailyRevenue.fromJson).toList(),
      revenue: totals.revenue,
      transactions: totals.transactions,
      previousRevenue: totals.previousRevenue,
      previousTransactions: totals.previousTransactions,
    );
  }
}

class DailyRevenue {
  final DateTime date;
  final double revenue;
  final int transactions;

  const DailyRevenue(this.date, this.revenue, this.transactions);

  factory DailyRevenue.fromJson(Map<String, dynamic> json) => DailyRevenue(
        DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
        _double(json['revenue']),
        _int(json['transactions']),
      );
}

class BranchPerformance {
  final int id;
  final String code;
  final String name;
  final double revenue;
  final int transactions;
  final int openShifts;

  const BranchPerformance(this.id, this.code, this.name, this.revenue, this.transactions, this.openShifts);

  factory BranchPerformance.fromJson(Map<String, dynamic> json) => BranchPerformance(
        _int(json['id']),
        json['code']?.toString() ?? '',
        json['name']?.toString() ?? '',
        _double(json['revenue']),
        _int(json['transactions']),
        _int(json['open_shifts']),
      );
}

/// A category or product in a ranking.
class RankedItem {
  final String name;
  final double revenue;
  final double qty;

  const RankedItem(this.name, this.revenue, this.qty);

  factory RankedItem.fromJson(Map<String, dynamic> json) =>
      RankedItem(json['name']?.toString() ?? '—', _double(json['revenue']), _double(json['qty']));
}

class Attention {
  final int openShifts;

  /// Shifts open for more than 12 hours: most likely someone forgot to close them.
  final int overdueShifts;
  final int cashDifferenceCount;
  final double cashDifferenceTotal;
  final int outOfStock;
  final int lowStock;
  final int voidedToday;

  const Attention({
    required this.openShifts,
    required this.overdueShifts,
    required this.cashDifferenceCount,
    required this.cashDifferenceTotal,
    required this.outOfStock,
    required this.lowStock,
    required this.voidedToday,
  });

  factory Attention.fromJson(Map<String, dynamic> json) {
    final cash = _map(json['cash_differences_today']);
    return Attention(
      openShifts: _int(json['open_shifts']),
      overdueShifts: _int(json['overdue_shifts']),
      cashDifferenceCount: _int(cash['count']),
      cashDifferenceTotal: _double(cash['total']),
      outOfStock: _int(json['out_of_stock']),
      lowStock: _int(json['low_stock']),
      voidedToday: _int(json['voided_today']),
    );
  }
}

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _list(dynamic v) => v is List ? v.map(_map).toList() : const [];

double _double(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}
