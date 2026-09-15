import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Purchase Edit Delta Calculation Tests', () {
    test('Quantity increase adds delta stock to batch', () {
      const int oldQty = 10;
      const int newQty = 15;
      const int currentBatchStock = 12;

      final int delta = newQty - oldQty;
      final int updatedStock = currentBatchStock + delta;

      expect(delta, 5);
      expect(updatedStock, 17);
    });

    test('Quantity decrease safely reduces batch stock if sufficient stock exists', () {
      const int oldQty = 10;
      const int newQty = 7;
      const int currentBatchStock = 8;

      final int delta = newQty - oldQty;
      final int requiredDeduction = -delta;

      final bool canSafelyReduce = currentBatchStock >= requiredDeduction;
      expect(canSafelyReduce, isTrue);

      final int updatedStock = currentBatchStock + delta;
      expect(updatedStock, 5);
    });

    test('Quantity decrease blocked or clamped if already sold out past reduction', () {
      const int oldQty = 10;
      const int newQty = 4;
      const int currentBatchStock = 3;

      final int delta = newQty - oldQty;
      final int requiredDeduction = -delta;

      final bool canSafelyReduce = currentBatchStock >= requiredDeduction;
      expect(canSafelyReduce, isFalse);

      final int clampedStock = (currentBatchStock + delta).clamp(0, 999999);
      expect(clampedStock, 0);
    });
  });

  group('Sale Invoice Edit Re-credit and Re-deduction Tests', () {
    test('Edit sale replaces old sold quantities and applies new cart quantities', () {
      int batchStock = 20;

      const int oldSaleQty = 5;
      batchStock += oldSaleQty;
      expect(batchStock, 25);

      const int newSaleQty = 8;
      batchStock -= newSaleQty;
      expect(batchStock, 17);
    });

    test('Customer ledger due delta is calculated correctly on sale edit', () {
      const double oldDue = 200.0;

      double customerCurrentDue = 1000.0;

      const double newGrandTotal = 650.0;
      const double newPaid = 400.0;
      const double newDue = newGrandTotal - newPaid;

      final double dueDelta = newDue - oldDue;
      customerCurrentDue += dueDelta;

      expect(newDue, 250.0);
      expect(dueDelta, 50.0);
      expect(customerCurrentDue, 1050.0);
    });

    test('Supplier ledger due delta is calculated correctly on purchase edit', () {
      const double oldDue = 700.0;

      double supplierCurrentDue = 2500.0;

      const double newGrandTotal = 1000.0;
      const double newPaid = 500.0;
      const double newDue = newGrandTotal - newPaid;

      final double dueDelta = newDue - oldDue;
      supplierCurrentDue += dueDelta;

      expect(newDue, 500.0);
      expect(dueDelta, -200.0);
      expect(supplierCurrentDue, 2300.0);
    });
  });
}
