import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:spendwise/database/app_database.dart';
import 'package:spendwise/models/records.dart';
import 'package:spendwise/repositories/finance_repository.dart';
import 'package:spendwise/services/recurrence_service.dart';

void main() {
  sqfliteFfiInit();
  test('monthly clamp returns to original day including leap years', () {
    expect(
      nextOccurrence(DateTime(2024, 1, 31), 'monthly', 31),
      DateTime(2024, 2, 29),
    );
    expect(
      nextOccurrence(DateTime(2024, 2, 29), 'monthly', 31),
      DateTime(2024, 3, 31),
    );
    expect(
      nextOccurrence(DateTime(2025, 1, 30), 'monthly', 30),
      DateTime(2025, 2, 28),
    );
    expect(
      nextOccurrence(DateTime(2026, 12, 31), 'daily', 31),
      DateTime(2027, 1, 1),
    );
  });
  test(
    'catch up is idempotent, honors end dates and preserves edited occurrences',
    () async {
      final db = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      try {
        final repo = FinanceRepository(db);
        final service = RecurrenceService(db);
        final category = (await repo.categories(type: TransactionType.expense))
            .first
            .id;
        await service.save(
          categoryId: category,
          amountSen: 100,
          description: 'Rent',
          frequency: 'monthly',
          start: DateTime(2026, 1, 31),
          end: DateTime(2026, 3, 31),
        );
        await service.generate(DateTime(2026, 4, 1));
        var rows = await repo.transactions();
        expect(rows.map((r) => calendarDate(r.date)), [
          '2026-03-31',
          '2026-02-28',
          '2026-01-31',
        ]);
        await repo.updateTransaction(
          id: rows.first.id,
          categoryId: category,
          type: TransactionType.expense,
          amountSen: 200,
          date: DateTime(2026, 3, 30),
        );
        await service.generate(DateTime(2026, 4, 1));
        rows = await repo.transactions();
        expect(rows, hasLength(3));
        expect(rows.first.amountSen, 200);
        expect((await service.rules()).single['is_active'], 0);
        await service.save(
          categoryId: category,
          amountSen: 10,
          description: '',
          frequency: 'weekly',
          start: DateTime(2026, 1, 1),
        );
        final id = (await service.rules())
            .map((r) => r['id'] as int)
            .reduce((a, b) => a > b ? a : b);
        await service.setActive(id, false);
        await service.generate(DateTime(2026, 1, 15));
        expect(await repo.transactions(), hasLength(3));
        await service.setActive(id, true);
        await service.generate(DateTime(2026, 1, 15));
        expect(await repo.transactions(), hasLength(6));
      } finally {
        await db.close();
      }
    },
  );
}
