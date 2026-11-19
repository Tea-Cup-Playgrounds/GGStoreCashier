// The accounting models read real API responses (captured from the dev API into
// test/fixtures/accounting): every field the finance screens use parses, numbers come through
// whether MySQL sent them as strings or numbers, and the totals agree with their rows.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gg_store_cashier/core/models/accounting.dart';
import 'package:gg_store_cashier/core/models/monthly_recap.dart';
import 'package:gg_store_cashier/features/finance/presentation/widgets/finance_widgets.dart';
import 'package:gg_store_cashier/core/models/access.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/accounting/$name.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  test('expense list and detail', () {
    final list = ExpenseList.fromJson(fixture('expenses'));
    expect(list.expenses, isNotEmpty);
    expect(list.total, greaterThan(0));
    expect(list.byCategory.fold<double>(0, (s, c) => s + c.$2), closeTo(list.total, 0.01));
    final x = list.expenses.first;
    expect(x.number, startsWith('EXP-'));
    expect(x.date, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(['Kas', 'Bank'], contains(x.paidFromLabel));

    final detail = Expense.fromJson(fixture('expense')['expense'] as Map<String, dynamic>);
    expect(detail.id, x.id);
    expect(detail.journalNumber, startsWith('JV-'));
  });

  test('expense categories', () {
    final categories = (fixture('categories')['categories'] as List).map((c) => ExpenseCategory.fromJson(c as Map<String, dynamic>)).toList();
    expect(categories.map((c) => c.code), contains('6-1000'));
    expect(categories.map((c) => c.code), isNot(contains('5-1000')), reason: 'HPP is booked by the system');
  });

  test('pulsa deposit', () {
    final d = PulsaDeposit.fromJson(fixture('pulsa'));
    expect(d.topUps, isNotEmpty);
    expect(d.topUps.first.amount, greaterThan(0));
    expect(d.usage.first.month, matches(RegExp(r'^\d{4}-\d{2}$')));
    expect(d.usage.first.sales, greaterThan(0));
  });

  test('journals, a journal with balanced lines, accounts', () {
    final list = (fixture('journals')['journals'] as List).map((j) => JournalSummary.fromJson(j as Map<String, dynamic>)).toList();
    expect(list.first.sourceType, 'manual');
    expect(list.first.amount, greaterThan(0));
    expect(journalSourceLabel(list.first.sourceType), 'Jurnal manual');

    final j = Journal.fromJson(fixture('journal')['journal'] as Map<String, dynamic>);
    expect(j.summary.id, list.first.id);
    expect(j.lines.length, greaterThanOrEqualTo(2));
    expect(j.totalDebit, closeTo(j.totalCredit, 0.001));
    expect(j.totalDebit, closeTo(list.first.amount, 0.01));

    final accounts = (fixture('accounts')['accounts'] as List).map((a) => LedgerAccount.fromJson(a as Map<String, dynamic>)).toList();
    expect(accounts.where((a) => a.code == '1-0000').single.isPostable, isFalse);
    expect(accounts.where((a) => a.code == '1-1100').single.isPostable, isTrue);
  });

  test('profit and loss totals add up', () {
    final pl = ProfitLoss.fromJson(fixture('profit_loss'));
    expect(pl.totalIncome, closeTo(pl.income.fold<double>(0, (s, r) => s + r.balance), 0.01));
    expect(pl.netProfit, closeTo(pl.totalIncome - pl.totalExpense, 0.01));
    expect(pl.grossProfit, closeTo(pl.totalIncome - pl.costOfGoods, 0.01));
    expect(pl.operatingExpense, closeTo(pl.expense.where((r) => !r.code!.startsWith('5-')).fold<double>(0, (s, r) => s + r.balance), 0.01));
  });

  test('balance sheet balances and has the computed profit lines', () {
    final bs = BalanceSheet.fromJson(fixture('balance_sheet'));
    expect(bs.balanced, isTrue);
    expect(bs.totalAssets, closeTo(bs.totalLiabilities + bs.totalEquity, 0.01));
    expect(bs.equity.where((r) => r.computed).length, 2);
  });

  test('periods', () {
    final periods = (fixture('periods')['periods'] as List).map((p) => AccountingPeriod.fromJson(p as Map<String, dynamic>)).toList();
    expect(periods.every((p) => p.month >= 1 && p.month <= 12), isTrue);
    expect(periods.where((p) => p.isClosed), isNotEmpty);
    expect(periods.firstWhere((p) => p.isClosed).closedByName, isNotNull);
  });

  test('manual journal line sends debit or credit only', () {
    expect(ManualJournalLine(accountCode: '1-1200', debit: 5000, memo: ' ').toJson(), {'account_code': '1-1200', 'debit': 5000.0});
    expect(ManualJournalLine(accountCode: '1-1100', credit: 5000, memo: 'x').toJson(), {'account_code': '1-1100', 'credit': 5000.0, 'memo': 'x'});
  });

  test('who sees which locations', () {
    const branchAdmin = UserAccess(isOwner: false, assignments: [
      AccessAssignment(locationId: 2, roleId: 2, roleName: 'Branch Manager', permissions: {'expenses.manage', 'sales.void'}),
    ]);
    const accountant = UserAccess(isOwner: false, assignments: [
      AccessAssignment(locationId: null, roleId: 5, roleName: 'Accountant', permissions: {'accounting.view', 'expenses.manage'}),
    ]);
    const owner = UserAccess(isOwner: true, assignments: []);
    expect(scopeFor(branchAdmin, ['expenses.manage', 'accounting.view']), {2});
    expect(scopeFor(branchAdmin, ['accounting.view']), isEmpty);
    expect(scopeFor(accountant, ['expenses.manage']), isNull, reason: 'every location, head office too');
    expect(scopeFor(owner, ['accounting.view']), isNull);
  });

  test('date helpers', () {
    expect(ymd(DateTime(2026, 3, 5)), '2026-03-05');
    expect(dayLabel('2026-11-14'), '14 Nov 2026');
    expect(yearMonthLabel('2026-03'), 'Maret 2026');
    final (from, to) = monthRange(DateTime(2026, 2));
    expect(from, '2026-02-01');
    expect(to, '2026-02-28');
  });

  test('monthly recap: spreadsheet formulas hold on a real response; branch managers get no allocation', () {
    final r = MonthlyRecap.fromJson(fixture('monthly_recap'));
    final o = r.omset;
    expect(r.month, '2026-10');
    expect(o.gross, greaterThan(0));
    expect(o.net, closeTo(o.gross - o.expenses - o.refund - o.discounts, 0.01));
    expect(o.expenses, closeTo(o.expenseLines.fold<double>(0, (s, l) => s + l.amount), 0.01));
    final a = r.allocation!;
    expect(a.netRevenue, o.net);
    expect(a.operational, closeTo(a.operationalLines.fold<double>(0, (s, l) => s + l.amount), 0.01));
    expect(a.remaining, closeTo(a.netRevenue - a.operational - a.stockPurchases - a.debtPayments - a.assets, 0.01));
    expect(r.categories, isNotEmpty);
    for (final c in r.categories) {
      expect(c.grossProfit, closeTo(c.revenue - c.cost, 0.01));
    }

    final branch = MonthlyRecap.fromJson(fixture('monthly_recap_branch'));
    expect(branch.allocation, isNull);
    expect(branch.omset.gross, lessThan(o.gross));
  });
}
