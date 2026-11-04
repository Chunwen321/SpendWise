import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:spendwise/database/app_database.dart';
import 'package:spendwise/models/records.dart';
import 'package:spendwise/repositories/finance_repository.dart';

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late String path;
  late AppDatabase db;
  late FinanceRepository repo;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('spendwise_test_');
    path = '${temp.path}/test.db';
    db = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    repo = FinanceRepository(db);
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  test(
    'schema, defaults and category CRUD protect referenced records',
    () async {
      expect(await db.connection.getVersion(), 2);
      expect(
        (await db.connection.rawQuery('PRAGMA foreign_keys'))
            .single
            .values
            .single,
        1,
      );
      expect(await repo.categories(), hasLength(14));
      final id = await repo.createCategory('Test', TransactionType.expense);
      await repo.renameCategory(id, 'Renamed');
      expect(
        (await repo.categories()).singleWhere((c) => c.id == id).name,
        'Renamed',
      );
      await repo.createTransaction(
        categoryId: id,
        type: TransactionType.expense,
        amountSen: 123,
        date: DateTime(2026, 11, 4),
      );
      await expectLater(
        repo.deleteCategory(id),
        throwsA(isA<DatabaseException>()),
      );
      final unused = await repo.createCategory(
        'Unused',
        TransactionType.income,
      );
      await repo.deleteCategory(unused);
      expect((await repo.categories()).any((c) => c.id == unused), isFalse);
    },
  );

  test('income and expense CRUD, date sorting, integer money and reopen persistence', () async {
    final expense = (await repo.categories(type: TransactionType.expense))
        .first
        .id;
    final income = (await repo.categories(type: TransactionType.income))
        .first
        .id;
    final id = await repo.createTransaction(
      categoryId: expense,
      type: TransactionType.expense,
      amountSen: parseRinggit('12.30'),
      date: DateTime(2026, 11, 3),
      description: 'Lunch',
    );
    final second = await repo.createTransaction(
      categoryId: income,
      type: TransactionType.income,
      amountSen: 100000,
      date: DateTime(2026, 11, 4),
    );
    expect((await repo.transactions()).map((t) => t.id), [second, id]);
    final createdAt = (await repo.transaction(id))!.createdAt;
    await repo.updateTransaction(
      id: id,
      categoryId: expense,
      type: TransactionType.expense,
      amountSen: 1500,
      date: DateTime(2026, 11, 2),
      description: 'Updated',
    );
    await db.close();
    db = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    repo = FinanceRepository(db);
    final saved = (await repo.transaction(id))!;
    expect(saved.amountSen, 1500);
    expect(saved.description, 'Updated');
    expect(saved.createdAt, createdAt);
    expect(calendarDate(saved.date), '2026-11-02');
    expect(await repo.categories(), hasLength(14));
    await repo.deleteTransaction(id);
    expect(await repo.transaction(id), isNull);
    expect((await repo.transactions()).single.amountSen, 100000);
    expect(
      (await db.connection.rawQuery('PRAGMA integrity_check'))
          .single
          .values
          .single,
      'ok',
    );
  });

  test('invalid writes fail and multi-write transactions roll back', () async {
    final expense = (await repo.categories(type: TransactionType.expense))
        .first
        .id;
    await expectLater(
      repo.createTransaction(
        categoryId: expense,
        type: TransactionType.income,
        amountSen: 100,
        date: DateTime(2026),
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect(
      () => repo.createTransaction(
        categoryId: expense,
        type: TransactionType.expense,
        amountSen: 0,
        date: DateTime(2026),
      ),
      throwsArgumentError,
    );
    await expectLater(
      db.connection.transaction((txn) async {
        await txn.insert('categories', {
          'name': 'Rollback',
          'type': 'expense',
          'created_at': 'now',
        });
        await txn.insert('categories', {
          'name': '',
          'type': 'expense',
          'created_at': 'now',
        });
      }),
      throwsA(isA<DatabaseException>()),
    );
    expect(await repo.categories(), hasLength(14));
    expect(await repo.transactions(), isEmpty);
  });

  test(
    'migration is repeatable and unsupported upgrades preserve data',
    () async {
      final category = (await repo.categories()).first;
      await AppDatabase.migrate(db.connection, 2, 2);
      await expectLater(
        AppDatabase.migrate(db.connection, 2, 3),
        throwsStateError,
      );
      expect((await repo.categories()).first.id, category.id);
      expect(await repo.categories(), hasLength(14));
    },
  );

  test('database constraints block invalid amounts and duplicate recurring occurrences', () async {
    final category = (await repo.categories(type: TransactionType.expense))
        .first
        .id;
    final rule = await db.connection.insert('recurring_rules', {
      'category_id': category,
      'amount_sen': 100,
      'frequency': 'monthly',
      'start_date': '2026-01-31',
      'next_due_date': '2026-01-31',
      'created_at': 'now',
      'updated_at': 'now',
    });
    final row = <String, Object?>{
      'category_id': category,
      'type': 'expense',
      'amount_sen': 100,
      'transaction_date': '2026-01-31',
      'created_at': 'now',
      'updated_at': 'now',
      'recurring_rule_id': rule,
      'recurrence_occurrence_date': '2026-01-31',
    };
    await db.connection.insert('transactions', row);
    await expectLater(
      db.connection.insert('transactions', row),
      throwsA(isA<DatabaseException>()),
    );
    for (final amount in [0, -1, 1.5, maxAmountSen + 1]) {
      await expectLater(
        db.connection.insert('transactions', {
          ...row,
          'amount_sen': amount,
          'recurrence_occurrence_date': '2026-02-28',
        }),
        throwsA(isA<DatabaseException>()),
      );
    }
    await expectLater(
      repo.deleteCategory(category),
      throwsA(isA<DatabaseException>()),
    );
    expect(await repo.transactions(), hasLength(1));
  });

  test('a newer schema is rejected without deleting records', () async {
    await db.connection.setVersion(3);
    await db.close();
    await expectLater(
      AppDatabase.open(factory: databaseFactoryFfi, path: path),
      throwsStateError,
    );
    final raw = await databaseFactoryFfi.openDatabase(path);
    expect(await raw.getVersion(), 3);
    expect(await raw.query('categories'), hasLength(14));
    await raw.close();
  });

  test('money parsing never uses floating point', () {
    expect(parseRinggit('0.01'), 1);
    expect(parseRinggit('12.3'), 1230);
    for (final value in [
      '0',
      '-1',
      '1.001',
      'NaN',
      '1e3',
      '9999999999999999999999',
    ]) {
      expect(() => parseRinggit(value), throwsFormatException);
    }
  });

  test('category reassignment is explicit, type-safe and atomic', () async {
    final source = (await repo.categories(type: TransactionType.expense))
        .first
        .id;
    final replacement = await repo.createCategory(
      'Replacement',
      TransactionType.expense,
    );
    final income = (await repo.categories(type: TransactionType.income))
        .first
        .id;
    final id = await repo.createTransaction(
      categoryId: source,
      type: TransactionType.expense,
      amountSen: 500,
      date: DateTime(2026),
    );
    await expectLater(
      repo.reassignAndDeleteCategory(source, income),
      throwsArgumentError,
    );
    expect((await repo.transaction(id))!.categoryId, source);
    await repo.reassignAndDeleteCategory(source, replacement);
    expect((await repo.transaction(id))!.categoryId, replacement);
    expect((await repo.categories()).any((c) => c.id == source), false);
  });
}
