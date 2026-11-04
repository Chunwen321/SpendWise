import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/records.dart';
import '../providers/finance_store.dart';
import 'main_shell.dart';

class TransactionEditor extends StatefulWidget {
  const TransactionEditor({super.key, this.existing});
  final FinancialTransaction? existing;
  @override
  State<TransactionEditor> createState() => _TransactionEditorState();
}

class _TransactionEditorState extends State<TransactionEditor> {
  final form = GlobalKey<FormState>();
  late final amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : '${widget.existing!.amountSen ~/ 100}.${(widget.existing!.amountSen % 100).toString().padLeft(2, '0')}',
  );
  late final description = TextEditingController(
    text: widget.existing?.description,
  );
  late TransactionType type = widget.existing?.type ?? TransactionType.expense;
  late DateTime date = widget.existing?.date ?? DateTime.now();
  late int? category = widget.existing?.categoryId;
  late int? account = widget.existing?.accountId;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    amount.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate() || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    final store = context.read<FinanceStore>();
    try {
      final id = widget.existing?.id;
      if (id == null) {
        await store.repository.createTransaction(
          accountId: account ?? store.accounts.first['id'] as int,
          categoryId: category!,
          type: type,
          amountSen: parseRinggit(amount.text),
          date: date,
          description: description.text,
        );
      } else {
        await store.repository.updateTransaction(
          accountId: account ?? store.accounts.first['id'] as int,
          id: id,
          categoryId: category!,
          type: type,
          amountSen: parseRinggit(amount.text),
          date: date,
          description: description.text,
        );
      }
      await store.refresh();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Could not save. Check the category and try again.';
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = context
        .watch<FinanceStore>()
        .categories
        .where((c) => c.type == type)
        .toList();
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (widget.existing != null)
            IconButton(
              tooltip: 'Delete transaction',
              icon: const Icon(Icons.delete_outline),
              onPressed: saving
                  ? null
                  : () async {
                      final store = context.read<FinanceStore>();
                      if (!await confirm(
                        context,
                        'Delete transaction?',
                        'This permanently removes the transaction from your records.',
                      )) {
                        return;
                      }
                      try {
                        await store.repository.deleteTransaction(
                          widget.existing!.id,
                        );
                        await store.refresh();
                        if (context.mounted) Navigator.pop(context);
                      } catch (_) {
                        if (context.mounted) {
                          message(context, 'Could not delete transaction.');
                        }
                      }
                    },
            ),
        ],
        title: Text(
          widget.existing == null ? 'Add transaction' : 'Edit transaction',
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
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Account'),
              items: [
                for (final a in context.read<FinanceStore>().accounts)
                  DropdownMenuItem(
                    value: a['id'] as int,
                    child: Text(a['name'] as String),
                  ),
              ],
              onChanged: saving ? null : (v) => setState(() => account = v),
              validator: (v) => v == null ? 'Choose an account.' : null,
            ),
            const SizedBox(height: 16),
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Expense'),
                ),
                ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Income'),
                ),
              ],
              selected: {type},
              onSelectionChanged: saving
                  ? null
                  : (v) => setState(() {
                      type = v.single;
                      category = null;
                    }),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: amount,
              decoration: const InputDecoration(labelText: 'Amount (RM)'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) {
                try {
                  parseRinggit(v ?? '');
                  return null;
                } catch (_) {
                  return 'Enter a positive amount with up to two decimals.';
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              key: ValueKey('$type-$category'),
              initialValue: category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final c in categories)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: saving ? null : (v) => setState(() => category = v),
              validator: (v) => v == null ? 'Choose a category.' : null,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(calendarDate(date)),
              trailing: const Icon(Icons.calendar_month),
              onTap: saving
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => date = picked);
                    },
            ),
            TextFormField(
              controller: description,
              maxLength: 1000,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            FilledButton(
              onPressed: saving ? null : save,
              child: Text(saving ? 'Saving…' : 'Save transaction'),
            ),
          ],
        ),
      ),
    );
  }
}
