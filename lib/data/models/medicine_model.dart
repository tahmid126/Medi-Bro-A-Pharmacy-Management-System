import 'batch_model.dart';

class MedicineModel {
  final String id;
  final String pharmacyId;
  final String? globalId;
  final String brandName;
  final String? genericName;
  final String dosageForm; // Tablet, Capsule, Syrup, etc.
  final String? strength;   // 500mg, 10ml, etc.
  final String? company;    // Square, Beximco, etc.
  final String? category;
  final String? rackLocation;
  final String unit;        // Pcs, Strip, Box, Bottle
  final int minStockAlert;
  final bool isActive;
  final List<BatchModel> batches;
  final int? piecesPerStrip;
  final int? stripsPerBox;
  final String? weight;
  final double? catalogPrice;

  MedicineModel({
    required this.id,
    required this.pharmacyId,
    this.globalId,
    required this.brandName,
    this.genericName,
    this.dosageForm = '',
    this.strength,
    this.company,
    this.category,
    this.rackLocation,
    this.unit = 'Pcs',
    this.minStockAlert = 10,
    this.isActive = true,
    this.batches = const [],
    this.piecesPerStrip,
    this.stripsPerBox,
    this.weight,
    this.catalogPrice,
  });

  int get totalStock => batches.fold(0, (sum, b) => sum + b.stockQty);
  
  bool get isLowStock => totalStock <= minStockAlert;
  bool get isOutOfStock => totalStock <= 0;

  BatchModel? get primaryActiveBatch {
    if (batches.isEmpty) return null;
    final validBatches = batches.where((b) => b.stockQty > 0).toList()
      ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    return validBatches.isNotEmpty ? validBatches.first : batches.first;
  }

  factory MedicineModel.fromJson(Map<String, dynamic> json, {List<BatchModel>? batches, double? catalogPrice}) {
    String? strength = json['strength'] as String?;
    String? weight = (json['weight'] as String?)?.trim();
    int? piecesPerStrip = (json['pieces_per_strip'] as num?)?.toInt();
    int? stripsPerBox = (json['strips_per_box'] as num?)?.toInt();

    // Fallback parsing from strength string (for older records or merged strings)
    if (strength != null && strength.isNotEmpty) {
      // 1. Extract [MRP: ...] if price not already present
      final mrpMatch = RegExp(r'\[MRP:\s*[৳$]?\s*(\d+(?:\.\d+)?)\]', caseSensitive: false).firstMatch(strength);
      if (mrpMatch != null) {
        catalogPrice ??= double.tryParse(mrpMatch.group(1)!);
        strength = strength.replaceAll(RegExp(r'\[MRP:\s*[৳$]?\s*\d+(?:\.\d+)?\]', caseSensitive: false), '').trim();
      }

      // 2. Extract packaging ratio like (10*10), (1*25), (25's) if not already present
      if (piecesPerStrip == null || stripsPerBox == null) {
        final packPattern = RegExp(r'[\(\[]\s*(\d+)\s*[*xX×]\s*(\d+)(?:\x27?s|\s*pcs)?\s*[\)\]]', caseSensitive: false);
        final packMatch = packPattern.firstMatch(strength);
        if (packMatch != null) {
          final sVal = int.tryParse(packMatch.group(1)!);
          final pVal = int.tryParse(packMatch.group(2)!);
          if (sVal != null && pVal != null) {
            if (sVal == 1) {
              piecesPerStrip ??= pVal;
            } else {
              stripsPerBox ??= sVal;
              piecesPerStrip ??= pVal;
            }
          }
        } else {
          final singlePackPattern = RegExp(r'[\(\[]\s*(\d+)(?:\x27?s|\s*pcs|\s*pack|\s*tabs|\s*caps|\s*sachets?)\s*[\)\]]', caseSensitive: false);
          final singleMatch = singlePackPattern.firstMatch(strength);
          if (singleMatch != null) {
            piecesPerStrip ??= int.tryParse(singleMatch.group(1)!);
          }
        }
      }

      // Strip pack size patterns from strength
      final stripPackRegex = RegExp(
        r'[\(\[]\s*\d+\s*[*xX×]\s*\d+.*[\)\]]|[\(\[]\s*\d+(?:\x27?s|\s*pcs|\s*pack|\s*tabs|\s*caps|\s*sachets?|\s*tubes?|.*?)[\)\]]',
        caseSensitive: false,
      );
      final strippedStrength = strength.replaceAll(stripPackRegex, '').trim();

      // 3. Extract weight/volume if not already present in DB
      if (weight == null || weight.isEmpty) {
        final parenVol = RegExp(
          r'[\(\[]\s*([^()\[\]]+?(?:ml|gm|g|l|kg|pads?|sachets?|tubes?|drops?|spray)[^()\[\]]*)\s*[\)\]]',
          caseSensitive: false,
        ).firstMatch(strength);
        if (parenVol != null) {
          weight = parenVol.group(1)!.replaceAll(RegExp(r'[\(\)\[\]]'), '').trim();
        } else {
          final standaloneVol = RegExp(
            r'^\d+(?:\.\d+)?\s*(?:ml|gm|g|l|kg|pads?|sachets?|tubes?|drops?|spray)$',
            caseSensitive: false,
          ).firstMatch(strippedStrength);
          if (standaloneVol != null) {
            weight = strippedStrength;
          }
        }
      }

      // 4. Clean strength to leave only genuine chemical potency
      String cleanStr = strippedStrength;
      if (weight != null && weight.isNotEmpty) {
        final wClean = weight.replaceAll(RegExp(r'[\(\)\[\]]'), '').trim().toLowerCase();
        // Remove parenthesized weight
        cleanStr = cleanStr.replaceAll(RegExp('\\s*\\(\\s*${RegExp.escape(wClean)}\\s*\\)', caseSensitive: false), '').trim();
        cleanStr = cleanStr.replaceAll(RegExp('\\s*\\[\\s*${RegExp.escape(wClean)}\\s*\\]', caseSensitive: false), '').trim();
        if (cleanStr.toLowerCase() == wClean || cleanStr.toLowerCase() == wClean.replaceAll(' ', '')) {
          cleanStr = '';
        }
      }

      // Strip pure physical weights from strength
      if (RegExp(r'^\d+(?:\.\d+)?\s*(?:ml|gm|g|l|kg|pads?|sachets?|tubes?|drops?|spray)$', caseSensitive: false).hasMatch(cleanStr)) {
        cleanStr = '';
      }

      // Unwrap outer parentheses
      if (cleanStr.startsWith('(') && cleanStr.endsWith(')')) {
        cleanStr = cleanStr.substring(1, cleanStr.length - 1).trim();
      }

      // If strength is only pack patterns or pure numbers, nullify it
      final packOnlyPattern = RegExp(
        r'^[\(\[]?\s*\d+\s*[*xX×]\s*\d+.*[\)\]]?$|^[\(\[]?\s*\d+(?:\x27?s|\s*pcs|\s*pack|\s*tabs|\s*caps)?\s*[\)\]]?$|^\d+$',
        caseSensitive: false,
      );
      if (cleanStr.isEmpty || packOnlyPattern.hasMatch(cleanStr)) {
        strength = null;
      } else {
        strength = cleanStr;
      }
    }

    double? resolvedCatalogPrice = catalogPrice ??
        (json['catalog_price'] as num?)?.toDouble() ??
        (json['default_mrp'] as num?)?.toDouble() ??
        (json['mrp'] as num?)?.toDouble() ??
        (json['mrp_price'] as num?)?.toDouble();

    if (resolvedCatalogPrice == null || resolvedCatalogPrice <= 0) {
      final rawBatches = json['batches'] as List?;
      if (rawBatches != null && rawBatches.isNotEmpty) {
        for (final b in rawBatches) {
          final m = (b['mrp'] as num?)?.toDouble() ?? double.tryParse(b['mrp']?.toString() ?? '');
          if (m != null && m > 0) {
            resolvedCatalogPrice = m;
            break;
          }
        }
      }
    }

    return MedicineModel(
      id: json['id'] as String,
      pharmacyId: json['pharmacy_id'] as String? ?? '',
      globalId: json['global_id'] as String?,
      brandName: json['brand_name'] as String? ?? 'Unnamed',
      genericName: json['generic_name'] as String?,
      dosageForm: (json['dosage_form'] as String?)?.trim() ?? '',
      strength: strength,
      company: json['company'] as String?,
      category: json['category'] as String?,
      rackLocation: json['rack_location'] as String?,
      unit: json['unit'] as String? ?? 'Pcs',
      minStockAlert: (json['min_stock_alert'] as num?)?.toInt() ?? 10,
      isActive: json['is_active'] as bool? ?? true,
      batches: batches ?? [],
      piecesPerStrip: piecesPerStrip,
      stripsPerBox: stripsPerBox,
      weight: (weight != null && weight.isNotEmpty) ? weight : null,
      catalogPrice: resolvedCatalogPrice,
    );
  }

  MedicineModel copyWith({
    String? id,
    String? pharmacyId,
    String? globalId,
    String? brandName,
    String? genericName,
    String? dosageForm,
    String? strength,
    String? company,
    String? category,
    String? rackLocation,
    String? unit,
    int? minStockAlert,
    bool? isActive,
    List<BatchModel>? batches,
    int? piecesPerStrip,
    int? stripsPerBox,
    String? weight,
    double? catalogPrice,
  }) {
    return MedicineModel(
      id: id ?? this.id,
      pharmacyId: pharmacyId ?? this.pharmacyId,
      globalId: globalId ?? this.globalId,
      brandName: brandName ?? this.brandName,
      genericName: genericName ?? this.genericName,
      dosageForm: dosageForm ?? this.dosageForm,
      strength: strength ?? this.strength,
      company: company ?? this.company,
      category: category ?? this.category,
      rackLocation: rackLocation ?? this.rackLocation,
      unit: unit ?? this.unit,
      minStockAlert: minStockAlert ?? this.minStockAlert,
      isActive: isActive ?? this.isActive,
      batches: batches ?? this.batches,
      piecesPerStrip: piecesPerStrip ?? this.piecesPerStrip,
      stripsPerBox: stripsPerBox ?? this.stripsPerBox,
      weight: weight ?? this.weight,
      catalogPrice: catalogPrice ?? this.catalogPrice,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pharmacy_id': pharmacyId,
      'global_id': globalId,
      'brand_name': brandName,
      'generic_name': genericName,
      'dosage_form': dosageForm,
      'strength': strength,
      'company': company,
      'category': category,
      'rack_location': rackLocation,
      'unit': unit,
      'min_stock_alert': minStockAlert,
      'is_active': isActive,
      'pieces_per_strip': piecesPerStrip,
      'strips_per_box': stripsPerBox,
      'weight': weight,
      'catalog_price': catalogPrice,
      'mrp': catalogPrice,
    };
  }
}
