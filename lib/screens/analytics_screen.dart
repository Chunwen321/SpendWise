import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/records.dart';
import '../providers/finance_store.dart';
import '../theme.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String period = 'Month';
  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = switch (period) {
      'Day' => today,
      'Week' => DateTime(
        today.year,
        today.month,
        today.day - today.weekday + 1,
      ),
      _ => DateTime(today.year, today.month),
    };
    final rows = store.transactions.where(
      (r) =>
          r.type == TransactionType.expense &&
          !r.date.isBefore(start) &&
          !r.date.isAfter(today),
    );
    final categories = <int, int>{};
    for (final row in rows) {
      categories.update(
        row.categoryId,
        (v) => v + row.amountSen,
        ifAbsent: () => row.amountSen,
      );
    }
    final total = categories.values.fold(0, (a, b) => a + b);
    final entries = categories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final colours = AppTheme.chartColours(context);
    final months = [
      for (var i = 5; i >= 0; i--) DateTime(today.year, today.month - i),
    ];
    final monthly = [
      for (final month in months)
        store.transactions
            .where(
              (r) =>
                  r.type == TransactionType.expense &&
                  r.date.year == month.year &&
                  r.date.month == month.month,
            )
            .fold(0, (sum, r) => sum + r.amountSen),
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SegmentedButton<String>(
          segments: [
            for (final p in ['Day', 'Week', 'Month'])
              ButtonSegment(value: p, label: Text(p)),
          ],
          selected: {period},
          onSelectionChanged: (v) => setState(() => period = v.single),
        ),
        const SizedBox(height: 16),
        Text(
          '$period spending: ${money(total)}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (total == 0)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text('No expenses for this period.'),
          )
        else ...[
          SizedBox(
            height: 240,
            child: Semantics(
              label: 'Spending breakdown by category. Detailed amounts below.',
              child: PieChart(
                PieChartData(
                  centerSpaceRadius: 48,
                  sections: [
                    for (var i = 0; i < entries.length; i++)
                      PieChartSectionData(
                        value: entries[i].value.toDouble(),
                        color: colours[i % colours.length],
                        radius: 45,
                        title: '',
                        showTitle: false,
                      ),
                  ],
                ),
              ),
            ),
          ),
          for (var i = 0; i < entries.length; i++)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: colours[i % colours.length],
                radius: 8,
              ),
              title: Text(store.categoryName(entries[i].key)),
              subtitle: Text(
                '${(entries[i].value / total * 100).toStringAsFixed(1)}%',
              ),
              trailing: Text(money(entries[i].value)),
            ),
        ],
        const SizedBox(height: 24),
        Text(
          'Monthly expense trend',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text('Last six calendar months • amounts in RM'),
        const SizedBox(height: 20),
        if (monthly.every((v) => v == 0))
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No monthly expenses yet.'),
          )
        else
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                barGroups: [
                  for (var i = 0; i < months.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: monthly[i] / 100,
                          color: Theme.of(context).colorScheme.primary,
                          width: 20,
                        ),
                      ],
                    ),
                ],
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, meta) =>
                          Text('${months[v.toInt().clamp(0, 5)].month}'),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        for (var i = 0; i < months.length; i++)
          ListTile(
            title: Text(
              '${months[i].year}-${months[i].month.toString().padLeft(2, '0')}',
            ),
            trailing: Text(money(monthly[i])),
          ),
      ],
    );
  }
}
