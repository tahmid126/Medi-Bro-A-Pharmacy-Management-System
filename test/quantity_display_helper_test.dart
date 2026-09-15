import 'package:flutter_test/flutter_test.dart';
import 'package:medibro_update/core/utils/quantity_display_helper.dart';

void main() {
  group('QuantityDisplayHelper Formatting Tests', () {
    test('Formats 1 Box of 10x10 tablet as 1B with price per box', () {
      final res = QuantityDisplayHelper.format(
        totalUnits: 100,
        totalPrice: 300.0,
        piecesPerStrip: 10,
        stripsPerBox: 10,
        dosageForm: 'Tablet',
      );
      expect(res.quantityDisplay, '1B');
      expect(res.unitRate, 300.0);
      expect(res.unitType, 'Box');
      expect(res.count, 1);
    });

    test('Formats 2 Boxes of 10x10 tablet as 2B with price per box', () {
      final res = QuantityDisplayHelper.format(
        totalUnits: 200,
        totalPrice: 600.0,
        piecesPerStrip: 10,
        stripsPerBox: 10,
        dosageForm: 'Tablet',
      );
      expect(res.quantityDisplay, '2B');
      expect(res.unitRate, 300.0);
      expect(res.count, 2);
    });

    test('Formats 1 Strip of 10 tablets as 1S with price per strip', () {
      final res = QuantityDisplayHelper.format(
        totalUnits: 10,
        totalPrice: 30.0,
        piecesPerStrip: 10,
        stripsPerBox: 10,
        dosageForm: 'Tablet',
      );
      expect(res.quantityDisplay, '1S');
      expect(res.unitRate, 30.0);
      expect(res.unitType, 'Strip');
      expect(res.count, 1);
    });

    test('Formats 3 Strips of 10 tablets as 3S with price per strip', () {
      final res = QuantityDisplayHelper.format(
        totalUnits: 30,
        totalPrice: 90.0,
        piecesPerStrip: 10,
        stripsPerBox: 10,
        dosageForm: 'Tablet',
      );
      expect(res.quantityDisplay, '3S');
      expect(res.unitRate, 30.0);
      expect(res.count, 3);
    });

    test('Formats 1 Unit tablet as 1X with single unit price', () {
      final res = QuantityDisplayHelper.format(
        totalUnits: 1,
        totalPrice: 3.0,
        piecesPerStrip: 10,
        stripsPerBox: 10,
        dosageForm: 'Tablet',
      );
      expect(res.quantityDisplay, '1X');
      expect(res.unitRate, 3.0);
      expect(res.count, 1);
    });

    test('Formats 5 Unit loose tablets as 5X with rate per unit', () {
      final res = QuantityDisplayHelper.format(
        totalUnits: 5,
        totalPrice: 15.0,
        piecesPerStrip: 10,
        stripsPerBox: 10,
        dosageForm: 'Tablet',
      );
      expect(res.quantityDisplay, '5X');
      expect(res.unitRate, 3.0);
      expect(res.count, 5);
    });

    test('Formats non-tablet medicine (Syrup bottle) as 1X with bottle rate', () {
      final res = QuantityDisplayHelper.format(
        totalUnits: 1,
        totalPrice: 85.0,
        piecesPerStrip: 1,
        stripsPerBox: 1,
        dosageForm: 'Syrup',
      );
      expect(res.quantityDisplay, '1X');
      expect(res.unitRate, 85.0);
      expect(res.count, 1);
    });

    test('Formats multiple bottles (e.g. 3 syrups) as 3X with rate per unit', () {
      final res = QuantityDisplayHelper.format(
        totalUnits: 3,
        totalPrice: 255.0,
        piecesPerStrip: 1,
        stripsPerBox: 1,
        dosageForm: 'Syrup',
      );
      expect(res.quantityDisplay, '3X');
      expect(res.unitRate, 85.0);
      expect(res.count, 3);
    });

    test('Honors explicit unitType Box override', () {
      final res = QuantityDisplayHelper.format(
        totalUnits: 100,
        totalPrice: 300.0,
        unitType: 'Box',
        rawQuantity: 1,
      );
      expect(res.quantityDisplay, '1B');
      expect(res.unitRate, 300.0);
    });

    test('Honors explicit unitType Strip override', () {
      final res = QuantityDisplayHelper.format(
        totalUnits: 10,
        totalPrice: 30.0,
        unitType: 'Strip',
        rawQuantity: 1,
      );
      expect(res.quantityDisplay, '1S');
      expect(res.unitRate, 30.0);
    });

    test('Honors explicit unitType Unit override', () {
      final res = QuantityDisplayHelper.format(
        totalUnits: 1,
        totalPrice: 3.0,
        unitType: 'Unit',
        rawQuantity: 1,
      );
      expect(res.quantityDisplay, '1X');
      expect(res.unitRate, 3.0);
    });
  });
}
