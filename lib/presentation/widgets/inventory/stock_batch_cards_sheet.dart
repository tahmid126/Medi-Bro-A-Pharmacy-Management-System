import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/medicine_packaging_helper.dart';
import '../../../../data/models/medicine_model.dart';

class StockBatchCardsSheet extends StatelessWidget {
  final MedicineModel medicine;
  final Map<String, dynamic> matchingGlobalMedicine;
  final VoidCallback onAddBatch;

  const StockBatchCardsSheet({
    super.key,
    required this.medicine,
    this.matchingGlobalMedicine = const {},
    required this.onAddBatch,
  });

  @override
  Widget build(BuildContext context) {
    final med = medicine;
    final packInfo = MedicinePackagingHelper.getPackagingInfo(
      med: med,
      matchingGlobalMedicine: matchingGlobalMedicine,
    );
    final int? pps = packInfo['pps'];
    final int? spb = packInfo['spb'];
    final bool hasStripsPerBox = spb != null && spb > 0;
    final bool hasPiecesPerStrip = pps != null && pps > 0;
    final double libraryMrp = packInfo['libraryMrp'] ?? 0.0;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4.5,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 12),

          // Sheet Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        med.brandName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${med.dosageForm} • ${med.strength ?? ""}${med.company != null && med.company!.isNotEmpty ? " • ${med.company}" : ""}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: onAddBatch,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text(
                    med.pharmacyId.isEmpty ? 'Stock In' : '+ Add Batch',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),
          const Divider(height: 1),

          // Batch Cards List
          Flexible(
            child: med.batches.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          med.pharmacyId.isEmpty
                              ? 'Not yet stocked in your shop'
                              : 'No active batches in stock',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          med.pharmacyId.isEmpty
                              ? 'Tap "Stock In" to add this medicine to your shop inventory.'
                              : 'Tap "+ Add Batch" to add a new batch.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shrinkWrap: true,
                    itemCount: med.batches.length,
                    itemBuilder: (context, index) {
                      final batch = med.batches[index];
                      final effectivePps = (pps != null && pps > 0) ? pps : 1;

                      final int fullStrips = batch.stockQty ~/ effectivePps;
                      final int remUnits = batch.stockQty % effectivePps;
                      final String stripLeftText = remUnits == 0
                          ? '$fullStrips Strip'
                          : '$fullStrips Strip + $remUnits ${med.unit}';

                      final double effectiveMrp = libraryMrp > 0
                          ? libraryMrp
                          : (batch.mrp > 0
                              ? batch.mrp
                              : (batch.sellingPrice > 0
                                  ? batch.sellingPrice
                                  : (packInfo['unitPrice'] as double)));

                      final double batchPurchasePrice = batch.purchasePrice > 0
                          ? batch.purchasePrice
                          : (batch.sellingPrice > 0
                              ? batch.sellingPrice
                              : effectiveMrp);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top Row: Left Top (Batch Number) vs Right Top (Exp Date: mm/yyyy)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.qr_code_rounded, size: 16, color: AppColors.primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Batch: ${batch.batchNumber}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.5,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: batch.isExpired
                                        ? Colors.red.shade50
                                        : (batch.isNearExpiry ? Colors.orange.shade50 : Colors.blue.shade50),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Exp Date: ${DateFormat('MM/yyyy').format(batch.expiryDate)}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: batch.isExpired
                                          ? Colors.red.shade700
                                          : (batch.isNearExpiry ? Colors.orange.shade800 : Colors.blue.shade800),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 10),

                            // Bottom Row: Left Bottom vs Right Bottom
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Left Bottom
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (hasStripsPerBox && hasPiecesPerStrip) ...[
                                      Text(
                                        '${med.unit} Left: ${batch.stockQty}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Strip Left: $stripLeftText',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12.5,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ] else if (hasPiecesPerStrip && effectivePps > 1) ...[
                                      Text(
                                        '${med.unit} Left: ${batch.stockQty} ${med.unit}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Pack Left: ${batch.stockQty ~/ effectivePps} Pack${batch.stockQty % effectivePps != 0 ? " + ${batch.stockQty % effectivePps} ${med.unit}" : ""}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12.5,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ] else ...[
                                      Text(
                                        '${med.unit} Left: ${batch.stockQty} ${med.unit}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12.5,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),

                                // Right Bottom: Retail Price (Purchase Price) & MRP
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Retail ${med.unit} Price: ৳${batchPurchasePrice.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12.5,
                                        color: Color(0xFF10B981),
                                      ),
                                    ),
                                    if (effectiveMrp > 0) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'MRP: ৳${effectiveMrp.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
