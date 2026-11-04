import '../database/app_database.dart';
import '../models/records.dart';

DateTime nextOccurrence(DateTime current, String frequency, int anchorDay) {
  return switch (frequency) {
    'daily' => DateTime(current.year, current.month, current.day + 1),
    'weekly' => DateTime(current.year, current.month, current.day + 7),
    'monthly' => DateTime(
      current.year,
      current.month + 1,
      anchorDay.clamp(1, DateTime(current.year, current.month + 2, 0).day),
    ),
    _ => throw ArgumentError('Invalid frequency'),
  };
}

class RecurrenceService {
  RecurrenceService(this.database);
  final AppDatabase database;
  Future<int> generate(DateTime now) =>
      database.connection.transaction((txn) async {
        final today = calendarDate(now);
        var generated = 0;
        final rules = await txn.query(
          'recurring_rules',
          where: 'is_active = 1 AND next_due_date <= ?',
          whereArgs: [today],
        );
        for (final rule in rules) {
          var due = DateTime.parse(rule['next_due_date'] as String);
          final anchor = DateTime.parse(rule['start_date'] as String).day;
          final end = rule['end_date'] as String?;
          while (calendarDate(due).compareTo(today) <= 0 &&
              (end == null || calendarDate(due).compareTo(end) <= 0)) {
            final timestamp = DateTime.now().toUtc().toIso8601String();
            await txn.rawInsert(
              '''INSERT OR IGNORE INTO transactions
          (category_id, type, amount_sen, description, transaction_date, created_at, updated_at, recurring_rule_id, recurrence_occurrence_date, account_id)
          VALUES (?, 'expense', ?, ?, ?, ?, ?, ?, ?, ?)''',
              [
                rule['category_id'],
                rule['amount_sen'],
                rule['description'],
                calendarDate(due),
                timestamp,
                timestamp,
                rule['id'],
                calendarDate(due),
                rule['account_id'],
              ],
            );
            if ((await txn.rawQuery('SELECT changes() AS count'))
                    .single['count'] ==
                1) {
              generated++;
            }
            due = nextOccurrence(due, rule['frequency'] as String, anchor);
          }
          await txn.update(
            'recurring_rules',
            {
              'next_due_date': calendarDate(due),
              'is_active': end != null && calendarDate(due).compareTo(end) > 0
                  ? 0
                  : 1,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [rule['id']],
          );
        }
        return generated;
      });

  Future<List<Map<String, Object?>>> rules() => database.connection.query(
    'recurring_rules',
    orderBy: 'next_due_date, id',
  );

  Future<void> save({
    int? accountId,
    int? id,
    required int categoryId,
    required int amountSen,
    required String description,
    required String frequency,
    required DateTime start,
    DateTime? end,
  }) async {
    if (amountSen < 1 ||
        amountSen > maxAmountSen ||
        !['daily', 'weekly', 'monthly'].contains(frequency) ||
        (end != null && calendarDate(end).compareTo(calendarDate(start)) < 0)) {
      throw ArgumentError('Invalid recurring expense.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await database.connection.transaction((txn) async {
      final values = <String, Object?>{
        'account_id': ?accountId,
        'category_id': categoryId,
        'amount_sen': amountSen,
        'description': description.trim(),
        'frequency': frequency,
        'start_date': calendarDate(start),
        'end_date': end == null ? null : calendarDate(end),
        'updated_at': now,
      };
      if (id == null) {
        values.addAll({
          'next_due_date': calendarDate(start),
          'is_active': 1,
          'created_at': now,
        });
        await txn.insert('recurring_rules', values);
      } else {
        // Preserve progress. Changes affect only occurrences not yet generated.
        final old = (await txn.query(
          'recurring_rules',
          where: 'id = ?',
          whereArgs: [id],
        )).single;
        if (old['start_date'] != calendarDate(start) ||
            old['frequency'] != frequency) {
          // A schedule edit starts today or later; recorded occurrences remain
          // unchanged and the unique rule/date constraint prevents duplicates.
          final today = DateTime.now();
          var next = DateTime(start.year, start.month, start.day);
          while (calendarDate(next).compareTo(calendarDate(today)) < 0) {
            next = nextOccurrence(next, frequency, start.day);
          }
          values['next_due_date'] = calendarDate(next);
        }
        await txn.update(
          'recurring_rules',
          values,
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
  }

  Future<void> setActive(int id, bool active) => database.connection.update(
    'recurring_rules',
    {
      'is_active': active ? 1 : 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    },
    where: 'id = ?',
    whereArgs: [id],
  );
}
