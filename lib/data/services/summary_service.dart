import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/supabase_constants.dart';
import '../models/summary_model.dart';
import 'supabase_service.dart';

class SummaryService {
  SummaryService._();
  static final SummaryService instance = SummaryService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  // ── Targets Persistence ───────────────────────────────────────────────────

  Future<Map<String, double>> loadTargets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final salesTarget = prefs.getDouble('sales_target') ?? 15000.0;
      final revenueTarget = prefs.getDouble('revenue_target') ?? 5000.0;
      return {
        'sales_target': salesTarget,
        'revenue_target': revenueTarget,
      };
    } catch (e) {
      debugPrint('[SummaryService] loadTargets error: ');
      return {
        'sales_target': 15000.0,
        'revenue_target': 5000.0,
      };
    }
  }

  Future<void> saveTargets({
    required double salesTarget,
    required double revenueTarget,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('sales_target', salesTarget);
      await prefs.setDouble('revenue_target', revenueTarget);
    } catch (e) {
      debugPrint('[SummaryService] saveTargets error: ');
    }
  }

  // ── Core Metrics Fetching ─────────────────────────────────────────────────

  Future<SummaryMetrics> fetchSummaryMetrics({
    required String pharmacyId,
  }) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final todayKey = DateFormat('yyyy-MM-dd').format(today);
      final thirtyDaysAgo = today.subtract(const Duration(days: 30));

      var query = _client
          .from(SupabaseConstants.invoicesTable)
          .select('id, created_at, grand_total, customer_id, invoice_items(quantity, total_price, purchase_price, batch_id)')
          .gte('created_at', thirtyDaysAgo.toIso8601String());

      if (pharmacyId.isNotEmpty) {
        query = query.eq('pharmacy_id', pharmacyId);
      }

      final invoicesRaw = await query.order('created_at');
      final invoiceList = List<Map<String, dynamic>>.from(invoicesRaw as List);

      // Collect batches where purchase_price might be missing or 0
      final Set<String> neededBatchIds = {};
      for (final inv in invoiceList) {
        final items = inv['invoice_items'] as List? ?? [];
        for (final it in items) {
          final pPrice = (it['purchase_price'] as num?)?.toDouble() ?? 0.0;
          final bId = it['batch_id']?.toString() ?? '';
          if (pPrice <= 0 && bId.isNotEmpty) {
            neededBatchIds.add(bId);
          }
        }
      }

      final Map<String, double> batchCostMap = {};
      if (neededBatchIds.isNotEmpty) {
        try {
          final batchesRaw = await _client
              .from(SupabaseConstants.batchesTable)
              .select('id, purchase_rate')
              .inFilter('id', neededBatchIds.toList());
          for (final b in (batchesRaw as List)) {
            final bid = b['id']?.toString() ?? '';
            final rate = (b['purchase_rate'] as num?)?.toDouble() ?? 0.0;
            if (bid.isNotEmpty) batchCostMap[bid] = rate;
          }
        } catch (e) {
          debugPrint('[SummaryService] batch cost lookup error: ');
        }
      }

      final Map<String, Set<String>> dailyCustomers = {};
      double todaySales = 0.0;
      double todayRevenue = 0.0;

      final weeklySales = List.filled(7, 0.0);
      final weeklyRevenue = List.filled(7, 0.0);
      final weeklyCustomers = List.filled(7, 0);

      final monthlySales = List.filled(4, 0.0);
      final monthlyRevenue = List.filled(4, 0.0);
      final monthlyCustomers = List.filled(4, 0);

      for (final inv in invoiceList) {
        final rawCreated = inv['created_at'];
        if (rawCreated == null) continue;

        final dt = DateTime.parse(rawCreated.toString()).toLocal();
        final dayOnly = DateTime(dt.year, dt.month, dt.day);
        final dateKey = DateFormat('yyyy-MM-dd').format(dayOnly);
        final cid = inv['customer_id']?.toString() ?? '';

        dailyCustomers.putIfAbsent(dateKey, () => <String>{});
        if (cid.isNotEmpty) {
          dailyCustomers[dateKey]!.add(cid);
        }

        final amount = (inv['grand_total'] as num?)?.toDouble() ?? 0.0;
        double profit = 0.0;
        final items = inv['invoice_items'] as List? ?? [];

        for (final it in items) {
          final qty = (it['quantity'] as num?)?.toInt() ?? 0;
          final lineTotal = (it['total_price'] as num?)?.toDouble() ?? 0.0;
          double pPrice = (it['purchase_price'] as num?)?.toDouble() ?? 0.0;
          if (pPrice <= 0) {
            final bId = it['batch_id']?.toString() ?? '';
            pPrice = batchCostMap[bId] ?? 0.0;
          }
          profit += (lineTotal - (pPrice * qty));
        }

        final daysAgo = today.difference(dayOnly).inDays;

        if (daysAgo == 0) {
          todaySales += amount;
          todayRevenue += profit;
        }

        if (daysAgo >= 0 && daysAgo < 7) {
          final idx = 6 - daysAgo;
          weeklySales[idx] += amount;
          weeklyRevenue[idx] += profit;
        }

        if (daysAgo >= 0 && daysAgo < 30) {
          final weekIdx = (daysAgo ~/ 7).clamp(0, 3);
          monthlySales[weekIdx] += amount;
          monthlyRevenue[weekIdx] += profit;
        }
      }

      final todayCustomers = dailyCustomers[todayKey]?.length ?? 0;

      for (int i = 0; i < 7; i++) {
        final d = today.subtract(Duration(days: 6 - i));
        final key = DateFormat('yyyy-MM-dd').format(d);
        weeklyCustomers[i] = dailyCustomers[key]?.length ?? 0;
      }

      for (int w = 0; w < 4; w++) {
        int total = 0;
        for (int d = 0; d < 7; d++) {
          final dayIdx = w * 7 + d;
          final day = today.subtract(Duration(days: dayIdx));
          final key = DateFormat('yyyy-MM-dd').format(day);
          total += dailyCustomers[key]?.length ?? 0;
        }
        monthlyCustomers[w] = total;
      }

      final weekDayLabels = List.generate(7, (i) {
        final d = today.subtract(Duration(days: 6 - i));
        return DateFormat('E').format(d);
      });

      return SummaryMetrics(
        todaySales: todaySales,
        todayRevenue: todayRevenue > 0 ? todayRevenue : 0.0,
        todayCustomers: todayCustomers,
        avgSpendPerCustomer:
            todayCustomers > 0 ? (todaySales / todayCustomers) : 0.0,
        weeklySales: weeklySales,
        weeklyRevenue: weeklyRevenue,
        weeklyCustomers: weeklyCustomers,
        weekDayLabels: weekDayLabels,
        monthlySales: monthlySales,
        monthlyRevenue: monthlyRevenue,
        monthlyCustomers: monthlyCustomers,
        weekLabels: const ['Wk 1', 'Wk 2', 'Wk 3', 'Wk 4'],
      );
    } catch (e) {
      debugPrint('[SummaryService] fetchSummaryMetrics error: \n');
      return SummaryMetrics.empty();
    }
  }

  // ── Top Customers ─────────────────────────────────────────────────────────

  Future<List<RankedCustomer>> fetchTopCustomers({
    required String pharmacyId,
    required String period, // 'Weekly' or 'Monthly'
  }) async {
    try {
      final now = DateTime.now();
      final from = period == 'Weekly'
          ? now.subtract(const Duration(days: 7))
          : now.subtract(const Duration(days: 30));

      var query = _client
          .from(SupabaseConstants.invoicesTable)
          .select('customer_id, grand_total')
          .gte('created_at', from.toIso8601String());

      if (pharmacyId.isNotEmpty) {
        query = query.eq('pharmacy_id', pharmacyId);
      }

      final invoicesRaw = await query;
      final Map<String, double> revenueByCustomer = {};

      for (final inv in (invoicesRaw as List)) {
        final cid = inv['customer_id']?.toString() ?? '';
        if (cid.isEmpty) continue;
        final total = (inv['grand_total'] as num?)?.toDouble() ?? 0.0;
        revenueByCustomer[cid] = (revenueByCustomer[cid] ?? 0.0) + total;
      }

      if (revenueByCustomer.isEmpty) return [];

      final customerIds = revenueByCustomer.keys.toList();
      var custQuery = _client
          .from(SupabaseConstants.customersTable)
          .select('id, name, phone, notes, current_due')
          .inFilter('id', customerIds);

      if (pharmacyId.isNotEmpty) {
        custQuery = custQuery.eq('pharmacy_id', pharmacyId);
      }

      final customersRaw = await custQuery;
      final List<RankedCustomer> results = [];

      for (final c in (customersRaw as List)) {
        final cid = c['id'].toString();
        final spent = revenueByCustomer[cid] ?? 0.0;
        final due = (c['current_due'] as num?)?.toDouble() ?? 0.0;
        results.add(
          RankedCustomer(
            id: cid,
            name: (c['name'] ?? 'Walking Customer').toString(),
            phone: (c['phone'] ?? '').toString(),
            notes: (c['notes'] ?? '').toString(),
            totalSpent: spent,
            currentDue: due > 0 ? due : 0.0,
            rank: 1,
          ),
        );
      }

      results.sort((a, b) => b.totalSpent.compareTo(a.totalSpent));

      return List.generate(
        results.length > 15 ? 15 : results.length,
        (i) => RankedCustomer(
          id: results[i].id,
          name: results[i].name,
          phone: results[i].phone,
          notes: results[i].notes,
          totalSpent: results[i].totalSpent,
          currentDue: results[i].currentDue,
          rank: i + 1,
        ),
      );
    } catch (e) {
      debugPrint('[SummaryService] fetchTopCustomers error: \n');
      return [];
    }
  }

  // ── Top Products ──────────────────────────────────────────────────────────

  Future<List<RankedProduct>> fetchTopProducts({
    required String pharmacyId,
    required String period, // 'Weekly' or 'Monthly'
  }) async {
    try {
      final now = DateTime.now();
      final from = period == 'Weekly'
          ? now.subtract(const Duration(days: 7))
          : now.subtract(const Duration(days: 30));

      var query = _client
          .from(SupabaseConstants.invoicesTable)
          .select('id, invoice_items(medicine_id, quantity, total_price, purchase_price, batch_id)')
          .gte('created_at', from.toIso8601String());

      if (pharmacyId.isNotEmpty) {
        query = query.eq('pharmacy_id', pharmacyId);
      }

      final invoicesRaw = await query;
      final Map<String, Map<String, dynamic>> byMedicine = {};
      final Set<String> neededBatchIds = {};

      for (final inv in (invoicesRaw as List)) {
        final items = inv['invoice_items'] as List? ?? [];
        for (final it in items) {
          final mid = it['medicine_id']?.toString() ?? '';
          if (mid.isEmpty) continue;

          final qty = (it['quantity'] as num?)?.toInt() ?? 0;
          final lineTotal = (it['total_price'] as num?)?.toDouble() ?? 0.0;
          final pPrice = (it['purchase_price'] as num?)?.toDouble() ?? 0.0;
          final bId = it['batch_id']?.toString() ?? '';

          if (pPrice <= 0 && bId.isNotEmpty) {
            neededBatchIds.add(bId);
          }

          byMedicine.putIfAbsent(mid, () => {
            'qty': 0,
            'revenue': 0.0,
            'items': <Map<String, dynamic>>[],
          });

          byMedicine[mid]!['qty'] = (byMedicine[mid]!['qty'] as int) + qty;
          byMedicine[mid]!['revenue'] =
              (byMedicine[mid]!['revenue'] as double) + lineTotal;
          (byMedicine[mid]!['items'] as List).add({
            'qty': qty,
            'lineTotal': lineTotal,
            'pPrice': pPrice,
            'bId': bId,
          });
        }
      }

      if (byMedicine.isEmpty) return [];

      final Map<String, double> batchCostMap = {};
      if (neededBatchIds.isNotEmpty) {
        try {
          final batchesRaw = await _client
              .from(SupabaseConstants.batchesTable)
              .select('id, purchase_rate')
              .inFilter('id', neededBatchIds.toList());
          for (final b in (batchesRaw as List)) {
            final bid = b['id']?.toString() ?? '';
            final rate = (b['purchase_rate'] as num?)?.toDouble() ?? 0.0;
            if (bid.isNotEmpty) batchCostMap[bid] = rate;
          }
        } catch (_) {}
      }

      final medIds = byMedicine.keys.toList();
      var medQuery = _client
          .from(SupabaseConstants.medicinesTable)
          .select('id, brand_name, dosage_form, strength')
          .inFilter('id', medIds);

      if (pharmacyId.isNotEmpty) {
        medQuery = medQuery.eq('pharmacy_id', pharmacyId);
      }

      final medicinesRaw = await medQuery;
      final Map<String, Map<String, dynamic>> medMap = {};
      for (final m in (medicinesRaw as List)) {
        medMap[m['id'].toString()] = m;
      }

      final List<RankedProduct> results = [];

      for (final mid in medIds) {
        final medData = medMap[mid];
        final entry = byMedicine[mid]!;
        final brandName = medData?['brand_name']?.toString() ?? '';
        final dosageForm = medData?['dosage_form']?.toString() ?? '';
        final strength = medData?['strength']?.toString() ?? '';

        final qty = entry['qty'] as int;
        final revenue = entry['revenue'] as double;
        double profit = 0.0;

        for (final it in (entry['items'] as List)) {
          final itemQty = it['qty'] as int;
          final itemLine = it['lineTotal'] as double;
          double itemCost = it['pPrice'] as double;
          if (itemCost <= 0) {
            itemCost = batchCostMap[it['bId']] ?? 0.0;
          }
          profit += (itemLine - (itemCost * itemQty));
        }

        results.add(
          RankedProduct(
            id: mid,
            brandName: brandName,
            dosageForm: dosageForm,
            strength: strength,
            quantitySold: qty,
            totalRevenue: revenue,
            grossProfit: profit > 0 ? profit : 0.0,
            rank: 1,
          ),
        );
      }

      results.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

      return List.generate(
        results.length > 15 ? 15 : results.length,
        (i) => RankedProduct(
          id: results[i].id,
          brandName: results[i].brandName,
          dosageForm: results[i].dosageForm,
          strength: results[i].strength,
          quantitySold: results[i].quantitySold,
          totalRevenue: results[i].totalRevenue,
          grossProfit: results[i].grossProfit,
          rank: i + 1,
        ),
      );
    } catch (e) {
      debugPrint('[SummaryService] fetchTopProducts error: \n');
      return [];
    }
  }
}
