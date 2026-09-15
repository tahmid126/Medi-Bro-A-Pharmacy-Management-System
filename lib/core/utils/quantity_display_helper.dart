class FormattedQuantity {
  final String quantityDisplay; // e.g. "1B", "1S", "1X", "2B"
  final double unitRate;        // rate per displayed unit (e.g. per box, strip, or single unit)
  final int count;              // e.g. 1, 2
  final String unitType;        // 'Box', 'Strip', 'Unit'
  final String unitSuffix;      // 'B', 'S', 'X'

  const FormattedQuantity({
    required this.quantityDisplay,
    required this.unitRate,
    required this.count,
    required this.unitType,
    required this.unitSuffix,
  });
}

class QuantityDisplayHelper {
  /// Format item quantity and calculated unit rate according to unit type:
  /// - Box: '[qty]B' with rate per box
  /// - Strip: '[qty]S' with rate per strip
  /// - Unit / all other items: '[qty]X' with rate per unit
  static FormattedQuantity format({
    required int totalUnits,
    required double totalPrice,
    String? unitType,
    int? rawQuantity,
    int? piecesPerStrip,
    int? stripsPerBox,
    String? dosageForm,
    String? medicineUnit,
  }) {
    final bool hasTwoTier = (piecesPerStrip != null && piecesPerStrip > 0) && (stripsPerBox != null && stripsPerBox > 0);
    final int pps = (piecesPerStrip != null && piecesPerStrip > 0) ? piecesPerStrip : 1;
    final int spb = (stripsPerBox != null && stripsPerBox > 0) ? stripsPerBox : 1;
    final int boxSize = hasTwoTier ? (spb * pps) : (piecesPerStrip != null && piecesPerStrip > 1 ? piecesPerStrip : (stripsPerBox != null && stripsPerBox > 1 ? stripsPerBox : 1));

    final normalizedUnit = (unitType ?? '').trim().toLowerCase();

    // 1. Explicit unitType provided
    if (normalizedUnit == 'box' || normalizedUnit == 'b') {
      int count = rawQuantity ?? (boxSize > 0 ? (totalUnits / boxSize).round() : 1);
      if (count <= 0) count = 1;
      final rate = count > 0 ? (totalPrice / count) : totalPrice;
      return FormattedQuantity(
        quantityDisplay: '${count}B',
        unitRate: rate,
        count: count,
        unitType: 'Box',
        unitSuffix: 'B',
      );
    } else if (normalizedUnit == 'strip' || normalizedUnit == 's') {
      int count = rawQuantity ?? (pps > 0 ? (totalUnits / pps).round() : 1);
      if (count <= 0) count = 1;
      final rate = count > 0 ? (totalPrice / count) : totalPrice;
      return FormattedQuantity(
        quantityDisplay: '${count}S',
        unitRate: rate,
        count: count,
        unitType: 'Strip',
        unitSuffix: 'S',
      );
    } else if (normalizedUnit == 'unit' || normalizedUnit == 'u' || normalizedUnit == 'x' || normalizedUnit == 'pcs') {
      int count = rawQuantity ?? (totalUnits > 0 ? totalUnits : 1);
      if (count <= 0) count = 1;
      final rate = count > 0 ? (totalPrice / count) : totalPrice;
      return FormattedQuantity(
        quantityDisplay: '${count}U',
        unitRate: rate,
        count: count,
        unitType: 'Unit',
        unitSuffix: 'U',
      );
    }

    // 2. Inferred from totalUnits and packaging
    if (boxSize > 1 && totalUnits >= boxSize && (totalUnits % boxSize == 0)) {
      final count = totalUnits ~/ boxSize;
      final rate = count > 0 ? (totalPrice / count) : totalPrice;
      return FormattedQuantity(
        quantityDisplay: '${count}B',
        unitRate: rate,
        count: count,
        unitType: 'Box',
        unitSuffix: 'B',
      );
    } else if (hasTwoTier && pps > 1 && totalUnits >= pps && (totalUnits % pps == 0)) {
      final count = totalUnits ~/ pps;
      final rate = count > 0 ? (totalPrice / count) : totalPrice;
      return FormattedQuantity(
        quantityDisplay: '${count}S',
        unitRate: rate,
        count: count,
        unitType: 'Strip',
        unitSuffix: 'S',
      );
    } else {
      final count = totalUnits > 0 ? totalUnits : 1;
      final rate = count > 0 ? (totalPrice / count) : totalPrice;
      return FormattedQuantity(
        quantityDisplay: '${count}U',
        unitRate: rate,
        count: count,
        unitType: 'Unit',
        unitSuffix: 'U',
      );
    }
  }
}
