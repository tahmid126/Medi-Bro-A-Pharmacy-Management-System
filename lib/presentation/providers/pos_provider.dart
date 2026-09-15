import 'package:flutter/material.dart';
import '../../core/utils/error_formatter.dart';
import '../../data/models/batch_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/medicine_model.dart';
import '../../data/services/pos_service.dart';

class PosCartItem {
  final MedicineModel medicine;
  final BatchModel batch;
  int quantity;
  double unitPrice;

  PosCartItem({
    required this.medicine,
    required this.batch,
    this.quantity = 1,
    required this.unitPrice,
  });

  double get totalPrice => quantity * unitPrice;
}

class PosProvider extends ChangeNotifier {
  final PosService _posService = PosService();

  final List<PosCartItem> _cartItems = [];
  CustomerModel? _selectedCustomer;
  String _customerName = 'Walking Customer';
  String? _customerPhone;

  double _discountAmount = 0.0;
  String _discountType = 'fixed'; // 'fixed' or 'percent'
  double _vatPercent = 0.0;
  double _paidAmount = 0.0;
  String _paymentMethod = 'cash'; // 'cash', 'bkash', 'nagad', 'card'
  String? _notes;

  bool _isProcessing = false;
  String? _errorMessage;

  List<PosCartItem> get cartItems => _cartItems;
  CustomerModel? get selectedCustomer => _selectedCustomer;
  String get customerName => _customerName;
  String? get customerPhone => _customerPhone;
  double get discountAmount => _discountAmount;
  String get discountType => _discountType;
  double get vatPercent => _vatPercent;
  double get paidAmount => _paidAmount;
  String get paymentMethod => _paymentMethod;
  String? get notes => _notes;
  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;

  double get subtotal => _cartItems.fold(0.0, (sum, item) => sum + item.totalPrice);

  double get calculatedDiscount {
    if (_discountType == 'percent') {
      return (subtotal * _discountAmount) / 100;
    }
    return _discountAmount;
  }

  double get calculatedVat {
    final afterDiscount = subtotal - calculatedDiscount;
    return (afterDiscount * _vatPercent) / 100;
  }

  double get grandTotal {
    final total = subtotal - calculatedDiscount + calculatedVat;
    return total > 0 ? total : 0.0;
  }

  double get dueAmount {
    final due = grandTotal - _paidAmount;
    return due > 0 ? due : 0.0;
  }

  void addToCart(MedicineModel med, BatchModel batch, {int qty = 1}) {
    final existingIndex = _cartItems.indexWhere(
      (item) => item.medicine.id == med.id && item.batch.id == batch.id,
    );

    if (existingIndex != -1) {
      final currentQty = _cartItems[existingIndex].quantity;
      if (currentQty + qty <= batch.stockQty) {
        _cartItems[existingIndex].quantity += qty;
      }
    } else {
      if (batch.stockQty >= qty) {
        _cartItems.add(
          PosCartItem(
            medicine: med,
            batch: batch,
            quantity: qty,
            unitPrice: batch.sellingPrice > 0 ? batch.sellingPrice : batch.mrp,
          ),
        );
      }
    }
    _paidAmount = grandTotal; // default full paid
    notifyListeners();
  }

  void updateQuantity(int index, int newQty) {
    if (index >= 0 && index < _cartItems.length) {
      final item = _cartItems[index];
      if (newQty <= 0) {
        _cartItems.removeAt(index);
      } else if (newQty <= item.batch.stockQty) {
        item.quantity = newQty;
      }
      _paidAmount = grandTotal;
      notifyListeners();
    }
  }

  void removeFromCart(int index) {
    if (index >= 0 && index < _cartItems.length) {
      _cartItems.removeAt(index);
      _paidAmount = grandTotal;
      notifyListeners();
    }
  }

  void clearCart() {
    _cartItems.clear();
    _selectedCustomer = null;
    _customerName = 'Walking Customer';
    _customerPhone = null;
    _discountAmount = 0.0;
    _paidAmount = 0.0;
    _notes = null;
    notifyListeners();
  }

  void setCustomer({CustomerModel? customer, String? name, String? phone}) {
    _selectedCustomer = customer;
    _customerName = customer?.name ?? name ?? 'Walking Customer';
    _customerPhone = customer?.phone ?? phone;
    notifyListeners();
  }

  void setDiscount(double amount, {String type = 'fixed'}) {
    _discountAmount = amount;
    _discountType = type;
    _paidAmount = grandTotal;
    notifyListeners();
  }

  void setVatPercent(double percent) {
    _vatPercent = percent;
    _paidAmount = grandTotal;
    notifyListeners();
  }

  void setPaidAmount(double amount) {
    _paidAmount = amount;
    notifyListeners();
  }

  void setPaymentMethod(String method) {
    _paymentMethod = method;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> checkout() async {
    if (_cartItems.isEmpty) return null;

    _isProcessing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final itemsPayload = _cartItems.map((item) {
        return {
          'medicine_id': item.medicine.id,
          'batch_id': item.batch.id,
          'medicine_name': item.medicine.brandName,
          'batch_number': item.batch.batchNumber,
          'expiry_date': item.batch.expiryDate.toIso8601String().split('T').first,
          'quantity': item.quantity,
          'unit_price': item.unitPrice,
          'mrp': item.batch.mrp,
          'purchase_price': item.batch.purchasePrice,
        };
      }).toList();

      final result = await _posService.submitSale(
        customerId: _selectedCustomer?.id,
        customerName: _customerName,
        customerPhone: _customerPhone,
        subtotal: subtotal,
        discountType: _discountType,
        discountAmount: calculatedDiscount,
        vatPercent: _vatPercent,
        vatAmount: calculatedVat,
        grandTotal: grandTotal,
        paidAmount: _paidAmount,
        dueAmount: dueAmount,
        paymentMethod: _paymentMethod,
        notes: _notes,
        items: itemsPayload,
      );

      clearCart();
      _isProcessing = false;
      notifyListeners();
      return result;
    } catch (e) {
      _errorMessage = ErrorFormatter.format(e);
      _isProcessing = false;
      notifyListeners();
      return null;
    }
  }
}
