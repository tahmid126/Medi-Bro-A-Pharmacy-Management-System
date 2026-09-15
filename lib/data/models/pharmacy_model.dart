class PharmacyModel {
  final String id;
  final String name;
  final String? licenseNo;
  final String? phone;
  final String? email;
  final String? address;
  final String? logoUrl;
  final String planType; // 'free_trial', 'basic', 'standard', 'pro', 'enterprise'
  final String status;   // 'active', 'past_due', 'suspended'
  final String currency;
  final DateTime? trialEndsAt;
  final DateTime? subscriptionEndsAt;
  final Map<String, dynamic> settings;

  PharmacyModel({
    required this.id,
    required this.name,
    this.licenseNo,
    this.phone,
    this.email,
    this.address,
    this.logoUrl,
    this.planType = 'free_trial',
    this.status = 'active',
    this.currency = 'BDT',
    this.trialEndsAt,
    this.subscriptionEndsAt,
    this.settings = const {},
  });

  factory PharmacyModel.fromJson(Map<String, dynamic> json) {
    return PharmacyModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Unnamed Pharmacy',
      licenseNo: json['license_no'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      address: json['address'] as String?,
      logoUrl: json['logo_url'] as String?,
      planType: json['plan_type'] as String? ?? 'free_trial',
      status: json['status'] as String? ?? 'active',
      currency: json['currency'] as String? ?? 'BDT',
      trialEndsAt: json['trial_ends_at'] != null
          ? DateTime.tryParse(json['trial_ends_at'])
          : null,
      subscriptionEndsAt: json['subscription_ends_at'] != null
          ? DateTime.tryParse(json['subscription_ends_at'])
          : null,
      settings: json['settings'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'license_no': licenseNo,
      'phone': phone,
      'email': email,
      'address': address,
      'logo_url': logoUrl,
      'plan_type': planType,
      'status': status,
      'currency': currency,
      'trial_ends_at': trialEndsAt?.toIso8601String(),
      'subscription_ends_at': subscriptionEndsAt?.toIso8601String(),
      'settings': settings,
    };
  }
}
