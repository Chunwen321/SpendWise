import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/records.dart';
import '../providers/finance_store.dart';
import 'main_shell.dart';

String accountKind(String kind) => switch (kind) {
  'cash' => 'Cash',
  'bank' => 'Bank account',
  'ewallet' => 'E-wallet',
  _ => 'Other',
};
IconData accountIcon(String kind) => switch (kind) {
  'cash' => Icons.payments_outlined,
  'bank' => Icons.account_balance_outlined,
  'ewallet' => Icons.account_balance_wallet_outlined,
  _ => Icons.wallet_outlined,
};

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            tooltip: 'Transfer between accounts',
            onPressed: store.accounts.length < 2
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AccountEditor(transfer: true),
                    ),
                  ),
            icon: const Icon(Icons.swap_horiz),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const AccountEditor()),
        ),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          const Text(
            'Opening balances plus recorded income, expenses and transfers. Transfers do not count as spending or income.',
          ),
          const SizedBox(height: 16),
          for (final account in store.accounts)
            Card(
              elevation: 0,
              child: ListTile(
                leading: Icon(accountIcon(account['kind'] as String)),
                title: Text(account['name'] as String),
                subtitle: Text(accountKind(account['kind'] as String)),
                trailing: Text(
                  money(store.accountBalance(account['id'] as int)),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AccountEditor(account: account),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AccountEditor extends StatefulWidget {
  const AccountEditor({super.key, this.account, this.transfer = false});
  final Map<String, Object?>? account;
  final bool transfer;
  @override
  State<AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<AccountEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.account?['name'] as String?,
  );
  late final amount = TextEditingController(
    text: widget.transfer
        ? ''
        : widget.account == null
        ? '0'
        : _decimal(widget.account!['opening_sen'] as int),
  );
  late String kind = widget.account?['kind'] as String? ?? 'cash';
  int? from, to;
  DateTime date = DateTime.now();
  bool busy = false;
  String _decimal(int value) =>
      '${value < 0 ? '-' : ''}${value.abs() ~/ 100}.${(value.abs() % 100).toString().padLeft(2, '0')}';
  int opening(String value) {
    final text = value.trim();
    if (RegExp(r'^-?0+(\.0{1,2})?$').hasMatch(text)) return 0;
    return text.startsWith('-')
        ? -parseRinggit(text.substring(1))
        : parseRinggit(text);
  }

  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.transfer
              ? 'Transfer between accounts'
              : widget.account == null
              ? 'Add account'
              : 'Edit account',
        ),
        actions: [
          if (widget.account != null)
            IconButton(
              tooltip: 'Delete account',
              icon: const Icon(Icons.delete_outline),
              onPressed: busy
                  ? null
                  : () async {
                      if (!await confirm(
                        context,
                        'Delete account?',
                        'Only unused accounts can be deleted. Transactions and transfers are preserved.',
                      )) {
                        return;
                      }
                      try {
                        await store.repository.deleteAccount(
                          widget.account!['id'] as int,
                        );
                        await store.refresh();
                        if (context.mounted) Navigator.pop(context);
                      } catch (_) {
                        if (context.mounted) {
                          message(
                            context,
                            'Account is in use, or is the last account. Keep it or reassign its transactions first.',
                          );
                        }
                      }
                    },
            ),
        ],
      ),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.transfer) ...[
              for (final source in [true, false])
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: DropdownButtonFormField<int>(
                    decoration: InputDecoration(
                      labelText: source ? 'From account' : 'To account',
                    ),
                    items: [
                      for (final a in store.accounts)
                        DropdownMenuItem(
                          value: a['id'] as int,
                          child: Text(a['name'] as String),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      if (source) {
                        from = v;
                      } else {
                        to = v;
                      }
                    }),
                    validator: (v) => v == null
                        ? 'Choose an account.'
                        : from == to
                        ? 'Choose different accounts.'
                        : null,
                  ),
                ),
            ] else ...[
              TextFormField(
                controller: name,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Account name'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter a name.' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Account type'),
                items: [
                  for (final k in ['cash', 'bank', 'ewallet', 'other'])
                    DropdownMenuItem(value: k, child: Text(accountKind(k))),
                ],
                onChanged: (v) => setState(() => kind = v!),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(
                labelText: widget.transfer
                    ? 'Transfer amount (RM)'
                    : 'Opening balance (RM)',
              ),
              validator: (v) {
                try {
                  if (widget.transfer) {
                    parseRinggit(v ?? '');
                  } else {
                    opening(v ?? '');
                  }
                  return null;
                } catch (_) {
                  return 'Enter a valid amount with up to two decimals.';
                }
              },
            ),
            const SizedBox(height: 16),
            if (widget.transfer)
              ListTile(
                title: const Text('Date'),
                subtitle: Text(calendarDate(date)),
                onTap: () async {
                  final v = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
                  );
                  if (v != null) setState(() => date = v);
                },
              )
            else
              const Text(
                'Use the balance before the transactions you will record here. Changing it adjusts this account’s balance without creating income or expenses.',
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      setState(() => busy = true);
                      try {
                        if (widget.transfer) {
                          await store.repository.transfer(
                            from: from!,
                            to: to!,
                            amountSen: parseRinggit(amount.text),
                            date: date,
                          );
                        } else {
                          await store.repository.saveAccount(
                            id: widget.account?['id'] as int?,
                            name: name.text,
                            kind: kind,
                            openingSen: opening(amount.text),
                          );
                        }
                        await store.refresh();
                        if (context.mounted) Navigator.pop(context);
                      } catch (_) {
                        if (context.mounted) {
                          message(
                            context,
                            'Could not save. Check the accounts and try again.',
                          );
                          setState(() => busy = false);
                        }
                      }
                    },
              child: Text(busy ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
