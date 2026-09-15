import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/supabase_constants.dart';
import '../models/batch_model.dart';
import '../models/medicine_model.dart';
import 'supabase_service.dart';

class InventoryService {
  final SupabaseClient _client = SupabaseService.instance.client;

  Future<List<MedicineModel>> fetchMedicines({String? search}) async {
    var query = _client
        .from(SupabaseConstants.medicinesTable)
        .select('*, batches(*)');

    if (search != null && search.trim().isNotEmpty) {
      query = query.or(
        'brand_name.ilike.%${search.trim()}%,generic_name.ilike.%${search.trim()}%',
      );
    }

    final data = await query.order('brand_name', ascending: true);

    return (data as List).map((json) {
      final rawBatches = (json['batches'] as List?);
      double? catalogPrice = (json['default_mrp'] as num?)?.toDouble() ?? (json['mrp'] as num?)?.toDouble();
      if (catalogPrice == null || catalogPrice <= 0) {
        if (rawBatches != null) {
          for (final b in rawBatches) {
            final m = (b['mrp'] as num?)?.toDouble() ?? double.tryParse(b['mrp']?.toString() ?? '');
            if (m != null && m > 0) {
              catalogPrice = m;
              break;
            }
          }
        }
      }

      if (catalogPrice == null || catalogPrice <= 0) {
        final rawStr = json['strength']?.toString();
        if (rawStr != null) {
          final mrpMatch = RegExp(r'\[MRP:\s*[৳$]?\s*(\d+(?:\.\d+)?)\]', caseSensitive: false).firstMatch(rawStr);
          if (mrpMatch != null) {
            catalogPrice = double.tryParse(mrpMatch.group(1)!);
          }
        }
      }

      final batchList = rawBatches
              ?.map((b) => BatchModel.fromJson(b))
              .where((b) => !(b.stockQty == 0 && (b.batchNumber == 'INITIAL' || b.batchNumber == 'DEFAULT')))
              .toList() ??
          [];
      return MedicineModel.fromJson(json, batches: batchList, catalogPrice: catalogPrice);
    }).toList();
  }

  Future<MedicineModel> addMedicine({
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
    // Optional initial batch
    String? batchNumber,
    DateTime? expiryDate,
    double purchasePrice = 0.0,
    double sellingPrice = 0.0,
    double mrp = 0.0,
    int initialStock = 0,
  }) async {
    final medData = await _client.from(SupabaseConstants.medicinesTable).insert({
      'pharmacy_id': pharmacyId,
      'brand_name': brandName.trim(),
      'generic_name': genericName?.trim(),
      'dosage_form': dosageForm,
      'strength': strength?.trim(),
      'company': company?.trim(),
      'category': category?.trim(),
      'rack_location': rackLocation?.trim(),
      'unit': unit,
      'min_stock_alert': minStockAlert,
    }).select().single();

    final medId = medData['id'] as String;
    List<BatchModel> createdBatches = [];

    if (batchNumber != null && expiryDate != null) {
      final batchData = await _client.from(SupabaseConstants.batchesTable).insert({
        'pharmacy_id': pharmacyId,
        'medicine_id': medId,
        'batch_number': batchNumber.trim(),
        'expiry_date': expiryDate.toIso8601String().split('T').first,
        'purchase_price': purchasePrice,
        'selling_price': sellingPrice,
        'mrp': mrp,
        'stock_qty': initialStock,
      }).select().single();

      createdBatches.add(BatchModel.fromJson(batchData));
    }

    return MedicineModel.fromJson(medData, batches: createdBatches, catalogPrice: mrp > 0 ? mrp : null);
  }

  Future<BatchModel> addBatch({
    required String pharmacyId,
    required String medicineId,
    required String batchNumber,
    required DateTime expiryDate,
    required double purchasePrice,
    required double sellingPrice,
    required double mrp,
    required int stockQty,
  }) async {
    final data = await _client.from(SupabaseConstants.batchesTable).insert({
      'pharmacy_id': pharmacyId,
      'medicine_id': medicineId,
      'batch_number': batchNumber.trim(),
      'expiry_date': expiryDate.toIso8601String().split('T').first,
      'purchase_price': purchasePrice,
      'selling_price': sellingPrice,
      'mrp': mrp,
      'stock_qty': stockQty,
    }).select().single();

    return BatchModel.fromJson(data);
  }

  Future<List<Map<String, dynamic>>> fetchGlobalMedicines() async {
    final data = await _client
        .from('global_medicines')
        .select('*')
        .order('brand_name', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> searchGlobalMedicines(String query) async {
    if (query.trim().isEmpty) return [];

    final data = await _client
        .from(SupabaseConstants.globalMedicinesTable)
        .select()
        .or('brand_name.ilike.%${query.trim()}%,generic_name.ilike.%${query.trim()}%')
        .limit(20);

    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> submitMedicineRequest({
    required String pharmacyId,
    required String brandName,
    String? genericName,
    String? dosageForm,
    String? strength,
    String? company,
    String? notes,
  }) async {
    await _client.from(SupabaseConstants.medicineRequestsTable).insert({
      'pharmacy_id': pharmacyId,
      'brand_name': brandName.trim(),
      'generic_name': genericName?.trim(),
      'dosage_form': dosageForm,
      'strength': strength?.trim(),
      'company': company?.trim(),
      'notes': notes,
      'status': 'pending',
    });
  }
}
