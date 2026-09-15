import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class DueEmptyState extends StatelessWidget {
  final String filterType;

  const DueEmptyState({
    super.key,
    required this.filterType,
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
            child: const Icon(
              Icons.check_circle_outline,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No pending dues',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            filterType == 'Customer'
                ? 'All customers are fully paid up.'
                : 'No outstanding supplier payments.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}