import 'package:flutter_test/flutter_test.dart';
import 'package:medibro_update/data/models/summary_model.dart';

void main() {
  group('SummaryMetrics Unit Tests', () {
    test('SummaryMetrics.empty() creates valid default structures', () {
      final metrics = SummaryMetrics.empty();

      expect(metrics.todaySales, 0.0);
      expect(metrics.todayRevenue, 0.0);
      expect(metrics.todayCustomers, 0);
      expect(metrics.avgSpendPerCustomer, 0.0);

      expect(metrics.weeklySales.length, 7);
      expect(metrics.weeklyRevenue.length, 7);
      expect(metrics.weeklyCustomers.length, 7);
      expect(metrics.weekDayLabels.length, 7);

      expect(metrics.monthlySales.length, 4);
      expect(metrics.monthlyRevenue.length, 4);
      expect(metrics.monthlyCustomers.length, 4);
      expect(metrics.weekLabels.length, 4);
    });

    test('Profit calculation: lineTotal - (purchasePrice * quantity)', () {
      const quantity = 3;
      const unitPrice = 100.0;
      const purchasePrice = 70.0;
      const lineTotal = quantity * unitPrice; // 300.0

      final profit = lineTotal - (purchasePrice * quantity); // 300 - 210 = 90.0
      expect(profit, 90.0);
    });

    test('Weekly day index mapping (today is index 6, 6 days ago is index 0)', () {
      final weeklySales = List.filled(7, 0.0);

      for (int daysAgo = 0; daysAgo < 7; daysAgo++) {
        final idx = 6 - daysAgo;
        weeklySales[idx] = (daysAgo + 1) * 100.0;
      }

      expect(weeklySales[6], 100.0); // Today (daysAgo = 0)
      expect(weeklySales[0], 700.0); // 6 days ago (daysAgo = 6)
    });

    test('Monthly week bucket calculation: daysAgo ~/ 7', () {
      final monthlySales = List.filled(4, 0.0);

      // Day 3 -> Week 0 (last 7 days)
      monthlySales[3 ~/ 7] += 500.0;
      // Day 10 -> Week 1 (8-14 days ago)
      monthlySales[10 ~/ 7] += 800.0;
      // Day 20 -> Week 2 (15-21 days ago)
      monthlySales[20 ~/ 7] += 1200.0;
      // Day 27 -> Week 3 (22-28 days ago)
      monthlySales[27 ~/ 7] += 1500.0;

      expect(monthlySales[0], 500.0);
      expect(monthlySales[1], 800.0);
      expect(monthlySales[2], 1200.0);
      expect(monthlySales[3], 1500.0);
    });

    test('Customer daily deduplication logic', () {
      final Map<String, Set<String>> dailyCustomers = {};
      const dateKey = '2026-09-11';

      dailyCustomers.putIfAbsent(dateKey, () => <String>{});
      // Same customer transacts 3 times today
      dailyCustomers[dateKey]!.add('cust-1');
      dailyCustomers[dateKey]!.add('cust-1');
      dailyCustomers[dateKey]!.add('cust-2');
      dailyCustomers[dateKey]!.add('cust-1');

      expect(dailyCustomers[dateKey]!.length, 2);
    });

    test('Target progress clamping', () {
      const salesTarget = 10000.0;
      const salesAchieved = 15000.0;

      final progress = (salesAchieved / salesTarget).clamp(0.0, 1.0);
      expect(progress, 1.0);

      const salesUnder = 5000.0;
      final progressUnder = (salesUnder / salesTarget).clamp(0.0, 1.0);
      expect(progressUnder, 0.5);
    });
  });
}
