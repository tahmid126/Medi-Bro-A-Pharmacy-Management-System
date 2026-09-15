import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Due Calculation and Payment Logic Tests', () {
    test('Remaining due calculation', () {
      const netDue = 1500.0;
      var payingNow = 500.0;
      var remaining = (netDue - payingNow).clamp(0.0, double.infinity);
      expect(remaining, 1000.0);

      // Paying full amount
      payingNow = 1500.0;
      remaining = (netDue - payingNow).clamp(0.0, double.infinity);
      expect(remaining, 0.0);

      // Paying more than due is clamped to 0
      payingNow = 2000.0;
      remaining = (netDue - payingNow).clamp(0.0, double.infinity);
      expect(remaining, 0.0);
    });

    test('Fully paid condition', () {
      const netDue = 850.0;
      var payingNow = 849.0;
      var fullyPaid = payingNow >= netDue && netDue > 0;
      expect(fullyPaid, isFalse);

      payingNow = 850.0;
      fullyPaid = payingNow >= netDue && netDue > 0;
      expect(fullyPaid, isTrue);

      payingNow = 900.0;
      fullyPaid = payingNow >= netDue && netDue > 0;
      expect(fullyPaid, isTrue);
    });

    test('Stepper increase and decrease clamping', () {
      const netDue = 100.0;
      var current = 99.0;

      // Increase clamped to max netDue
      var next = (current + 1).clamp(0.0, netDue);
      expect(next, 100.0);

      // Increasing further stays at netDue
      next = (next + 1).clamp(0.0, netDue);
      expect(next, 100.0);

      // Decrease clamped to 0.0
      current = 0.5;
      next = (current - 1).clamp(0.0, double.infinity);
      expect(next, 0.0);
    });

    test('Total due aggregation and sorting', () {
      final dues = [
        {'id': '1', 'name': 'Rahim', 'net_due': 500.0},
        {'id': '2', 'name': 'Karim', 'net_due': 1200.0},
        {'id': '3', 'name': 'Square Pharma', 'net_due': 4500.0},
      ];

      final total = dues.fold(0.0, (s, e) => s + (e['net_due'] as double));
      expect(total, 6200.0);

      dues.sort((a, b) => (b['net_due'] as double).compareTo(a['net_due'] as double));
      expect(dues.first['name'], 'Square Pharma');
      expect(dues.last['name'], 'Rahim');
    });

    test('Multi-invoice overpayment and previous due reconciliation', () {
      // User scenario:
      // Invoice 1: 85 bill, paid 80 -> 5 due
      // Invoice 2: 90 bill, paid 92 -> overpaid 2 towards previous due
      // Total billed = 85 + 90 = 175
      // Total paid = 80 + 92 = 172
      // Net due = 175 - 172 = 3
      const inv1Billed = 85.0;
      const inv1Paid = 80.0;

      const inv2Billed = 90.0;
      const inv2Paid = 92.0;

      const totalBilled = inv1Billed + inv2Billed;
      const totalPaid = inv1Paid + inv2Paid;
      final netDue = (totalBilled - totalPaid).clamp(0.0, double.infinity);

      expect(totalBilled, 175.0);
      expect(totalPaid, 172.0);
      expect(netDue, 3.0);

      // Subsequent payment of 3 in Due page
      const directPaid = 3.0;
      final finalTotalPaid = totalPaid + directPaid;
      final finalNetDue = (totalBilled - finalTotalPaid).clamp(0.0, double.infinity);

      expect(finalTotalPaid, 175.0);
      expect(finalNetDue, 0.0);
    });
  });
}
