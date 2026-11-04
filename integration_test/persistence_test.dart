import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:spendwise/database/app_database.dart';
import 'package:spendwise/models/records.dart';
import 'package:spendwise/repositories/finance_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android SQLite persists a transaction after closing and reopening',
    (_) async {
      // Unique test-only file: never open or delete the user's spendwise.db.
      final path = p.join(
        await getDatabasesPath(),
        'persistence_test_${DateTime.now().microsecondsSinceEpoch}.db',
      );
      var db = await AppDatabase.open(path: path);
      try {
        var repo = FinanceRepository(db);
        final category = (await repo.categories(type: TransactionType.expense))
            .first;
        final id = await repo.createTransaction(
          categoryId: category.id,
          type: TransactionType.expense,
          amountSen: 1234,
          date: DateTime(2026, 11, 4),
        );
        await db.close();
        db = await AppDatabase.open(path: path);
        repo = FinanceRepository(db);
        expect((await repo.transaction(id))!.amountSen, 1234);
      } finally {
        await db.close();
        await deleteDatabase(path);
      }
    },
  );
}
