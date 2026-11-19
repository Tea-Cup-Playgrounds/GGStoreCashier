/// GET /api/reports/monthly-recap — Rekap Bulanan (see API/src/routes/reports.js).
class MonthlyRecap {
  final String month;
  final RecapOmset omset;
  final List<RecapCategory> categories;

  /// Owner and accountant only; null for branch managers.
  final RecapAllocation? allocation;

  const MonthlyRecap({required this.month, required this.omset, required this.categories, required this.allocation});

  factory MonthlyRecap.fromJson(Map<String, dynamic> json) => MonthlyRecap(
        month: json['month']?.toString() ?? '',
        omset: RecapOmset.fromJson(_map(json['omset'])),
        categories: _list(json['categories']).map(RecapCategory.fromJson).toList(),
        allocation: json['allocation'] is Map ? RecapAllocation.fromJson(_map(json['allocation'])) : null,
      );
}

class RecapLine {
  final String code;
  final String name;
  final double amount;
  final int count;

  const RecapLine(this.code, this.name, this.amount, this.count);

  factory RecapLine.fromJson(Map<String, dynamic> json) =>
      RecapLine(json['code']?.toString() ?? '', json['name']?.toString() ?? '', _d(json['amount']), _i(json['count']));
}

class RecapOmset {
  final double gross, cash, qrisDebit, transfer, ewallet, expenses, refund, discounts, net;
  final int transactions;
  final List<RecapLine> expenseLines;

  const RecapOmset({
    required this.gross,
    required this.cash,
    required this.qrisDebit,
    required this.transfer,
    required this.ewallet,
    required this.expenses,
    required this.refund,
    required this.discounts,
    required this.net,
    required this.transactions,
    required this.expenseLines,
  });

  factory RecapOmset.fromJson(Map<String, dynamic> j) => RecapOmset(
        gross: _d(j['gross']),
        cash: _d(j['cash']),
        qrisDebit: _d(j['qris_debit']),
        transfer: _d(j['transfer']),
        ewallet: _d(j['ewallet']),
        expenses: _d(j['expenses']),
        refund: _d(j['refund']),
        discounts: _d(j['discounts']),
        net: _d(j['net']),
        transactions: _i(j['transactions']),
        expenseLines: _list(j['expense_lines']).map(RecapLine.fromJson).toList(),
      );
}

class RecapAllocation {
  final double netRevenue, operational, stockPurchases, stockGoods, stockPulsa, debtPayments, assets, remaining, pulsaBalance;
  final List<RecapLine> operationalLines;

  const RecapAllocation({
    required this.netRevenue,
    required this.operational,
    required this.stockPurchases,
    required this.stockGoods,
    required this.stockPulsa,
    required this.debtPayments,
    required this.assets,
    required this.remaining,
    required this.pulsaBalance,
    required this.operationalLines,
  });

  factory RecapAllocation.fromJson(Map<String, dynamic> j) => RecapAllocation(
        netRevenue: _d(j['net_revenue']),
        operational: _d(j['operational']),
        stockPurchases: _d(j['stock_purchases']),
        stockGoods: _d(j['stock_goods']),
        stockPulsa: _d(j['stock_pulsa']),
        debtPayments: _d(j['debt_payments']),
        assets: _d(j['assets']),
        remaining: _d(j['remaining']),
        pulsaBalance: _d(j['pulsa_balance']),
        operationalLines: _list(j['operational_lines']).map(RecapLine.fromJson).toList(),
      );
}

class RecapCategory {
  final String name;
  final double qty, revenue, cost, grossProfit;

  const RecapCategory(this.name, this.qty, this.revenue, this.cost, this.grossProfit);

  factory RecapCategory.fromJson(Map<String, dynamic> j) =>
      RecapCategory(j['name']?.toString() ?? '—', _d(j['qty']), _d(j['revenue']), _d(j['cost']), _d(j['gross_profit']));
}

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _list(dynamic v) => v is List ? v.map(_map).toList() : const [];
double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
int _i(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0);
