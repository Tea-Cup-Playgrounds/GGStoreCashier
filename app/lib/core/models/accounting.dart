// Models for /api/accounting, /api/expenses and /api/pulsa-deposit (see API/src/routes).
import 'json_parse.dart';

/// Labels for journal source types, as in the web back office.
const journalSourceLabels = <String, String>{
  'sale': 'Penjualan',
  'sale_void': 'Pembatalan penjualan',
  'sale_return': 'Retur penjualan',
  'goods_receipt': 'Penerimaan barang',
  'supplier_payment': 'Pembayaran supplier',
  'stock_adjustment': 'Penyesuaian stok',
  'opname': 'Stok opname',
  'transfer': 'Transfer',
  'cash_session': 'Shift kasir',
  'expense': 'Biaya',
  'expense_void': 'Pembatalan biaya',
  'opening_balance': 'Saldo awal',
  'pulsa_deposit': 'Top up deposit pulsa',
  'manual': 'Jurnal manual',
};

/// Journals voided from the journal screen; the rest are voided through their own documents.
const journalsVoidableHere = {'manual', 'opening_balance', 'pulsa_deposit'};

String journalSourceLabel(String type) => journalSourceLabels[type] ?? type;

// ── expenses ─────────────────────────────────────────────────────────────────

class ExpenseCategory {
  final int id;
  final String code;
  final String name;

  const ExpenseCategory({required this.id, required this.code, required this.name});

  String get label => '$code $name';

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) =>
      ExpenseCategory(id: parseInt(json['id']), code: json['code'].toString(), name: json['name'].toString());
}

class Expense {
  final String id;
  final String number;
  final int? locationId;
  final String? locationCode;
  final String date; // YYYY-MM-DD
  final String accountCode;
  final String accountName;
  final double amount;
  final String paidFrom; // cash | bank
  final String? payee;
  final String? note;
  final String status; // posted | void
  final String? voidReason;
  final String? voidedByName;
  final String? journalNumber;
  final String? createdByName;

  const Expense({
    required this.id,
    required this.number,
    this.locationId,
    this.locationCode,
    required this.date,
    required this.accountCode,
    required this.accountName,
    required this.amount,
    required this.paidFrom,
    this.payee,
    this.note,
    required this.status,
    this.voidReason,
    this.voidedByName,
    this.journalNumber,
    this.createdByName,
  });

  bool get isVoid => status == 'void';
  String get paidFromLabel => paidFrom == 'cash' ? 'Kas' : 'Bank';

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'].toString(),
        number: json['number'].toString(),
        locationId: parseNullableInt(json['location_id']),
        locationCode: json['location_code'] as String?,
        date: json['expense_date'].toString(),
        accountCode: json['account_code'].toString(),
        accountName: json['account_name'].toString(),
        amount: parseDouble(json['amount']),
        paidFrom: json['paid_from']?.toString() ?? 'cash',
        payee: json['payee'] as String?,
        note: json['note'] as String?,
        status: json['status']?.toString() ?? 'posted',
        voidReason: json['void_reason'] as String?,
        voidedByName: json['voided_by_name'] as String?,
        journalNumber: json['journal_number'] as String?,
        createdByName: json['created_by_name'] as String?,
      );
}

class ExpenseList {
  final List<Expense> expenses;
  final double total;
  final List<(String category, double amount)> byCategory;

  const ExpenseList({required this.expenses, required this.total, required this.byCategory});

  factory ExpenseList.fromJson(Map<String, dynamic> json) => ExpenseList(
        expenses: parseList(json['expenses'], Expense.fromJson),
        total: parseDouble(json['total']),
        byCategory: ((json['by_category'] as List?) ?? const [])
            .map((e) => (e['category'].toString(), parseDouble(e['amount'])))
            .toList(),
      );
}

// ── pulsa deposit ────────────────────────────────────────────────────────────

class PulsaTopUp {
  final String entryId;
  final String number;
  final String date;
  final String? locationCode;
  final double amount;
  final String status;

  const PulsaTopUp({required this.entryId, required this.number, required this.date, this.locationCode, required this.amount, required this.status});

  bool get isVoid => status == 'void';

  factory PulsaTopUp.fromJson(Map<String, dynamic> json) => PulsaTopUp(
        entryId: json['entry_id'].toString(),
        number: json['number'].toString(),
        date: json['date'].toString(),
        locationCode: json['location_code'] as String?,
        amount: parseDouble(json['amount']),
        status: json['status']?.toString() ?? 'posted',
      );
}

class PulsaUsage {
  final String month; // YYYY-MM
  final double used;
  final int sales;

  const PulsaUsage({required this.month, required this.used, required this.sales});

  factory PulsaUsage.fromJson(Map<String, dynamic> json) =>
      PulsaUsage(month: json['month'].toString(), used: parseDouble(json['used']), sales: parseInt(json['sales']));
}

class PulsaDeposit {
  final double balance;
  final List<PulsaTopUp> topUps;
  final List<PulsaUsage> usage;

  const PulsaDeposit({required this.balance, required this.topUps, required this.usage});

  factory PulsaDeposit.fromJson(Map<String, dynamic> json) => PulsaDeposit(
        balance: parseDouble(json['balance']),
        topUps: parseList(json['top_ups'], PulsaTopUp.fromJson),
        usage: parseList(json['usage'], PulsaUsage.fromJson),
      );
}

// ── chart of accounts and journals ───────────────────────────────────────────

class LedgerAccount {
  final int id;
  final String code;
  final String name;
  final String type; // asset | liability | equity | income | expense
  final bool isPostable;
  final bool isActive;

  const LedgerAccount({required this.id, required this.code, required this.name, required this.type, required this.isPostable, required this.isActive});

  String get label => '$code $name';

  factory LedgerAccount.fromJson(Map<String, dynamic> json) => LedgerAccount(
        id: parseInt(json['id']),
        code: json['code'].toString(),
        name: json['name'].toString(),
        type: json['type'].toString(),
        isPostable: json['is_postable'] == true || json['is_postable'] == 1,
        isActive: json['is_active'] == true || json['is_active'] == 1,
      );
}

class JournalSummary {
  final String id;
  final String number;
  final String entryDate;
  final int? locationId;
  final String? locationCode;
  final String sourceType;
  final String? memo;
  final String status; // posted | void
  final String? reversesEntryId;
  final double amount;

  const JournalSummary({
    required this.id,
    required this.number,
    required this.entryDate,
    this.locationId,
    this.locationCode,
    required this.sourceType,
    this.memo,
    required this.status,
    this.reversesEntryId,
    required this.amount,
  });

  bool get isVoid => status == 'void';
  bool get isReversal => reversesEntryId != null;

  factory JournalSummary.fromJson(Map<String, dynamic> json) => JournalSummary(
        id: json['id'].toString(),
        number: json['number'].toString(),
        entryDate: json['entry_date'].toString(),
        locationId: parseNullableInt(json['location_id']),
        locationCode: json['location_code'] as String?,
        sourceType: json['source_type'].toString(),
        memo: json['memo'] as String?,
        status: json['status']?.toString() ?? 'posted',
        reversesEntryId: json['reverses_entry_id'] as String?,
        amount: parseDouble(json['amount']),
      );
}

class JournalLine {
  final String accountCode;
  final String accountName;
  final int? locationId;
  final double debit;
  final double credit;
  final String? memo;

  const JournalLine({required this.accountCode, required this.accountName, this.locationId, required this.debit, required this.credit, this.memo});

  factory JournalLine.fromJson(Map<String, dynamic> json) => JournalLine(
        accountCode: json['account_code'].toString(),
        accountName: json['account_name'].toString(),
        locationId: parseNullableInt(json['location_id']),
        debit: parseDouble(json['debit']),
        credit: parseDouble(json['credit']),
        memo: json['memo'] as String?,
      );
}

class Journal {
  final JournalSummary summary;
  final String? createdByName;
  final List<JournalLine> lines;

  const Journal({required this.summary, this.createdByName, required this.lines});

  double get totalDebit => lines.fold(0, (s, l) => s + l.debit);
  double get totalCredit => lines.fold(0, (s, l) => s + l.credit);

  factory Journal.fromJson(Map<String, dynamic> json) => Journal(
        summary: JournalSummary.fromJson({...json, 'amount': json['amount'] ?? 0}),
        createdByName: json['created_by_name'] as String?,
        lines: parseList(json['lines'], JournalLine.fromJson),
      );
}

/// One line typed into a manual journal.
class ManualJournalLine {
  String? accountCode;
  double debit;
  double credit;
  String memo;

  ManualJournalLine({this.accountCode, this.debit = 0, this.credit = 0, this.memo = ''});

  Map<String, dynamic> toJson() => {
        'account_code': accountCode,
        if (debit > 0) 'debit': debit,
        if (credit > 0) 'credit': credit,
        if (memo.trim().isNotEmpty) 'memo': memo.trim(),
      };
}

// ── reports ──────────────────────────────────────────────────────────────────

class ReportRow {
  final String? code;
  final String name;
  final String? type;
  final double balance;
  final bool computed;

  const ReportRow({this.code, required this.name, this.type, required this.balance, this.computed = false});

  factory ReportRow.fromJson(Map<String, dynamic> json) => ReportRow(
        code: json['code'] as String?,
        name: json['name'].toString(),
        type: json['type'] as String?,
        balance: parseDouble(json['balance']),
        computed: json['computed'] == true,
      );
}

class ProfitLoss {
  final List<ReportRow> income;
  final List<ReportRow> expense;
  final double totalIncome;
  final double costOfGoods;
  final double grossProfit;
  final double totalExpense;
  final double netProfit;

  const ProfitLoss({
    required this.income,
    required this.expense,
    required this.totalIncome,
    required this.costOfGoods,
    required this.grossProfit,
    required this.totalExpense,
    required this.netProfit,
  });

  /// Operating costs: every expense that is not cost of goods (5-xxxx).
  double get operatingExpense => totalExpense - costOfGoods;

  factory ProfitLoss.fromJson(Map<String, dynamic> json) {
    final t = Map<String, dynamic>.from(json['totals'] as Map);
    return ProfitLoss(
      income: parseList(json['income'], ReportRow.fromJson),
      expense: parseList(json['expense'], ReportRow.fromJson),
      totalIncome: parseDouble(t['income']),
      costOfGoods: parseDouble(t['cost_of_goods']),
      grossProfit: parseDouble(t['gross_profit']),
      totalExpense: parseDouble(t['expense']),
      netProfit: parseDouble(t['net_profit']),
    );
  }
}

class BalanceSheet {
  final String to;
  final List<ReportRow> assets;
  final List<ReportRow> liabilities;
  final List<ReportRow> equity;
  final double totalAssets;
  final double totalLiabilities;
  final double totalEquity;
  final double difference;

  const BalanceSheet({
    required this.to,
    required this.assets,
    required this.liabilities,
    required this.equity,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.totalEquity,
    required this.difference,
  });

  bool get balanced => difference.abs() < 0.005;

  factory BalanceSheet.fromJson(Map<String, dynamic> json) {
    final t = Map<String, dynamic>.from(json['totals'] as Map);
    return BalanceSheet(
      to: json['to'].toString(),
      assets: parseList(json['assets'], ReportRow.fromJson),
      liabilities: parseList(json['liabilities'], ReportRow.fromJson),
      equity: parseList(json['equity'], ReportRow.fromJson),
      totalAssets: parseDouble(t['assets']),
      totalLiabilities: parseDouble(t['liabilities']),
      totalEquity: parseDouble(t['equity']),
      difference: parseDouble(t['difference']),
    );
  }
}

class AccountingPeriod {
  final int year;
  final int month;
  final String status; // open | closed
  final DateTime? closedAt;
  final String? closedByName;

  const AccountingPeriod({required this.year, required this.month, required this.status, this.closedAt, this.closedByName});

  bool get isClosed => status == 'closed';

  factory AccountingPeriod.fromJson(Map<String, dynamic> json) => AccountingPeriod(
        year: parseInt(json['year']),
        month: parseInt(json['month']),
        status: json['status']?.toString() ?? 'open',
        closedAt: parseDate(json['closed_at']),
        closedByName: json['closed_by_name'] as String?,
      );
}
