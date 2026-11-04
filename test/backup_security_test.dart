import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:spendwise/database/app_database.dart';
import 'package:spendwise/models/records.dart';
import 'package:spendwise/repositories/finance_repository.dart';
import 'package:spendwise/services/backup_service.dart';
import 'package:spendwise/services/app_lock_service.dart';
import 'package:spendwise/services/recurrence_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('encrypted backup restores transactions and rules; bad import leaves original records', () async {
    final db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    try {
      final repo = FinanceRepository(db),
          service = BackupService(db, factory: databaseFactoryFfi);
      final category = (await repo.categories(type: TransactionType.expense))
          .first
          .id;
      await RecurrenceService(db).save(
        categoryId: category,
        amountSen: 1234,
        description: 'Subscription',
        frequency: 'monthly',
        start: DateTime(2026, 1, 31),
      );
      await RecurrenceService(db).generate(DateTime(2026, 2, 28));
      final bytes = await service.export('a long test passphrase');
      expect(utf8.decode(bytes).contains('Subscription'), isFalse);
      final payload = await service.read(bytes, 'a long test passphrase');
      final original = await db.connection.query('transactions');
      await expectLater(
        service.restore({
          ...payload,
          'transactions': [
            {'id': 1, 'category_id': 9999, 'type': 'expense', 'amount_sen': -1},
          ],
        }),
        throwsA(anything),
      );
      expect(await db.connection.query('transactions'), original);
      final encrypted = bytes;
      await expectLater(
        service.read(encrypted, 'wrong password'),
        throwsA(anything),
      );
      final envelope =
          jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;
      final ciphertext = base64Decode(envelope['ciphertext'] as String);
      ciphertext[0] ^= 1;
      envelope['ciphertext'] = base64Encode(ciphertext);
      await expectLater(
        service.read(
          utf8.encode(jsonEncode(envelope)),
          'a long test passphrase',
        ),
        throwsA(anything),
      );
      await db.connection.execute(
        "CREATE TRIGGER reject_restore BEFORE INSERT ON transactions BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      await expectLater(
        service.restore(payload),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.connection.query('transactions'), original);
      await db.connection.execute('DROP TRIGGER reject_restore');
      await db.connection.delete('transactions');
      await service.restore(payload);
      expect(await db.connection.query('transactions'), original);
      expect(await db.connection.query('recurring_rules'), hasLength(1));
    } finally {
      await db.close();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('PIN hashing, persistent cooldown, startup lock and timeout', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final lock = AppLockService();
    await lock.load();
    expect(lock.enabled, false);
    await lock.configure('123456');
    final raw = await lock.storage.read(key: 'spendwise.lock');
    expect(raw!.contains('123456'), isFalse);
    lock.lock();
    expect(lock.locked, true);
    expect(await lock.verify('000000'), false);
    final restarted = AppLockService();
    await restarted.load();
    expect(restarted.locked, true);
    expect(restarted.remainingSeconds, greaterThan(0));
    expect(await restarted.verify('123456'), false);
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(await restarted.verify('123456'), true);
    await restarted.setOptions(seconds: 0);
    restarted.background();
    restarted.resume();
    expect(restarted.locked, true);
    expect(await restarted.verify('123456'), true);
    await restarted.disable('123456');
    expect(restarted.enabled, false);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('corrupt secure storage fails closed', () async {
    FlutterSecureStorage.setMockInitialValues({'spendwise.lock': 'invalid'});
    final lock = AppLockService();
    await lock.load();
    expect(lock.ready, false);
    expect(lock.locked, true);
  });
}
