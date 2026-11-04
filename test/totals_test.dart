import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/models/records.dart';
import 'package:spendwise/providers/finance_store.dart';

void main() {
  FinancialTransaction row(
    int amount,
    DateTime date, {
    TransactionType type = TransactionType.expense,
  }) => FinancialTransaction(
    id: 1,
    categoryId: 1,
    type: type,
    amountSen: amount,
    description: '',
    date: date,
    createdAt: '',
    updatedAt: '',
  );
  test(
    'local calendar totals use Monday and exclude future period spending',
    () {
      final totals = Totals([
        row(100, DateTime(2026, 11, 1)),
        row(200, DateTime(2026, 11, 2)),
        row(300, DateTime(2026, 11, 4)),
        row(400, DateTime(2026, 11, 5)),
        row(1000, DateTime(2026, 10, 31), type: TransactionType.income),
      ], DateTime(2026, 11, 4, 23));
      expect(totals.balance, 0);
      expect(totals.day, 300);
      expect(totals.week, 500);
      expect(totals.thisMonth, 600);
      expect(money(-123), '-RM 1.23');
    },
  );
}
