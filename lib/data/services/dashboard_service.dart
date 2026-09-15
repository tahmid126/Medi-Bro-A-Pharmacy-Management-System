import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class DashboardMetrics {
  final double todaySales;
  final double todayRevenue;
  final int totalInvoicesToday;

  DashboardMetrics({
    required this.todaySales,
    required this.todayRevenue,
    required this.totalInvoicesToday,
  });
}

class DashboardService {
  DashboardService._();
  static final DashboardService instance = DashboardService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  Future<DashboardMetrics> fetchTodayMetrics({required String pharmacyId}) async {
    try {
      final todayStr = DateTime.now().toIso8601String().split('T').first;

      var query = _client
          .from('invoices')
          .select('grand_total, invoice_items(total_price, purchase_price, quantity)')
          .gte('created_at', '$todayStr 00:00:00');

      if (pharmacyId.isNotEmpty) {
        query = query.eq('pharmacy_id', pharmacyId);
      }

      final invoicesData = await query;

      double salesSum = 0.0;
      double revenueSum = 0.0;
      int invoiceCount = 0;

      for (var inv in (invoicesData as List)) {
        invoiceCount++;
        final total = (inv['grand_total'] as num?)?.toDouble() ?? 0.0;
        salesSum += total;

        final items = inv['invoice_items'] as List? ?? [];
        for (var it in items) {
          final lineTotal = (it['total_price'] as num?)?.toDouble() ?? 0.0;
          final pPrice = (it['purchase_price'] as num?)?.toDouble() ?? 0.0;
          final qty = (it['quantity'] as num?)?.toInt() ?? 0;
          revenueSum += (lineTotal - (pPrice * qty));
        }
      }

      return DashboardMetrics(
        todaySales: salesSum,
        todayRevenue: revenueSum > 0 ? revenueSum : 0.0,
        totalInvoicesToday: invoiceCount,
      );
    } catch (e) {
      debugPrint('[DashboardService] fetchTodayMetrics error: $e');
      return DashboardMetrics(
        todaySales: 0.0,
        todayRevenue: 0.0,
        totalInvoicesToday: 0,
      );
    }
  }
}