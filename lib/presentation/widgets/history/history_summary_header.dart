import 'package:flutter/material.dart';

class HistorySummaryHeader extends StatelessWidget {
  final int totalCount;
  final String countLabel; // e.g. "Invoices" or "Purchases"
  final double totalAmount;
  final String amountLabel; // e.g. "Bills"
  final double paidAmount;
  final double dueAmount;
  final String dueLabel; // e.g. "Due" or "Payable"

  const HistorySummaryHeader({
    super.key,
    required this.totalCount,
    required this.countLabel,
    required this.totalAmount,
    this.amountLabel = 'Bills',
    required this.paidAmount,
    required this.dueAmount,
    this.dueLabel = 'Due',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          Text(
            'Total: $totalCount $countLabel',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$amountLabel: ৳${totalAmount.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Paid: ৳${paidAmount.toStringAsFixed(0)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$dueLabel: ৳${dueAmount.toStringAsFixed(0)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: dueAmount > 0.01 ? Colors.red.shade700 : Colors.grey.shade600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
