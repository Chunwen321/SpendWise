import 'package:flutter/foundation.dart' hide Category;

import '../models/records.dart';
import '../repositories/finance_repository.dart';
import '../services/recurrence_service.dart';

String money(int sen) =>
    '${sen < 0 ? '-' : ''}RM ${(sen.abs() ~/ 100)}.${(sen.abs() % 100).toString().padLeft(2, '0')}';

class FinanceStore extends ChangeNotifier {
  FinanceStore(this.repository);
  final FinanceRepository repository;
  List<Category> categories = [];
  List<FinancialTransaction> transactions = [];
  List<Map<String, Object?>> accounts = [], transfers = [];
  bool loading = true;
  String? error;
  Future<void> refresh() async {
    try {
      await RecurrenceService(repository.database).generate(DateTime.now());
      categories = await repository.categories();
      transactions = await repository.transactions();
      accounts = await repository.accounts();
      transfers = await repository.transfers();
      error = null;
    } catch (_) {
      error = 'Could not load records. Please try again.';
    }
    loading = false;
    notifyListeners();
  }

  String categoryName(int id) =>
      categories.where((c) => c.id == id).firstOrNull?.name ??
      'Category unavailable';
  String accountName(int id) =>
      accounts.where((a) => a['id'] == id).firstOrNull?['name'] as String? ??
      'Account unavailable';
  int accountBalance(int id) {
    var balance =
        accounts.where((a) => a['id'] == id).firstOrNull?['opening_sen']
            as int? ??
        0;
    for (final row in transactions.where((r) => r.accountId == id)) {
      balance += row.type == TransactionType.income
          ? row.amountSen
          : -row.amountSen;
    }
    for (final row in transfers) {
      if (row['from_account_id'] == id) balance -= row['amount_sen'] as int;
      if (row['to_account_id'] == id) balance += row['amount_sen'] as int;
    }
    return balance;
  }

  int get overallBalance =>
      accounts.fold(0, (sum, a) => sum + accountBalance(a['id'] as int));
}

class Totals {
  Totals(List<FinancialTransaction> rows, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final monday = DateTime(
      today.year,
      today.month,
      today.day - today.weekday + 1,
    );
    final month = DateTime(today.year, today.month);
    for (final row in rows) {
      if (row.type == TransactionType.income) {
        income += row.amountSen;
        continue;
      }
      expense += row.amountSen;
      if (row.date == today) day += row.amountSen;
      if (!row.date.isBefore(monday) && !row.date.isAfter(today)) {
        week += row.amountSen;
      }
      if (!row.date.isBefore(month) && !row.date.isAfter(today)) {
        thisMonth += row.amountSen;
      }
    }
  }
  int income = 0, expense = 0, day = 0, week = 0, thisMonth = 0;
  int get balance => income - expense;
}
