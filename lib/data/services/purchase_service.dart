import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/supabase_constants.dart';
import '../models/purchase_model.dart';
import 'supabase_service.dart';

class PurchaseService {
  final SupabaseClient _client = SupabaseService.instance.client;

  Future<PurchaseModel> recordPurchase({
    required String pharmacyId,
    String? supplierId,
    String? supplierName,
    required double totalAmount,
    double discountAmount = 0.0,
    required double grandTotal,
    required double paidAmount,
    required double dueAmount,
    String paymentMethod = 'cash',
    DateTime? purchaseDate,
    String? notes,
    required List<PurchaseItemModel> items,
  }) async {
    final purchaseNo = 'PUR-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

    // 0. Auto-resolve supplier if supplierId is missing
    if ((supplierId == null || supplierId.isEmpty) && supplierName != null && supplierName.trim().isNotEmpty) {
      final existingSupp = await _client
          .from(SupabaseConstants.suppliersTable)
          .select('id')
          .eq('pharmacy_id', pharmacyId)
          .ilike('company_name', supplierName.trim())
          .maybeSingle();

      if (existingSupp != null) {
        supplierId = existingSupp['id']?.toString();
      } else if (dueAmount > 0.001) {
        final newSupp = await _client.from(SupabaseConstants.suppliersTable).insert({
          'pharmacy_id': pharmacyId,
          'name': supplierName.trim(),
          'company_name': supplierName.trim(),
          'current_due': 0.0,
        }).select('id').single();
        supplierId = newSupp['id']?.toString();
      }
    }

    // 1. Insert Purchase
    final purchaseData = await _client.from(SupabaseConstants.purchasesTable).insert({
      'pharmacy_id': pharmacyId,
      'purchase_number': purchaseNo,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'total_amount': totalAmount,
      'discount_amount': discountAmount,
      'grand_total': grandTotal,
      'paid_amount': paidAmount,
      'due_amount': dueAmount,
      'payment_method': paymentMethod,
      'purchase_date': (purchaseDate ?? DateTime.now()).toIso8601String().split('T').first,
      'notes': notes,
    }).select().single();

    final purchaseId = purchaseData['id'] as String;

    // 2. Insert items and update stock batches
    for (var item in items) {
      // Check existing batch
      final existingBatch = await _client
          .from(SupabaseConstants.batchesTable)
          .select()
          .eq('pharmacy_id', pharmacyId)
          .eq('medicine_id', item.medicineId)
          .eq('batch_number', item.batchNumber)
          .maybeSingle();

      String batchId;
      final double effectiveMrp = item.mrp > 0 ? item.mrp : (item.sellingPrice > 0 ? item.sellingPrice : item.purchasePrice);
      final double effectiveSelling = item.sellingPrice > 0 ? item.sellingPrice : effectiveMrp;

      if (existingBatch != null) {
        batchId = existingBatch['id'] as String;
        final currentQty = (existingBatch['stock_qty'] as num?)?.toInt() ?? 0;
        final existingMrp = (existingBatch['mrp'] as num?)?.toDouble() ?? 0.0;
        await _client.from(SupabaseConstants.batchesTable).update({
          'stock_qty': currentQty + item.quantity,
          'purchase_price': item.purchasePrice,
          'selling_price': effectiveSelling,
          'mrp': item.mrp > 0 ? item.mrp : (existingMrp > 0 ? existingMrp : effectiveMrp),
          'expiry_date': item.expiryDate.toIso8601String().split('T').first,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', batchId);
      } else {
        final newBatch = await _client.from(SupabaseConstants.batchesTable).insert({
          'pharmacy_id': pharmacyId,
          'medicine_id': item.medicineId,
          'batch_number': item.batchNumber,
          'expiry_date': item.expiryDate.toIso8601String().split('T').first,
          'purchase_price': item.purchasePrice,
          'selling_price': effectiveSelling,
          'mrp': effectiveMrp,
          'stock_qty': item.quantity,
        }).select().single();
        batchId = newBatch['id'] as String;
      }

      // Insert purchase_item
      await _client.from(SupabaseConstants.purchaseItemsTable).insert({
        'pharmacy_id': pharmacyId,
        'purchase_id': purchaseId,
        'medicine_id': item.medicineId,
        'batch_id': batchId,
        'medicine_name': item.medicineName,
        'batch_number': item.batchNumber,
        'expiry_date': item.expiryDate.toIso8601String().split('T').first,
        'quantity': item.quantity,
        'purchase_price': item.purchasePrice,
        'selling_price': effectiveSelling,
        'total_price': item.totalPrice,
      });

      // Update medicine rack location if provided
      if (item.rackLocation != null && item.rackLocation!.trim().isNotEmpty) {
        try {
          await _client
              .from(SupabaseConstants.medicinesTable)
              .update({'rack_location': item.rackLocation!.trim()})
              .eq('id', item.medicineId);
        } catch (e) {
          debugPrint('Error updating medicine rack location: ');
        }
      }
    }

    // 3. Update Supplier balance if supplier exists
    if (supplierId != null) {
      try {
        final supplier = await _client
            .from(SupabaseConstants.suppliersTable)
            .select()
            .eq('id', supplierId)
            .maybeSingle();

        if (supplier != null) {
          final currentDue = (supplier['current_due'] as num?)?.toDouble() ?? 0.0;
          final rawNewDue = currentDue + grandTotal - paidAmount;
          final newDue = rawNewDue > 0.001 ? rawNewDue : 0.0;

          await _client
              .from(SupabaseConstants.suppliersTable)
              .update({'current_due': newDue})
              .eq('id', supplierId);

          await _client.from(SupabaseConstants.supplierLedgersTable).insert({
            'pharmacy_id': pharmacyId,
            'supplier_id': supplierId,
            'purchase_id': purchaseId,
            'entry_type': 'purchase',
            'debit': paidAmount,
            'credit': grandTotal,
            'balance': newDue,
            'notes': 'Purchase #$purchaseNo (Total: ৳${grandTotal.toStringAsFixed(2)}, Paid: ৳${paidAmount.toStringAsFixed(2)})',
          });
        }
      } catch (e) {
        // Supplier table update error caught gracefully
      }
    }

    return PurchaseModel.fromJson(purchaseData, items: items);
  }

  Future<List<PurchaseModel>> fetchPurchases({int limit = 50}) async {
    final data = await _client
        .from(SupabaseConstants.purchasesTable)
        .select('*, purchase_items(*)')
        .order('created_at', ascending: false)
        .limit(limit);

    return (data as List).map((json) {
      final items = (json['purchase_items'] as List?)
              ?.map((i) => PurchaseItemModel.fromJson(i))
              .toList() ??
          [];
      return PurchaseModel.fromJson(json, items: items);
    }).toList();
  }

  /// Check whether a purchase can be safely deleted without causing negative stock
  /// or conflicting with already sold units.
  Future<Map<String, dynamic>> canDeletePurchase(String purchaseId) async {
    final purchaseData = await _client
        .from(SupabaseConstants.purchasesTable)
        .select('*, purchase_items(*)')
        .eq('id', purchaseId)
        .maybeSingle();

    if (purchaseData == null) {
      return {'canDelete': false, 'reason': 'Purchase record not found.'};
    }

    final List<dynamic> items = purchaseData['purchase_items'] as List? ?? [];
    final List<Map<String, dynamic>> soldItems = [];

    for (var item in items) {
      final String? batchId = item['batch_id']?.toString();
      final int importedQty = (item['quantity'] as num?)?.toInt() ?? 0;
      final String medName = item['medicine_name']?.toString() ?? 'Medicine';
      final String batchNo = item['batch_number']?.toString() ?? '-';

      if (batchId != null && batchId.isNotEmpty) {
        final batch = await _client
            .from(SupabaseConstants.batchesTable)
            .select()
            .eq('id', batchId)
            .maybeSingle();

        if (batch != null) {
          final int remainingQty = (batch['stock_qty'] as num?)?.toInt() ?? 0;
          if (remainingQty < importedQty) {
            soldItems.add({
              'medicine_name': medName,
              'batch_number': batchNo,
              'imported_qty': importedQty,
              'remaining_qty': remainingQty,
              'sold_qty': importedQty - remainingQty,
            });
          }
        }
      }
    }

    if (soldItems.isNotEmpty) {
      return {
        'canDelete': false,
        'soldItems': soldItems,
        'reason':
            'Cannot delete purchase: units from this lot have already been sold in POS sales.',
      };
    }

    return {'canDelete': true, 'soldItems': <Map<String, dynamic>>[]};
  }

  /// Delete a purchase record safely, reversing stock and supplier due balance.
  Future<void> deletePurchase(
    String purchaseId, {
    bool force = false,
  }) async {
    final check = await canDeletePurchase(purchaseId);
    if (!force && check['canDelete'] != true) {
      throw Exception(check['reason'] ?? 'Cannot delete purchase with sold items.');
    }

    final purchaseData = await _client
        .from(SupabaseConstants.purchasesTable)
        .select('*, purchase_items(*)')
        .eq('id', purchaseId)
        .maybeSingle();

    if (purchaseData == null) return;

    final String pharmacyId = purchaseData['pharmacy_id']?.toString() ?? '';
    final String purchaseNo = purchaseData['purchase_number']?.toString() ?? '';
    final String? supplierId = purchaseData['supplier_id']?.toString();
    final double grandTotal = (purchaseData['grand_total'] as num?)?.toDouble() ?? 0.0;
    final double paidAmount = (purchaseData['paid_amount'] as num?)?.toDouble() ?? 0.0;
    final double dueAmount = (purchaseData['due_amount'] as num?)?.toDouble() ?? (grandTotal - paidAmount);
    final List<dynamic> items = purchaseData['purchase_items'] as List? ?? [];

    // 1. Revert stock in batches
    for (var item in items) {
      final String? batchId = item['batch_id']?.toString();
      final int qty = (item['quantity'] as num?)?.toInt() ?? 0;

      if (batchId != null && batchId.isNotEmpty) {
        final batch = await _client
            .from(SupabaseConstants.batchesTable)
            .select()
            .eq('id', batchId)
            .maybeSingle();

        if (batch != null) {
          final int currentQty = (batch['stock_qty'] as num?)?.toInt() ?? 0;
          final int newQty = (currentQty - qty).clamp(0, 9999999);
          if (newQty == 0 && !force) {
            // Delete batch if empty and no sales
            await _client.from(SupabaseConstants.batchesTable).delete().eq('id', batchId);
          } else {
            await _client.from(SupabaseConstants.batchesTable).update({
              'stock_qty': newQty,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', batchId);
          }
        }
      }
    }

    // 2. Revert Supplier due & ledger
    if (supplierId != null && supplierId.isNotEmpty) {
      try {
        final supplier = await _client
            .from(SupabaseConstants.suppliersTable)
            .select()
            .eq('id', supplierId)
            .maybeSingle();

        if (supplier != null) {
          final double curDue = (supplier['current_due'] as num?)?.toDouble() ?? 0.0;
          final double newDue = (curDue - dueAmount) > 0.001 ? (curDue - dueAmount) : 0.0;

          await _client
              .from(SupabaseConstants.suppliersTable)
              .update({'current_due': newDue})
              .eq('id', supplierId);

          await _client.from(SupabaseConstants.supplierLedgersTable).insert({
            'pharmacy_id': pharmacyId,
            'supplier_id': supplierId,
            'purchase_id': purchaseId,
            'entry_type': 'purchase_cancelled',
            'debit': dueAmount,
            'credit': 0.0,
            'balance': newDue,
            'notes': 'Purchase #$purchaseNo Cancelled/Deleted - Payable reversed (৳${dueAmount.toStringAsFixed(2)})',
          });
        }
      } catch (e) {
        debugPrint('Supplier due reversal notice: $e');
      }
    }

    // 3. Delete items and purchase record
    await _client
        .from(SupabaseConstants.purchaseItemsTable)
        .delete()
        .eq('purchase_id', purchaseId);
    await _client
        .from(SupabaseConstants.purchasesTable)
        .delete()
        .eq('id', purchaseId);
  }

  /// Update purchase details (supplier, notes, payment, batch info)
  Future<void> updatePurchase({
    required String purchaseId,
    String? supplierId,
    String? supplierName,
    required double grandTotal,
    required double paidAmount,
    required double dueAmount,
    String? notes,
  }) async {
    final oldPurchase = await _client
        .from(SupabaseConstants.purchasesTable)
        .select()
        .eq('id', purchaseId)
        .maybeSingle();

    if (oldPurchase == null) throw Exception('Purchase not found: $purchaseId');

    final String? oldSupplierId = oldPurchase['supplier_id']?.toString();
    final double oldDue = (oldPurchase['due_amount'] as num?)?.toDouble() ?? 0.0;

    await _client.from(SupabaseConstants.purchasesTable).update({
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'grand_total': grandTotal,
      'paid_amount': paidAmount,
      'due_amount': dueAmount,
      if (notes != null) 'notes': notes,
    }).eq('id', purchaseId);

    // Reconcile supplier due
    if (oldSupplierId != null && oldSupplierId != supplierId) {
      // Revert from old supplier
      final oldSupp = await _client
          .from(SupabaseConstants.suppliersTable)
          .select()
          .eq('id', oldSupplierId)
          .maybeSingle();
      if (oldSupp != null) {
        final curDue = (oldSupp['current_due'] as num?)?.toDouble() ?? 0.0;
        await _client.from(SupabaseConstants.suppliersTable).update({
          'current_due': (curDue - oldDue).clamp(0.0, 9999999.0),
        }).eq('id', oldSupplierId);
      }
      // Add to new supplier
      if (supplierId != null && supplierId.isNotEmpty) {
        final newSupp = await _client
            .from(SupabaseConstants.suppliersTable)
            .select()
            .eq('id', supplierId)
            .maybeSingle();
        if (newSupp != null) {
          final curDue = (newSupp['current_due'] as num?)?.toDouble() ?? 0.0;
          await _client.from(SupabaseConstants.suppliersTable).update({
            'current_due': curDue + dueAmount,
          }).eq('id', supplierId);
        }
      }
    } else if (supplierId != null && supplierId.isNotEmpty) {
      final dueDelta = dueAmount - oldDue;
      if (dueDelta.abs() > 0.001) {
        final supp = await _client
            .from(SupabaseConstants.suppliersTable)
            .select()
            .eq('id', supplierId)
            .maybeSingle();
        if (supp != null) {
          final curDue = (supp['current_due'] as num?)?.toDouble() ?? 0.0;
          await _client.from(SupabaseConstants.suppliersTable).update({
            'current_due': (curDue + dueDelta).clamp(0.0, 9999999.0),
          }).eq('id', supplierId);
        }
      }
    }
  }

  Future<Map<String, dynamic>?> fetchPurchaseById(String purchaseId) async {
    final data = await _client
        .from(SupabaseConstants.purchasesTable)
        .select('*, purchase_items(*)')
        .eq('id', purchaseId)
        .maybeSingle();
    return data;
  }

  Future<void> updatePurchaseWithItems({
    required String purchaseId,
    String? supplierId,
    String? supplierName,
    required double totalAmount,
    double discountAmount = 0.0,
    required double grandTotal,
    required double paidAmount,
    required double dueAmount,
    String paymentMethod = 'cash',
    DateTime? purchaseDate,
    String? notes,
    required List<PurchaseItemModel> items,
  }) async {
    final oldPurchaseData = await _client
        .from(SupabaseConstants.purchasesTable)
        .select('*, purchase_items(*)')
        .eq('id', purchaseId)
        .maybeSingle();

    if (oldPurchaseData == null) {
      throw Exception('Purchase not found: ');
    }

    final String pharmacyId = oldPurchaseData['pharmacy_id']?.toString() ?? '';
    final String? oldSupplierId = oldPurchaseData['supplier_id']?.toString();
    final double oldDue = (oldPurchaseData['due_amount'] as num?)?.toDouble() ?? 0.0;
    final List<dynamic> oldItems = oldPurchaseData['purchase_items'] as List? ?? [];

    // Auto-resolve supplier if supplierId is missing
    if ((supplierId == null || supplierId.isEmpty) && supplierName != null && supplierName.trim().isNotEmpty) {
      final existingSupp = await _client
          .from(SupabaseConstants.suppliersTable)
          .select('id')
          .eq('pharmacy_id', pharmacyId)
          .ilike('company_name', supplierName.trim())
          .maybeSingle();

      if (existingSupp != null) {
        supplierId = existingSupp['id']?.toString();
      } else if (dueAmount > 0.001) {
        final newSupp = await _client.from(SupabaseConstants.suppliersTable).insert({
          'pharmacy_id': pharmacyId,
          'name': supplierName.trim(),
          'company_name': supplierName.trim(),
          'current_due': 0.0,
        }).select('id').single();
        supplierId = newSupp['id']?.toString();
      }
    }

    final Map<String, dynamic> oldItemsMap = {};
    for (var oi in oldItems) {
      final mid = oi['medicine_id']?.toString() ?? '';
      if (mid.isNotEmpty) {
        oldItemsMap[mid] = oi;
      }
    }

    final Set<String> processedOldMedIds = {};

    for (var newItem in items) {
      final medId = newItem.medicineId;
      final existingOldItem = oldItemsMap[medId];

      if (existingOldItem != null) {
        processedOldMedIds.add(medId);
        final String? batchId = existingOldItem['batch_id']?.toString();
        final int oldQty = (existingOldItem['quantity'] as num?)?.toInt() ?? 0;
        final int newQty = newItem.quantity;
        final int qtyDelta = newQty - oldQty;

        if (batchId != null && batchId.isNotEmpty) {
          final batch = await _client
              .from(SupabaseConstants.batchesTable)
              .select()
              .eq('id', batchId)
              .maybeSingle();

          if (batch != null) {
            final int currentStock = (batch['stock_qty'] as num?)?.toInt() ?? 0;
            final int newStock = (currentStock + qtyDelta).clamp(0, 9999999);
            final double effectiveMrp = newItem.mrp > 0
                ? newItem.mrp
                : (newItem.sellingPrice > 0 ? newItem.sellingPrice : newItem.purchasePrice);
            final double effectiveSelling = newItem.sellingPrice > 0 ? newItem.sellingPrice : effectiveMrp;

            await _client.from(SupabaseConstants.batchesTable).update({
              'stock_qty': newStock,
              'purchase_price': newItem.purchasePrice,
              'selling_price': effectiveSelling,
              'mrp': effectiveMrp,
              'expiry_date': newItem.expiryDate.toIso8601String().split('T').first,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', batchId);
          }
        }

        await _client.from(SupabaseConstants.purchaseItemsTable).update({
          'quantity': newQty,
          'purchase_price': newItem.purchasePrice,
          'selling_price': newItem.sellingPrice,
          'total_price': newItem.totalPrice,
          'batch_number': newItem.batchNumber,
          'expiry_date': newItem.expiryDate.toIso8601String().split('T').first,
        }).eq('id', existingOldItem['id']);
      } else {
        final existingBatch = await _client
            .from(SupabaseConstants.batchesTable)
            .select()
            .eq('pharmacy_id', pharmacyId)
            .eq('medicine_id', newItem.medicineId)
            .eq('batch_number', newItem.batchNumber)
            .maybeSingle();

        String batchId;
        final double effectiveMrp = newItem.mrp > 0
            ? newItem.mrp
            : (newItem.sellingPrice > 0 ? newItem.sellingPrice : newItem.purchasePrice);
        final double effectiveSelling = newItem.sellingPrice > 0 ? newItem.sellingPrice : effectiveMrp;

        if (existingBatch != null) {
          batchId = existingBatch['id'] as String;
          final currentQty = (existingBatch['stock_qty'] as num?)?.toInt() ?? 0;
          await _client.from(SupabaseConstants.batchesTable).update({
            'stock_qty': currentQty + newItem.quantity,
            'purchase_price': newItem.purchasePrice,
            'selling_price': effectiveSelling,
            'mrp': effectiveMrp,
            'expiry_date': newItem.expiryDate.toIso8601String().split('T').first,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', batchId);
        } else {
          final newBatch = await _client.from(SupabaseConstants.batchesTable).insert({
            'pharmacy_id': pharmacyId,
            'medicine_id': newItem.medicineId,
            'batch_number': newItem.batchNumber,
            'expiry_date': newItem.expiryDate.toIso8601String().split('T').first,
            'purchase_price': newItem.purchasePrice,
            'selling_price': effectiveSelling,
            'mrp': effectiveMrp,
            'stock_qty': newItem.quantity,
          }).select().single();
          batchId = newBatch['id'] as String;
        }

        await _client.from(SupabaseConstants.purchaseItemsTable).insert({
          'pharmacy_id': pharmacyId,
          'purchase_id': purchaseId,
          'medicine_id': newItem.medicineId,
          'batch_id': batchId,
          'medicine_name': newItem.medicineName,
          'batch_number': newItem.batchNumber,
          'expiry_date': newItem.expiryDate.toIso8601String().split('T').first,
          'quantity': newItem.quantity,
          'purchase_price': newItem.purchasePrice,
          'selling_price': effectiveSelling,
          'total_price': newItem.totalPrice,
        });
      }
    }

    for (var oi in oldItems) {
      final mid = oi['medicine_id']?.toString() ?? '';
      if (!processedOldMedIds.contains(mid)) {
        final String? batchId = oi['batch_id']?.toString();
        final int oldQty = (oi['quantity'] as num?)?.toInt() ?? 0;

        if (batchId != null && batchId.isNotEmpty && oldQty > 0) {
          final batch = await _client
              .from(SupabaseConstants.batchesTable)
              .select()
              .eq('id', batchId)
              .maybeSingle();

          if (batch != null) {
            final int currentStock = (batch['stock_qty'] as num?)?.toInt() ?? 0;
            final int remaining = (currentStock - oldQty).clamp(0, 9999999);
            await _client.from(SupabaseConstants.batchesTable).update({
              'stock_qty': remaining,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', batchId);
          }
        }

        await _client
            .from(SupabaseConstants.purchaseItemsTable)
            .delete()
            .eq('id', oi['id']);
      }
    }

    await _client.from(SupabaseConstants.purchasesTable).update({
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'total_amount': totalAmount,
      'discount_amount': discountAmount,
      'grand_total': grandTotal,
      'paid_amount': paidAmount,
      'due_amount': dueAmount,
      'payment_method': paymentMethod,
      if (purchaseDate != null) 'purchase_date': purchaseDate.toIso8601String().split('T').first,
      if (notes != null) 'notes': notes,
    }).eq('id', purchaseId);

    if (oldSupplierId != null && oldSupplierId != supplierId) {
      final oldSupp = await _client
          .from(SupabaseConstants.suppliersTable)
          .select()
          .eq('id', oldSupplierId)
          .maybeSingle();
      if (oldSupp != null) {
        final curDue = (oldSupp['current_due'] as num?)?.toDouble() ?? 0.0;
        await _client.from(SupabaseConstants.suppliersTable).update({
          'current_due': (curDue - oldDue).clamp(0.0, 9999999.0),
        }).eq('id', oldSupplierId);
      }
      if (supplierId != null && supplierId.isNotEmpty) {
        final newSupp = await _client
            .from(SupabaseConstants.suppliersTable)
            .select()
            .eq('id', supplierId)
            .maybeSingle();
        if (newSupp != null) {
          final curDue = (newSupp['current_due'] as num?)?.toDouble() ?? 0.0;
          await _client.from(SupabaseConstants.suppliersTable).update({
            'current_due': curDue + dueAmount,
          }).eq('id', supplierId);
        }
      }
    } else if (supplierId != null && supplierId.isNotEmpty) {
      final dueDelta = dueAmount - oldDue;
      if (dueDelta.abs() > 0.001) {
        final supp = await _client
            .from(SupabaseConstants.suppliersTable)
            .select()
            .eq('id', supplierId)
            .maybeSingle();
        if (supp != null) {
          final curDue = (supp['current_due'] as num?)?.toDouble() ?? 0.0;
          await _client.from(SupabaseConstants.suppliersTable).update({
            'current_due': (curDue + dueDelta).clamp(0.0, 9999999.0),
          }).eq('id', supplierId);
        }
      }
    }
  }

}
