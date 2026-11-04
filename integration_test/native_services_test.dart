import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:spendwise/database/app_database.dart';
import 'package:spendwise/models/records.dart';
import 'package:spendwise/repositories/finance_repository.dart';
import 'package:spendwise/services/app_lock_service.dart';
import 'package:spendwise/services/backup_service.dart';
import 'package:spendwise/services/recurrence_service.dart';
import 'package:spendwise/main.dart';
import 'package:spendwise/theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native secure storage persists a PIN verifier and unlocks', (
    tester,
  ) async {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(
        resetOnError: false,
        preferencesKeyPrefix: 'integration_test_only',
      ),
    );
    final lock = AppLockService(storage: storage);
    try {
      await storage.delete(key: 'spendwise.lock');
      await lock.load();
      await lock.configure('418253');
      final restarted = AppLockService(storage: storage);
      await restarted.load();
      expect(restarted.enabled, true);
      expect(restarted.locked, true);
      final preferences = await AppearancePreferences.load();
      await tester.pumpWidget(
        SpendWiseApp(
          preferences: preferences,
          lock: restarted,
          home: const Scaffold(body: Text('Private financial screen')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private financial screen'), findsNothing);
      expect(find.text('Unlock SpendWise'), findsOneWidget);
      expect(await restarted.verify('418253'), true);
      await tester.pumpAndSettle();
      expect(find.text('Private financial screen'), findsOneWidget);
      restarted.lock();
      await tester.pumpAndSettle();
      expect(find.text('Private financial screen'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    } finally {
      await storage.delete(key: 'spendwise.lock');
    }
  });
  testWidgets(
    'Android encrypted backup writes, validates and restores actual records',
    (_) async {
      final db = await AppDatabase.open(
        path: inMemoryDatabasePath,
        singleInstance: false,
      );
      File? file;
      try {
        final repo = FinanceRepository(db);
        final category = (await repo.categories(type: TransactionType.expense))
            .first
            .id;
        await RecurrenceService(db).save(
          categoryId: category,
          amountSen: 4321,
          description: 'Native backup test',
          frequency: 'monthly',
          start: DateTime(2026, 1, 31),
        );
        await RecurrenceService(db).generate(DateTime(2026, 2, 28));
        final service = BackupService(db);
        final encrypted = await service.export('native test passphrase');
        file = File(
          '${(await getTemporaryDirectory()).path}/native-integration-test.swbackup',
        );
        await service.writeVerified(file, encrypted, 'native test passphrase');
        final payload = await service.read(
          await file.readAsBytes(),
          'native test passphrase',
        );
        await db.connection.delete('transactions');
        await service.restore(payload);
        expect(await repo.transactions(), hasLength(2));
        expect((await repo.transactions()).first.amountSen, 4321);
        expect(await RecurrenceService(db).rules(), hasLength(1));
      } finally {
        await db.close();
        if (file != null && await file.exists()) await file.delete();
      }
    },
  );
}
