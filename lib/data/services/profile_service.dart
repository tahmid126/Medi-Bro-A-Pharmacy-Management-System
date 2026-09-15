import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile_model.dart';
import '../models/pharmacy_model.dart';
import '../../core/constants/supabase_constants.dart';
import 'supabase_service.dart';

class ProfileService {
  ProfileService._();
  static final ProfileService instance = ProfileService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  // ==========================================
  // FETCH
  // ==========================================
  Future<ProfileModel?> fetchProfile(String userId) async {
    try {
      final data = await _client
          .from(SupabaseConstants.profilesTable)
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (data == null) return null;
      return ProfileModel.fromJson(data);
    } catch (e) {
      debugPrint('[ProfileService] fetchProfile error: $e');
      return null;
    }
  }

  Future<PharmacyModel?> fetchPharmacy(String pharmacyId) async {
    try {
      final data = await _client
          .from(SupabaseConstants.pharmaciesTable)
          .select()
          .eq('id', pharmacyId)
          .maybeSingle();
      if (data == null) return null;
      return PharmacyModel.fromJson(data);
    } catch (e) {
      debugPrint('[ProfileService] fetchPharmacy error: $e');
      return null;
    }
  }

  // ==========================================
  // UPDATE PROFILE
  // ==========================================
  Future<void> updateProfile({
    required String userId,
    required String fullName,
    String? phone,
    String? avatarUrl,
  }) async {
    try {
      final payload = <String, dynamic>{
        'full_name': fullName.trim(),
        if (phone != null) 'phone': phone.trim(),
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      };
      await _client
          .from(SupabaseConstants.profilesTable)
          .update(payload)
          .eq('id', userId);
    } catch (e) {
      debugPrint('[ProfileService] updateProfile error: $e');
      rethrow;
    }
  }

  // ==========================================
  // UPDATE PHARMACY
  // ==========================================
  Future<void> updatePharmacy({
    required String pharmacyId,
    required String name,
    String? phone,
    String? email,
    String? address,
    String? licenseNo,
  }) async {
    try {
      final payload = <String, dynamic>{
        'name': name.trim(),
        if (phone != null) 'phone': phone.trim(),
        if (email != null) 'email': email.trim(),
        if (address != null) 'address': address.trim(),
        if (licenseNo != null) 'license_no': licenseNo.trim(),
      };
      await _client
          .from(SupabaseConstants.pharmaciesTable)
          .update(payload)
          .eq('id', pharmacyId);
    } catch (e) {
      debugPrint('[ProfileService] updatePharmacy error: $e');
      rethrow;
    }
  }

  // ==========================================
  // CREATE PHARMACY FOR USER (IF NONE EXISTS)
  // ==========================================
  Future<PharmacyModel?> createPharmacyForUser({
    required String userId,
    required String name,
    String? phone,
    String? email,
    String? address,
    String? licenseNo,
  }) async {
    try {
      final pharmPayload = <String, dynamic>{
        'name': name.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        if (address != null && address.trim().isNotEmpty) 'address': address.trim(),
        if (licenseNo != null && licenseNo.trim().isNotEmpty) 'license_no': licenseNo.trim(),
        'status': 'active',
        'plan_type': 'free_trial',
      };
      final newPharmData = await _client
          .from(SupabaseConstants.pharmaciesTable)
          .insert(pharmPayload)
          .select()
          .single();

      final newPharmId = newPharmData['id'] as String;

      // Link to user profile
      await _client
          .from(SupabaseConstants.profilesTable)
          .update({'pharmacy_id': newPharmId})
          .eq('id', userId);

      return PharmacyModel.fromJson(newPharmData);
    } catch (e) {
      debugPrint('[ProfileService] createPharmacyForUser error: $e');
      return null;
    }
  }

  // ==========================================
  // UPLOAD AVATAR PHOTO (STORAGE WITH BASE64 FALLBACK)
  // ==========================================
  Future<String?> uploadAvatar({
    required String userId,
    required List<int> fileBytes,
    required String fileName,
  }) async {
    // 1. Try Supabase Storage first
    try {
      final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'jpg';
      final path = 'avatars/$userId/profile.$ext';

      await _client.storage.from('medibro-public').uploadBinary(
            path,
            Uint8List.fromList(fileBytes),
            fileOptions: FileOptions(
              contentType: 'image/$ext',
              upsert: true,
            ),
          );

      final publicUrl =
          _client.storage.from('medibro-public').getPublicUrl(path);
      if (publicUrl.isNotEmpty) return publicUrl;
    } catch (e) {
      debugPrint('[ProfileService] Storage upload error: $e. Falling back to data URI.');
    }

    // 2. Reliable Fallback: Base64 Data URI (saved in DB text column, works 100%)
    try {
      final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'jpeg';
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      final base64String = base64Encode(fileBytes);
      return 'data:$mime;base64,$base64String';
    } catch (e) {
      debugPrint('[ProfileService] Base64 fallback error: $e');
      return null;
    }
  }
}