import '../../core/constants/supabase_constants.dart';
import 'supabase_service.dart';

class CompanyGroupResult {
  final List<Map<String, dynamic>> uniqueCompanies;
  final Map<String, List<Map<String, dynamic>>> companyContacts;

  const CompanyGroupResult({
    required this.uniqueCompanies,
    required this.companyContacts,
  });
}

class ContactsService {
  static final _supabase = SupabaseService.instance.client;

  /// Fetch customers list with optional search query
  static Future<List<Map<String, dynamic>>> fetchCustomers({
    required String pharmacyId,
    String query = '',
  }) async {
    var q = _supabase
        .from(SupabaseConstants.customersTable)
        .select('id, name, phone, address, email, current_due')
        .eq('pharmacy_id', pharmacyId);

    if (query.isNotEmpty) {
      q = q.or('name.ilike.%$query%,phone.ilike.%$query%,address.ilike.%$query%');
    }

    final data = await q.order('name');
    return List<Map<String, dynamic>>.from(data);
  }

  /// Fetch suppliers and group by company_name
  static Future<CompanyGroupResult> fetchSuppliersGroupedByCompany({
    required String pharmacyId,
    String query = '',
  }) async {
    var q = _supabase
        .from(SupabaseConstants.suppliersTable)
        .select('id, name, company_name, phone, email, address, current_due')
        .eq('pharmacy_id', pharmacyId);

    if (query.isNotEmpty) {
      q = q.or('company_name.ilike.%$query%,name.ilike.%$query%,phone.ilike.%$query%');
    }

    final allRows = List<Map<String, dynamic>>.from(await q.order('company_name'));

    final Map<String, List<Map<String, dynamic>>> companyContacts = {};
    final Map<String, Map<String, dynamic>> uniqueCompanies = {};

    for (final row in allRows) {
      final cName = (row['company_name'] ?? row['name'] ?? 'General Supplier').toString().trim();
      if (!uniqueCompanies.containsKey(cName)) {
        uniqueCompanies[cName] = {
          'company_name': cName,
          'id': row['id'],
          'is_local': true,
        };
      }
      companyContacts.putIfAbsent(cName, () => []).add(row);
    }

    final sortedList = uniqueCompanies.values.toList()
      ..sort((a, b) => (a['company_name'] as String).compareTo(b['company_name'] as String));

    return CompanyGroupResult(
      uniqueCompanies: sortedList,
      companyContacts: companyContacts,
    );
  }

  /// Search global catalog for potential new companies
  static Future<List<String>> searchGlobalCompanies(String query, {int limit = 5}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    try {
      final rows = await _supabase
          .from(SupabaseConstants.globalMedicinesTable)
          .select('company')
          .ilike('company', '%$trimmed%')
          .limit(limit);
      final list = <String>[];
      final seen = <String>{};
      for (final r in (rows as List)) {
        final gName = r['company']?.toString().trim() ?? '';
        if (gName.isNotEmpty && !seen.contains(gName.toLowerCase())) {
          seen.add(gName.toLowerCase());
          list.add(gName);
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Delete a customer
  static Future<void> deleteCustomer(String id) async {
    await _supabase
        .from(SupabaseConstants.customersTable)
        .delete()
        .eq('id', id);
  }

  /// Delete all supplier contacts for a company
  static Future<void> deleteCompanyContacts({
    required String pharmacyId,
    required String companyName,
  }) async {
    await _supabase
        .from(SupabaseConstants.suppliersTable)
        .delete()
        .eq('pharmacy_id', pharmacyId)
        .eq('company_name', companyName);
  }

  /// Delete a single supplier contact
  static Future<void> deleteSingleSupplier(String id) async {
    await _supabase
        .from(SupabaseConstants.suppliersTable)
        .delete()
        .eq('id', id);
  }
}
