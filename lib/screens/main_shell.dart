import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/records.dart';
import '../providers/finance_store.dart';
import '../theme.dart';
import 'transaction_editor.dart';
import 'overview_screen.dart';
import 'ledger_screen.dart';
import 'accounts_screen.dart';
import 'analytics_screen.dart';
import 'recurring_screen.dart';
import 'backup_screen.dart';
import 'security.dart';
import '../services/app_lock_service.dart';

Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ??
    false;
void message(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.preferences, this.lock});
  final AppearancePreferences preferences;
  final AppLockService? lock;
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int index = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<FinanceStore>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          ['Overview', 'Transactions', 'Analytics', 'Settings'][index],
        ),
        centerTitle: false,
        actions: [
          if (index == 0)
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => setState(() => index = 3),
            ),
        ],
      ),
      body: store.loading
          ? const Center(child: CircularProgressIndicator())
          : store.error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(store.error!),
                  FilledButton(
                    onPressed: store.refresh,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : IndexedStack(
              index: index,
              children: [
                HomeScreen(
                  onTransactions: () => setState(() => index = 1),
                  onAnalytics: () => setState(() => index = 2),
                ),
                const HistoryScreen(),
                const AnalyticsScreen(),
                ListView(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.account_balance_wallet_outlined,
                      ),
                      title: const Text('Manage accounts'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const AccountsScreen(),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.palette_outlined),
                      title: const Text('Appearance'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              SettingsScreen(preferences: widget.preferences),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.category_outlined),
                      title: const Text('Manage categories'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const CategoriesScreen(),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.repeat),
                      title: const Text('Manage recurring expenses'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const RecurringScreen(),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.backup_outlined),
                      title: const Text('Backup and restore'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const BackupScreen(),
                        ),
                      ),
                    ),
                    if (widget.lock != null)
                      ListTile(
                        leading: const Icon(Icons.lock_outline),
                        title: const Text('App lock'),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                SecuritySettings(service: widget.lock!),
                          ),
                        ),
                      ),
                    const AboutListTile(
                      applicationName: 'SpendWise',
                      applicationVersion: '1.1.0',
                      applicationLegalese: 'Offline personal expense tracker. Amounts in Malaysian Ringgit.',
                    ),
                  ],
                ),
              ],
            ),
      floatingActionButton: index < 2 && !store.loading
          ? FloatingActionButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const TransactionEditor(),
                ),
              ),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (v) => setState(() => index = v),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                label: 'Transactions',
              ),
              NavigationDestination(
                icon: Icon(Icons.bar_chart),
                label: 'Analytics',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.row, this.grouped = false});
  final FinancialTransaction row;
  final bool grouped;
  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final name = store.categoryName(row.categoryId);
    final lower = name.toLowerCase();
    final icon = lower.contains('food')
        ? Icons.restaurant
        : lower.contains('transport')
        ? Icons.directions_car_outlined
        : lower.contains('shopping')
        ? Icons.shopping_bag_outlined
        : lower.contains('grocer')
        ? Icons.local_grocery_store_outlined
        : lower.contains('health')
        ? Icons.favorite_border
        : lower.contains('bill')
        ? Icons.receipt_outlined
        : row.type == TransactionType.income
        ? Icons.south_west
        : Icons.north_east;
    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        child: Icon(icon),
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        grouped
            ? '${store.accountName(row.accountId)}${row.description.isEmpty ? '' : '\n${row.description}'}'
            : '${calendarDate(row.date)}${row.description.isEmpty ? '' : '\n${row.description}'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: row.description.isNotEmpty,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${row.type == TransactionType.income ? '+' : '-'}${money(row.amountSen)}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: row.type == TransactionType.expense
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.tertiary,
            ),
          ),
          Text(row.type.name, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => TransactionEditor(existing: row),
        ),
      ),
      onLongPress: () async {
        if (await confirm(
          context,
          'Delete transaction?',
          'This permanently removes ${money(row.amountSen)} from your records.',
        )) {
          try {
            await store.repository.deleteTransaction(row.id);
            await store.refresh();
          } catch (_) {
            if (context.mounted) {
              message(context, 'Could not delete transaction.');
            }
          }
        }
      },
    );
    return grouped ? tile : Card(child: tile);
  }
}

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});
  Future<void> reassign(BuildContext context, Category source) async {
    final store = context.read<FinanceStore>();
    final choices = store.categories
        .where((c) => c.id != source.id && c.type == source.type)
        .toList();
    if (choices.isEmpty) {
      message(
        context,
        'Create another ${source.type.name} category before reassigning records.',
      );
      return;
    }
    int? replacement;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Reassign and delete category?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Move all transactions and recurring rules from ${source.name} to:',
              ),
              DropdownButton<int>(
                isExpanded: true,
                value: replacement,
                hint: const Text('Choose replacement'),
                items: [
                  for (final c in choices)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => replacement = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: replacement == null
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Reassign and delete'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      try {
        await store.repository.reassignAndDeleteCategory(
          source.id,
          replacement!,
        );
        await store.refresh();
      } catch (_) {
        if (context.mounted) {
          message(
            context,
            'Could not reassign. Existing records were preserved.',
          );
        }
      }
    }
  }

  Future<void> edit(BuildContext context, Category? existing) async {
    final store = context.read<FinanceStore>();
    final text = TextEditingController(text: existing?.name);
    var type = existing?.type ?? TransactionType.expense;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? 'Add category' : 'Rename category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: text,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              if (existing == null)
                DropdownButton<TransactionType>(
                  value: type,
                  items: [
                    for (final v in TransactionType.values)
                      DropdownMenuItem(value: v, child: Text(v.name)),
                  ],
                  onChanged: (v) => setState(() => type = v!),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (text.text.trim().isNotEmpty) Navigator.pop(context, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final name = text.text; // Dispose after the closing dialog animation.
    if (accepted == true) {
      try {
        if (existing == null) {
          await store.repository.createCategory(name, type);
        } else {
          await store.repository.renameCategory(existing.id, name);
        }
        await store.refresh();
      } catch (_) {
        if (context.mounted) {
          message(
            context,
            'Could not save category. Use a unique, non-empty name.',
          );
        }
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    text.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => edit(context, null),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          for (final c in store.categories)
            ListTile(
              title: Text(c.name),
              subtitle: Text(c.type.name),
              onTap: () => edit(context, c),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirm(
                    context,
                    'Delete category?',
                    'Referenced categories cannot be deleted.',
                  )) {
                    try {
                      await store.repository.deleteCategory(c.id);
                      await store.refresh();
                    } catch (_) {
                      if (context.mounted) {
                        await reassign(context, c);
                      }
                    }
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
