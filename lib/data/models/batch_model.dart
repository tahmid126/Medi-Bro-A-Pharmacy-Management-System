class BatchModel {
  final String id;
  final String pharmacyId;
  final String medicineId;
  final String batchNumber;
  final DateTime expiryDate;
  final double purchasePrice;
  final double sellingPrice;
  final double mrp;
  final int stockQty;
  final bool isActive;

  BatchModel({
    required this.id,
    required this.pharmacyId,
    required this.medicineId,
    required this.batchNumber,
    required this.expiryDate,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.mrp,
    required this.stockQty,
    this.isActive = true,
  });

  bool get isExpired => expiryDate.isBefore(DateTime.now());
  bool get isNearExpiry {
    final diff = expiryDate.difference(DateTime.now()).inDays;
    return diff >= 0 && diff <= 90; // within 3 months
  }

  factory BatchModel.fromJson(Map<String, dynamic> json) {
    return BatchModel(
      id: json['id'] as String,
      pharmacyId: json['pharmacy_id'] as String,
      medicineId: json['medicine_id'] as String,
      batchNumber: json['batch_number'] as String? ?? 'N/A',
      expiryDate: DateTime.parse(json['expiry_date'] as String),
      purchasePrice: (json['purchase_price'] as num?)?.toDouble() ?? 0.0,
      sellingPrice: (json['selling_price'] as num?)?.toDouble() ?? 0.0,
      mrp: (json['mrp'] as num?)?.toDouble() ?? 0.0,
      stockQty: (json['stock_qty'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pharmacy_id': pharmacyId,
      'medicine_id': medicineId,
      'batch_number': batchNumber,
      'expiry_date': expiryDate.toIso8601String().split('T').first,
      'purchase_price': purchasePrice,
      'selling_price': sellingPrice,
      'mrp': mrp,
      'stock_qty': stockQty,
      'is_active': isActive,
    };
  }
}
