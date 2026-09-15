import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../data/models/medicine_model.dart';
import 'history_item_table.dart';

class ImportHistoryCard extends StatelessWidget {
  final Map<String, dynamic> purchase;
  final Map<String, MedicineModel> medMap;
  final VoidCallback onPayment;
  final VoidCallback onPrint;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;
  final bool isProcessing;

  const ImportHistoryCard({
    super.key,
    required this.purchase,
    required this.medMap,
    required this.onPayment,
    required this.onPrint,
    required this.onDelete,
    this.onEdit,
    this.isProcessing = false,
  });

  @override
  Widget build(BuildContext context) {
    final purchaseNo = purchase['purchase_number'] ?? 'PUR';
    final suppName = purchase['supplier_name'] ?? 'Supplier';
    final grandTotal = (purchase['grand_total'] as num?)?.toDouble() ?? 0.0;
    final paidAmount = (purchase['paid_amount'] as num?)?.toDouble() ?? 0.0;
    final dueAmount = (purchase['due_amount'] as num?)?.toDouble() ?? (grandTotal - paidAmount);
    final statusLabel = _statusText(dueAmount, paidAmount);
    final statusBadgeColor = _statusColor(statusLabel);

    Map<String, dynamic>? notesData;
    final notesRaw = purchase['notes'];
    if (notesRaw != null && notesRaw is String && notesRaw.trim().startsWith('{')) {
      try {
        notesData = jsonDecode(notesRaw) as Map<String, dynamic>;
      } catch (_) {}
    }
    final itemsDetail = notesData?['items_detail'] as List<dynamic>?;

    final double rawSubtotal = (purchase['total_amount'] as num?)?.toDouble() ??
        (notesData?['subtotal'] as num?)?.toDouble() ??
        0.0;
    final double discountAmount = (purchase['discount_amount'] as num?)?.toDouble() ??
        (notesData?['discount_amount'] as num?)?.toDouble() ??
        0.0;
    final double totalCost = rawSubtotal > 0 ? rawSubtotal : (grandTotal + discountAmount);
    final double afterDiscount = totalCost - discountAmount;

    String? discountLabel;
    if (discountAmount > 0.001) {
      final discType = notesData?['discount_type']?.toString().trim();
      final num? discPercent = (notesData?['discount_percent'] as num?) ?? (notesData?['discount_value'] as num?);

      if (discType == '%' && discPercent != null && discPercent > 0) {
        final p = discPercent.toDouble();
        discountLabel = p % 1 == 0 ? '${p.toInt()}%' : '${p.toStringAsFixed(1)}%';
      } else if (discType == 'Cash' || discType == 'cash' || discType == '৳') {
        final v = (notesData?['discount_value'] as num?)?.toDouble() ?? discountAmount;
        discountLabel = '${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)} tk';
      } else {
        // Fallback for records where discount_type wasn't saved:
        // check if discountAmount matches a round percentage of totalCost (e.g. 2%, 5%, 10%, 12%)
        if (totalCost > 0) {
          final computedPct = (discountAmount / totalCost) * 100;
          if ((computedPct - computedPct.round()).abs() < 0.02 && computedPct.round() > 0) {
            discountLabel = '${computedPct.round()}%';
          } else {
            discountLabel = '${discountAmount.toStringAsFixed(discountAmount % 1 == 0 ? 0 : 2)} tk';
          }
        } else {
          discountLabel = '${discountAmount.toStringAsFixed(discountAmount % 1 == 0 ? 0 : 2)} tk';
        }
      }
    }

    DateTime date;
    try {
      final dStr = purchase['created_at'] ?? purchase['purchase_date'];
      date = DateTime.parse(dStr.toString()).toLocal();
    } catch (_) {
      date = DateTime.now();
    }

    final items = List<Map<String, dynamic>>.from(purchase['purchase_items'] ?? []);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(
          suppName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Text(
          '#$purchaseNo • ${DateFormat('dd MMM yyyy, hh:mm a').format(date)}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '৳${grandTotal.toStringAsFixed(2)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black,
                fontSize: 14,
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusBadgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  color: statusBadgeColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HistoryItemTable(
                  items: items,
                  medMap: medMap,
                  isCost: true,
                  itemsDetail: itemsDetail,
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 240,
                    child: Column(
                      children: [
                        _summaryRow('total cost', totalCost.toStringAsFixed(totalCost % 1 == 0 ? 0 : 2)),
                        if (discountLabel != null)
                          _summaryRow('after $discountLabel Discount', afterDiscount.toStringAsFixed(2)),
                        if (grandTotal != totalCost || discountLabel != null)
                          _summaryRow('adjusted', grandTotal.toStringAsFixed(grandTotal % 1 == 0 ? 0 : 2)),
                        _summaryRow('paid', paidAmount.toStringAsFixed(paidAmount % 1 == 0 ? 0 : 2), color: Colors.green.shade700),
                        _summaryRow(
                          'payable',
                          (dueAmount > 0.01 ? dueAmount.toStringAsFixed(dueAmount % 1 == 0 ? 0 : 2) : '0'),
                          color: dueAmount > 0.01 ? Colors.red.shade700 : Colors.grey.shade700,
                          isBold: dueAmount > 0.01,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (onEdit != null)
                      TextButton.icon(
                        onPressed: isProcessing ? null : onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
                        label: const Text('Edit', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                      ),
                    if (dueAmount > 0.01)
                      ElevatedButton.icon(
                        onPressed: isProcessing ? null : onPayment,
                        icon: const Icon(Icons.payment, size: 15),
                        label: const Text('Make Payment'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: isProcessing ? null : onPrint,
                      icon: const Icon(Icons.print_outlined, size: 16),
                      label: const Text('Print PDF'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: isProcessing ? null : onDelete,
                      icon: isProcessing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
                            )
                          : const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                      label: const Text('Delete', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.red.shade300),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  String _statusText(double due, double paid) {
    if (due <= 0.01) return 'PAID';
    if (paid > 0 && due > 0) return 'PARTIAL';
    return 'CREDIT';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'PAID':
        return Colors.green;
      case 'PARTIAL':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }
}
