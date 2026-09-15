import 'package:flutter/material.dart';
import '../../core/utils/error_formatter.dart';
import '../../data/models/pharmacy_model.dart';
import '../../data/models/profile_model.dart';
import '../../data/services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  String? _errorMessage;
  ProfileModel? _currentProfile;
  PharmacyModel? _currentPharmacy;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  ProfileModel? get currentProfile => _currentProfile;
  PharmacyModel? get currentPharmacy => _currentPharmacy;
  bool get isAuthenticated => _authService.currentUser != null && _currentProfile != null;

  Future<void> checkAuthStatus() async {
    _isLoading = true;
    notifyListeners();

    try {
      if (_authService.currentUser != null) {
        await _loadUserData();
      }
    } catch (e) {
      _errorMessage = ErrorFormatter.format(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _authService.signIn(email: email, password: password);
      if (res.user != null) {
        await _loadUserData();
        _isLoading = false;
        notifyListeners();
        return true;
      }
      _errorMessage = 'Incorrect email or password. Please check your credentials.';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = ErrorFormatter.format(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> registerPharmacy({
    required String email,
    required String password,
    required String fullName,
    required String pharmacyName,
    String? phone,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _authService.signUpStoreOwner(
        email: email,
        password: password,
        fullName: fullName,
        pharmacyName: pharmacyName,
        phone: phone,
      );

      if (res.user != null) {
        await _loadUserData();
        _isLoading = false;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _errorMessage = ErrorFormatter.format(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    _currentProfile = null;
    _currentPharmacy = null;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.signOut();
    } catch (e) {
      debugPrint('[AuthProvider] signOut error: $e');
    } finally {
      _currentProfile = null;
      _currentPharmacy = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadUserData() async {
    try {
      _currentProfile = await _authService.fetchCurrentProfile();
      if (_currentProfile?.pharmacyId != null) {
        _currentPharmacy = await _authService.fetchPharmacy(_currentProfile!.pharmacyId!);
      }
    } catch (_) {}

    // Ensure _currentProfile is never null when currentUser exists
    if (_currentProfile == null && _authService.currentUser != null) {
      final user = _authService.currentUser!;
      final meta = user.userMetadata ?? {};
      _currentProfile = ProfileModel(
        id: user.id,
        fullName: meta['full_name'] as String? ?? user.email?.split('@').first ?? 'User',
        phone: meta['phone'] as String?,
        role: meta['role'] as String? ?? 'owner',
      );
    }
  }
}
