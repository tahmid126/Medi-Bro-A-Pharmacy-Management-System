import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class DraftEmptyState extends StatelessWidget {
  final String filterType;
  final IconData cardIcon;

  const DraftEmptyState({
    super.key,
    required this.filterType,
    required this.cardIcon,
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
            child: Icon(cardIcon, size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          const Text(
            "No drafts found",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            filterType == 'Customer'
                ? "Create a new sale and save it as a draft to continue later."
                : "Start a new purchase and save it as a draft to continue later.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}