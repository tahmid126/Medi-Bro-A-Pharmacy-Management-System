import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class StockSortChipsBar extends StatelessWidget {
  final String? currentSortMode;
  final ValueChanged<String?> onSortChanged;

  const StockSortChipsBar({
    super.key,
    required this.currentSortMode,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _sortChip(
            mode: 'expiry',
            label: 'Expiring Soon',
            icon: Icons.hourglass_bottom_rounded,
          ),
          const SizedBox(width: 8),
          _sortChip(
            mode: 'low_stock',
            label: 'Low Stock',
            icon: Icons.trending_down_rounded,
          ),
          const SizedBox(width: 8),
          _sortChip(
            mode: 'high_stock',
            label: 'High Stock',
            icon: Icons.trending_up_rounded,
          ),
          const SizedBox(width: 8),
          _sortChip(
            mode: 'a_z',
            label: 'A to Z',
            icon: Icons.sort_by_alpha_rounded,
          ),
        ],
      ),
    );
  }

  Widget _sortChip({
    required String mode,
    required String label,
    required IconData icon,
  }) {
    final isSelected = currentSortMode == mode;
    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: isSelected ? Colors.white : AppColors.primary,
          ),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? Colors.white : Colors.grey.shade800,
      ),
      selectedColor: AppColors.primary,
      backgroundColor: Colors.white,
      checkmarkColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? AppColors.primary : Colors.grey.shade300,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (selected) {
        onSortChanged(selected ? mode : null);
      },
    );
  }
}
