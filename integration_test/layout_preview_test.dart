import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:spendwise/database/app_database.dart';
import 'package:spendwise/main.dart';
import 'package:spendwise/models/records.dart';
import 'package:spendwise/providers/finance_store.dart';
import 'package:spendwise/repositories/finance_repository.dart';
import 'package:spendwise/screens/main_shell.dart';
import 'package:spendwise/theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'overview and grouped ledger render in light and dark without overflow',
    (tester) async {
      final db = await AppDatabase.open(
        path: inMemoryDatabasePath,
        singleInstance: false,
      );
      final repo = FinanceRepository(db);
      await repo.saveAccount(
        id: 1,
        name: 'Cash',
        kind: 'cash',
        openingSen: 30000,
      );
      await repo.saveAccount(
        name: 'Everyday bank',
        kind: 'bank',
        openingSen: 125000,
      );
      await repo.saveAccount(
        name: 'TNG eWallet',
        kind: 'ewallet',
        openingSen: 5000,
      );
      final category = (await repo.categories(type: TransactionType.expense))
          .firstWhere((c) => c.name == 'Food & Drinks')
          .id;
      final today = DateTime.now();
      await repo.createTransaction(
        accountId: 3,
        categoryId: category,
        type: TransactionType.expense,
        amountSen: 1040,
        date: today,
        description: 'Lunch',
      );
      await repo.createTransaction(
        accountId: 1,
        categoryId: category,
        type: TransactionType.expense,
        amountSen: 990,
        date: DateTime(today.year, today.month, today.day - 1),
        description: 'Breakfast',
      );
      await repo.transfer(from: 2, to: 3, amountSen: 5000, date: today);
      final store = FinanceStore(repo);
      await store.refresh();
      final preferences = await AppearancePreferences.load();
      final original = preferences.mode;
      Future<void> capture(String name) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('preview')),
        );
        final picture = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${(await getApplicationDocumentsDirectory()).path}/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      }

      try {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('preview'),
            child: ChangeNotifierProvider.value(
              value: store,
              child: SpendWiseApp(
                preferences: preferences,
                home: MainShell(preferences: preferences),
              ),
            ),
          ),
        );
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          await preferences.setMode(mode);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Home').last);
          await tester.pumpAndSettle();
          expect(find.text('Overall accounts'), findsOneWidget);
          await capture('overview-${mode.name}');
          await tester.tap(find.text('Transactions').last);
          await tester.pumpAndSettle();
          expect(find.text('Transfer'), findsOneWidget);
          expect(find.text('Food & Drinks'), findsWidgets);
          await capture('ledger-${mode.name}');
          expect(tester.takeException(), isNull);
        }
        if (const bool.fromEnvironment('EXPORT_PREVIEWS')) {
          debugPrint('UI previews ready for export');
          // Keep the test-only installation alive briefly for adb retrieval.
          await Future<void>.delayed(const Duration(seconds: 40));
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await preferences.setMode(original);
        store.dispose();
        await db.close();
      }
    },
  );
}
