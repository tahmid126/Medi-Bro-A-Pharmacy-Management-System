import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class AdminService {
  AdminService._();
  static final AdminService instance = AdminService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  // ==========================================
  // GLOBAL MEDICINE CATALOG
  // ==========================================
  Future<List<Map<String, dynamic>>> fetchGlobalMedicines({
    String? searchQuery,
    String? availabilityFilter,
    int limit = 300,
  }) async {
    try {
      var query = _client
          .from('global_medicines')
          .select('*');

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.trim();
        query = query.or('brand_name.ilike.%$q%,generic_name.ilike.%$q%,company.ilike.%$q%');
      }

      if (availabilityFilter == 'available') {
        query = query.eq('is_available', true);
      } else if (availabilityFilter == 'unavailable') {
        query = query.eq('is_available', false);
      }

      final data = await query.order('brand_name', ascending: true).limit(limit);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('[AdminService] fetchGlobalMedicines error: $e');
      rethrow;
    }
  }

  Future<void> toggleMedicineAvailability({
    required String medicineId,
    required bool isCurrentlyAvailable,
  }) async {
    try {
      await _client
          .from('global_medicines')
          .update({'is_available': !isCurrentlyAvailable})
          .eq('id', medicineId);
    } catch (e) {
      debugPrint('[AdminService] toggleMedicineAvailability error: $e');
      rethrow;
    }
  }

  Future<void> deleteGlobalMedicine(String medicineId) async {
    try {
      await _client
          .from('global_medicines')
          .delete()
          .eq('id', medicineId);
    } catch (e) {
      debugPrint('[AdminService] deleteGlobalMedicine error: $e');
      rethrow;
    }
  }

  // ==========================================
  // PHARMACIES MANAGEMENT
  // ==========================================
  Future<List<Map<String, dynamic>>> fetchPharmacies({
    String? searchQuery,
  }) async {
    try {
      var query = _client
          .from('pharmacies')
          .select('*, profiles(id, full_name, phone, role)');

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.trim();
        query = query.or('name.ilike.%$q%,phone.ilike.%$q%,address.ilike.%$q%');
      }

      final data = await query.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('[AdminService] fetchPharmacies error: $e');
      rethrow;
    }
  }

  Future<void> updatePharmacyStatus({
    required String pharmacyId,
    required String nextStatus,
  }) async {
    try {
      await _client
          .from('pharmacies')
          .update({'status': nextStatus})
          .eq('id', pharmacyId);
    } catch (e) {
      debugPrint('[AdminService] updatePharmacyStatus error: $e');
      rethrow;
    }
  }
}