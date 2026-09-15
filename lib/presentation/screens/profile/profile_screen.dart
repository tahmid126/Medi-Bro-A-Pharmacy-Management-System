import 'dart:typed_data';
import '../../../data/services/supabase_service.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/pharmacy_model.dart';
import '../../../data/models/profile_model.dart';
import '../../../data/services/profile_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common/medi_app_bar.dart';
import '../../widgets/common/avatar_helper.dart';
import '../auth/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _profileService = ProfileService.instance;
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  // Profile controllers
  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // Pharmacy controllers
  final _pharmacyNameCtrl = TextEditingController();
  final _pharmacyPhoneCtrl = TextEditingController();
  final _pharmacyEmailCtrl = TextEditingController();
  final _pharmacyAddressCtrl = TextEditingController();
  final _pharmacyLicenseCtrl = TextEditingController();

  ProfileModel? _profile;
  PharmacyModel? _pharmacy;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  Uint8List? _selectedImageBytes;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _pharmacyNameCtrl.dispose();
    _pharmacyPhoneCtrl.dispose();
    _pharmacyEmailCtrl.dispose();
    _pharmacyAddressCtrl.dispose();
    _pharmacyLicenseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final authProvider = context.read<AuthProvider>();
    final profile = authProvider.currentProfile;
    var pharmacy = authProvider.currentPharmacy;

    if (pharmacy == null && profile?.pharmacyId != null) {
      pharmacy = await _profileService.fetchPharmacy(profile!.pharmacyId!);
    }

    if (profile != null) {
      _profile = profile;
      _fullNameCtrl.text = profile.fullName;
      _phoneCtrl.text = profile.phone ?? '';
      _avatarUrl = profile.avatarUrl;
    }

    if (pharmacy != null) {
      _pharmacy = pharmacy;
      _pharmacyNameCtrl.text = pharmacy.name;
      _pharmacyPhoneCtrl.text = pharmacy.phone ?? '';
      _pharmacyEmailCtrl.text = pharmacy.email ?? '';
      _pharmacyAddressCtrl.text = pharmacy.address ?? '';
      _pharmacyLicenseCtrl.text = pharmacy.licenseNo ?? '';
    } else if (profile != null && !profile.isSuperAdmin) {
      // Prefill if pharmacy not created yet
      final meta = SupabaseService.instance.client.auth.currentUser?.userMetadata ?? {};
      if (_pharmacyNameCtrl.text.isEmpty) {
        _pharmacyNameCtrl.text = meta['pharmacy_name'] as String? ?? '';
      }
      if (_pharmacyEmailCtrl.text.isEmpty) {
        _pharmacyEmailCtrl.text = SupabaseService.instance.client.auth.currentUser?.email ?? '';
      }
    }

    setState(() => _isLoading = false);
  }

  Future<void> _pickAndUploadPhoto() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 85,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      setState(() {
        _selectedImageBytes = bytes;
        _isUploadingPhoto = true;
      });

      final fileName = picked.name;
      final userId = _profile?.id ?? SupabaseService.instance.client.auth.currentUser?.id ?? '';

      final uploadedUrl = await _profileService.uploadAvatar(
        userId: userId,
        fileBytes: bytes,
        fileName: fileName,
      );

      if (uploadedUrl != null) {
        setState(() {
          _avatarUrl = uploadedUrl;
          _isUploadingPhoto = false;
        });
        // Immediately save avatar url to profile
        await _profileService.updateProfile(
          userId: userId,
          fullName: _fullNameCtrl.text,
          phone: _phoneCtrl.text,
          avatarUrl: uploadedUrl,
        );
        _showSnack('Profile photo updated!', success: true);
      } else {
        setState(() => _isUploadingPhoto = false);
        _showSnack('Photo upload failed. Check storage bucket.', success: false);
      }
    } catch (e) {
      setState(() => _isUploadingPhoto = false);
      _showSnack('Error picking photo: $e', success: false);
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final userId = _profile?.id ?? SupabaseService.instance.client.auth.currentUser?.id ?? '';
      final pharmacyId = _pharmacy?.id ?? _profile?.pharmacyId ?? '';
      final isSuperAdmin = _profile?.isSuperAdmin ?? false;

      // 1. Update user profile
      await _profileService.updateProfile(
        userId: userId,
        fullName: _fullNameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        avatarUrl: _avatarUrl,
      );

      // 2. Update or create pharmacy
      if (!isSuperAdmin) {
        if (pharmacyId.isNotEmpty) {
          await _profileService.updatePharmacy(
            pharmacyId: pharmacyId,
            name: _pharmacyNameCtrl.text.trim(),
            phone: _pharmacyPhoneCtrl.text.trim(),
            email: _pharmacyEmailCtrl.text.trim(),
            address: _pharmacyAddressCtrl.text.trim(),
            licenseNo: _pharmacyLicenseCtrl.text.trim(),
          );
        } else if (_pharmacyNameCtrl.text.trim().isNotEmpty) {
          final newPharm = await _profileService.createPharmacyForUser(
            userId: userId,
            name: _pharmacyNameCtrl.text.trim(),
            phone: _pharmacyPhoneCtrl.text.trim(),
            email: _pharmacyEmailCtrl.text.trim(),
            address: _pharmacyAddressCtrl.text.trim(),
            licenseNo: _pharmacyLicenseCtrl.text.trim(),
          );
          if (newPharm != null) {
            _pharmacy = newPharm;
          }
        }
      }

      // 3. Refresh auth provider state and reload local UI
      if (!mounted) return;
      final authProv = context.read<AuthProvider>();
      await authProv.checkAuthStatus();
      await _loadData();

      if (mounted) {
        _showSnack('Profile and Store details saved successfully!', success: true);
      }
    } catch (e) {
      _showSnack('Failed to save: $e', success: false);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String message, {required bool success}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: success ? const Color(0xFF10B981) : Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = _profile?.isSuperAdmin ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      endDrawer: const AppDrawer(),
appBar: MediAppBar(
        title: 'My Profile',
        actions: [
          if (!_isSaving)
            TextButton.icon(
              onPressed: _saveChanges,
              icon: const Icon(Icons.save_outlined, color: Colors.white, size: 18),
              label: const Text(
                'Save',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async => _loadData(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  // â”€â”€â”€ Hero Avatar Section â”€â”€â”€
                  _buildAvatarSection(isSuperAdmin),

                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // â”€â”€â”€ Personal Info Section â”€â”€â”€
                          _sectionHeader(
                            icon: Icons.person_outline_rounded,
                            title: 'Personal Information',
                            color: AppColors.primary,
                          ),
                          const SizedBox(height: 12),

                          _buildCard(
                            children: [
                              _inputField(
                                controller: _fullNameCtrl,
                                label: 'Full Name',
                                icon: Icons.badge_outlined,
                                hint: 'Enter your full name',
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                              ),
                              const SizedBox(height: 14),
                              _inputField(
                                controller: _phoneCtrl,
                                label: 'Phone Number',
                                icon: Icons.phone_outlined,
                                hint: 'e.g. 01700000000',
                                keyboardType: TextInputType.phone,
                              ),
                              const SizedBox(height: 12),

                              // Role Badge
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isSuperAdmin
                                      ? Colors.amber.shade50
                                      : AppColors.primary.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSuperAdmin
                                        ? Colors.amber.shade300
                                        : AppColors.primary.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isSuperAdmin
                                          ? Icons.shield_rounded
                                          : Icons.store_rounded,
                                      size: 18,
                                      color: isSuperAdmin ? Colors.amber.shade800 : AppColors.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Account Role',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          isSuperAdmin
                                              ? 'Super Administrator'
                                              : _roleLabel(_profile?.role ?? 'owner'),
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: isSuperAdmin
                                                ? Colors.amber.shade800
                                                : AppColors.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isSuperAdmin ? Colors.amber.shade100 : Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        isSuperAdmin ? 'READ-ONLY ROLE' : 'ACTIVE',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: isSuperAdmin ? Colors.amber.shade800 : Colors.green.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // â”€â”€â”€ Pharmacy Section (only for non-super-admin) â”€â”€â”€
                          if (!isSuperAdmin) ...[
                            _sectionHeader(
                              icon: Icons.storefront_rounded,
                              title: 'Pharmacy / Store Details',
                              color: const Color(0xFF0284C7),
                            ),
                            const SizedBox(height: 12),

                            _buildCard(
                              children: [
                                _buildInfoReadOnly(
                                  label: 'Pharmacy Status',
                                  value: (_pharmacy?.status ?? 'active').toUpperCase(),
                                  icon: Icons.verified_outlined,
                                  valueColor: _pharmacy?.status == 'active'
                                      ? Colors.green.shade700
                                      : Colors.red.shade700,
                                ),
                                const SizedBox(height: 14),
                                _buildInfoReadOnly(
                                  label: 'Plan Type',
                                  value: _planLabel(_pharmacy?.planType ?? 'free_trial'),
                                  icon: Icons.workspace_premium_outlined,
                                  valueColor: const Color(0xFF7C3AED),
                                ),
                                const Divider(height: 24),

                                _inputField(
                                  controller: _pharmacyNameCtrl,
                                  label: 'Pharmacy Name',
                                  icon: Icons.local_pharmacy_outlined,
                                  hint: 'e.g. Popular Pharmacy',
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty) ? 'Pharmacy name required' : null,
                                ),
                                const SizedBox(height: 14),
                                _inputField(
                                  controller: _pharmacyPhoneCtrl,
                                  label: 'Store Contact Phone',
                                  icon: Icons.phone_in_talk_outlined,
                                  hint: 'Store phone number',
                                  keyboardType: TextInputType.phone,
                                ),
                                const SizedBox(height: 14),
                                _inputField(
                                  controller: _pharmacyEmailCtrl,
                                  label: 'Store Email',
                                  icon: Icons.email_outlined,
                                  hint: 'pharmacy@email.com',
                                  keyboardType: TextInputType.emailAddress,
                                ),
                                const SizedBox(height: 14),
                                _inputField(
                                  controller: _pharmacyAddressCtrl,
                                  label: 'Store Address',
                                  icon: Icons.location_on_outlined,
                                  hint: 'Full store address',
                                  maxLines: 2,
                                ),
                                const SizedBox(height: 14),
                                _inputField(
                                  controller: _pharmacyLicenseCtrl,
                                  label: 'Drug License No.',
                                  icon: Icons.receipt_long_outlined,
                                  hint: 'Official drug license number',
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 24),

                          // â”€â”€â”€ Save Button â”€â”€â”€
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton.icon(
                              onPressed: _isSaving ? null : _saveChanges,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_rounded, size: 20),
                              label: Text(
                                _isSaving ? 'Saving...' : 'Save All Changes',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // â”€â”€â”€ Danger Zone: Sign Out â”€â”€â”€
                          OutlinedButton.icon(
                            onPressed: () async {
                              final nav = Navigator.of(context, rootNavigator: true);
                              final auth = context.read<AuthProvider>();
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  title: const Text('Sign Out?'),
                                  content: const Text('Are you sure you want to sign out?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                      child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await auth.logout();
                                nav.pushAndRemoveUntil(
                                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                                  (route) => false,
                                );
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              side: BorderSide(color: Colors.red.shade300),
                              minimumSize: const Size(double.infinity, 48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: const Text(
                              'Sign Out',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),

                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
              ),
    );
  }

  // â”€â”€â”€ Avatar Hero Section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildAvatarSection(bool isSuperAdmin) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.75),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          // Avatar with edit button
          Stack(
            children: [
              // Photo
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: _isUploadingPhoto
                      ? const Center(
                          child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5),
                        )
                      : _selectedImageBytes != null
                          ? Image.memory(_selectedImageBytes!, fit: BoxFit.cover)
                          : (_avatarUrl != null && _avatarUrl!.isNotEmpty && getAvatarImageProvider(_avatarUrl) != null
                              ? Image(
                                  image: getAvatarImageProvider(_avatarUrl)!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _defaultAvatar(),
                                )
                              : _defaultAvatar()),
                ),
              ),

              // Edit camera button
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _pickAndUploadPhoto,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.camera_alt_rounded, size: 16, color: AppColors.primary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Name
          Text(
            _profile?.fullName ?? 'User',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),

          // Phone
          if (_profile?.phone != null && _profile!.phone!.isNotEmpty)
            Text(
              _profile!.phone!,
              style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.85)),
            ),
          const SizedBox(height: 8),

          // Pharmacy name badge
          if (_pharmacy != null && !isSuperAdmin)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storefront_rounded, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    _pharmacy!.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          else if (isSuperAdmin)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.amber.shade400.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.shield_rounded, size: 14, color: Colors.black87),
                  SizedBox(width: 6),
                  Text(
                    'Super Administrator',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _defaultAvatar() {
    final initials = (_profile?.fullName ?? 'U')
        .trim()
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return Container(
      color: AppColors.primary.withValues(alpha: 0.15),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
            prefixIcon: Icon(icon, color: AppColors.primary, size: 19),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildInfoReadOnly({
    required String label,
    required String value,
    required IconData icon,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade500),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: valueColor ?? const Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'owner':
        return 'Pharmacy Owner';
      case 'manager':
        return 'Store Manager';
      case 'cashier':
        return 'Cashier';
      default:
        return role;
    }
  }

  String _planLabel(String plan) {
    switch (plan) {
      case 'free_trial':
        return 'Free Trial';
      case 'basic':
        return 'Basic Plan';
      case 'standard':
        return 'Standard Plan';
      case 'pro':
        return 'Pro Plan';
      case 'enterprise':
        return 'Enterprise';
      default:
        return plan;
    }
  }
}