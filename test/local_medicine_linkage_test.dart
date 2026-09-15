import 'package:flutter_test/flutter_test.dart';
import 'package:medibro_update/data/models/batch_model.dart';
import 'package:medibro_update/data/models/medicine_model.dart';

void main() {
  group('Local Medicine & Silent Linkage Tests', () {
    test('Local medicine has null globalId and displays Local badge condition', () {
      final localMed = MedicineModel(
        id: 'loc_med_101',
        pharmacyId: 'pharm_1',
        globalId: null,
        brandName: 'Test Herbal Syrup',
        genericName: 'Herbal Blend',
        dosageForm: 'Syrup',
        strength: '100ml',
        company: 'Local Health Labs',
        rackLocation: 'Rack A-1',
        unit: 'Bottle',
        batches: [
          BatchModel(
            id: 'b-1',
            pharmacyId: 'pharm_1',
            medicineId: 'loc_med_101',
            batchNumber: 'B-202609-01',
            expiryDate: DateTime(2027, 9, 1),
            purchasePrice: 40.0,
            sellingPrice: 60.0,
            mrp: 60.0,
            stockQty: 25,
          ),
        ],
      );

      final isLocal = localMed.globalId == null || localMed.globalId!.isEmpty;
      expect(isLocal, isTrue);
      expect(localMed.totalStock, 25);
      expect(localMed.rackLocation, 'Rack A-1');
    });

    test('Notes regex extracts LocalMedId accurately for Admin silent linkage', () {
      const notes = 'LocalMedId:loc_med_101 | Packaging: 10 pcs/strip, 10 units/box, Base Unit: Piece, MRP: ৳12.0, Rack: Drawer 2';
      final match = RegExp(r'LocalMedId:([^\s|]+)').firstMatch(notes);

      expect(match, isNotNull);
      expect(match!.group(1), 'loc_med_101');
    });

    test('Silent linkage transforms Local medicine into Global without losing batches or stock', () {
      final initialLocalMed = MedicineModel(
        id: 'loc_med_101',
        pharmacyId: 'pharm_1',
        globalId: null,
        brandName: 'Napa Quick Release',
        genericName: 'Paracetamol',
        dosageForm: 'Tablet',
        batches: [
          BatchModel(
            id: 'b-10',
            pharmacyId: 'pharm_1',
            medicineId: 'loc_med_101',
            batchNumber: 'B-01',
            expiryDate: DateTime(2027, 1, 1),
            purchasePrice: 2.0,
            sellingPrice: 2.5,
            mrp: 2.5,
            stockQty: 100,
          ),
        ],
      );

      expect(initialLocalMed.globalId, isNull);

      // Admin approves -> silent linkage assigns global_id
      const newGlobalId = 'gm_998877';
      final linkedMed = MedicineModel(
        id: initialLocalMed.id,
        pharmacyId: initialLocalMed.pharmacyId,
        globalId: newGlobalId,
        brandName: initialLocalMed.brandName,
        genericName: initialLocalMed.genericName,
        dosageForm: initialLocalMed.dosageForm,
        batches: initialLocalMed.batches,
      );

      expect(linkedMed.globalId, 'gm_998877');
      expect(linkedMed.totalStock, 100);
      expect(linkedMed.batches.first.id, 'b-10');
      // Badge disappears
      final isLocalAfterApproval = linkedMed.globalId == null || linkedMed.globalId!.isEmpty;
      expect(isLocalAfterApproval, isFalse);
    });
  });
}
