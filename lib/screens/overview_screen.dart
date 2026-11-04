import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/finance_store.dart';
import 'recurring_screen.dart';
import 'accounts_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onTransactions,
    required this.onAnalytics,
  });
  final VoidCallback onTransactions, onAnalytics;
  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final totals = Totals(store.transactions, DateTime.now());
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        children: [
          Text(
            'Your money, at a glance',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'An overview of all your recorded finances',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Card(
            color: Theme.of(context).brightness == Brightness.dark
                ? scheme.primaryContainer
                : scheme.primary.withValues(alpha: .35),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        color: scheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Overall accounts',
                        style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.account_balance_outlined),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Current balance',
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      money(store.overallBalance),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Across all recorded transactions • All time',
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _AmountCard(
                  label: 'Total expenses',
                  value: totals.expense,
                  icon: Icons.north_east_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AmountCard(
                  label: 'Total income',
                  value: totals.income,
                  icon: Icons.south_west_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            'Your accounts',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          for (final account in store.accounts)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(20),
                leading: CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Icon(accountIcon(account['kind'] as String)),
                ),
                title: Text(account['name'] as String),
                subtitle: Text(accountKind(account['kind'] as String)),
                trailing: Text(
                  money(store.accountBalance(account['id'] as int)),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AccountEditor(account: account),
                  ),
                ),
              ),
            ),
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const AccountsScreen()),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Manage accounts and transfers'),
          ),
          const SizedBox(height: 28),
          Text(
            'Quick access',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: _Shortcut(
                      icon: Icons.receipt_long_outlined,
                      label: 'Transactions',
                      onTap: onTransactions,
                    ),
                  ),
                  Expanded(
                    child: _Shortcut(
                      icon: Icons.donut_large_outlined,
                      label: 'Analytics',
                      onTap: onAnalytics,
                    ),
                  ),
                  Expanded(
                    child: _Shortcut(
                      icon: Icons.repeat_rounded,
                      label: 'Recurring',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const RecurringScreen(),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _Shortcut(
                      icon: Icons.account_balance_outlined,
                      label: 'Accounts',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const AccountsScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Spending snapshot',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(onPressed: onAnalytics, child: const Text('View all')),
            ],
          ),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                for (final entry in {
                  'Today': totals.day,
                  'This week': totals.week,
                  'This month': totals.thisMonth,
                }.entries)
                  ListTile(
                    title: Text(entry.key),
                    trailing: Text(
                      money(entry.value),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onTransactions,
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('View detailed transactions'),
          ),
        ],
      ),
    );
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final int value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22),
          const SizedBox(height: 16),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              money(value),
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          Text('All time', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    ),
  );
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Column(
        children: [
          Icon(icon, size: 26),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    ),
  );
}
