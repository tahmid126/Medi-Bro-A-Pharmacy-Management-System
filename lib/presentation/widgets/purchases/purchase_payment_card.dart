import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class PurchasePaymentCard extends StatelessWidget {
  final double previousDue;
  final double todayBill;
  final double newDueAfterThis;
  final TextEditingController payingNowController;
  final VoidCallback onPayFull;
  final VoidCallback onChanged;

  const PurchasePaymentCard({
    super.key,
    required this.previousDue,
    required this.todayBill,
    required this.newDueAfterThis,
    required this.payingNowController,
    required this.onPayFull,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_rounded, color: AppColors.primary, size: 18),
              const SizedBox(width: 6),
              const Text(
                'Payment & Due Summary',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Previous Due
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Previous Due:', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              Text(
                '\u09f3${previousDue.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                  color: previousDue > 0 ? Colors.red.shade600 : Colors.green.shade600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Total Bill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Today\'s Bill:', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              Text(
                '\u09f3${todayBill.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF1E293B)),
              ),
            ],
          ),

          const Divider(height: 20),

          // Paying Now Field + Pay Full button
          Row(
            children: [
              const Text(
                'Paying Now:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF1E293B)),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: onPayFull,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade50,
                  foregroundColor: Colors.blue.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(60, 28),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('Pay Full', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                height: 38,
                child: TextField(
                  controller: payingNowController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    prefixText: '\u09f3 ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  onChanged: (val) => onChanged(),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // New Due After This
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: newDueAfterThis > 0 ? Colors.red.shade50 : Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'New Due After This:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: newDueAfterThis > 0 ? Colors.red.shade800 : Colors.green.shade800,
                  ),
                ),
                Text(
                  '\u09f3${newDueAfterThis.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: newDueAfterThis > 0 ? Colors.red.shade800 : Colors.green.shade800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
