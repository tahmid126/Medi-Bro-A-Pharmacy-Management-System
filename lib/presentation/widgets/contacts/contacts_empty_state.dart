import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class ContactsEmptyState extends StatelessWidget {
  final String tab;

  const ContactsEmptyState({
    super.key,
    required this.tab,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.contacts_rounded, size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            tab == 'Customer' ? 'No customers found' : 'No companies found',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E)),
          ),
          const SizedBox(height: 8),
          Text(
            tab == 'Customer'
                ? 'Tap the "+" button above to add a new customer.'
                : 'Tap the "+" button above to add a company contact.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}
