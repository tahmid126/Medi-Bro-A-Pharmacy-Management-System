import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medibro_update/data/services/draft_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DraftService Export Tests', () {
    test('Save, search and load export draft', () async {
      final draftId = await DraftService.saveExportDraft(
        draftName: 'June Customer Order',
        customerId: null, // Test null ID scenario!
        customerName: 'Rahim Uddin',
        customerPhone: '01711111111',
        discountType: '%',
        discountValue: 10.0,
        items: [
          {
            'medicine_id': 'med-1',
            'quantity': 5,
            'unit_type': 'Strip',
            'unit_selling_price': 15.0,
          },
        ],
      );

      expect(draftId, isNotEmpty);

      final drafts = await DraftService.getExportDrafts();
      expect(drafts.length, 1);
      expect(drafts.first['draft_name'], 'June Customer Order');
      expect(drafts.first['customer_name'], 'Rahim Uddin');

      // Filter by filterName (even when customerId is null!)
      final filteredByName = await DraftService.getExportDrafts(filterName: 'Rahim');
      expect(filteredByName.length, 1);

      // Search by partial text
      final searchResult = await DraftService.getExportDrafts(searchQuery: 'june');
      expect(searchResult.length, 1);

      final searchPhone = await DraftService.getExportDrafts(searchQuery: '01711');
      expect(searchPhone.length, 1);

      final noMatch = await DraftService.getExportDrafts(searchQuery: 'nonexistent');
      expect(noMatch.length, 0);

      // Delete draft
      await DraftService.deleteExportDraft(draftId);
      final remaining = await DraftService.getExportDrafts();
      expect(remaining.length, 0);
    });
  });

  group('DraftService Import Tests', () {
    test('Save and filter import draft with null supplier_id', () async {
      final draftId = await DraftService.saveImportDraft(
        draftName: 'Square Pharma Stock In',
        supplierId: null, // e.g. entered or global catalog company
        supplierName: 'Square Pharmaceuticals Ltd.',
        discountType: 'TK',
        discountValue: 50.0,
        items: [
          {
            'medicine_id': 'med-2',
            'quantity': 10,
            'batch_number': 'B-2026-99',
            'retail_price': 12.0,
          },
        ],
      );

      expect(draftId, isNotEmpty);

      // Filter by supplier name (e.g. clicked from autocomplete suggestions)
      final matchedByName = await DraftService.getImportDrafts(filterName: 'Square');
      expect(matchedByName.length, 1);

      // Realtime search query
      final queryMatched = await DraftService.getImportDrafts(searchQuery: 'pharma');
      expect(queryMatched.length, 1);

      // Delete import draft
      await DraftService.deleteImportDraft(draftId);
      final remaining = await DraftService.getImportDrafts();
      expect(remaining.length, 0);
    });
  });
}
