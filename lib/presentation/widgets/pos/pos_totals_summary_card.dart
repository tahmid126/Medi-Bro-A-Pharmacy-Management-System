import 'package:flutter/material.dart';

class PosTotalsSummaryCard extends StatelessWidget {
  final double subtotal;
  final String discountType; // '%' or 'Cash'
  final double discountValue;
  final TextEditingController discountController;
  final double discountAmount;
  final double finalTotal;
  final ValueChanged<String> onDiscountTypeChanged;
  final ValueChanged<double> onDiscountValueChanged;
  final VoidCallback onChanged;

  const PosTotalsSummaryCard({
    super.key,
    required this.subtotal,
    required this.discountType,
    required this.discountValue,
    required this.discountController,
    required this.discountAmount,
    required this.finalTotal,
    required this.onDiscountTypeChanged,
    required this.onDiscountValueChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Subtotal Card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total (Retail Value):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
              ),
              Text(
                '\u09f3${subtotal.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Classic Orange Discount Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.local_offer_rounded, color: Colors.orange.shade700, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Discount',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: Colors.orange.shade900),
                      ),
                    ],
                  ),
                  // Discount Type Toggle (% or Cash)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => onDiscountTypeChanged('%'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: discountType == '%' ? Colors.orange.shade600 : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: discountType == '%' ? Colors.white : Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => onDiscountTypeChanged('Cash'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: discountType == 'Cash' ? Colors.orange.shade600 : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Cash',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: discountType == 'Cash' ? Colors.white : Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Discount Value Input (+ / - Buttons)
              Row(
                children: [
                  Text(
                    'Discount Value:',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.remove_circle, color: Colors.orange.shade600, size: 22),
                        onPressed: () {
                          if (discountValue > 0) {
                            final nextVal = (discountValue - 1).clamp(0, double.infinity).toDouble();
                            discountController.text = nextVal.toStringAsFixed(0);
                            onDiscountValueChanged(nextVal);
                          }
                        },
                      ),
                      SizedBox(
                        width: 60,
                        child: TextField(
                          controller: discountController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.orange.shade300),
                            ),
                          ),
                          onChanged: (val) {
                            final nextVal = double.tryParse(val) ?? 0.0;
                            onDiscountValueChanged(nextVal);
                          },
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.add_circle, color: Colors.orange.shade700, size: 22),
                        onPressed: () {
                          final nextVal = discountValue + 1;
                          discountController.text = nextVal.toStringAsFixed(0);
                          onDiscountValueChanged(nextVal);
                        },
                      ),
                    ],
                  ),
                ],
              ),

              const Divider(color: Color(0xFFFED7AA)),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Discount Amount (${discountType == '%' ? '${discountValue.toStringAsFixed(0)}%' : 'Cash'}):',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                  ),
                  Text(
                    '- \u09f3${discountAmount.toStringAsFixed(2)}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red.shade700),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Net Total:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
                  ),
                  Text(
                    '\u09f3${finalTotal.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
