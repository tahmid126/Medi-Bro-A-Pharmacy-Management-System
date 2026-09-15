import 'package:flutter/material.dart';
import 'batch_model.dart';
import 'medicine_model.dart';

class ExportCartItem {
  final MedicineModel medicine;
  final BatchModel? batch;
  int quantity;
  String unitType; // 'Unit', 'Strip', 'Box'
  double singleUnitMrp; // MRP per individual unit/piece
  double singleUnitCost; // Purchase price per individual unit/piece
  double unitSellingPrice; // Selling price for 1 of the selected unitType
  int piecesPerStrip;
  int stripsPerBox;
  double discountPercent;
  String discountMode; // '%' or 'Cash'
  final TextEditingController qtyController;
  final TextEditingController priceController;

  ExportCartItem({
    required this.medicine,
    this.batch,
    this.quantity = 1,
    required this.unitType,
    required this.singleUnitMrp,
    required this.singleUnitCost,
    required this.unitSellingPrice,
    required this.piecesPerStrip,
    required this.stripsPerBox,
    this.discountPercent = 0.0,
    this.discountMode = '%',
  })  : qtyController = TextEditingController(text: quantity.toString()),
        priceController = TextEditingController(
          text: unitSellingPrice > 0 ? unitSellingPrice.toStringAsFixed(2) : '',
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

  double get selectedUnitMrp => singleUnitMrp * multiplier;
  double get selectedUnitCost => singleUnitCost * multiplier;
  int get effectiveUnits => quantity * multiplier;
  double get lineTotal => unitSellingPrice * quantity;

  void dispose() {
    qtyController.dispose();
    priceController.dispose();
  }
}
