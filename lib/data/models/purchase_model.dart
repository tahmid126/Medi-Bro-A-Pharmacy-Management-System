class PurchaseItemModel {
  final String? id;
  final String medicineId;
  final String? batchId;
  final String medicineName;
  final String dosageForm;
  final String? strength;
  final String? weight;
  final String batchNumber;
  final DateTime expiryDate;
  final int quantity; // effective total individual units (e.g. 2 strips * 10 = 20)
  final int rawQuantity; // quantity entered by user (e.g. 2)
  final String unitType; // 'Unit', 'Strip', 'Box'
  final int piecesPerStrip;
  final int stripsPerBox;
  final double purchasePrice; // rate per unit
  final double sellingPrice;
  final double mrp;
  final double totalPrice;
  final String? rackLocation;

  PurchaseItemModel({
    this.id,
    required this.medicineId,
    this.batchId,
    required this.medicineName,
    this.dosageForm = '',
    this.strength,
    this.weight,
    required this.batchNumber,
    required this.expiryDate,
    required this.quantity,
    int? rawQuantity,
    this.unitType = 'Unit',
    this.piecesPerStrip = 1,
    this.stripsPerBox = 1,
    required this.purchasePrice,
    required this.sellingPrice,
    double? mrp,
    required this.totalPrice,
    this.rackLocation,
  })  : rawQuantity = rawQuantity ?? quantity,
        mrp = mrp ?? (sellingPrice > 0 ? sellingPrice : purchasePrice);

  factory PurchaseItemModel.fromJson(Map<String, dynamic> json) {
    return PurchaseItemModel(
      id: json['id'] as String?,
      medicineId: json['medicine_id'] as String,
      batchId: json['batch_id'] as String?,
      medicineName: json['medicine_name'] as String? ?? '',
      dosageForm: (json['dosage_form'] as String?)?.trim() ?? '',
      strength: json['strength'] as String?,
      weight: json['weight'] as String?,
      batchNumber: json['batch_number'] as String? ?? '',
      expiryDate: DateTime.parse(json['expiry_date'] as String),
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      rawQuantity: (json['raw_quantity'] as num?)?.toInt(),
      unitType: json['unit_type'] as String? ?? 'Unit',
      piecesPerStrip: (json['pieces_per_strip'] as num?)?.toInt() ?? 1,
      stripsPerBox: (json['strips_per_box'] as num?)?.toInt() ?? 1,
      purchasePrice: (json['purchase_price'] as num?)?.toDouble() ?? 0.0,
      sellingPrice: (json['selling_price'] as num?)?.toDouble() ?? 0.0,
      mrp: (json['mrp'] as num?)?.toDouble(),
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0.0,
      rackLocation: json['rack_location'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'medicine_id': medicineId,
      'batch_id': batchId,
      'medicine_name': medicineName,
      'batch_number': batchNumber,
      'expiry_date': expiryDate.toIso8601String().split('T').first,
      'quantity': quantity,
      'purchase_price': purchasePrice,
      'selling_price': sellingPrice,
      'total_price': totalPrice,
    };
  }
}

class PurchaseModel {
  final String id;
  final String pharmacyId;
  final String purchaseNumber;
  final String? supplierId;
  final String? supplierName;
  final double totalAmount;
  final double discountAmount;
  final double grandTotal;
  final double paidAmount;
  final double dueAmount;
  final String paymentMethod;
  final DateTime purchaseDate;
  final String? notes;
  final List<PurchaseItemModel> items;

  PurchaseModel({
    required this.id,
    required this.pharmacyId,
    required this.purchaseNumber,
    this.supplierId,
    this.supplierName,
    required this.totalAmount,
    this.discountAmount = 0.0,
    required this.grandTotal,
    required this.paidAmount,
    required this.dueAmount,
    this.paymentMethod = 'cash',
    required this.purchaseDate,
    this.notes,
    this.items = const [],
  });

  factory PurchaseModel.fromJson(Map<String, dynamic> json, {List<PurchaseItemModel>? items}) {
    return PurchaseModel(
      id: json['id'] as String,
      pharmacyId: json['pharmacy_id'] as String,
      purchaseNumber: json['purchase_number'] as String? ?? '',
      supplierId: json['supplier_id'] as String?,
      supplierName: json['supplier_name'] as String?,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0.0,
      grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0.0,
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0.0,
      dueAmount: (json['due_amount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      purchaseDate: json['purchase_date'] != null
          ? DateTime.parse(json['purchase_date'])
          : DateTime.now(),
      notes: json['notes'] as String?,
      items: items ?? [],
    );
  }
}
