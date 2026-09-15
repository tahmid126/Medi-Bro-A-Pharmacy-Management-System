import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/supabase_constants.dart';
import '../../data/models/medicine_model.dart';
import '../../data/services/supabase_service.dart';

class HistoryService {
  final SupabaseClient _client;

  HistoryService({SupabaseClient? client})
      : _client = client ?? SupabaseService.instance.client;

  // ===========================================================================
  // EXPORT / INVOICE HISTORY
  // ===========================================================================

  /// Fetches all invoices and their items for the given pharmacy.
  Future<List<Map<String, dynamic>>> fetchInvoices(String pharmacyId) async {
    try {
      final response = await _client
          .from(SupabaseConstants.invoicesTable)
          .select('*, invoice_items(*)')
          .eq('pharmacy_id', pharmacyId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching invoices: $e');
      rethrow;
    }
  }

  /// Searches customers across both in-memory loaded invoices and the database customers table.
  Future<List<Map<String, dynamic>>> searchCustomers({
    required String pharmacyId,
    required String query,
    required List<Map<String, dynamic>> loadedInvoices,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    final List<Map<String, dynamic>> combined = [];
    final Set<String> seen = {};

    // 1. Match from loaded invoices
    for (final inv in loadedInvoices) {
      final cName = (inv['customer_name'] ?? '').toString().trim();
      final cPhone = (inv['customer_phone'] ?? '').toString().trim();
      final disp = cPhone.isNotEmpty ? '$cName ($cPhone)' : cName;
      if ((cName.toLowerCase().contains(q) || cPhone.toLowerCase().contains(q)) &&
          !seen.contains(disp)) {
        seen.add(disp);
        combined.add({
          'id': inv['customer_id'],
          'name': disp,
          'raw_name': cName,
          'phone': cPhone,
        });
      }
    }

    // 2. Match from customers database table
    try {
      final res = await _client
          .from(SupabaseConstants.customersTable)
          .select('id, name, phone')
          .eq('pharmacy_id', pharmacyId)
          .or('name.ilike.%$q%,phone.ilike.%$q%')
          .limit(10);

      for (final e in (res as List)) {
        final name = (e['name'] ?? '').toString().trim();
        final phone = (e['phone'] ?? '').toString().trim();
        final disp = phone.isNotEmpty ? '$name ($phone)' : name;
        if (!seen.contains(disp)) {
          seen.add(disp);
          combined.add({
            'id': e['id'],
            'name': disp,
            'raw_name': name,
            'phone': phone,
          });
        }
      }
    } catch (e) {
      debugPrint('Error searching database customers table: $e');
    }

    return combined.take(12).toList();
  }

  /// Safely deletes an invoice, reversing sold quantities back into stock batches
  /// and adjusting customer balance.
  Future<void> deleteInvoiceWithReversal({
    required String invoiceId,
    required String pharmacyId,
  }) async {
    try {
      // 1. Fetch invoice details with items
      final invRes = await _client
          .from(SupabaseConstants.invoicesTable)
          .select('*, invoice_items(*)')
          .eq('id', invoiceId)
          .single();

      final items = List<Map<String, dynamic>>.from(invRes['invoice_items'] ?? []);

      // 2. Return sold quantities back to batches
      for (final item in items) {
        final batchId = item['batch_id']?.toString();
        final qty = (item['quantity'] as num?)?.toInt() ?? 0;

        if (batchId != null && batchId.isNotEmpty && qty > 0) {
          try {
            final bRes = await _client
                .from(SupabaseConstants.batchesTable)
                .select('stock_quantity')
                .eq('id', batchId)
                .maybeSingle();

            if (bRes != null) {
              final currentStock = (bRes['stock_quantity'] as num?)?.toInt() ?? 0;
              await _client
                  .from(SupabaseConstants.batchesTable)
                  .update({'stock_quantity': currentStock + qty})
                  .eq('id', batchId);
            }
          } catch (e) {
            debugPrint('Warning returning stock for batch $batchId: $e');
          }
        }
      }

      // 3. Reverse customer balance if due existed
      final customerId = invRes['customer_id']?.toString();
      final dueAmount = (invRes['due_amount'] as num?)?.toDouble() ?? 0.0;
      if (customerId != null && customerId.isNotEmpty && dueAmount > 0.001) {
        try {
          final cRes = await _client
              .from(SupabaseConstants.customersTable)
              .select('balance')
              .eq('id', customerId)
              .maybeSingle();

          if (cRes != null) {
            final currentBalance = (cRes['balance'] as num?)?.toDouble() ?? 0.0;
            final newBalance = (currentBalance - dueAmount).clamp(0.0, double.infinity);
            await _client
                .from(SupabaseConstants.customersTable)
                .update({'balance': newBalance})
                .eq('id', customerId);
          }
        } catch (e) {
          debugPrint('Warning reversing customer balance for $customerId: $e');
        }
      }

      // 4. Delete invoice items then invoice
      await _client
          .from(SupabaseConstants.invoiceItemsTable)
          .delete()
          .eq('invoice_id', invoiceId);

      await _client
          .from(SupabaseConstants.invoicesTable)
          .delete()
          .eq('id', invoiceId);
    } catch (e) {
      debugPrint('Error in deleteInvoiceWithReversal: $e');
      rethrow;
    }
  }

  // ===========================================================================
  // IMPORT / PURCHASE HISTORY
  // ===========================================================================

  /// Fetches all purchases and their items for the given pharmacy.
  Future<List<Map<String, dynamic>>> fetchPurchases(String pharmacyId) async {
    try {
      final response = await _client
          .from(SupabaseConstants.purchasesTable)
          .select('*, purchase_items(*)')
          .eq('pharmacy_id', pharmacyId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching purchases: $e');
      rethrow;
    }
  }

  /// Searches companies across loaded purchases, local medicines, suppliers, and global medicines.
  Future<List<Map<String, dynamic>>> searchCompanies({
    required String pharmacyId,
    required String query,
    required List<Map<String, dynamic>> loadedPurchases,
    required List<MedicineModel> localMedicines,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    final List<Map<String, dynamic>> combined = [];
    final Set<String> seen = {};

    // 1. From loaded purchase history records
    for (final pur in loadedPurchases) {
      final sName = (pur['supplier_name'] ?? '').toString().trim();
      final suppId = pur['supplier_id']?.toString();
      if (sName.toLowerCase().contains(q) && !seen.contains(sName.toLowerCase())) {
        seen.add(sName.toLowerCase());
        combined.add({'id': suppId, 'name': sName, 'raw_name': sName});
      }
    }

    // 2. From local pharmacy inventory
    for (final med in localMedicines) {
      final cName = (med.company ?? '').trim();
      if (cName.toLowerCase().contains(q) && !seen.contains(cName.toLowerCase())) {
        seen.add(cName.toLowerCase());
        combined.add({'id': null, 'name': cName, 'raw_name': cName});
      }
    }

    // 3. From suppliers table in Supabase
    try {
      final sRes = await _client
          .from(SupabaseConstants.suppliersTable)
          .select('id, name, company_name')
          .eq('pharmacy_id', pharmacyId)
          .or('company_name.ilike.%$q%,name.ilike.%$q%')
          .limit(10);

      for (final e in (sRes as List)) {
        final cName = (e['company_name'] ?? e['name'] ?? '').toString().trim();
        if (cName.isNotEmpty && !seen.contains(cName.toLowerCase())) {
          seen.add(cName.toLowerCase());
          combined.add({'id': e['id']?.toString(), 'name': cName, 'raw_name': cName});
        }
      }
    } catch (e) {
      debugPrint('Warning searching suppliers table: $e');
    }

    // 4. From global_medicines table
    try {
      final gmRes = await _client
          .from(SupabaseConstants.globalMedicinesTable)
          .select('company')
          .ilike('company', '%$q%')
          .limit(10);

      for (final gm in (gmRes as List)) {
        final comp = gm['company']?.toString().trim();
        if (comp != null && comp.isNotEmpty && !seen.contains(comp.toLowerCase())) {
          seen.add(comp.toLowerCase());
          combined.add({'id': null, 'name': comp, 'raw_name': comp});
        }
      }
    } catch (e) {
      debugPrint('Warning searching global medicines: $e');
    }

    return combined.take(12).toList();
  }

  /// Records an incremental payment against an existing purchase bill.
  Future<void> recordPurchasePayment({
    required String purchaseId,
    required double paymentAmount,
    required String paymentMethod,
    String? note,
  }) async {
    try {
      // 1. Get current purchase numbers
      final pRes = await _client
          .from(SupabaseConstants.purchasesTable)
          .select('grand_total, paid_amount, due_amount, supplier_id, pharmacy_id')
          .eq('id', purchaseId)
          .single();

      final grandTotal = (pRes['grand_total'] as num?)?.toDouble() ?? 0.0;
      final currentPaid = (pRes['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final newPaid = currentPaid + paymentAmount;
      final newDue = (grandTotal - newPaid).clamp(0.0, double.infinity);
      final suppId = pRes['supplier_id']?.toString();
      final pharmId = pRes['pharmacy_id']?.toString();

      // 2. Update purchase record
      await _client.from(SupabaseConstants.purchasesTable).update({
        'paid_amount': newPaid,
        'due_amount': newDue,
        'payment_method': paymentMethod,
      }).eq('id', purchaseId);

      // 3. Also update supplier current_due & supplier_ledgers for two-way sync
      if (suppId != null && suppId.isNotEmpty) {
        try {
          final sRes = await _client
              .from(SupabaseConstants.suppliersTable)
              .select('current_due')
              .eq('id', suppId)
              .maybeSingle();

          if (sRes != null) {
            final sDue = (sRes['current_due'] as num?)?.toDouble() ?? 0.0;
            final updatedSDue = (sDue - paymentAmount).clamp(0.0, double.infinity);
            await _client
                .from(SupabaseConstants.suppliersTable)
                .update({'current_due': updatedSDue})
                .eq('id', suppId);

            if (pharmId != null && pharmId.isNotEmpty) {
              await _client.from(SupabaseConstants.supplierLedgersTable).insert({
                'pharmacy_id': pharmId,
                'supplier_id': suppId,
                'entry_type': 'payment_made',
                'debit': paymentAmount,
                'credit': 0,
                'balance': updatedSDue,
                'payment_method': paymentMethod,
                'notes': 'Purchase bill payment (History)',
              });
            }
          }
        } catch (e) {
          debugPrint('Warning syncing supplier current_due from purchase payment: $e');
        }
      }
    } catch (e) {
      debugPrint('Error recording purchase payment: $e');
      rethrow;
    }
  }

  /// Validates whether a purchase can be safely deleted (fails if any items have already been sold in POS),
  /// and deletes it along with its batches and items.
  Future<void> deletePurchaseWithValidation({
    required String purchaseId,
    required String pharmacyId,
  }) async {
    try {
      // 1. Fetch purchase items
      final purRes = await _client
          .from(SupabaseConstants.purchasesTable)
          .select('*, purchase_items(*)')
          .eq('id', purchaseId)
          .single();

      final items = List<Map<String, dynamic>>.from(purRes['purchase_items'] ?? []);

      // 2. Check if any batches were sold
      for (final item in items) {
        final batchId = item['batch_id']?.toString();
        final purQty = (item['quantity'] as num?)?.toInt() ?? 0;

        if (batchId != null && batchId.isNotEmpty) {
          final bRes = await _client
              .from(SupabaseConstants.batchesTable)
              .select('stock_quantity')
              .eq('id', batchId)
              .maybeSingle();

          if (bRes != null) {
            final currentStock = (bRes['stock_quantity'] as num?)?.toInt() ?? 0;
            if (currentStock < purQty) {
              throw Exception(
                'Items from this purchase have already been sold to customers in POS sales. '
                'Deleting this purchase would cause negative inventory.',
              );
            }
          }
        }
      }

      // 3. Remove batches created by this purchase
      for (final item in items) {
        final batchId = item['batch_id']?.toString();
        if (batchId != null && batchId.isNotEmpty) {
          await _client
              .from(SupabaseConstants.batchesTable)
              .delete()
              .eq('id', batchId);
        }
      }

      // 4. Delete purchase items then purchase
      await _client
          .from(SupabaseConstants.purchaseItemsTable)
          .delete()
          .eq('purchase_id', purchaseId);

      await _client
          .from(SupabaseConstants.purchasesTable)
          .delete()
          .eq('id', purchaseId);
    } catch (e) {
      debugPrint('Error in deletePurchaseWithValidation: $e');
      rethrow;
    }
  }
}
