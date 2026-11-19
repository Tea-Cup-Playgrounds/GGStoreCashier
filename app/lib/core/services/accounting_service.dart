import '../models/accounting.dart';
import '../models/monthly_recap.dart';
import 'api_client.dart';

/// Client for /api/expenses, /api/pulsa-deposit and /api/accounting (see API/src/routes). The API
/// checks every permission again; location null means head office (Pusat) when sending and
/// "every location the user may see" when reading.
class AccountingService {
  // ── expenses (Biaya) ──

  static Future<List<ExpenseCategory>> expenseCategories() async =>
      ApiClient.list(await ApiClient.request('GET', '/api/expenses/categories'), 'categories', ExpenseCategory.fromJson);

  static Future<ExpenseList> expenses({int? locationId, String? from, String? to}) async {
    final body = await ApiClient.request('GET', '/api/expenses', query: {
      if (locationId != null) 'location_id': locationId,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    });
    return ExpenseList.fromJson(body);
  }

  static Future<Expense> expense(String id) async =>
      ApiClient.one(await ApiClient.request('GET', '/api/expenses/$id'), 'expense', Expense.fromJson);

  static Future<Expense> createExpense({
    int? locationId,
    required String date,
    required String accountCode,
    required double amount,
    required String paidFrom,
    String? payee,
    String? note,
  }) async {
    final body = await ApiClient.request('POST', '/api/expenses', data: {
      'location_id': locationId,
      'date': date,
      'account_code': accountCode,
      'amount': amount,
      'paid_from': paidFrom,
      if (payee != null && payee.isNotEmpty) 'payee': payee,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return Expense.fromJson(Map<String, dynamic>.from(body['expense'] as Map));
  }

  static Future<void> voidExpense(String id, String reason) =>
      ApiClient.request('POST', '/api/expenses/$id/void', data: {'reason': reason});

  // ── pulsa deposit ──

  static Future<PulsaDeposit> pulsaDeposit({int? locationId, String? from, String? to}) async {
    final body = await ApiClient.request('GET', '/api/pulsa-deposit', query: {
      if (locationId != null) 'location_id': locationId,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    });
    return PulsaDeposit.fromJson(body);
  }

  /// Returns the API's confirmation message (it names the journal number).
  static Future<String> topUpPulsa({int? locationId, required String date, required double amount, required String paidFrom, String? note}) async {
    final body = await ApiClient.request('POST', '/api/pulsa-deposit/top-ups', data: {
      'location_id': locationId,
      'date': date,
      'amount': amount,
      'paid_from': paidFrom,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return body['message']?.toString() ?? 'Top up dicatat';
  }

  // ── accounts and journals ──

  static Future<List<LedgerAccount>> accounts() async =>
      ApiClient.list(await ApiClient.request('GET', '/api/accounting/accounts'), 'accounts', LedgerAccount.fromJson);

  static Future<List<JournalSummary>> journals({int? locationId, String? from, String? to, String? sourceType}) async {
    final body = await ApiClient.request('GET', '/api/accounting/journals', query: {
      if (locationId != null) 'location_id': locationId,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (sourceType != null) 'source_type': sourceType,
    });
    return ApiClient.list(body, 'journals', JournalSummary.fromJson);
  }

  static Future<Journal> journal(String id) async =>
      ApiClient.one(await ApiClient.request('GET', '/api/accounting/journals/$id'), 'journal', Journal.fromJson);

  /// Posts a manual journal and returns the API's message ("Jurnal JV-… disimpan").
  static Future<String> postManualJournal({required String date, int? locationId, required String memo, required List<ManualJournalLine> lines}) async {
    final body = await ApiClient.request('POST', '/api/accounting/journals', data: {
      'date': date,
      'location_id': locationId,
      'memo': memo,
      'lines': lines.map((l) => l.toJson()).toList(),
    });
    return body['message']?.toString() ?? 'Jurnal disimpan';
  }

  static Future<void> voidJournal(String id, String reason) =>
      ApiClient.request('POST', '/api/accounting/journals/$id/void', data: {'reason': reason});

  // ── reports ──

  static Future<ProfitLoss> profitLoss({int? locationId, required String from, required String to}) async {
    final body = await ApiClient.request('GET', '/api/accounting/profit-loss', query: {
      if (locationId != null) 'location_id': locationId,
      'from': from,
      'to': to,
    });
    return ProfitLoss.fromJson(body);
  }

  /// Rekap Bulanan for [month] ('YYYY-MM'); location null = every location the user may read.
  static Future<MonthlyRecap> monthlyRecap({int? locationId, required String month}) async {
    final body = await ApiClient.request('GET', '/api/reports/monthly-recap', query: {
      if (locationId != null) 'location_id': locationId,
      'month': month,
    });
    return MonthlyRecap.fromJson(body);
  }

  static Future<BalanceSheet> balanceSheet({int? locationId, required String to}) async {
    final body = await ApiClient.request('GET', '/api/accounting/balance-sheet', query: {
      if (locationId != null) 'location_id': locationId,
      'to': to,
    });
    return BalanceSheet.fromJson(body);
  }

  // ── periods ──

  static Future<List<AccountingPeriod>> periods() async =>
      ApiClient.list(await ApiClient.request('GET', '/api/accounting/periods'), 'periods', AccountingPeriod.fromJson);

  static Future<String> setPeriod(int year, int month, {required bool close}) async {
    final body = await ApiClient.request('POST', '/api/accounting/periods/$year/$month/${close ? 'close' : 'reopen'}');
    return body['message']?.toString() ?? (close ? 'Periode ditutup' : 'Periode dibuka kembali');
  }
}
