import '../database/app_database.dart';
import '../models/records.dart';

class FinanceRepository {
  FinanceRepository(this.database);
  final AppDatabase database;

  Future<List<Category>> categories({TransactionType? type}) async =>
      (await database.connection.query(
        'categories',
        where: type == null ? null : 'type = ?',
        whereArgs: type == null ? null : [type.name],
        orderBy: 'type, name COLLATE NOCASE, id',
      )).map(Category.fromMap).toList();

  String _name(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 100) {
      throw ArgumentError('Category name must contain 1–100 characters.');
    }
    return trimmed;
  }

  Future<int> createCategory(String name, TransactionType type) =>
      database.connection.insert('categories', {
        'name': _name(name),
        'type': type.name,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

  Future<void> renameCategory(int id, String name) async {
    final count = await database.connection.update(
      'categories',
      {'name': _name(name)},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count != 1) throw StateError('Category no longer exists.');
  }

  /// Foreign keys block deletion if transactions or rules reference the category.
  Future<void> deleteCategory(int id) async {
    final count = await database.connection.delete(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count != 1) throw StateError('Category no longer exists.');
  }

  Future<void> reassignAndDeleteCategory(int id, int replacementId) =>
      database.connection.transaction((txn) async {
        if (id == replacementId) {
          throw ArgumentError('Choose another category.');
        }
        final source = (await txn.query(
          'categories',
          where: 'id = ?',
          whereArgs: [id],
        )).single;
        final replacement = (await txn.query(
          'categories',
          where: 'id = ?',
          whereArgs: [replacementId],
        )).single;
        if (source['type'] != replacement['type']) {
          throw ArgumentError('Category types must match.');
        }
        await txn.update(
          'transactions',
          {
            'category_id': replacementId,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'category_id = ?',
          whereArgs: [id],
        );
        await txn.update(
          'recurring_rules',
          {
            'category_id': replacementId,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'category_id = ?',
          whereArgs: [id],
        );
        await txn.delete('categories', where: 'id = ?', whereArgs: [id]);
      });

  Map<String, Object?> _values(
    int categoryId,
    TransactionType type,
    int amountSen,
    DateTime date,
    String description,
  ) {
    if (amountSen <= 0 || amountSen > maxAmountSen) {
      throw ArgumentError('Amount is outside the supported range.');
    }
    if (date.year < 1 || date.year > 9999) throw ArgumentError('Invalid date.');
    return {
      'category_id': categoryId,
      'type': type.name,
      'amount_sen': amountSen,
      'transaction_date': calendarDate(date),
      'description': description.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<int> createTransaction({
    int accountId = 1,
    required int categoryId,
    required TransactionType type,
    required int amountSen,
    required DateTime date,
    String description = '',
  }) {
    final values = _values(categoryId, type, amountSen, date, description);
    values['created_at'] = values['updated_at'];
    values['account_id'] = accountId;
    return database.connection.insert('transactions', values);
  }

  Future<FinancialTransaction?> transaction(int id) async {
    final rows = await database.connection.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : FinancialTransaction.fromMap(rows.single);
  }

  Future<List<FinancialTransaction>> transactions() async =>
      (await database.connection.query(
        'transactions',
        orderBy: 'transaction_date DESC, id DESC',
      )).map(FinancialTransaction.fromMap).toList();

  Future<void> updateTransaction({
    int? accountId,
    required int id,
    required int categoryId,
    required TransactionType type,
    required int amountSen,
    required DateTime date,
    String description = '',
  }) async {
    final count = await database.connection.update(
      'transactions',
      {
        ..._values(categoryId, type, amountSen, date, description),
        'account_id': ?accountId,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count != 1) throw StateError('Transaction no longer exists.');
  }

  Future<void> deleteTransaction(int id) async {
    final count = await database.connection.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count != 1) throw StateError('Transaction no longer exists.');
  }

  Future<List<Map<String, Object?>>> accounts() =>
      database.connection.query('accounts', orderBy: 'id');
  Future<List<Map<String, Object?>>> transfers() => database.connection.query(
    'transfers',
    orderBy: 'transaction_date DESC, id DESC',
  );
  Future<void> saveAccount({
    int? id,
    required String name,
    required String kind,
    required int openingSen,
  }) async {
    if (!['cash', 'bank', 'ewallet', 'other'].contains(kind) ||
        openingSen.abs() > maxAmountSen) {
      throw ArgumentError('Invalid account.');
    }
    final values = {
      'name': _name(name),
      'kind': kind,
      'opening_sen': openingSen,
    };
    if (id == null) {
      await database.connection.insert('accounts', {
        ...values,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } else {
      await database.connection.update(
        'accounts',
        values,
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> deleteAccount(int id) async {
    await database.connection.transaction((txn) async {
      if ((await txn.query('accounts')).length <= 1) {
        throw StateError('Keep at least one account.');
      }
      await txn.delete('accounts', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> transfer({
    required int from,
    required int to,
    required int amountSen,
    required DateTime date,
    String description = '',
  }) async {
    if (from == to || amountSen <= 0 || amountSen > maxAmountSen) {
      throw ArgumentError('Invalid transfer.');
    }
    await database.connection.insert('transfers', {
      'from_account_id': from,
      'to_account_id': to,
      'amount_sen': amountSen,
      'transaction_date': calendarDate(date),
      'description': description.trim(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> deleteTransfer(int id) async {
    await database.connection.delete(
      'transfers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
