import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/records.dart';
import '../providers/finance_store.dart';
import '../services/recurrence_service.dart';
import 'main_shell.dart';

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});
  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  late final service = RecurrenceService(
    context.read<FinanceStore>().repository.database,
  );
  late Future<List<Map<String, Object?>>> rows = service.rules();
  void reload() {
    setState(() => rows = service.rules());
  }

  Future<void> edit([Map<String, Object?>? rule]) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RecurringEditor(service: service, rule: rule),
      ),
    );
    if (mounted) reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recurring expenses')),
    floatingActionButton: FloatingActionButton(
      onPressed: edit,
      child: const Icon(Icons.add),
    ),
    body: FutureBuilder(
      future: rows,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: FilledButton(
              onPressed: reload,
              child: const Text('Could not load. Retry'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rules = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Generated on opening or resuming SpendWise. Monthly rules use the last day of shorter months, then return to their original day. Paused rules catch up when resumed. Cancel stops future generation and keeps recorded transactions.',
            ),
            if (rules.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No recurring expenses yet.'),
              ),
            for (final r in rules)
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: Text(
                        '${context.read<FinanceStore>().categoryName(r['category_id'] as int)} • ${money(r['amount_sen'] as int)}',
                      ),
                      subtitle: Text(
                        '${r['frequency']} • Next: ${r['next_due_date']}\n${r['description']}',
                      ),
                      onTap: () => edit(r),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () async {
                            try {
                              await service.setActive(
                                r['id'] as int,
                                r['is_active'] == 0,
                              );
                              await service.generate(DateTime.now());
                              if (!context.mounted) return;
                              await context.read<FinanceStore>().refresh();
                              if (mounted) reload();
                            } catch (_) {
                              if (context.mounted) {
                                message(context, 'Could not update rule.');
                              }
                            }
                          },
                          child: Text(r['is_active'] == 1 ? 'Pause' : 'Resume'),
                        ),
                        TextButton(
                          onPressed: () async {
                            if (await confirm(
                              context,
                              'Cancel recurring expense?',
                              'Recorded transactions will stay saved.',
                            )) {
                              await service.setActive(r['id'] as int, false);
                              reload();
                            }
                          },
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 90),
          ],
        );
      },
    ),
  );
}

class RecurringEditor extends StatefulWidget {
  const RecurringEditor({super.key, required this.service, this.rule});
  final RecurrenceService service;
  final Map<String, Object?>? rule;
  @override
  State<RecurringEditor> createState() => _RecurringEditorState();
}

class _RecurringEditorState extends State<RecurringEditor> {
  final form = GlobalKey<FormState>();
  late final amount = TextEditingController(
    text: widget.rule == null
        ? ''
        : ((widget.rule!['amount_sen'] as int) / 100).toStringAsFixed(2),
  );
  late final description = TextEditingController(
    text: widget.rule?['description'] as String?,
  );
  late int? category = widget.rule?['category_id'] as int?;
  late int? account = widget.rule?['account_id'] as int?;
  late String frequency = widget.rule?['frequency'] as String? ?? 'monthly';
  late DateTime start = widget.rule == null
      ? DateTime.now()
      : DateTime.parse(widget.rule!['start_date'] as String);
  late DateTime? end = widget.rule?['end_date'] == null
      ? null
      : DateTime.parse(widget.rule!['end_date'] as String);
  bool busy = false;
  @override
  void dispose() {
    amount.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.rule == null
            ? 'Add recurring expense'
            : 'Edit recurring expense',
      ),
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField<int>(
            initialValue:
                account ??
                context.read<FinanceStore>().accounts.firstOrNull?['id']
                    as int?,
            decoration: const InputDecoration(labelText: 'Account'),
            items: [
              for (final a in context.read<FinanceStore>().accounts)
                DropdownMenuItem(
                  value: a['id'] as int,
                  child: Text(a['name'] as String),
                ),
            ],
            onChanged: (v) => setState(() => account = v),
            validator: (v) => v == null ? 'Choose an account.' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount (RM)'),
            validator: (v) {
              try {
                parseRinggit(v ?? '');
                return null;
              } catch (_) {
                return 'Enter a positive RM amount.';
              }
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Expense category'),
            items: [
              for (final c in context.read<FinanceStore>().categories.where(
                (c) => c.type == TransactionType.expense,
              ))
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => category = v,
            validator: (v) => v == null ? 'Choose a category.' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: frequency,
            decoration: const InputDecoration(labelText: 'Frequency'),
            items: [
              for (final f in ['daily', 'weekly', 'monthly'])
                DropdownMenuItem(value: f, child: Text(f)),
            ],
            onChanged: (v) => setState(() => frequency = v!),
          ),
          ListTile(
            title: const Text('Start date'),
            subtitle: Text(calendarDate(start)),
            onTap: () async {
              final v = await showDatePicker(
                context: context,
                initialDate: start,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (v != null) setState(() => start = v);
            },
          ),
          ListTile(
            title: const Text('End date (optional)'),
            subtitle: Text(end == null ? 'No end date' : calendarDate(end!)),
            trailing: end == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => end = null),
                  ),
            onTap: () async {
              final v = await showDatePicker(
                context: context,
                initialDate: end ?? start,
                firstDate: start,
                lastDate: DateTime(2100),
              );
              if (v != null) setState(() => end = v);
            },
          ),
          TextFormField(
            controller: description,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          if (widget.rule != null)
            const Text(
              'Edits preserve recorded transactions. A changed schedule begins today or later; it does not backfill earlier dates.',
            ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    setState(() => busy = true);
                    try {
                      await widget.service.save(
                        accountId:
                            account ??
                            context.read<FinanceStore>().accounts.first['id']
                                as int,
                        id: widget.rule?['id'] as int?,
                        categoryId: category!,
                        amountSen: parseRinggit(amount.text),
                        description: description.text,
                        frequency: frequency,
                        start: start,
                        end: end,
                      );
                      await widget.service.generate(DateTime.now());
                      if (context.mounted) {
                        await context.read<FinanceStore>().refresh();
                      }
                      if (context.mounted) Navigator.pop(context);
                    } catch (_) {
                      if (context.mounted) {
                        message(
                          context,
                          'Could not save recurring expense. Check the dates.',
                        );
                        setState(() => busy = false);
                      }
                    }
                  },
            child: const Text('Save recurring expense'),
          ),
        ],
      ),
    ),
  );
}
