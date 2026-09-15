import 'package:flutter/material.dart';
import '../../core/utils/error_formatter.dart';
import '../../data/models/batch_model.dart';
import '../../data/models/medicine_model.dart';
import '../../data/services/inventory_service.dart';

class InventoryProvider extends ChangeNotifier {
  final InventoryService _inventoryService = InventoryService();

  List<MedicineModel> _medicines = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _searchQuery = '';

  List<MedicineModel> get medicines => _medicines;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;

  List<MedicineModel> get lowStockMedicines =>
      _medicines.where((m) => m.isLowStock && !m.isOutOfStock).toList();

  List<MedicineModel> get outOfStockMedicines =>
      _medicines.where((m) => m.isOutOfStock).toList();

  Future<void> loadMedicines({String? search}) async {
    _isLoading = true;
    _errorMessage = null;
    if (search != null) _searchQuery = search;
    notifyListeners();

    try {
      _medicines = await _inventoryService.fetchMedicines(search: _searchQuery);
    } catch (e) {
      _errorMessage = ErrorFormatter.format(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addMedicine({
    required String pharmacyId,
    required String brandName,
    String? genericName,
    String dosageForm = 'Tablet',
    String? strength,
    String? company,
    String? category,
    String? rackLocation,
    String unit = 'Pcs',
    int minStockAlert = 10,
    String? batchNumber,
    DateTime? expiryDate,
    double purchasePrice = 0.0,
    double sellingPrice = 0.0,
    double mrp = 0.0,
    int initialStock = 0,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final created = await _inventoryService.addMedicine(
        pharmacyId: pharmacyId,
        brandName: brandName,
        genericName: genericName,
        dosageForm: dosageForm,
        strength: strength,
        company: company,
        category: category,
        rackLocation: rackLocation,
        unit: unit,
        minStockAlert: minStockAlert,
        batchNumber: batchNumber,
        expiryDate: expiryDate,
        purchasePrice: purchasePrice,
        sellingPrice: sellingPrice,
        mrp: mrp,
        initialStock: initialStock,
      );

      _medicines.insert(0, created);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = ErrorFormatter.format(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> addBatch({
    required String pharmacyId,
    required String medicineId,
    required String batchNumber,
    required DateTime expiryDate,
    required double purchasePrice,
    required double sellingPrice,
    required double mrp,
    required int stockQty,
  }) async {
    try {
      final batch = await _inventoryService.addBatch(
        pharmacyId: pharmacyId,
        medicineId: medicineId,
        batchNumber: batchNumber,
        expiryDate: expiryDate,
        purchasePrice: purchasePrice,
        sellingPrice: sellingPrice,
        mrp: mrp,
        stockQty: stockQty,
      );

      final index = _medicines.indexWhere((m) => m.id == medicineId);
      if (index != -1) {
        final currentMed = _medicines[index];
        final updatedBatches = List<BatchModel>.from(currentMed.batches)..add(batch);
        _medicines[index] = MedicineModel(
          id: currentMed.id,
          pharmacyId: currentMed.pharmacyId,
          globalId: currentMed.globalId,
          brandName: currentMed.brandName,
          genericName: currentMed.genericName,
          dosageForm: currentMed.dosageForm,
          strength: currentMed.strength,
          company: currentMed.company,
          category: currentMed.category,
          rackLocation: currentMed.rackLocation,
          unit: currentMed.unit,
          minStockAlert: currentMed.minStockAlert,
          isActive: currentMed.isActive,
          batches: updatedBatches,
        );
        notifyListeners();
      }
      return true;
    } catch (e) {
      _errorMessage = ErrorFormatter.format(e);
      notifyListeners();
      return false;
    }
  }
}
