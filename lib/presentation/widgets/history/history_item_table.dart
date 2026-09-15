import 'package:flutter/material.dart';
import '../../../../core/utils/quantity_display_helper.dart';
import '../../../../data/models/medicine_model.dart';

class HistoryItemTable extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final Map<String, MedicineModel> medMap;
  final bool isCost; // true for Import (Cost), false for Export (Rate)
  final List<dynamic>? itemsDetail; // detailed items info parsed from notes

  const HistoryItemTable({
    super.key,
    required this.items,
    required this.medMap,
    this.isCost = false,
    this.itemsDetail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(4),
          1: FlexColumnWidth(2.2),
          2: FlexColumnWidth(2.2),
          3: FlexColumnWidth(2.0),
          4: FlexColumnWidth(2.4),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            children: [
              _buildHeaderCell('Medicine'),
              _buildHeaderCell('Batch'),
              _buildHeaderCell('Qty', align: TextAlign.center),
              _buildHeaderCell(isCost ? 'Cost' : 'Rate', align: TextAlign.right),
              _buildHeaderCell('Total', align: TextAlign.right),
            ],
          ),
          ...items.map((item) => _buildRow(item)),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Text(
        text,
        textAlign: align,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }

  Map<String, dynamic>? _findDetail(Map<String, dynamic> item) {
    if (itemsDetail == null || itemsDetail!.isEmpty) return null;
    final medId = item['medicine_id']?.toString();
    final medName = item['medicine_name']?.toString().toLowerCase().trim();
    for (final d in itemsDetail!) {
      if (d is Map) {
        final dMedId = d['medicine_id']?.toString();
        if (medId != null && dMedId != null && medId == dMedId) {
          return Map<String, dynamic>.from(d);
        }
        final dName = (d['brand_name'] ?? d['medicine_name'])?.toString().toLowerCase().trim();
        if (medName != null && dName != null && medName == dName) {
          return Map<String, dynamic>.from(d);
        }
      }
    }
    return null;
  }

  String _unitSuffix(String? unitType) {
    if (unitType == null || unitType.isEmpty) return 'U';
    final u = unitType.trim().toLowerCase();
    if (u.startsWith('b')) return 'B';
    if (u.startsWith('s')) return 'S';
    return 'U';
  }

  TableRow _buildRow(Map<String, dynamic> item) {
    final medId = item['medicine_id']?.toString() ?? '';
    final med = medMap[medId];
    final int totalUnits = (item['quantity'] as num?)?.toInt() ?? 1;
    final double totalPrice = ((item['total_price'] as num?)?.toDouble() ?? 0.0);
    final fmt = QuantityDisplayHelper.format(
      totalUnits: totalUnits,
      totalPrice: totalPrice,
      piecesPerStrip: med?.piecesPerStrip,
      stripsPerBox: med?.stripsPerBox,
      dosageForm: med?.dosageForm,
      medicineUnit: med?.unit,
    );

    final detail = _findDetail(item);
    String quantityDisplay;
    double displayRate;

    if (detail != null) {
      final int rawQty = (detail['raw_quantity'] as num?)?.toInt() ?? 0;
      final int bonusQty = (detail['bonus_quantity'] as num?)?.toInt() ?? 0;
      final String unitType = detail['unit_type']?.toString() ?? 'Unit';
      final String bonusUnitType = detail['bonus_unit_type']?.toString() ?? unitType;
      final String rawSuffix = _unitSuffix(unitType);
      final String bonusSuffix = _unitSuffix(bonusUnitType);

      if (bonusQty > 0) {
        quantityDisplay = '$rawQty$rawSuffix(+$bonusQty$bonusSuffix)';
      } else if (rawQty > 0) {
        quantityDisplay = '$rawQty$rawSuffix';
      } else {
        quantityDisplay = fmt.quantityDisplay;
      }

      // Cost Rate for Import or Selling Rate for Export for the SELECTED unit type (Box, Strip, or Unit)
      if (isCost) {
        final unitPurchasePrice = (detail['unit_purchase_price'] as num?)?.toDouble();
        final lineTotal = (detail['line_total'] as num?)?.toDouble();
        if (unitPurchasePrice != null && unitPurchasePrice > 0) {
          displayRate = unitPurchasePrice;
        } else if (rawQty > 0 && lineTotal != null && lineTotal > 0) {
          displayRate = lineTotal / rawQty;
        } else {
          displayRate = fmt.unitRate;
        }
      } else {
        final unitSellingPrice = (detail['unit_selling_price'] as num?)?.toDouble();
        final lineTotal = (detail['line_total'] as num?)?.toDouble();
        if (unitSellingPrice != null && unitSellingPrice > 0) {
          displayRate = unitSellingPrice;
        } else if (rawQty > 0 && lineTotal != null && lineTotal > 0) {
          displayRate = lineTotal / rawQty;
        } else {
          displayRate = fmt.unitRate;
        }
      }
    } else {
      quantityDisplay = fmt.quantityDisplay;
      displayRate = fmt.unitRate;
    }

    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Text(
            item['medicine_name'] ?? 'Item',
            style: const TextStyle(fontSize: 11),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Text(
            item['batch_number'] ?? '-',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              quantityDisplay,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                color: Colors.teal.shade800,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Text(
            '৳${displayRate.toStringAsFixed(2)}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Text(
            '৳${totalPrice.toStringAsFixed(2)}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
