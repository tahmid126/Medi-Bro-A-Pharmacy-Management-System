class ProfileModel {
  final String id;
  final String? pharmacyId;
  final String fullName;
  final String? phone;
  final String role; // 'super_admin', 'owner', 'manager', 'cashier'
  final String? avatarUrl;
  final bool isActive;

  ProfileModel({
    required this.id,
    this.pharmacyId,
    required this.fullName,
    this.phone,
    this.role = 'owner',
    this.avatarUrl,
    this.isActive = true,
  });

  bool get isOwner => role == 'owner';
  bool get isManager => role == 'manager' || role == 'owner';
  bool get isSuperAdmin => role.toLowerCase() == 'super_admin' || role.toLowerCase() == 'admin';

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'] as String,
      pharmacyId: json['pharmacy_id'] as String?,
      fullName: json['full_name'] as String? ?? 'User',
      phone: json['phone'] as String?,
      role: json['role'] as String? ?? 'owner',
      avatarUrl: json['avatar_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pharmacy_id': pharmacyId,
      'full_name': fullName,
      'phone': phone,
      'role': role,
      'avatar_url': avatarUrl,
      'is_active': isActive,
    };
  }
}
