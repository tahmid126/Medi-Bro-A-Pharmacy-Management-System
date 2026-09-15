import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/medicine_packaging_helper.dart';
import '../../../data/models/purchase_cart_item.dart';

class PurchaseCartItemCard extends StatelessWidget {
  final int index;
  final CartItemEntry item;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final bool isEditing;

  const PurchaseCartItemCard({
    super.key,
    required this.index,
    required this.item,
    required this.onEdit,
    required this.onRemove,
    this.isEditing = false,
  });

  @override
  Widget build(BuildContext context) {
    final med = item.medicine;
    final bonus = item.bonusQuantity;

    // Clean strength and weight (e.g. "10 mg" or "30 mg/5 ml (50 ml)")
    final String cleanStrengthWeight = MedicinePackagingHelper.formatStrengthAndWeight(
      rawStrength: med.strength,
      rawWeight: med.weight,
    );

    final String baseSubDetails = cleanStrengthWeight.isNotEmpty
        ? cleanStrengthWeight
        : (med.genericName != null && med.genericName!.trim().isNotEmpty
            ? med.genericName!.trim()
            : '-');

    final String subDetails = bonus > 0
        ? '$baseSubDetails • Avg: ৳${item.effectiveUnitBuyPrice.toStringAsFixed(item.effectiveUnitBuyPrice % 1 == 0 ? 0 : 2)}/${item.unitType}'
        : baseSubDetails;

    final String formattedTotal = item.lineTotal.toStringAsFixed(
      item.lineTotal.truncateToDouble() == item.lineTotal ? 0 : 2,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isEditing ? const Color(0xFFF0F9FF) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEditing ? AppColors.primary : const Color(0xFFE2E8F0),
          width: isEditing ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isEditing
                ? AppColors.primary.withValues(alpha: 0.1)
                : const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isEditing ? AppColors.primary : const Color(0xFFCBD5E1),
                width: 3.5,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Line 1: 1) Fexo Oral Suspension             [edit] [delete]
              Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '$index)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: isEditing ? AppColors.primary : const Color(0xFF3B82F6),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            med.brandName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (med.dosageForm.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
                            ),
                            child: Text(
                              med.dosageForm,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Edit Action
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onEdit,
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isEditing ? AppColors.primary.withValues(alpha: 0.12) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: isEditing ? AppColors.primary.withValues(alpha: 0.3) : const Color(0xFFE2E8F0),
                            width: 0.8,
                          ),
                        ),
                        child: Icon(
                          isEditing ? Icons.edit_note_rounded : Icons.edit_outlined,
                          size: 14,
                          color: isEditing ? AppColors.primary : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  // Delete Action
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onRemove,
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: const Color(0xFFFECACA), width: 0.8),
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          size: 14,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 5),

              // Line 2: Strength & Weight                     2 Unit (+1)   Tk 99
              Row(
                children: [
                  const SizedBox(width: 22), // Indents under brand name
                  // Strength and weight details (takes available space on left)
                  Expanded(
                    child: Text(
                      subDetails,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Quantity + Unit Chip right before Tk price
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${item.quantity} ${item.unitType}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        if (bonus > 0) ...[
                          const SizedBox(width: 3),
                          Builder(
                            builder: (context) {
                              final String bType = item.bonusUnitType.trim();
                              final String letter = bType.isNotEmpty
                                  ? bType[0].toUpperCase()
                                  : (item.unitType.trim().isNotEmpty ? item.unitType.trim()[0].toUpperCase() : 'U');
                              return Text(
                                '(+$bonus$letter)',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF059669),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Price
                  RichText(
                    textAlign: TextAlign.end,
                    text: TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Tk ',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        TextSpan(
                          text: formattedTotal,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

