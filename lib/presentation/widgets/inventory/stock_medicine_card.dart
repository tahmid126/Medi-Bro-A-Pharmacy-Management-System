import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/medicine_packaging_helper.dart';
import '../../../../data/models/medicine_model.dart';

class StockMedicineCard extends StatefulWidget {
  final MedicineModel medicine;
  final Map<String, dynamic> matchingGlobalMedicine;
  final String viewMode; // 'stock' vs 'library' vs 'admin'
  final VoidCallback onTap;
  final VoidCallback? onAddBatch;
  final VoidCallback? onEdit;
  final VoidCallback? onSuggestEdit;
  final VoidCallback? onDelete;
  final ValueChanged<String>? onCompanyTap;
  final ValueChanged<String>? onGenericTap;
  final ValueChanged<String>? onTypeTap;
  final Widget? middleContent;
  final Widget? bottomActions;
  final bool showAddStock;
  final bool? isExpanded;
  final VoidCallback? onToggleExpand;

  const StockMedicineCard({
    super.key,
    required this.medicine,
    this.matchingGlobalMedicine = const {},
    required this.viewMode,
    required this.onTap,
    this.onAddBatch,
    this.onEdit,
    this.onSuggestEdit,
    this.onDelete,
    this.onCompanyTap,
    this.onGenericTap,
    this.onTypeTap,
    this.middleContent,
    this.bottomActions,
    this.showAddStock = true,
    this.isExpanded,
    this.onToggleExpand,
  });

  @override
  State<StockMedicineCard> createState() => _StockMedicineCardState();
}

class _StockMedicineCardState extends State<StockMedicineCard> {
  bool _internalExpanded = false;

  bool get _isExpanded => widget.isExpanded ?? _internalExpanded;

  void _collapse() {
    if (widget.onToggleExpand != null && _isExpanded) {
      widget.onToggleExpand!();
    } else if (mounted) {
      setState(() => _internalExpanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final med = widget.medicine;
    final gm = widget.matchingGlobalMedicine;
    final isLocal = (med.globalId == null || med.globalId!.isEmpty) && widget.viewMode != 'admin';

    final packInfo = MedicinePackagingHelper.getPackagingInfo(
      med: med,
      matchingGlobalMedicine: gm,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.viewMode != 'admin'
                ? () {
                    if (widget.onToggleExpand != null) {
                      widget.onToggleExpand!();
                    } else {
                      setState(() => _internalExpanded = !_internalExpanded);
                    }
                  }
                : widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Column: Medicine Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Brand Name + Dosage Form Badge
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              med.brandName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: (med.isActive == false || gm['is_available'] == false)
                                    ? Colors.grey.shade600
                                    : const Color(0xFF1E293B),
                                decoration: (med.isActive == false || gm['is_available'] == false)
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            if (med.dosageForm.trim().isNotEmpty)
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: widget.onTypeTap != null ? () => widget.onTypeTap!(med.dosageForm) : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    med.dosageForm,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ),
                            if (widget.viewMode != 'admin' && isLocal)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Colors.amber.shade300,
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.storefront_rounded,
                                      size: 11,
                                      color: Colors.amber.shade900,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Local',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      _isExpanded
                                          ? Icons.keyboard_arrow_up_rounded
                                          : Icons.keyboard_arrow_down_rounded,
                                      size: 13,
                                      color: Colors.amber.shade900,
                                    ),
                                  ],
                                ),
                              )
                            else if (widget.viewMode != 'admin')
                              Icon(
                                _isExpanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                size: 16,
                                color: Colors.grey.shade400,
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),

                        // Generic Name (Underlined, clickable)
                        if (med.genericName != null &&
                            med.genericName!.trim().isNotEmpty &&
                            med.genericName!.trim().toLowerCase() != 'null')
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onGenericTap != null ? () => widget.onGenericTap!(med.genericName!) : null,
                            child: Text(
                              med.genericName!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF0284C7),
                                decoration: TextDecoration.underline,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),

                        // Strength
                        if (med.strength != null &&
                            med.strength!.trim().isNotEmpty) ...[
                          Builder(
                            builder: (context) {
                              String cleanStrength = med.strength!.trim();

                              // Strip pack size patterns like (15*10), (1*12), (25's), [10x10], etc.
                              final packPattern = RegExp(
                                r'[\(\[]\s*\d+\s*[*xX×]\s*\d+.*[\)\]]|[\(\[]\s*\d+(?:\x27?s|\s*pcs|\s*pack|\s*tabs|\s*caps)?\s*[\)\]]',
                                caseSensitive: false,
                              );
                              cleanStrength = cleanStrength.replaceAll(packPattern, '').trim();

                              // Strip [MRP: ...] tag
                              cleanStrength = cleanStrength.replaceAll(RegExp(r'\[MRP:\s*[৳$]?\s*\d+(?:\.\d+)?\]', caseSensitive: false), '').trim();

                              // Strip parenthesized weight/volume like (50 ml), (10.25 gm)
                              final parenVol = RegExp(
                                r'[\(\[]\s*\d+(?:\.\d+)?\s*(?:ml|gm|g|l|kg|iu)\s*[\)\]]',
                                caseSensitive: false,
                              );
                              cleanStrength = cleanStrength.replaceAll(parenVol, '').trim();

                              // If it's enclosed in outer parentheses, unwrap them
                              if (cleanStrength.startsWith('(') && cleanStrength.endsWith(')')) {
                                cleanStrength = cleanStrength.substring(1, cleanStrength.length - 1).trim();
                              }

                              // Strip any trailing parentheses
                              final lastOpen = cleanStrength.lastIndexOf('(');
                              if (lastOpen >= 0 && cleanStrength.endsWith(')')) {
                                cleanStrength = cleanStrength.substring(0, lastOpen).trim();
                              }

                              // If the remaining string is empty or just a pure number or pack-size like 10*10, don't show it
                              if (cleanStrength.isEmpty ||
                                  RegExp(r'^\d+$').hasMatch(cleanStrength) ||
                                  RegExp(r'^\d+\s*[*xX×]\s*\d+$').hasMatch(cleanStrength)) {
                                return const SizedBox.shrink();
                              }

                              // If cleanStrength equals the resolved packaging weight, or if it is purely a physical weight/volume (not a chemical strength), DO NOT display it on the left side!
                              final resolvedWt = (packInfo['weight'] ?? med.weight ?? gm['weight'] ?? '').toString().trim().toLowerCase().replaceAll(RegExp(r'[\(\)\[\]]'), '');
                              final cleanLower = cleanStrength.toLowerCase();
                              if (resolvedWt.isNotEmpty && (cleanLower == resolvedWt || cleanLower == resolvedWt.replaceAll(' ', ''))) {
                                return const SizedBox.shrink();
                              }

                              // Pure physical weight/volume without parens (e.g. "10.25 gm", "100 ml", "15 g", "25 sachets") belongs on the right side price line, never as left-side strength!
                              if (RegExp(r'^\d+(?:\.\d+)?\s*(?:ml|gm|g|l|kg|pads?|sachets?|tubes?|drops?|spray)$', caseSensitive: false).hasMatch(cleanStrength)) {
                                return const SizedBox.shrink();
                              }

                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  cleanStrength,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],

                        // Company Chip
                        if (med.company != null &&
                            med.company!.trim().isNotEmpty &&
                            med.company!.trim().toLowerCase() != 'unknown' &&
                            med.company!.trim().toLowerCase() != 'n/a' &&
                            med.company!.trim().toLowerCase() != 'null') ...[
                          const SizedBox(height: 6),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onCompanyTap != null ? () => widget.onCompanyTap!(med.company!) : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.domain_rounded,
                                    size: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      med.company!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Right Column: Stock Indicator & Pricing
                  IntrinsicWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // 1.1 Top Stock Line
                        if (widget.viewMode == 'stock') ...[
                          if (med.totalStock <= 0)
                            const Text(
                              'Stock Out',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFEF4444),
                              ),
                            )
                          else
                            Text(
                              '${med.totalStock} ${med.unit} | ${med.batches.length} Batch${med.batches.length != 1 ? "es" : ""}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          const SizedBox(height: 6),
                        ] else if (widget.viewMode != 'admin') ...[
                          if (med.pharmacyId.isEmpty) ...[
                            if (widget.showAddStock)
                              ElevatedButton(
                                onPressed: widget.onAddBatch,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                child: const Text(
                                  '+ Add Stock',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ] else
                            Text(
                              med.totalStock <= 0
                                  ? 'Stock Out'
                                  : '${med.totalStock} ${med.unit} | ${med.batches.length} Batch${med.batches.length != 1 ? "es" : ""}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: med.totalStock <= 0
                                    ? const Color(0xFFEF4444)
                                    : const Color(0xFF10B981),
                              ),
                            ),
                          const SizedBox(height: 6),
                        ],

                        // 1.2, 1.3, 1.4 Pricing & Packaging breakdown
                        _buildRightSidePriceInfo(med, packInfo, gm),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Expanded Actions for User (Local vs Global Medicine)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: (_isExpanded && widget.viewMode != 'admin')
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Batches button
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  _collapse();
                                  widget.onTap();
                                },
                                icon: const Icon(Icons.layers_outlined, size: 14, color: Color(0xFF475569)),
                                label: const Text(
                                  'Batches',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  side: BorderSide(color: Colors.grey.shade300),
                                  backgroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                            if (isLocal) ...[
                              // Local Medicine: Edit & Delete buttons
                              if (widget.onEdit != null) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      _collapse();
                                      widget.onEdit?.call();
                                    },
                                    icon: const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF2563EB)),
                                    label: const Text(
                                      'Edit',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2563EB)),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      side: const BorderSide(color: Color(0xFF93C5FD)),
                                      backgroundColor: const Color(0xFFEFF6FF),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ),
                              ],
                              if (widget.onDelete != null) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      _collapse();
                                      widget.onDelete?.call();
                                    },
                                    icon: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFDC2626)),
                                    label: const Text(
                                      'Delete',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFDC2626)),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                                      backgroundColor: const Color(0xFFFEF2F2),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ),
                              ],
                            ] else ...[
                              // Global Medicine: Suggest Edit button (NO Delete button)
                              if (widget.onSuggestEdit != null || widget.onEdit != null) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      _collapse();
                                      (widget.onSuggestEdit ?? widget.onEdit)?.call();
                                    },
                                    icon: const Icon(Icons.edit_note_rounded, size: 16, color: Color(0xFF2563EB)),
                                    label: const Text(
                                      'Suggest Edit',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2563EB)),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      side: const BorderSide(color: Color(0xFF93C5FD)),
                                      backgroundColor: const Color(0xFFEFF6FF),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          if (widget.middleContent != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: widget.middleContent!,
            ),
          ],
          if (widget.bottomActions != null) ...[
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: widget.bottomActions!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRightSidePriceInfo(
    MedicineModel med,
    Map<String, dynamic> packInfo,
    Map<String, dynamic> gm,
  ) {
    final int? pps = packInfo['pps'];
    final int? spb = packInfo['spb'];
    final String? wt = packInfo['weight'];
    double unitPrice = packInfo['unitPrice'] ?? 0.0;
    if (unitPrice <= 0 && med.catalogPrice != null && med.catalogPrice! > 0) {
      unitPrice = med.catalogPrice!;
    }
    if (unitPrice <= 0 && med.strength != null) {
      final mrpMatch = RegExp(r'\[MRP:\s*[৳$]?\s*(\d+(?:\.\d+)?)\]', caseSensitive: false).firstMatch(med.strength!);
      if (mrpMatch != null) {
        unitPrice = double.tryParse(mrpMatch.group(1)!) ?? 0.0;
      }
    }

    final bool hasStripsPerBox = spb != null && spb > 1;
    final bool hasPiecesPerStrip = pps != null && pps > 1;

    String weightDisplay = (wt != null && wt.trim().isNotEmpty) ? wt.trim() : '';
    if (weightDisplay.isEmpty && med.weight != null && med.weight!.trim().isNotEmpty) {
      weightDisplay = med.weight!.trim();
    }
    if (weightDisplay.isEmpty && gm.isNotEmpty && gm['weight'] != null && gm['weight'].toString().trim().isNotEmpty) {
      weightDisplay = gm['weight'].toString().trim();
    }
    if (weightDisplay.isEmpty && med.strength != null) {
      final parenVol = RegExp(
        r'[\(\[]\s*([^()\[\]]+?(?:ml|gm|g|l|kg|pads?|sachets?|tubes?|drops?|spray)[^()\[\]]*)\s*[\)\]]',
        caseSensitive: false,
      ).firstMatch(med.strength!);
      if (parenVol != null) {
        weightDisplay = parenVol.group(1)!.trim();
      } else {
        final matches = RegExp(
          r'(?:^|[^\/\w])(\d+(?:\.\d+)?\s*(?:ml|gm|g|l|kg|pads?|sachets?|tubes?))\b',
          caseSensitive: false,
        ).allMatches(med.strength!);
        if (matches.isNotEmpty) {
          weightDisplay = matches.last.group(1)!.trim();
        }
      }
    }
    weightDisplay = weightDisplay.replaceAll(RegExp(r'[\(\)\[\]]'), '').trim();

    // Resolve the correct unit label: prefer global default_unit over local med.unit
    String unitLabel = med.unit;
    if (gm.isNotEmpty && gm['default_unit'] != null && gm['default_unit'].toString().trim().isNotEmpty) {
      unitLabel = gm['default_unit'].toString().trim();
    }

    // State 1: Both unit_per_strip (pps) and strip_per_box (spb) present (Tablet / Capsule logic: no weight)
    if (hasStripsPerBox && hasPiecesPerStrip) {
      final double stripPrice = unitPrice * pps;
      final double boxPrice = unitPrice * pps * spb;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$unitLabel Price: ৳${unitPrice.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Strip Price: ৳${stripPrice.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.blue.shade700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '($spb * $pps: ৳${boxPrice.toStringAsFixed(2)})',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      );
    }

    // State 2: Neither unit_per_strip nor strip_per_box present
    if (!hasPiecesPerStrip && !hasStripsPerBox) {
      final String priceLabel;
      if (weightDisplay.isNotEmpty) {
        priceLabel = '$weightDisplay $unitLabel: ৳${unitPrice.toStringAsFixed(2)}';
      } else {
        priceLabel = '$unitLabel: ৳${unitPrice.toStringAsFixed(2)}';
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            priceLabel,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
        ],
      );
    }

    // State 3: Only pack size present (unit per strip / pack quantity)
    final int packQty = hasPiecesPerStrip ? pps : (hasStripsPerBox ? spb : 1);
    final double packPrice = unitPrice * packQty;
    final String firstLineLabel;
    if (weightDisplay.isNotEmpty) {
      firstLineLabel = '$weightDisplay $unitLabel: ৳${unitPrice.toStringAsFixed(2)}';
    } else {
      firstLineLabel = 'Per $unitLabel: ৳${unitPrice.toStringAsFixed(2)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          firstLineLabel,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          "($packQty's $unitLabel: ৳${packPrice.toStringAsFixed(2)})",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.blue.shade700,
          ),
        ),
      ],
    );
  }
}
