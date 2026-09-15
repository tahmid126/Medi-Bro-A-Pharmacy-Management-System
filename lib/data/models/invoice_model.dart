class CustomerModel {
  final String id;
  final String pharmacyId;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final double totalPurchased;
  final double currentDue;
  final bool isActive;

  CustomerModel({
    required this.id,
    required this.pharmacyId,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.totalPurchased = 0.0,
    this.currentDue = 0.0,
    this.isActive = true,
  });

  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    return CustomerModel(
      id: json['id'] as String,
      pharmacyId: json['pharmacy_id'] as String,
      name: json['name'] as String? ?? 'Walking Customer',
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      address: json['address'] as String?,
      totalPurchased: (json['total_purchased'] as num?)?.toDouble() ?? 0.0,
      currentDue: (json['current_due'] as num?)?.toDouble() ?? 0.0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pharmacy_id': pharmacyId,
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'total_purchased': totalPurchased,
      'current_due': currentDue,
      'is_active': isActive,
    };
  }
}

class InvoiceItemModel {
  final String? id;
  final String medicineId;
  final String batchId;
  final String medicineName;
  final String? batchNumber;
  final DateTime? expiryDate;
  final int quantity;
  final double unitPrice;
  final double mrp;
  final double purchasePrice;
  final double totalPrice;

  InvoiceItemModel({
    this.id,
    required this.medicineId,
    required this.batchId,
    required this.medicineName,
    this.batchNumber,
    this.expiryDate,
    required this.quantity,
    required this.unitPrice,
    required this.mrp,
    this.purchasePrice = 0.0,
    required this.totalPrice,
  });

  factory InvoiceItemModel.fromJson(Map<String, dynamic> json) {
    return InvoiceItemModel(
      id: json['id'] as String?,
      medicineId: json['medicine_id'] as String,
      batchId: json['batch_id'] as String,
      medicineName: json['medicine_name'] as String? ?? '',
      batchNumber: json['batch_number'] as String?,
      expiryDate: json['expiry_date'] != null ? DateTime.tryParse(json['expiry_date']) : null,
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      mrp: (json['mrp'] as num?)?.toDouble() ?? 0.0,
      purchasePrice: (json['purchase_price'] as num?)?.toDouble() ?? 0.0,
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'medicine_id': medicineId,
      'batch_id': batchId,
      'medicine_name': medicineName,
      'batch_number': batchNumber,
      'expiry_date': expiryDate?.toIso8601String().split('T').first,
      'quantity': quantity,
      'unit_price': unitPrice,
      'mrp': mrp,
      'purchase_price': purchasePrice,
      'total_price': totalPrice,
    };
  }
}

class InvoiceModel {
  final String id;
  final String pharmacyId;
  final String invoiceNumber;
  final String? customerId;
  final String customerName;
  final String? customerPhone;
  final double subtotal;
  final String discountType;
  final double discountAmount;
  final double vatPercent;
  final double vatAmount;
  final double grandTotal;
  final double paidAmount;
  final double dueAmount;
  final String paymentMethod;
  final String status;
  final String? notes;
  final String? servedBy;
  final DateTime createdAt;
  final List<InvoiceItemModel> items;

  InvoiceModel({
    required this.id,
    required this.pharmacyId,
    required this.invoiceNumber,
    this.customerId,
    this.customerName = 'Walking Customer',
    this.customerPhone,
    required this.subtotal,
    this.discountType = 'fixed',
    this.discountAmount = 0.0,
    this.vatPercent = 0.0,
    this.vatAmount = 0.0,
    required this.grandTotal,
    required this.paidAmount,
    required this.dueAmount,
    this.paymentMethod = 'cash',
    this.status = 'completed',
    this.notes,
    this.servedBy,
    required this.createdAt,
    this.items = const [],
  });

  factory InvoiceModel.fromJson(Map<String, dynamic> json, {List<InvoiceItemModel>? items}) {
    return InvoiceModel(
      id: json['id'] as String,
      pharmacyId: json['pharmacy_id'] as String,
      invoiceNumber: json['invoice_number'] as String? ?? '',
      customerId: json['customer_id'] as String?,
      customerName: json['customer_name'] as String? ?? 'Walking Customer',
      customerPhone: json['customer_phone'] as String?,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      discountType: json['discount_type'] as String? ?? 'fixed',
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0.0,
      vatPercent: (json['vat_percent'] as num?)?.toDouble() ?? 0.0,
      vatAmount: (json['vat_amount'] as num?)?.toDouble() ?? 0.0,
      grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0.0,
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0.0,
      dueAmount: (json['due_amount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      status: json['status'] as String? ?? 'completed',
      notes: json['notes'] as String?,
      servedBy: json['served_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      items: items ?? [],
    );
  }
}
