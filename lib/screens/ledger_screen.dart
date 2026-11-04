import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/records.dart';
import '../providers/finance_store.dart';
import 'main_shell.dart';

const monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
String ledgerDay(DateTime date) =>
    '${monthNames[date.month - 1].substring(0, 3)} ${date.day}, ${date.year} · ${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][date.weekday - 1]}';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String query = '';
  TransactionType? type;
  int? category;
  DateTimeRange? range;
  bool oldest = false;
  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final start = range?.start ?? month;
    final end = range?.end ?? DateTime(month.year, month.month + 1, 0);
    final period = store.transactions
        .where((r) => !r.date.isBefore(start) && !r.date.isAfter(end))
        .toList();
    final income = period
        .where((r) => r.type == TransactionType.income)
        .fold(0, (sum, r) => sum + r.amountSen);
    final expenses = period
        .where((r) => r.type == TransactionType.expense)
        .fold(0, (sum, r) => sum + r.amountSen);
    final rows = period
        .where(
          (r) =>
              (type == null || type == r.type) &&
              (category == null || category == r.categoryId) &&
              '${r.description} ${store.categoryName(r.categoryId)}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
        )
        .toList();
    rows.sort((a, b) {
      final value = a.date.compareTo(b.date);
      final result = value == 0 ? a.id.compareTo(b.id) : value;
      return oldest ? result : -result;
    });
    final groups = <String, List<FinancialTransaction>>{};
    for (final row in rows) {
      groups.putIfAbsent(calendarDate(row.date), () => []).add(row);
    }
    final transfers = store.transfers
        .where(
          (r) =>
              type == null &&
              category == null &&
              (r['transaction_date'] as String).compareTo(
                    calendarDate(start),
                  ) >=
                  0 &&
              (r['transaction_date'] as String).compareTo(calendarDate(end)) <=
                  0 &&
              'transfer ${store.accountName(r['from_account_id'] as int)} ${store.accountName(r['to_account_id'] as int)} ${r['description']}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
        )
        .toList();
    final transferGroups = <String, List<Map<String, Object?>>>{};
    for (final row in transfers) {
      transferGroups
          .putIfAbsent(row['transaction_date'] as String, () => [])
          .add(row);
    }
    final days = {...groups.keys, ...transferGroups.keys}.toList()
      ..sort((a, b) => oldest ? a.compareTo(b) : b.compareTo(a));
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: () => setState(() {
                  month = DateTime(month.year, month.month - 1);
                  range = null;
                }),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: month,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2100),
                    );
                    if (date != null) {
                      setState(() {
                        month = DateTime(date.year, date.month);
                        range = null;
                      });
                    }
                  },
                  child: Text(
                    range == null
                        ? '${monthNames[month.month - 1]} ${month.year}'
                        : 'Custom date range',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: () => setState(() {
                  month = DateTime(month.year, month.month + 1);
                  range = null;
                }),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
              child: Row(
                children: [
                  for (final item in {
                    'Expenses': expenses,
                    'Income': income,
                    'Balance': income - expenses,
                  }.entries)
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            item.key,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              money(item.value),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search description or category',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Filters and sorting'),
            leading: const Icon(Icons.tune),
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<TransactionType>(
                      initialValue: type,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('All types')),
                        DropdownMenuItem(
                          value: TransactionType.income,
                          child: Text('Income'),
                        ),
                        DropdownMenuItem(
                          value: TransactionType.expense,
                          child: Text('Expense'),
                        ),
                      ],
                      onChanged: (v) => setState(() => type = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      key: ValueKey(category),
                      initialValue:
                          store.categories.any((c) => c.id == category)
                          ? category
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All categories'),
                        ),
                        for (final c in store.categories)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(
                              '${c.name} (${c.type.name})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => category = v),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.date_range),
                    label: const Text('Date range'),
                    onPressed: () async {
                      final value = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2100),
                        initialDateRange: range,
                      );
                      if (value != null) setState(() => range = value);
                    },
                  ),
                  if (range != null)
                    TextButton(
                      onPressed: () => setState(() => range = null),
                      child: const Text('Clear dates'),
                    ),
                  FilterChip(
                    label: Text(oldest ? 'Oldest first' : 'Newest first'),
                    selected: oldest,
                    onSelected: (v) => setState(() => oldest = v),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (days.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No matching transactions.')),
            ),
          for (final day in days) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ledgerDay(DateTime.parse(day)),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  Text(
                    money(
                      (groups[day] ?? []).fold(
                        0,
                        (sum, r) =>
                            sum +
                            (r.type == TransactionType.income
                                ? r.amountSen
                                : -r.amountSen),
                      ),
                    ),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            ),
            Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  for (final row
                      in groups[day] ?? <FinancialTransaction>[]) ...[
                    TransactionTile(row: row, grouped: true),
                    const Divider(height: 1, indent: 76),
                  ],
                  for (final row
                      in transferGroups[day] ?? <Map<String, Object?>>[])
                    ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.swap_horiz),
                      ),
                      title: const Text('Transfer'),
                      subtitle: Text(
                        '${store.accountName(row['from_account_id'] as int)} → ${store.accountName(row['to_account_id'] as int)}',
                      ),
                      trailing: Text(money(row['amount_sen'] as int)),
                      onTap: () async {
                        final store = context.read<FinanceStore>();
                        if (await confirm(
                          context,
                          'Delete transfer?',
                          'This reverses the transfer in both account balances.',
                        )) {
                          try {
                            await store.repository.deleteTransfer(
                              row['id'] as int,
                            );
                            await store.refresh();
                          } catch (_) {
                            if (context.mounted) {
                              message(context, 'Could not delete transfer.');
                            }
                          }
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
          if (rows.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Text(
                'Tap a transaction for details or hold to delete.',
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
