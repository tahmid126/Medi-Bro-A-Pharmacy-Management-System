import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class PurchasePaymentDialog extends StatefulWidget {
  final Map<String, dynamic> purchase;
  final Future<void> Function(double amount, String method) onConfirmPayment;

  const PurchasePaymentDialog({
    super.key,
    required this.purchase,
    required this.onConfirmPayment,
  });

  @override
  State<PurchasePaymentDialog> createState() => _PurchasePaymentDialogState();
}

class _PurchasePaymentDialogState extends State<PurchasePaymentDialog> {
  final TextEditingController _amountController = TextEditingController();
  String _selectedMethod = 'Cash';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final grandTotal = (widget.purchase['grand_total'] as num?)?.toDouble() ?? 0.0;
    final paidAmount = (widget.purchase['paid_amount'] as num?)?.toDouble() ?? 0.0;
    final dueAmount = (widget.purchase['due_amount'] as num?)?.toDouble() ?? (grandTotal - paidAmount);
    _amountController.text = dueAmount.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grandTotal = (widget.purchase['grand_total'] as num?)?.toDouble() ?? 0.0;
    final paidAmount = (widget.purchase['paid_amount'] as num?)?.toDouble() ?? 0.0;
    final dueAmount = (widget.purchase['due_amount'] as num?)?.toDouble() ?? (grandTotal - paidAmount);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Pay Due: ${widget.purchase['supplier_name'] ?? 'Supplier'}',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Due:', style: TextStyle(fontSize: 13, color: Colors.black87)),
                  Text(
                    '৳${dueAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Payment Amount (৳)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                prefixText: '৳ ',
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _selectedMethod,
              decoration: InputDecoration(
                labelText: 'Payment Method',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: ['Cash', 'Bank Transfer', 'bKash', 'Nagad', 'Rocket', 'Cheque']
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedMethod = val);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _isSubmitting
              ? null
              : () async {
                  final pay = double.tryParse(_amountController.text.trim()) ?? 0.0;
                  if (pay <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a valid payment amount.')),
                    );
                    return;
                  }
                  if (pay > dueAmount + 0.01) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Payment cannot exceed current due amount.')),
                    );
                    return;
                  }

                  final nav = Navigator.of(context);
                  setState(() => _isSubmitting = true);
                  try {
                    await widget.onConfirmPayment(pay, _selectedMethod);
                    if (mounted) nav.pop();
                  } finally {
                    if (mounted) setState(() => _isSubmitting = false);
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: _isSubmitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Submit Payment', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
