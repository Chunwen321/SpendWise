enum TransactionType { income, expense }

String calendarDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.type,
    required this.createdAt,
  });
  final int id;
  final String name;
  final TransactionType type;
  final String createdAt;

  factory Category.fromMap(Map<String, Object?> row) => Category(
    id: row['id'] as int,
    name: row['name'] as String,
    type: TransactionType.values.byName(row['type'] as String),
    createdAt: row['created_at'] as String,
  );
}

class FinancialTransaction {
  const FinancialTransaction({
    required this.id,
    required this.categoryId,
    required this.type,
    required this.amountSen,
    required this.description,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
    this.recurringRuleId,
    this.recurrenceOccurrenceDate,
    this.accountId = 1,
  });
  final int id;
  final int categoryId;
  final int accountId;
  final TransactionType type;
  final int amountSen;
  final String description;
  final DateTime date;
  final String createdAt;
  final String updatedAt;
  final int? recurringRuleId;
  final String? recurrenceOccurrenceDate;

  factory FinancialTransaction.fromMap(Map<String, Object?> row) =>
      FinancialTransaction(
        id: row['id'] as int,
        categoryId: row['category_id'] as int,
        accountId: row['account_id'] as int? ?? 1,
        type: TransactionType.values.byName(row['type'] as String),
        amountSen: row['amount_sen'] as int,
        description: row['description'] as String,
        date: DateTime.parse(row['transaction_date'] as String),
        createdAt: row['created_at'] as String,
        updatedAt: row['updated_at'] as String,
        recurringRuleId: row['recurring_rule_id'] as int?,
        recurrenceOccurrenceDate: row['recurrence_occurrence_date'] as String?,
      );
}

/// Parse RM without floating point rounding; amounts must be positive.
int parseRinggit(String input) {
  final value = input.trim();
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) {
    throw const FormatException(
      'Enter a positive amount with at most two decimals.',
    );
  }
  final parts = value.split('.');
  final sen =
      BigInt.parse(parts[0]) * BigInt.from(100) +
      BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
  if (sen <= BigInt.zero || sen > BigInt.from(maxAmountSen)) {
    throw const FormatException('Amount is outside the supported range.');
  }
  return sen.toInt();
}

// Keeps sums practical and individual amounts within exact integer ranges.
const maxAmountSen = 999999999999;
