import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:spendwise/database/app_database.dart';
import 'package:spendwise/models/records.dart';
import 'package:spendwise/providers/finance_store.dart';
import 'package:spendwise/repositories/finance_repository.dart';
import 'package:spendwise/services/backup_service.dart';
import 'package:spendwise/services/recurrence_service.dart';

void main() {
  sqfliteFfiInit();
  test('version 1 migration preserves financial records', () async {
    final temp = await Directory.systemTemp.createTemp('spendwise_migration_');
    final path = '${temp.path}/legacy.db';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => AppDatabase.migrate(db, 0, 1),
      ),
    );
    await old.insert('transactions', {
      'category_id': 1,
      'type': 'expense',
      'amount_sen': 456,
      'transaction_date': '2026-11-04',
      'description': 'Preserved',
      'created_at': 'now',
      'updated_at': 'now',
    });
    await old.close();
    final upgraded = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    try {
      final repo = FinanceRepository(upgraded);
      expect(await upgraded.connection.getVersion(), 2);
      expect((await repo.transactions()).single.amountSen, 456);
      expect((await repo.transactions()).single.accountId, 1);
      expect((await repo.accounts()).single['name'], 'Main ledger');
    } finally {
      await upgraded.close();
      await temp.delete(recursive: true);
    }
  });

  test(
    'accounts, transfers and recurring charges keep overall totals accurate',
    () async {
      final db = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
        singleInstance: false,
      );
      try {
        final repo = FinanceRepository(db);
        await repo.saveAccount(name: 'Cash', kind: 'cash', openingSen: 10000);
        await repo.saveAccount(name: 'Bank', kind: 'bank', openingSen: 50000);
        final cash =
            (await repo.accounts()).firstWhere((a) => a['name'] == 'Cash')['id']
                as int;
        final bank =
            (await repo.accounts()).firstWhere((a) => a['name'] == 'Bank')['id']
                as int;
        final expense = (await repo.categories(type: TransactionType.expense))
            .first
            .id;
        final income = (await repo.categories(type: TransactionType.income))
            .first
            .id;
        await repo.createTransaction(
          accountId: cash,
          categoryId: expense,
          type: TransactionType.expense,
          amountSen: 1234,
          date: DateTime.now(),
        );
        await repo.createTransaction(
          accountId: bank,
          categoryId: income,
          type: TransactionType.income,
          amountSen: 5000,
          date: DateTime.now(),
        );
        await repo.transfer(
          from: bank,
          to: cash,
          amountSen: 2000,
          date: DateTime.now(),
        );
        final store = FinanceStore(repo);
        await store.refresh();
        expect(store.accountBalance(cash), 10766);
        expect(store.accountBalance(bank), 53000);
        expect(store.overallBalance, 63766);
        expect(Totals(store.transactions, DateTime.now()).expense, 1234);
        await expectLater(
          repo.deleteAccount(cash),
          throwsA(isA<DatabaseException>()),
        );
        await repo.deleteTransfer(store.transfers.single['id'] as int);
        await store.refresh();
        expect(store.accountBalance(cash), 8766);
        expect(store.overallBalance, 63766);
        await RecurrenceService(db).save(
          accountId: bank,
          categoryId: expense,
          amountSen: 100,
          description: '',
          frequency: 'daily',
          start: DateTime.now(),
        );
        await store.refresh();
        expect(store.accountBalance(bank), 54900);
        final backup = BackupService(db, factory: databaseFactoryFfi);
        final payload = await backup.snapshot();
        await backup.restore(payload);
        expect(await repo.accounts(), hasLength(3));
        expect(
          (await repo.transactions())
              .where((r) => r.recurringRuleId != null)
              .single
              .accountId,
          bank,
        );
        store.dispose();
      } finally {
        await db.close();
      }
    },
  );

  test('legacy backup upgrades without inventing account balances', () async {
    final db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    try {
      final repo = FinanceRepository(db);
      final category = (await repo.categories(type: TransactionType.expense))
          .first
          .id;
      await repo.createTransaction(
        categoryId: category,
        type: TransactionType.expense,
        amountSen: 123,
        date: DateTime(2026, 11, 4),
      );
      final service = BackupService(db, factory: databaseFactoryFfi);
      final snapshot = await service.snapshot();
      final legacy = <String, Object?>{
        'schema': 1,
        'categories': snapshot['categories'],
        for (final table in ['transactions', 'recurring_rules'])
          table: [
            for (final row in snapshot[table] as List)
              Map<String, Object?>.from(row as Map)..remove('account_id'),
          ],
      };
      await service.restore(legacy);
      expect((await repo.transactions()).single.amountSen, 123);
      expect((await repo.transactions()).single.accountId, 1);
      expect((await repo.accounts()).single['opening_sen'], 0);
    } finally {
      await db.close();
    }
  });
}
