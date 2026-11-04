import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._(this.connection);
  final Database connection;
  static const schemaVersion = 2;

  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? path,
    bool singleInstance = true,
  }) async {
    final selected = factory ?? databaseFactory;
    final location =
        path ?? p.join(await selected.getDatabasesPath(), 'spendwise.db');
    final db = await selected.openDatabase(
      location,
      options: OpenDatabaseOptions(
        singleInstance: singleInstance,
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => migrate(db, 0, version),
        onUpgrade: migrate,
        onDowngrade: (db, oldVersion, newVersion) async {
          throw StateError('This database needs a newer version of SpendWise.');
        },
      ),
    );
    return AppDatabase._(db);
  }

  /// Sqflite wraps creation/upgrades in a transaction. Append ordered migration
  /// steps here for future versions; never reset a database on an upgrade error.
  static Future<void> migrate(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (newVersion > schemaVersion || oldVersion > newVersion) {
      throw StateError('Unsupported database schema version.');
    }
    if (oldVersion < 1 && newVersion >= 1) {
      await db.execute('''CREATE TABLE categories (
        id INTEGER PRIMARY KEY, name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 100),
        type TEXT NOT NULL CHECK(type IN ('income','expense')),
        created_at TEXT NOT NULL, UNIQUE(id, type), UNIQUE(name, type))''');
      await db.execute(
        '''CREATE TABLE recurring_rules (
        id INTEGER PRIMARY KEY, category_id INTEGER NOT NULL,
        type TEXT NOT NULL DEFAULT 'expense' CHECK(type = 'expense'),
        amount_sen INTEGER NOT NULL CHECK(typeof(amount_sen) = 'integer' AND amount_sen BETWEEN 1 AND 999999999999),
        description TEXT NOT NULL DEFAULT '',
        frequency TEXT NOT NULL CHECK(frequency IN ('daily','weekly','monthly')),
        start_date TEXT NOT NULL, end_date TEXT, next_due_date TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        CHECK(end_date IS NULL OR end_date >= start_date),
        FOREIGN KEY(category_id, type) REFERENCES categories(id, type) ON DELETE RESTRICT ON UPDATE RESTRICT)''',
      );
      await db.execute(
        '''CREATE TABLE transactions (
        id INTEGER PRIMARY KEY, category_id INTEGER NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('income','expense')),
        amount_sen INTEGER NOT NULL CHECK(typeof(amount_sen) = 'integer' AND amount_sen BETWEEN 1 AND 999999999999),
        description TEXT NOT NULL DEFAULT '', transaction_date TEXT NOT NULL,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        recurring_rule_id INTEGER REFERENCES recurring_rules(id) ON DELETE RESTRICT,
        recurrence_occurrence_date TEXT,
        CHECK((recurring_rule_id IS NULL AND recurrence_occurrence_date IS NULL) OR
              (recurring_rule_id IS NOT NULL AND recurrence_occurrence_date IS NOT NULL)),
        UNIQUE(recurring_rule_id, recurrence_occurrence_date),
        FOREIGN KEY(category_id, type) REFERENCES categories(id, type) ON DELETE RESTRICT ON UPDATE RESTRICT)''',
      );
      await db.execute(
        'CREATE INDEX transactions_date ON transactions(transaction_date, id)',
      );
      await db.execute(
        'CREATE INDEX transactions_category ON transactions(category_id, type)',
      );
      await db.execute(
        'CREATE INDEX recurring_category ON recurring_rules(category_id, type)',
      );
      await db.execute(
        'CREATE INDEX recurring_due ON recurring_rules(is_active, next_due_date)',
      );
      const defaults = {
        'expense': [
          'Food & Drinks',
          'Transport',
          'Shopping',
          'Groceries',
          'Bills',
          'Entertainment',
          'Healthcare',
          'Education',
          'Other',
        ],
        'income': ['Salary', 'Allowance', 'Freelance', 'Gifts', 'Other'],
      };
      final now = DateTime.now().toUtc().toIso8601String();
      for (final entry in defaults.entries) {
        for (final name in entry.value) {
          await db.insert('categories', {
            'name': name,
            'type': entry.key,
            'created_at': now,
          });
        }
      }
    }
    if (oldVersion < 2 && newVersion >= 2) {
      await db.execute('''CREATE TABLE accounts (
        id INTEGER PRIMARY KEY, name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 100),
        kind TEXT NOT NULL CHECK(kind IN ('cash','bank','ewallet','other')),
        opening_sen INTEGER NOT NULL DEFAULT 0 CHECK(typeof(opening_sen) = 'integer' AND opening_sen BETWEEN -999999999999 AND 999999999999),
        created_at TEXT NOT NULL)''');
      await db.insert('accounts', {
        'id': 1,
        'name': 'Main ledger',
        'kind': 'other',
        'opening_sen': 0,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN account_id INTEGER REFERENCES accounts(id) ON DELETE RESTRICT',
      );
      await db.execute(
        'ALTER TABLE recurring_rules ADD COLUMN account_id INTEGER REFERENCES accounts(id) ON DELETE RESTRICT',
      );
      // SQLite cannot add a non-null REFERENCES default to populated tables.
      // Fill existing rows inside the migration transaction; triggers keep
      // legacy inserts assigned and prevent clearing an assigned account.
      for (final table in ['transactions', 'recurring_rules']) {
        await db.update(table, {'account_id': 1});
        await db.execute(
          'CREATE TRIGGER ${table}_default_account AFTER INSERT ON $table WHEN NEW.account_id IS NULL BEGIN UPDATE $table SET account_id = 1 WHERE id = NEW.id; END',
        );
        await db.execute(
          "CREATE TRIGGER ${table}_require_account BEFORE UPDATE OF account_id ON $table WHEN NEW.account_id IS NULL BEGIN SELECT RAISE(ABORT, 'Account is required'); END",
        );
      }
      await db.execute(
        'CREATE INDEX transactions_account ON transactions(account_id)',
      );
      await db.execute(
        'CREATE INDEX recurring_account ON recurring_rules(account_id)',
      );
      await db.execute('''CREATE TABLE transfers (
        id INTEGER PRIMARY KEY, from_account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
        to_account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
        amount_sen INTEGER NOT NULL CHECK(typeof(amount_sen) = 'integer' AND amount_sen BETWEEN 1 AND 999999999999),
        transaction_date TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL,
        CHECK(from_account_id != to_account_id))''');
      await db.execute(
        'CREATE INDEX transfers_date ON transfers(transaction_date, id)',
      );
    }
  }

  Future<void> close() => connection.close();
}
