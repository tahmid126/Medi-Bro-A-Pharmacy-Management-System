import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/supabase_constants.dart';
import '../models/invoice_model.dart';
import 'supabase_service.dart';

class PosService {
  final SupabaseClient _client = SupabaseService.instance.client;

  Future<Map<String, dynamic>> submitSale({
    String? customerId,
    String? customerName,
    String? customerPhone,
    required double subtotal,
    String discountType = 'fixed',
    double discountAmount = 0.0,
    double vatPercent = 0.0,
    double vatAmount = 0.0,
    required double grandTotal,
    required double paidAmount,
    required double dueAmount,
    required String paymentMethod,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    final response = await _client.rpc(
      'process_pos_sale',
      params: {
        'p_customer_id': customerId,
        'p_customer_name': customerName ?? 'Walking Customer',
        'p_customer_phone': customerPhone,
        'p_subtotal': subtotal,
        'p_discount_type': discountType,
        'p_discount_amount': discountAmount,
        'p_vat_percent': vatPercent,
        'p_vat_amount': vatAmount,
        'p_grand_total': grandTotal,
        'p_paid_amount': paidAmount,
        'p_due_amount': dueAmount,
        'p_payment_method': paymentMethod,
        'p_notes': notes,
        'p_items': items,
      },
    );

    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> recordSale({
    required String pharmacyId,
    String? customerId,
    String? customerName,
    String? customerPhone,
    required double subtotal,
    String discountType = 'fixed',
    double discountAmount = 0.0,
    double vatPercent = 0.0,
    double vatAmount = 0.0,
    required double grandTotal,
    required double paidAmount,
    required double dueAmount,
    String paymentMethod = 'cash',
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    final invoiceNo = 'INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

    // 0. Auto-resolve customer if customerId is missing
    if ((customerId == null || customerId.isEmpty) &&
        customerName != null &&
        customerName.trim().isNotEmpty &&
        customerName.trim().toLowerCase() != 'walking customer') {
      final existingCust = await _client
          .from(SupabaseConstants.customersTable)
          .select('id')
          .eq('pharmacy_id', pharmacyId)
          .ilike('name', customerName.trim())
          .maybeSingle();

      if (existingCust != null) {
        customerId = existingCust['id']?.toString();
      } else if (dueAmount > 0.001) {
        final newCust = await _client.from(SupabaseConstants.customersTable).insert({
          'pharmacy_id': pharmacyId,
          'name': customerName.trim(),
          'phone': customerPhone,
          'current_due': 0.0,
          'total_purchased': 0.0,
        }).select('id').single();
        customerId = newCust['id']?.toString();
      }
    }

    // 1. Insert Invoice
    final invoiceData = await _client.from(SupabaseConstants.invoicesTable).insert({
      'pharmacy_id': pharmacyId,
      'invoice_number': invoiceNo,
      'customer_id': customerId,
      'customer_name': customerName ?? 'Walking Customer',
      'customer_phone': customerPhone,
      'subtotal': subtotal,
      'discount_type': discountType,
      'discount_amount': discountAmount,
      'vat_percent': vatPercent,
      'vat_amount': vatAmount,
      'grand_total': grandTotal,
      'paid_amount': paidAmount,
      'due_amount': dueAmount,
      'payment_method': paymentMethod,
      'notes': notes,
      'status': 'completed',
    }).select().single();

    final invoiceId = invoiceData['id'] as String;

    // 2. Insert items and decrement stock from batches
    for (var item in items) {
      final medicineId = item['medicine_id'] as String;
      final batchId = item['batch_id'] as String?;
      final quantity = (item['quantity'] as num).toInt();
      final unitPrice = (item['unit_price'] as num).toDouble();
      final mrp = (item['mrp'] as num?)?.toDouble() ?? unitPrice;
      final purchasePrice = (item['purchase_price'] as num?)?.toDouble() ?? 0.0;
      final totalPrice = (item['total_price'] as num?)?.toDouble() ?? (unitPrice * quantity);
      final medicineName = (item['medicine_name'] ?? '').toString();
      final batchNumber = item['batch_number'] as String?;
      final expiryDate = item['expiry_date'];

      String finalBatchId = batchId ?? '';
      if (finalBatchId.isNotEmpty) {
        final existingBatch = await _client
            .from(SupabaseConstants.batchesTable)
            .select()
            .eq('id', finalBatchId)
            .maybeSingle();

        if (existingBatch != null) {
          final currentQty = (existingBatch['stock_qty'] as num?)?.toInt() ?? 0;
          await _client.from(SupabaseConstants.batchesTable).update({
            'stock_qty': (currentQty - quantity).clamp(0, 999999),
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', finalBatchId);
        }
      } else {
        final firstBatch = await _client
            .from(SupabaseConstants.batchesTable)
            .select()
            .eq('pharmacy_id', pharmacyId)
            .eq('medicine_id', medicineId)
            .order('stock_qty', ascending: false)
            .limit(1)
            .maybeSingle();
        if (firstBatch != null) {
          finalBatchId = firstBatch['id'] as String;
          final currentQty = (firstBatch['stock_qty'] as num?)?.toInt() ?? 0;
          await _client.from(SupabaseConstants.batchesTable).update({
            'stock_qty': (currentQty - quantity).clamp(0, 999999),
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', finalBatchId);
        }
      }

      await _client.from(SupabaseConstants.invoiceItemsTable).insert({
        'pharmacy_id': pharmacyId,
        'invoice_id': invoiceId,
        'medicine_id': medicineId,
        'batch_id': finalBatchId.isNotEmpty ? finalBatchId : null,
        'medicine_name': medicineName,
        'batch_number': batchNumber,
        'expiry_date': expiryDate,
        'quantity': quantity,
        'unit_price': unitPrice,
        'mrp': mrp,
        'purchase_price': purchasePrice,
        'total_price': totalPrice,
      });
    }

    // 3. Update Customer balance if customerId exists
    if (customerId != null && customerId.isNotEmpty) {
      try {
        final customer = await _client
            .from(SupabaseConstants.customersTable)
            .select()
            .eq('id', customerId)
            .maybeSingle();

        if (customer != null) {
          final currentDue = (customer['current_due'] as num?)?.toDouble() ?? 0.0;
          final totalPurchased = (customer['total_purchased'] as num?)?.toDouble() ?? 0.0;
          
          // Customer owed: currentDue + grandTotal of this sale
          // Customer paid: paidAmount at counter
          final rawNewDue = currentDue + grandTotal - paidAmount;
          final newDue = rawNewDue > 0.001 ? rawNewDue : 0.0;
          final newTotalPurchased = totalPurchased + grandTotal;

          await _client.from(SupabaseConstants.customersTable).update({
            'current_due': newDue,
            'total_purchased': newTotalPurchased,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', customerId);

          // Always record sale ledger entry for customer
          await _client.from(SupabaseConstants.customerLedgersTable).insert({
            'pharmacy_id': pharmacyId,
            'customer_id': customerId,
            'invoice_id': invoiceId,
            'entry_type': 'sale_invoice',
            'debit': grandTotal,
            'credit': paidAmount,
            'balance': newDue,
            'payment_method': paymentMethod,
            'notes': 'Invoice #$invoiceNo (Total: ৳${grandTotal.toStringAsFixed(2)}, Paid: ৳${paidAmount.toStringAsFixed(2)}, New Due: ৳${newDue.toStringAsFixed(2)})',
          });
        }
      } catch (e) {
        // Customer ledger error caught gracefully
      }
    }

    return invoiceData;
  }

  Future<List<InvoiceModel>> fetchInvoices({int limit = 50}) async {
    final data = await _client
        .from(SupabaseConstants.invoicesTable)
        .select('*, invoice_items(*)')
        .order('created_at', ascending: false)
        .limit(limit);

    return (data as List).map((json) {
      final items = (json['invoice_items'] as List?)
              ?.map((i) => InvoiceItemModel.fromJson(i))
              .toList() ??
          [];
      return InvoiceModel.fromJson(json, items: items);
    }).toList();
  }

  /// Cancel and reverse a sale invoice (Return/Cancel).
  /// Re-credits stock to batches, adjusts customer current_due & total_purchased,
  /// records a ledger reversal, and marks the invoice as cancelled (or permanently deletes it).
  Future<void> cancelOrDeleteSaleInvoice(
    String invoiceId, {
    bool permanentDelete = false,
  }) async {
    // 1. Fetch invoice with items
    final invoiceData = await _client
        .from(SupabaseConstants.invoicesTable)
        .select('*, invoice_items(*)')
        .eq('id', invoiceId)
        .maybeSingle();

    if (invoiceData == null) {
      throw Exception('Invoice not found: $invoiceId');
    }

    final String pharmacyId = invoiceData['pharmacy_id']?.toString() ?? '';
    final String invoiceNo = invoiceData['invoice_number']?.toString() ?? '';
    final String? customerId = invoiceData['customer_id']?.toString();
    final double grandTotal = (invoiceData['grand_total'] as num?)?.toDouble() ?? 0.0;
    final double paidAmount = (invoiceData['paid_amount'] as num?)?.toDouble() ?? 0.0;
    final double dueAmount = (invoiceData['due_amount'] as num?)?.toDouble() ?? (grandTotal - paidAmount);
    final List<dynamic> items = invoiceData['invoice_items'] as List? ?? [];

    // 2. Re-credit stock for all sold items
    for (var item in items) {
      final String? batchId = item['batch_id']?.toString();
      final int qty = (item['quantity'] as num?)?.toInt() ?? 0;

      if (batchId != null && batchId.isNotEmpty && qty > 0) {
        final batch = await _client
            .from(SupabaseConstants.batchesTable)
            .select()
            .eq('id', batchId)
            .maybeSingle();

        if (batch != null) {
          final int currentStock = (batch['stock_qty'] as num?)?.toInt() ?? 0;
          await _client.from(SupabaseConstants.batchesTable).update({
            'stock_qty': currentStock + qty,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', batchId);
        }
      }
    }

    // 3. Reconcile Customer due & ledger
    if (customerId != null && customerId.isNotEmpty) {
      try {
        final customer = await _client
            .from(SupabaseConstants.customersTable)
            .select()
            .eq('id', customerId)
            .maybeSingle();

        if (customer != null) {
          final double currentDue = (customer['current_due'] as num?)?.toDouble() ?? 0.0;
          final double totalPurchased = (customer['total_purchased'] as num?)?.toDouble() ?? 0.0;

          // Deduct this invoice's due from customer's current_due
          final double newDue = (currentDue - dueAmount) > 0.001 ? (currentDue - dueAmount) : 0.0;
          final double newTotalPurchased = (totalPurchased - grandTotal) > 0.001 ? (totalPurchased - grandTotal) : 0.0;

          await _client.from(SupabaseConstants.customersTable).update({
            'current_due': newDue,
            'total_purchased': newTotalPurchased,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', customerId);

          // Add reversal record in customer_ledgers
          await _client.from(SupabaseConstants.customerLedgersTable).insert({
            'pharmacy_id': pharmacyId,
            'customer_id': customerId,
            'invoice_id': invoiceId,
            'entry_type': 'invoice_cancelled',
            'debit': 0.0,
            'credit': dueAmount,
            'balance': newDue,
            'notes': 'Invoice #$invoiceNo Cancelled/Returned - Due reversed (৳${dueAmount.toStringAsFixed(2)})',
          });
        }
      } catch (e) {
        debugPrint('Customer balance reversal notice: $e');
      }
    }

    // 4. Update status or permanent delete
    if (permanentDelete) {
      await _client
          .from(SupabaseConstants.invoiceItemsTable)
          .delete()
          .eq('invoice_id', invoiceId);
      await _client
          .from(SupabaseConstants.invoicesTable)
          .delete()
          .eq('id', invoiceId);
    } else {
      await _client.from(SupabaseConstants.invoicesTable).update({
        'status': 'cancelled',
        'notes': 'Invoice cancelled & stock returned at ${DateTime.now().toIso8601String()}',
      }).eq('id', invoiceId);
    }
  }

  /// Update invoice details (customer, discount, paid amount, notes)
  Future<void> updateSaleInvoice({
    required String invoiceId,
    String? customerId,
    String? customerName,
    String? customerPhone,
    required double grandTotal,
    required double paidAmount,
    required double dueAmount,
    String? discountType,
    double? discountAmount,
    String? notes,
  }) async {
    final oldInvoice = await _client
        .from(SupabaseConstants.invoicesTable)
        .select()
        .eq('id', invoiceId)
        .maybeSingle();

    if (oldInvoice == null) throw Exception('Invoice not found: $invoiceId');

    final String? oldCustomerId = oldInvoice['customer_id']?.toString();
    final double oldDue = (oldInvoice['due_amount'] as num?)?.toDouble() ?? 0.0;
    final double oldGrandTotal = (oldInvoice['grand_total'] as num?)?.toDouble() ?? 0.0;

    // Update invoice record
    await _client.from(SupabaseConstants.invoicesTable).update({
      'customer_id': customerId,
      'customer_name': customerName ?? 'Walking Customer',
      'customer_phone': customerPhone,
      'grand_total': grandTotal,
      'paid_amount': paidAmount,
      'due_amount': dueAmount,
      if (discountType != null) 'discount_type': discountType,
      if (discountAmount != null) 'discount_amount': discountAmount,
      if (notes != null) 'notes': notes,
      'status': dueAmount <= 0.001 ? 'completed' : 'partial',
    }).eq('id', invoiceId);

    // Reconcile customer if customer changed or due amount changed
    if (oldCustomerId != null && oldCustomerId != customerId) {
      // 1. Revert from old customer
      final oldCust = await _client
          .from(SupabaseConstants.customersTable)
          .select()
          .eq('id', oldCustomerId)
          .maybeSingle();
      if (oldCust != null) {
        final curDue = (oldCust['current_due'] as num?)?.toDouble() ?? 0.0;
        final curTotal = (oldCust['total_purchased'] as num?)?.toDouble() ?? 0.0;
        await _client.from(SupabaseConstants.customersTable).update({
          'current_due': (curDue - oldDue).clamp(0.0, 9999999.0),
          'total_purchased': (curTotal - oldGrandTotal).clamp(0.0, 9999999.0),
        }).eq('id', oldCustomerId);
      }

      // 2. Add to new customer
      if (customerId != null && customerId.isNotEmpty) {
        final newCust = await _client
            .from(SupabaseConstants.customersTable)
            .select()
            .eq('id', customerId)
            .maybeSingle();
        if (newCust != null) {
          final curDue = (newCust['current_due'] as num?)?.toDouble() ?? 0.0;
          final curTotal = (newCust['total_purchased'] as num?)?.toDouble() ?? 0.0;
          await _client.from(SupabaseConstants.customersTable).update({
            'current_due': curDue + dueAmount,
            'total_purchased': curTotal + grandTotal,
          }).eq('id', customerId);
        }
      }
    } else if (customerId != null && customerId.isNotEmpty) {
      // Same customer, due changed
      final dueDelta = dueAmount - oldDue;
      final totalDelta = grandTotal - oldGrandTotal;
      if (dueDelta.abs() > 0.001 || totalDelta.abs() > 0.001) {
        final cust = await _client
            .from(SupabaseConstants.customersTable)
            .select()
            .eq('id', customerId)
            .maybeSingle();
        if (cust != null) {
          final curDue = (cust['current_due'] as num?)?.toDouble() ?? 0.0;
          final curTotal = (cust['total_purchased'] as num?)?.toDouble() ?? 0.0;
          await _client.from(SupabaseConstants.customersTable).update({
            'current_due': (curDue + dueDelta).clamp(0.0, 9999999.0),
            'total_purchased': (curTotal + totalDelta).clamp(0.0, 9999999.0),
          }).eq('id', customerId);
        }
      }
    }
  }

  Future<Map<String, dynamic>?> fetchInvoiceById(String invoiceId) async {
    final data = await _client
        .from(SupabaseConstants.invoicesTable)
        .select('*, invoice_items(*)')
        .eq('id', invoiceId)
        .maybeSingle();
    return data;
  }

  Future<void> updateSaleInvoiceWithItems({
    required String invoiceId,
    String? customerId,
    String? customerName,
    String? customerPhone,
    required double subtotal,
    String discountType = 'fixed',
    double discountAmount = 0.0,
    double vatPercent = 0.0,
    double vatAmount = 0.0,
    required double grandTotal,
    required double paidAmount,
    required double dueAmount,
    String paymentMethod = 'cash',
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    final oldInvoice = await _client
        .from(SupabaseConstants.invoicesTable)
        .select('*, invoice_items(*)')
        .eq('id', invoiceId)
        .maybeSingle();

    if (oldInvoice == null) throw Exception('Invoice not found: ');

    final String pharmacyId = oldInvoice['pharmacy_id']?.toString() ?? '';
    final String? oldCustomerId = oldInvoice['customer_id']?.toString();
    final double oldDue = (oldInvoice['due_amount'] as num?)?.toDouble() ?? 0.0;
    final double oldGrandTotal = (oldInvoice['grand_total'] as num?)?.toDouble() ?? 0.0;
    final List<dynamic> oldItems = oldInvoice['invoice_items'] as List? ?? [];

    // Auto-resolve customer if customerId is missing
    if ((customerId == null || customerId.isEmpty) &&
        customerName != null &&
        customerName.trim().isNotEmpty &&
        customerName.trim().toLowerCase() != 'walking customer') {
      final existingCust = await _client
          .from(SupabaseConstants.customersTable)
          .select('id')
          .eq('pharmacy_id', pharmacyId)
          .ilike('name', customerName.trim())
          .maybeSingle();

      if (existingCust != null) {
        customerId = existingCust['id']?.toString();
      } else if (dueAmount > 0.001) {
        final newCust = await _client.from(SupabaseConstants.customersTable).insert({
          'pharmacy_id': pharmacyId,
          'name': customerName.trim(),
          'phone': customerPhone,
          'current_due': 0.0,
          'total_purchased': 0.0,
        }).select('id').single();
        customerId = newCust['id']?.toString();
      }
    }

    for (var oi in oldItems) {
      final String? batchId = oi['batch_id']?.toString();
      final int qty = (oi['quantity'] as num?)?.toInt() ?? 0;
      if (batchId != null && batchId.isNotEmpty && qty > 0) {
        final batch = await _client
            .from(SupabaseConstants.batchesTable)
            .select()
            .eq('id', batchId)
            .maybeSingle();
        if (batch != null) {
          final int currentStock = (batch['stock_qty'] as num?)?.toInt() ?? 0;
          await _client.from(SupabaseConstants.batchesTable).update({
            'stock_qty': currentStock + qty,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', batchId);
        }
      }
    }

    await _client.from(SupabaseConstants.invoiceItemsTable).delete().eq('invoice_id', invoiceId);

    for (var item in items) {
      final medicineId = item['medicine_id'] as String;
      final batchId = item['batch_id'] as String?;
      final quantity = (item['quantity'] as num).toInt();
      final unitPrice = (item['unit_price'] as num).toDouble();
      final mrp = (item['mrp'] as num?)?.toDouble() ?? unitPrice;
      final purchasePrice = (item['purchase_price'] as num?)?.toDouble() ?? 0.0;
      final totalPrice = (item['total_price'] as num?)?.toDouble() ?? (unitPrice * quantity);
      final medicineName = (item['medicine_name'] ?? '').toString();
      final batchNumber = item['batch_number'] as String?;
      final expiryDate = item['expiry_date'];

      String finalBatchId = batchId ?? '';
      if (finalBatchId.isNotEmpty) {
        final existingBatch = await _client
            .from(SupabaseConstants.batchesTable)
            .select()
            .eq('id', finalBatchId)
            .maybeSingle();

        if (existingBatch != null) {
          final currentQty = (existingBatch['stock_qty'] as num?)?.toInt() ?? 0;
          await _client.from(SupabaseConstants.batchesTable).update({
            'stock_qty': (currentQty - quantity).clamp(0, 999999),
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', finalBatchId);
        }
      } else {
        final firstBatch = await _client
            .from(SupabaseConstants.batchesTable)
            .select()
            .eq('pharmacy_id', pharmacyId)
            .eq('medicine_id', medicineId)
            .order('stock_qty', ascending: false)
            .limit(1)
            .maybeSingle();
        if (firstBatch != null) {
          finalBatchId = firstBatch['id'] as String;
          final currentQty = (firstBatch['stock_qty'] as num?)?.toInt() ?? 0;
          await _client.from(SupabaseConstants.batchesTable).update({
            'stock_qty': (currentQty - quantity).clamp(0, 999999),
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', finalBatchId);
        }
      }

      await _client.from(SupabaseConstants.invoiceItemsTable).insert({
        'pharmacy_id': pharmacyId,
        'invoice_id': invoiceId,
        'medicine_id': medicineId,
        'batch_id': finalBatchId.isNotEmpty ? finalBatchId : null,
        'medicine_name': medicineName,
        'batch_number': batchNumber,
        'expiry_date': expiryDate,
        'quantity': quantity,
        'unit_price': unitPrice,
        'mrp': mrp,
        'purchase_price': purchasePrice,
        'total_price': totalPrice,
      });
    }

    await _client.from(SupabaseConstants.invoicesTable).update({
      'customer_id': customerId,
      'customer_name': customerName ?? 'Walking Customer',
      'customer_phone': customerPhone,
      'subtotal': subtotal,
      'discount_type': discountType,
      'discount_amount': discountAmount,
      'vat_percent': vatPercent,
      'vat_amount': vatAmount,
      'grand_total': grandTotal,
      'paid_amount': paidAmount,
      'due_amount': dueAmount,
      'payment_method': paymentMethod,
      'notes': notes,
      'status': dueAmount <= 0.001 ? 'completed' : 'partial',
    }).eq('id', invoiceId);

    if (oldCustomerId != null && oldCustomerId != customerId) {
      final oldCust = await _client
          .from(SupabaseConstants.customersTable)
          .select()
          .eq('id', oldCustomerId)
          .maybeSingle();
      if (oldCust != null) {
        final curDue = (oldCust['current_due'] as num?)?.toDouble() ?? 0.0;
        final curTotal = (oldCust['total_purchased'] as num?)?.toDouble() ?? 0.0;
        await _client.from(SupabaseConstants.customersTable).update({
          'current_due': (curDue - oldDue).clamp(0.0, 9999999.0),
          'total_purchased': (curTotal - oldGrandTotal).clamp(0.0, 9999999.0),
        }).eq('id', oldCustomerId);
      }

      if (customerId != null && customerId.isNotEmpty) {
        final newCust = await _client
            .from(SupabaseConstants.customersTable)
            .select()
            .eq('id', customerId)
            .maybeSingle();
        if (newCust != null) {
          final curDue = (newCust['current_due'] as num?)?.toDouble() ?? 0.0;
          final curTotal = (newCust['total_purchased'] as num?)?.toDouble() ?? 0.0;
          await _client.from(SupabaseConstants.customersTable).update({
            'current_due': curDue + dueAmount,
            'total_purchased': curTotal + grandTotal,
          }).eq('id', customerId);
        }
      }
    } else if (customerId != null && customerId.isNotEmpty) {
      final dueDelta = dueAmount - oldDue;
      final totalDelta = grandTotal - oldGrandTotal;
      final cust = await _client
          .from(SupabaseConstants.customersTable)
          .select()
          .eq('id', customerId)
          .maybeSingle();
      if (cust != null) {
        final curDue = (cust['current_due'] as num?)?.toDouble() ?? 0.0;
        final curTotal = (cust['total_purchased'] as num?)?.toDouble() ?? 0.0;
        await _client.from(SupabaseConstants.customersTable).update({
          'current_due': (curDue + dueDelta).clamp(0.0, 9999999.0),
          'total_purchased': (curTotal + totalDelta).clamp(0.0, 9999999.0),
        }).eq('id', customerId);
      }
    }
  }

}
