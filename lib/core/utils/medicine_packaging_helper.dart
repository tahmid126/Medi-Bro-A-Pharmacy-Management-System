import '../../data/models/medicine_model.dart';

class MedicinePackagingHelper {
  /// Resolves packaging info (pps = pieces per strip, spb = strips per box, weight, unitPrice)
  /// given a local medicine and an optional matching global medicine map.
  static Map<String, dynamic> getPackagingInfo({
    MedicineModel? med,
    Map<String, dynamic>? matchingGlobalMedicine,
  }) {
    int? pps;
    int? spb;
    String? wt;

    final gm = matchingGlobalMedicine ?? {};

    final rawMedStr = med?.strength?.toString().trim() ?? '';
    final rawGmStr = gm['strength']?.toString().trim() ?? '';
    final rawMedWt = med?.weight?.toString().trim() ?? '';
    final rawGmWt = gm['weight']?.toString().trim() ?? '';

    // Pattern for two-tier pack: e.g. "15*10", "15 x 10", "15*10's", "(15*10)", "[15*10]"
    final twoTierPackRegex = RegExp(
      r'[\(\[]?\s*(\d+)\s*[*xX×]\s*(\d+)(?:\x27?s|\s*pcs)?\s*[\)\]]?',
      caseSensitive: false,
    );

    // Pattern for single-tier pack: e.g. "25's", "10's", "100's", "(25's)"
    final singleTierPackRegex = RegExp(
      r'[\(\[]?\s*(\d+)(?:\x27?s|\s*pcs|\s*pack|\s*tabs|\s*caps)\s*[\)\]]?',
      caseSensitive: false,
    );

    // Helper to check invalid weight string
    bool isInvalidWeight(String text) {
      final t = text.trim();
      if (t.isEmpty) return true;
      if (RegExp(r'^[\(\[]?\s*\d+\s*[*xX×]\s*\d+\s*[\)\]]?$').hasMatch(t)) {
        return true;
      }
      if (RegExp(r'^\[MRP:.*\]$', caseSensitive: false).hasMatch(t)) {
        return true;
      }
      return false;
    }

    // 1. Direct DB columns (Primary source of truth)
    if (med?.piecesPerStrip != null && med!.piecesPerStrip! > 0) {
      pps = med.piecesPerStrip;
    } else if (gm['pieces_per_strip'] != null) {
      pps = int.tryParse(gm['pieces_per_strip'].toString());
    }

    if (med?.stripsPerBox != null && med!.stripsPerBox! > 0) {
      spb = med.stripsPerBox;
    } else if (gm['strips_per_box'] != null) {
      spb = int.tryParse(gm['strips_per_box'].toString());
    }

    if (rawMedWt.isNotEmpty && !isInvalidWeight(rawMedWt)) {
      wt = rawMedWt.replaceAll(RegExp(r'[\(\)\[\]]'), '').trim();
    } else if (rawGmWt.isNotEmpty && !isInvalidWeight(rawGmWt)) {
      wt = rawGmWt.replaceAll(RegExp(r'[\(\)\[\]]'), '').trim();
    }

    // 2. Fallback: Search for explicit pack size in strength candidates if not in DB
    if (pps == null && spb == null) {
      Match? packMatch;
      for (final candidate in [rawMedStr, rawGmStr]) {
        if (candidate.isNotEmpty) {
          packMatch = twoTierPackRegex.firstMatch(candidate);
          if (packMatch != null) break;
        }
      }

      if (packMatch != null) {
        final s = int.tryParse(packMatch.group(1)!);
        final p = int.tryParse(packMatch.group(2)!);
        if (s != null && s > 1 && p != null && p > 1) {
          spb = s;
          pps = p;
        } else if (s == 1 && p != null && p > 1) {
          pps = p;
          spb = null;
        } else if (p == 1 && s != null && s > 1) {
          pps = s;
          spb = null;
        }
      } else {
        Match? singleMatch;
        for (final candidate in [rawMedStr, rawGmStr]) {
          if (candidate.isNotEmpty) {
            singleMatch = singleTierPackRegex.firstMatch(candidate);
            if (singleMatch != null) break;
          }
        }
        if (singleMatch != null) {
          pps = int.tryParse(singleMatch.group(1)!);
          spb = null;
        }
      }
    }

    if (wt == null || wt.isEmpty) {
      for (final candidate in [rawMedStr, rawGmStr]) {
        if (candidate.isNotEmpty) {
          final parenVol = RegExp(
            r'[\(\[]\s*([^()\[\]]+?(?:ml|gm|g|l|kg|pads?|sachets?|tubes?|drops?|spray)[^()\[\]]*)\s*[\)\]]',
            caseSensitive: false,
          ).firstMatch(candidate);
          if (parenVol != null) {
            wt =
                parenVol.group(1)!.replaceAll(RegExp(r'[\(\)\[\]]'), '').trim();
            break;
          }
          final standaloneMatch = RegExp(
            r'(?:^|[^\/\w])(\d+(?:\.\d+)?\s*(?:ml|gm|g|l|kg|pads?|sachets?|tubes?))\b',
            caseSensitive: false,
          ).firstMatch(candidate);
          if (standaloneMatch != null) {
            wt = standaloneMatch.group(1)!.trim();
            break;
          }
        }
      }
    }

    // Pure data-driven packaging normalization:
    if (spb == 1) {
      spb = null;
    }
    if (pps == 1 && spb != null && spb > 1) {
      pps = spb;
      spb = null;
    } else if (pps == 1 && (spb == null || spb <= 1)) {
      pps = null;
      spb = null;
    }

    final bool hasValidPps = pps != null && pps > 1;
    final bool hasValidSpb = spb != null && spb > 1;

    if (!hasValidPps && hasValidSpb) {
      pps = spb;
      spb = null;
    } else if (!hasValidPps && !hasValidSpb) {
      pps = null;
      spb = null;
    }

    // Resolve unit price: prioritize local pharmacy catalogPrice / batch price, then library
    final double libraryMrp =
        double.tryParse(
          gm['default_mrp']?.toString() ?? gm['mrp']?.toString() ?? '0',
        ) ??
        0.0;
    double unitPrice = 0.0;
    if (med?.catalogPrice != null && med!.catalogPrice! > 0) {
      unitPrice = med.catalogPrice!;
    } else if (med != null &&
        med.batches.isNotEmpty &&
        med.primaryActiveBatch != null &&
        med.primaryActiveBatch!.mrp > 0) {
      unitPrice = med.primaryActiveBatch!.mrp;
    } else if (libraryMrp > 0) {
      unitPrice = libraryMrp;
    }

    return {
      'pps': pps,
      'spb': spb,
      'weight': wt,
      'unitPrice': unitPrice,
      'libraryMrp': libraryMrp,
    };
  }

  /// Finds matching global medicine strictly by globalId or exact (brandName + dosageForm).
  /// Never matches cross-dosage-form (e.g. Syrup must NEVER match or inherit data from a Tablet).
  static Map<String, dynamic> findMatchingGlobalMedicine(
    MedicineModel med,
    List<Map<String, dynamic>> globalMedicines,
  ) {
    if (globalMedicines.isEmpty) return {};

    if (med.globalId != null && med.globalId!.isNotEmpty) {
      final found = globalMedicines.firstWhere(
        (gm) => gm['id']?.toString() == med.globalId,
        orElse: () => {},
      );
      if (found.isNotEmpty) return found;
    }

    final bLower = med.brandName.trim().toLowerCase();
    final dLower = med.dosageForm.trim().toLowerCase();
    if (bLower.isEmpty) return {};

    // Strict match by brand_name + dosage_form
    if (dLower.isNotEmpty) {
      return globalMedicines.firstWhere((gm) {
        final gBrand = (gm['brand_name'] ?? '').toString().trim().toLowerCase();
        final gDosage =
            (gm['dosage_form'] ?? '').toString().trim().toLowerCase();
        return gBrand == bLower && gDosage == dLower;
      }, orElse: () => {});
    }

    // Fallback only if local medicine has no dosageForm specified:
    return globalMedicines.firstWhere((gm) {
      final gBrand = (gm['brand_name'] ?? '').toString().trim().toLowerCase();
      return gBrand == bLower;
    }, orElse: () => {});
  }

  /// Formats clean strength and weight, stripping out pack-sizes like "15*10" or "10's",
  /// and avoiding duplicate volume when strength already includes it (e.g. "30 mg/5 ml (50 ml)").
  static String formatStrengthAndWeight({
    String? rawStrength,
    String? rawWeight,
  }) {
    String s = rawStrength?.trim() ?? '';
    String w = rawWeight?.trim() ?? '';

    // 1. Remove pack-size from strength like "(15*10)", "(6*5)", "(10's)"
    s =
        s
            .replaceAll(RegExp(r'[\(\[]\s*\d+\s*[*xX×]\s*\d+\s*[\)\]]'), '')
            .trim();
    s =
        s
            .replaceAll(
              RegExp(
                r'[\(\[]\s*\d+(?:\x27?s|\s*pcs|\s*pack)?\s*[\)\]]',
                caseSensitive: false,
              ),
              '',
            )
            .trim();

    // If s is only pure digits or a pack size like 10*10, ignore it
    if (RegExp(r'^\d+$').hasMatch(s) ||
        RegExp(r'^\d+\s*[*xX×]\s*\d+$').hasMatch(s)) {
      s = '';
    }

    // 2. Check if rawWeight is actual volume/weight or just a pack size
    final isRealWeight = RegExp(
      r'^\(?\d+(?:\.\d+)?\s*(?:ml|gm|g|mg|l|kg|iu)\)?$',
      caseSensitive: false,
    ).hasMatch(w);
    if (!isRealWeight) {
      // It's a pack size like "15*10", "10's", etc. -> Ignore it as weight!
      w = '';
    } else {
      // Clean up wrapping brackets if any
      w = w.replaceAll(RegExp(r'[\(\)\[\]]'), '').trim();
    }

    // 3. If s already contains w (e.g. s = "30 mg/5 ml (50 ml)" and w = "50 ml"), don't add w again
    if (w.isNotEmpty && s.toLowerCase().contains(w.toLowerCase())) {
      w = '';
    }

    if (s.isNotEmpty && w.isNotEmpty) {
      return '$s ($w)';
    } else if (s.isNotEmpty) {
      return s;
    } else if (w.isNotEmpty) {
      return w;
    }
    return '';
  }
}
