import '../../core/constants/supabase_constants.dart';
import 'supabase_service.dart';

class DueService {
  static final _supabase = SupabaseService.instance.client;

  /// Fetch pending customer dues
  static Future<List<Map<String, dynamic>>> fetchCustomerDues({
    required String pharmacyId,
    String? filterId,
  }) async {
    var query = _supabase
        .from(SupabaseConstants.customersTable)
        .select('id, name, phone, current_due, total_purchased')
        .eq('pharmacy_id', pharmacyId);

    if (filterId != null) {
      query = query.eq('id', filterId);
    } else {
      query = query.gt('current_due', 0.001);
    }

    final data = await query.order('current_due', ascending: false);
    final rows = List<Map<String, dynamic>>.from(data);

    final Map<String, Map<String, dynamic>> duesMap = {};
    for (final row in rows) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;

      final netDue = (row['current_due'] as num?)?.toDouble() ?? 0.0;
      if (netDue <= 0.001) continue;

      final totalPurchased = (row['total_purchased'] as num?)?.toDouble() ?? 0.0;
      final totalPaid = totalPurchased > netDue ? (totalPurchased - netDue) : 0.0;
      final totalBilled = totalPurchased > 0 ? totalPurchased : netDue + totalPaid;

      duesMap[id] = {
        'id': id,
        'name': row['name'] ?? 'Walking Customer',
        'phone': row['phone'] ?? '',
        'total_billed': totalBilled,
        'total_paid': totalPaid,
        'net_due': netDue,
      };
    }

    // Also include any invoices with due_amount > 0 that might not be in duesMap
    final Set<String> fromTableCustIds = duesMap.keys.toSet();
    try {
      var invQuery = _supabase
          .from(SupabaseConstants.invoicesTable)
          .select('id, customer_id, customer_name, customer_phone, grand_total, paid_amount, due_amount')
          .eq('pharmacy_id', pharmacyId)
          .gt('due_amount', 0.001);

      if (filterId != null) {
        invQuery = invQuery.eq('customer_id', filterId);
      }

      final invData = await invQuery;
      for (final inv in invData) {
        final cid = inv['customer_id']?.toString();
        final invDue = (inv['due_amount'] as num?)?.toDouble() ?? 0.0;
        if (invDue <= 0.001) continue;

        if (cid != null && fromTableCustIds.contains(cid)) {
          // Already counted through customer's current_due from table
          continue;
        }

        final key = (cid != null && cid.isNotEmpty) ? cid : ('inv_${inv['id']}');
        final name = (inv['customer_name']?.toString().trim().isNotEmpty == true)
            ? inv['customer_name'].toString().trim()
            : 'Walking Customer';
        final phone = inv['customer_phone']?.toString() ?? '';
        final grandTotal = (inv['grand_total'] as num?)?.toDouble() ?? invDue;
        final paid = (inv['paid_amount'] as num?)?.toDouble() ?? 0.0;

        if (duesMap.containsKey(key)) {
          final existing = duesMap[key]!;
          existing['net_due'] = (existing['net_due'] as double) + invDue;
          existing['total_billed'] = (existing['total_billed'] as double) + grandTotal;
          existing['total_paid'] = (existing['total_paid'] as double) + paid;
        } else {
          duesMap[key] = {
            'id': key,
            'name': name,
            'phone': phone,
            'total_billed': grandTotal,
            'total_paid': paid,
            'net_due': invDue,
          };
        }
      }
    } catch (_) {}

    final result = duesMap.values.toList();
    result.sort((a, b) => ((b['net_due'] as num?)?.toDouble() ?? 0.0).compareTo((a['net_due'] as num?)?.toDouble() ?? 0.0));
    return result;
  }

  /// Fetch pending supplier dues
  static Future<List<Map<String, dynamic>>> fetchSupplierDues({
    required String pharmacyId,
    String? filterId,
  }) async {
    var query = _supabase
        .from(SupabaseConstants.suppliersTable)
        .select('id, name, company_name, phone, current_due')
        .eq('pharmacy_id', pharmacyId);

    if (filterId != null) {
      query = query.eq('id', filterId);
    } else {
      query = query.gt('current_due', 0.001);
    }

    final data = await query.order('current_due', ascending: false);
    final rows = List<Map<String, dynamic>>.from(data);

    final Map<String, Map<String, dynamic>> duesMap = {};
    for (final row in rows) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;

      final netDue = (row['current_due'] as num?)?.toDouble() ?? 0.0;
      if (netDue <= 0.001) continue;

      final name = (row['company_name'] as String?)?.trim().isNotEmpty == true
          ? row['company_name']
          : (row['name'] ?? 'Unknown Supplier');

      duesMap[id] = {
        'id': id,
        'name': name,
        'phone': row['phone'] ?? '',
        'total_billed': netDue,
        'total_paid': 0.0,
        'net_due': netDue,
      };
    }

    // Also include any purchases with due_amount > 0 that might not be in duesMap
    final Set<String> fromTableSuppIds = duesMap.keys.toSet();
    try {
      var purQuery = _supabase
          .from(SupabaseConstants.purchasesTable)
          .select('id, supplier_id, supplier_name, grand_total, paid_amount, due_amount')
          .eq('pharmacy_id', pharmacyId)
          .gt('due_amount', 0.001);

      if (filterId != null) {
        purQuery = purQuery.eq('supplier_id', filterId);
      }

      final purData = await purQuery;
      for (final pur in purData) {
        final sid = pur['supplier_id']?.toString();
        final purDue = (pur['due_amount'] as num?)?.toDouble() ?? 0.0;
        if (purDue <= 0.001) continue;

        if (sid != null && fromTableSuppIds.contains(sid)) {
          // Already counted through supplier's current_due from table
          continue;
        }

        final key = (sid != null && sid.isNotEmpty) ? sid : ('pur_${pur['id']}');
        final name = (pur['supplier_name']?.toString().trim().isNotEmpty == true)
            ? pur['supplier_name'].toString().trim()
            : 'Unknown Supplier';
        final grandTotal = (pur['grand_total'] as num?)?.toDouble() ?? purDue;
        final paid = (pur['paid_amount'] as num?)?.toDouble() ?? 0.0;

        if (duesMap.containsKey(key)) {
          final existing = duesMap[key]!;
          existing['net_due'] = (existing['net_due'] as double) + purDue;
          existing['total_billed'] = (existing['total_billed'] as double) + grandTotal;
          existing['total_paid'] = (existing['total_paid'] as double) + paid;
        } else {
          duesMap[key] = {
            'id': key,
            'name': name,
            'phone': '',
            'total_billed': grandTotal,
            'total_paid': paid,
            'net_due': purDue,
          };
        }
      }
    } catch (_) {}

    final result = duesMap.values.toList();
    result.sort((a, b) => ((b['net_due'] as num?)?.toDouble() ?? 0.0).compareTo((a['net_due'] as num?)?.toDouble() ?? 0.0));
    return result;
  }

  /// Search customer or supplier filter suggestions
  static Future<List<Map<String, dynamic>>> searchFilterEntities({
    required String pharmacyId,
    required String filterType,
    required String query,
  }) async {
    if (query.trim().isEmpty) return [];

    if (filterType == 'Customer') {
      final data = await _supabase
          .from(SupabaseConstants.customersTable)
          .select('id, name, phone')
          .eq('pharmacy_id', pharmacyId)
          .or('name.ilike.%$query%,phone.ilike.%$query%')
          .limit(10);
      return List<Map<String, dynamic>>.from(data);
    } else {
      final data = await _supabase
          .from(SupabaseConstants.suppliersTable)
          .select('id, name, company_name, phone')
          .eq('pharmacy_id', pharmacyId)
          .or('company_name.ilike.%$query%,name.ilike.%$query%,phone.ilike.%$query%')
          .limit(10);
      return List<Map<String, dynamic>>.from(data);
    }
  }

  /// Fetch pending and paid purchases for a supplier
  static Future<Map<String, List<Map<String, dynamic>>>> fetchSupplierBills({
    required String pharmacyId,
    required String supplierId,
  }) async {
    try {
      var query = _supabase
          .from(SupabaseConstants.purchasesTable)
          .select('id, purchase_number, grand_total, paid_amount, due_amount, created_at, purchase_date')
          .eq('pharmacy_id', pharmacyId);

      if (supplierId.startsWith('pur_')) {
        query = query.eq('id', supplierId.replaceFirst('pur_', ''));
      } else {
        query = query.eq('supplier_id', supplierId);
      }

      final data = await query.order('created_at', ascending: true);
      final list = List<Map<String, dynamic>>.from(data);

      final List<Map<String, dynamic>> pending = [];
      final List<Map<String, dynamic>> paid = [];

      for (final item in list) {
        final due = (item['due_amount'] as num?)?.toDouble() ?? 0.0;
        if (due > 0.001) {
          pending.add(item);
        } else {
          paid.add(item);
        }
      }

      // Order paid by created_at DESC (most recent first)
      paid.sort((a, b) {
        final aDate = a['created_at']?.toString() ?? '';
        final bDate = b['created_at']?.toString() ?? '';
        return bDate.compareTo(aDate);
      });

      return {
        'pending': pending,
        'paid': paid,
      };
    } catch (e) {
      return {'pending': [], 'paid': []};
    }
  }

  /// Fetch pending and paid invoices for a customer
  static Future<Map<String, List<Map<String, dynamic>>>> fetchCustomerBills({
    required String pharmacyId,
    required String customerId,
  }) async {
    try {
      var query = _supabase
          .from(SupabaseConstants.invoicesTable)
          .select('id, invoice_number, grand_total, paid_amount, due_amount, status, created_at')
          .eq('pharmacy_id', pharmacyId);

      if (customerId.startsWith('inv_')) {
        query = query.eq('id', customerId.replaceFirst('inv_', ''));
      } else {
        query = query.eq('customer_id', customerId);
      }

      final data = await query.order('created_at', ascending: true);
      final list = List<Map<String, dynamic>>.from(data);

      final List<Map<String, dynamic>> pending = [];
      final List<Map<String, dynamic>> paid = [];

      for (final item in list) {
        final due = (item['due_amount'] as num?)?.toDouble() ?? 0.0;
        if (due > 0.001) {
          pending.add(item);
        } else {
          paid.add(item);
        }
      }

      paid.sort((a, b) {
        final aDate = a['created_at']?.toString() ?? '';
        final bDate = b['created_at']?.toString() ?? '';
        return bDate.compareTo(aDate);
      });

      return {
        'pending': pending,
        'paid': paid,
      };
    } catch (e) {
      return {'pending': [], 'paid': []};
    }
  }

  /// Record due payment (updates current_due, ledger, and applies FIFO across selected invoices)
  static Future<void> recordDuePayment({
    required String pharmacyId,
    required String filterType,
    required String id,
    required double paying,
    required double netDue,
    List<String>? selectedInvoiceIds,
  }) async {
    final fallbackNewDue = (netDue - paying) > 0.001 ? (netDue - paying) : 0.0;

    if (id.startsWith('inv_')) {
      final invId = id.replaceFirst('inv_', '');
      final inv = await _supabase.from(SupabaseConstants.invoicesTable).select().eq('id', invId).maybeSingle();
      if (inv != null) {
        final currentPaid = (inv['paid_amount'] as num?)?.toDouble() ?? 0.0;
        final currentDue = (inv['due_amount'] as num?)?.toDouble() ?? 0.0;
        final updatedDue = (currentDue - paying) > 0.001 ? (currentDue - paying) : 0.0;
        await _supabase.from(SupabaseConstants.invoicesTable).update({
          'paid_amount': currentPaid + paying,
          'due_amount': updatedDue,
          'status': updatedDue <= 0.001 ? 'completed' : 'partial',
        }).eq('id', invId);
      }
      return;
    }

    if (id.startsWith('pur_')) {
      final purId = id.replaceFirst('pur_', '');
      final pur = await _supabase.from(SupabaseConstants.purchasesTable).select().eq('id', purId).maybeSingle();
      if (pur != null) {
        final currentPaid = (pur['paid_amount'] as num?)?.toDouble() ?? 0.0;
        final currentDue = (pur['due_amount'] as num?)?.toDouble() ?? 0.0;
        final updatedDue = (currentDue - paying) > 0.001 ? (currentDue - paying) : 0.0;
        await _supabase.from(SupabaseConstants.purchasesTable).update({
          'paid_amount': currentPaid + paying,
          'due_amount': updatedDue,
        }).eq('id', purId);
      }
      return;
    }

    if (filterType == 'Customer') {
      // 1. Allocate paying amount across customer invoices using FIFO
      double remainingPay = paying;
      try {
        var invQuery = _supabase
            .from(SupabaseConstants.invoicesTable)
            .select('id, grand_total, paid_amount, due_amount')
            .eq('pharmacy_id', pharmacyId)
            .eq('customer_id', id)
            .gt('due_amount', 0.001)
            .order('created_at', ascending: true);

        final invoices = await invQuery;
        for (final inv in invoices) {
          if (remainingPay <= 0.0001) break;
          final invId = inv['id']?.toString() ?? '';
          if (selectedInvoiceIds != null && selectedInvoiceIds.isNotEmpty && !selectedInvoiceIds.contains(invId)) {
            continue;
          }

          final curDue = (inv['due_amount'] as num?)?.toDouble() ?? 0.0;
          final curPaid = (inv['paid_amount'] as num?)?.toDouble() ?? 0.0;
          final payThis = remainingPay >= curDue ? curDue : remainingPay;

          final updatedDue = (curDue - payThis) > 0.001 ? (curDue - payThis) : 0.0;
          final updatedPaid = curPaid + payThis;

          await _supabase.from(SupabaseConstants.invoicesTable).update({
            'paid_amount': updatedPaid,
            'due_amount': updatedDue,
            'status': updatedDue <= 0.001 ? 'completed' : 'partial',
          }).eq('id', invId);

          remainingPay -= payThis;
        }
      } catch (_) {}

      // 2. Accurately recalculate customer's remaining due from all remaining unpaid invoices
      double finalCustomerDue = fallbackNewDue;
      try {
        final remainingInvoices = await _supabase
            .from(SupabaseConstants.invoicesTable)
            .select('due_amount')
            .eq('pharmacy_id', pharmacyId)
            .eq('customer_id', id)
            .gt('due_amount', 0.001);

        double sumDue = 0.0;
        for (final inv in (remainingInvoices as List)) {
          sumDue += (inv['due_amount'] as num?)?.toDouble() ?? 0.0;
        }
        finalCustomerDue = sumDue;
      } catch (_) {}

      // 3. Update customer current_due
      await _supabase
          .from(SupabaseConstants.customersTable)
          .update({'current_due': finalCustomerDue})
          .eq('id', id);

      // 4. Insert customer ledger record
      await _supabase.from(SupabaseConstants.customerLedgersTable).insert({
        'pharmacy_id': pharmacyId,
        'customer_id': id,
        'entry_type': 'payment_received',
        'debit': 0,
        'credit': paying,
        'balance': finalCustomerDue,
        'payment_method': 'cash',
        'notes': 'Due payment collected',
      });
    } else {
      // 1. Allocate paying amount across supplier purchases using FIFO
      double remainingPay = paying;
      try {
        var purQuery = _supabase
            .from(SupabaseConstants.purchasesTable)
            .select('id, grand_total, paid_amount, due_amount')
            .eq('pharmacy_id', pharmacyId)
            .eq('supplier_id', id)
            .gt('due_amount', 0.001)
            .order('created_at', ascending: true);

        final purchases = await purQuery;
        for (final pur in purchases) {
          if (remainingPay <= 0.0001) break;
          final purId = pur['id']?.toString() ?? '';
          if (selectedInvoiceIds != null && selectedInvoiceIds.isNotEmpty && !selectedInvoiceIds.contains(purId)) {
            continue;
          }

          final curDue = (pur['due_amount'] as num?)?.toDouble() ?? 0.0;
          final curPaid = (pur['paid_amount'] as num?)?.toDouble() ?? 0.0;
          final payThis = remainingPay >= curDue ? curDue : remainingPay;

          final updatedDue = (curDue - payThis) > 0.001 ? (curDue - payThis) : 0.0;
          final updatedPaid = curPaid + payThis;

          await _supabase.from(SupabaseConstants.purchasesTable).update({
            'paid_amount': updatedPaid,
            'due_amount': updatedDue,
          }).eq('id', purId);

          remainingPay -= payThis;
        }
      } catch (_) {}

      // 2. Accurately recalculate supplier's remaining due from all remaining unpaid purchases
      double finalSupplierDue = fallbackNewDue;
      try {
        final remainingPurchases = await _supabase
            .from(SupabaseConstants.purchasesTable)
            .select('due_amount')
            .eq('pharmacy_id', pharmacyId)
            .eq('supplier_id', id)
            .gt('due_amount', 0.001);

        double sumDue = 0.0;
        for (final pur in (remainingPurchases as List)) {
          sumDue += (pur['due_amount'] as num?)?.toDouble() ?? 0.0;
        }
        finalSupplierDue = sumDue;
      } catch (_) {}

      // 3. Update supplier current_due
      await _supabase
          .from(SupabaseConstants.suppliersTable)
          .update({'current_due': finalSupplierDue})
          .eq('id', id);

      // 4. Insert supplier ledger record
      await _supabase.from(SupabaseConstants.supplierLedgersTable).insert({
        'pharmacy_id': pharmacyId,
        'supplier_id': id,
        'entry_type': 'payment_made',
        'debit': paying,
        'credit': 0,
        'balance': finalSupplierDue,
        'payment_method': 'cash',
        'notes': 'Due payment made to supplier',
      });
    }
  }
}
