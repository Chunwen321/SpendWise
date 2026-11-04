import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:spendwise/database/app_database.dart';
import 'package:spendwise/main.dart';
import 'package:spendwise/providers/finance_store.dart';
import 'package:spendwise/repositories/finance_repository.dart';
import 'package:spendwise/screens/main_shell.dart';
import 'package:spendwise/screens/transaction_editor.dart';
import 'package:spendwise/theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('add, edit, filter, chart and confirmed delete use real SQLite', (
    tester,
  ) async {
    final db = await AppDatabase.open(
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    final store = FinanceStore(FinanceRepository(db));
    await store.refresh();
    final preferences = await AppearancePreferences.load();
    try {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: SpendWiseApp(
            preferences: preferences,
            home: MainShell(preferences: preferences),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Current balance'), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (RM)'),
        '12.34',
      );
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<int>, 'Category'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Food & Drinks').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description (optional)'),
        'Integration lunch',
      );
      await tester.scrollUntilVisible(
        find.text('Save transaction'),
        180,
        scrollable: find
            .descendant(
              of: find.byType(TransactionEditor),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await tester.tap(find.text('Save transaction'));
      for (
        var i = 0;
        i < 40 && find.byType(TransactionEditor).evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.pumpAndSettle();
      expect(store.transactions, hasLength(1));
      expect(store.transactions.single.amountSen, 1234);
      await tester.tap(find.text('Transactions').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search description or category'),
        'not present',
      );
      await tester.pumpAndSettle();
      expect(find.text('No matching transactions.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Search description or category'),
        'lunch',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TransactionTile).hitTestable().first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (RM)'),
        '15.00',
      );
      await tester.scrollUntilVisible(
        find.text('Save transaction'),
        180,
        scrollable: find
            .descendant(
              of: find.byType(TransactionEditor),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await tester.tap(find.text('Save transaction'));
      for (
        var i = 0;
        i < 40 && find.byType(TransactionEditor).evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.pumpAndSettle();
      expect(store.transactions.single.amountSen, 1500);
      await tester.tap(find.text('Analytics').last);
      await tester.pumpAndSettle();
      expect(find.text('Month spending: RM 15.00'), findsOneWidget);
      await tester.tap(find.text('Transactions').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TransactionTile).hitTestable().first);
      await tester.pumpAndSettle();
      expect(find.byType(TransactionEditor), findsOneWidget);
      await tester.tap(find.byTooltip('Delete transaction'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.transactions, hasLength(1));
      await tester.tap(find.byTooltip('Delete transaction'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      for (var i = 0; i < 20 && store.transactions.isNotEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.pumpAndSettle();
      expect(store.transactions, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      await db.close();
    }
  });
}
