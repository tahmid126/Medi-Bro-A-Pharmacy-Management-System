import 'package:flutter/material.dart';
import 'medicine_model.dart';

class CartItemEntry {
  final MedicineModel medicine;
  String batchNumber;
  DateTime expiryDate;
  int quantity;
  int bonusQuantity;
  String unitType; // 'Unit', 'Strip', 'Box'
  String bonusUnitType; // 'Unit', 'Strip', 'Box'
  double unitPurchasePrice; // Buy rate for 1 of the selected unitType (e.g. 1 Box or 1 Unit)
  double mrp; // library MRP per individual unit
  double discountPercent;
  String discountMode; // '%' or 'Cash'
  int piecesPerStrip;
  int stripsPerBox;
  String? rackLocation;
  final TextEditingController qtyController;
  final TextEditingController priceController;
  final TextEditingController rackController;

  CartItemEntry({
    required this.medicine,
    required this.batchNumber,
    required this.expiryDate,
    this.quantity = 1,
    this.bonusQuantity = 0,
    this.unitType = 'Unit',
    String? bonusUnitType,
    required this.unitPurchasePrice,
    required this.mrp,
    this.discountPercent = 12.0,
    this.discountMode = '%',
    required this.piecesPerStrip,
    required this.stripsPerBox,
    this.rackLocation,
  })  : bonusUnitType = bonusUnitType ?? unitType,
        qtyController = TextEditingController(text: quantity.toString()),
        priceController = TextEditingController(
          text: unitPurchasePrice > 0 ? unitPurchasePrice.toStringAsFixed(2) : '',
        ),
        rackController = TextEditingController(
          text: rackLocation ?? medicine.rackLocation ?? '',
        );

  bool get hasTwoTierPack => piecesPerStrip > 1 && stripsPerBox > 1;
  bool get hasSingleTierPack => (piecesPerStrip > 1 || stripsPerBox > 1) && !hasTwoTierPack;

  int get boxPieces {
    if (hasTwoTierPack) {
      return stripsPerBox * piecesPerStrip;
    } else if (hasSingleTierPack) {
      return piecesPerStrip > 1 ? piecesPerStrip : stripsPerBox;
    }
    return 1;
  }

  int get multiplier {
    switch (unitType) {
      case 'Strip':
        return piecesPerStrip > 0 ? piecesPerStrip : 1;
      case 'Box':
        return boxPieces;
      default:
        return 1;
    }
  }

  int get bonusMultiplier {
    switch (bonusUnitType) {
      case 'Strip':
        return piecesPerStrip > 0 ? piecesPerStrip : 1;
      case 'Box':
        return boxPieces;
      default:
        return 1;
    }
  }

  /// Calculated MRP for the selected unitType
  double get unitMrp => mrp * multiplier;

  /// Total physical units including bonus (if same unit) or total pcs
  int get totalUnitsWithBonus => unitType == bonusUnitType ? (quantity + bonusQuantity) : effectiveUnits;

  /// Effective stock units in individual pieces for database insertion
  int get effectiveUnits => (quantity * multiplier) + (bonusQuantity * bonusMultiplier);

  /// Billed Line Total (bonus items are free)
  double get lineTotal => unitPurchasePrice * quantity;

  /// True buy rate per individual unit based on the purchase price of the selected packaging (unadjusted by free bonus units)
  double get singleUnitBuyPrice => multiplier > 0
      ? (unitPurchasePrice / multiplier)
      : unitPurchasePrice;

  /// Weighted average cost per individual base unit (accounting for free bonus units)
  double get effectiveSingleUnitBuyPrice => effectiveUnits > 0
      ? (lineTotal / effectiveUnits)
      : singleUnitBuyPrice;

  /// Weighted average buy rate for the selected unitType (e.g. per Box or Strip)
  double get effectiveUnitBuyPrice => effectiveSingleUnitBuyPrice * multiplier;

  // Backwards compatibility getter & setter
  double get retailPrice => singleUnitBuyPrice;
  set retailPrice(double val) => unitPurchasePrice = val;

  void dispose() {
    qtyController.dispose();
    priceController.dispose();
    rackController.dispose();
  }
}
