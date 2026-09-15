import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/pharmacy_model.dart';
import '../models/profile_model.dart';
import '../../core/constants/supabase_constants.dart';
import 'supabase_service.dart';

class AuthService {
  final SupabaseClient _client = SupabaseService.instance.client;

  User? get currentUser => _client.auth.currentUser;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<AuthResponse> signUpStoreOwner({
    required String email,
    required String password,
    required String fullName,
    required String pharmacyName,
    String? phone,
  }) async {
    return await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'full_name': fullName.trim(),
        'pharmacy_name': pharmacyName.trim(),
        'role': 'owner',
        'phone': phone?.trim(),
      },
    );
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      try {
        await _client.auth.signOut();
      } catch (_) {}
    }
  }

  Future<ProfileModel?> fetchCurrentProfile() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final response = await _client
          .from(SupabaseConstants.profilesTable)
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (response != null) {
        return ProfileModel.fromJson(response);
      }
    } catch (e) {
      // Continue to fallback
    }

    // Fallback: If profile row was not found (or initial RLS delay), create or synthesize
    try {
      final meta = user.userMetadata ?? {};
      final fullName = meta['full_name'] as String? ?? user.email?.split('@').first ?? 'User';
      final phone = meta['phone'] as String?;
      final role = meta['role'] as String? ?? 'owner';
      final pharmacyName = meta['pharmacy_name'] as String?;

      String? pharmacyId;
      if (pharmacyName != null && pharmacyName.isNotEmpty) {
        try {
          final existingPharm = await _client
              .from(SupabaseConstants.pharmaciesTable)
              .select('id')
              .eq('name', pharmacyName)
              .maybeSingle();
          if (existingPharm != null) {
            pharmacyId = existingPharm['id'] as String?;
          }
        } catch (_) {}
      }

      final newMap = <String, dynamic>{
        'id': user.id,
        'full_name': fullName,
        if (phone != null) 'phone': phone,
        'role': role,
        if (pharmacyId != null) 'pharmacy_id': pharmacyId,
        'is_active': true,
      };

      await _client.from(SupabaseConstants.profilesTable).upsert(newMap);

      final retry = await _client
          .from(SupabaseConstants.profilesTable)
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (retry != null) {
        return ProfileModel.fromJson(retry);
      }
    } catch (_) {}

    // In-memory fallback guaranteeing ProfileModel is never null while user is authenticated
    final meta = user.userMetadata ?? {};
    return ProfileModel(
      id: user.id,
      fullName: meta['full_name'] as String? ?? user.email?.split('@').first ?? 'User',
      phone: meta['phone'] as String?,
      role: meta['role'] as String? ?? 'owner',
    );
  }

  Future<PharmacyModel?> fetchPharmacy(String pharmacyId) async {
    final response = await _client
        .from(SupabaseConstants.pharmaciesTable)
        .select()
        .eq('id', pharmacyId)
        .maybeSingle();

    if (response == null) return null;
    return PharmacyModel.fromJson(response);
  }
}
