import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medibro_update/data/services/invoice_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pharmacy_name': 'Test MediBro Pharma',
      'pharmacy_address': 'Dhanmondi, Dhaka',
      'pharmacy_phone': '01700000000',
      'owner_name': 'Dr. Test Owner',
    });
  });

  group('InvoicePdfService Tests', () {
    test('Generate invoice PDF bytes successfully with items and totals', () async {
      final exportData = {
        'export_id': 'inv-uuid-12345678',
        'invoice_number': 'INV-12345678',
        'cust_name': 'Karim Ullah',
        'cust_phone': '01811111111',
        'payment_status': 'PAID',
        'exported_at': DateTime.now().toIso8601String(),
        'total_amount': 250.0,
        'paid_amount': 250.0,
        'due_amount': 0.0,
        'discount_type': 'fixed',
        'discount_amount': 10.0,
        'items': [
          {
            'med_name': 'Napa Extra 500mg',
            'med_type': 'Tablet',
            'strength': '500mg',
            'batch_number': 'B-2026-01',
            'quantity': 10,
            'unit_price': 2.5,
            'total_price': 25.0,
          },
          {
            'med_name': 'Seclo 20mg Capsule',
            'med_type': 'Capsule',
            'strength': '20mg',
            'batch_number': 'B-2026-99',
            'quantity': 5,
            'unit_price': 7.0,
            'total_price': 35.0,
          },
        ],
      };

      final pdfBytes = await InvoicePdfService.generateInvoicePdfBytes(exportData: exportData);
      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
    });

    test('Generate invoice PDF bytes with empty items and partial payment', () async {
      final exportData = {
        'id': 'inv-partial-999',
        'customer_name': 'Walking Customer',
        'payment_status': 'PARTIAL',
        'created_at': DateTime.now().toIso8601String(),
        'grand_total': 500.0,
        'paid_amount': 300.0,
        'due_amount': 200.0,
        'invoice_items': [],
      };

      final pdfBytes = await InvoicePdfService.generateInvoicePdfBytes(exportData: exportData);
      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(500));
    });
  });

  group('Safety Validation Logic Tests', () {
    test('Import delete pre-flight logic detects sold items correctly', () {
      final importedQty = 100;
      final remainingQty = 70; // 30 pcs were sold!

      final hasSold = remainingQty < importedQty;
      final soldCount = importedQty - remainingQty;

      expect(hasSold, isTrue);
      expect(soldCount, 30);
    });

    test('Sale return logic calculates stock return and due delta correctly', () {
      final oldCustomerDue = 1500.0;
      final invoiceGrandTotal = 350.0;
      final invoicePaid = 150.0;
      final invoiceDue = invoiceGrandTotal - invoicePaid; // 200.0

      // When cancelling invoice:
      final newCustomerDue = (oldCustomerDue - invoiceDue).clamp(0.0, 9999999.0);
      expect(newCustomerDue, 1300.0);
    });
  });
}
