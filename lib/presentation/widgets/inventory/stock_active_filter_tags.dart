import 'package:flutter/material.dart';

class StockActiveFilterTags extends StatelessWidget {
  final String? selectedGenericName;
  final String? selectedMedicineType;
  final String? sortMode;
  final VoidCallback onClearGeneric;
  final VoidCallback onClearType;
  final VoidCallback onClearSort;

  const StockActiveFilterTags({
    super.key,
    this.selectedGenericName,
    this.selectedMedicineType,
    this.sortMode,
    required this.onClearGeneric,
    required this.onClearType,
    required this.onClearSort,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedGenericName == null &&
        selectedMedicineType == null &&
        sortMode == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (selectedGenericName != null)
            _activeFilterChip(
              icon: Icons.science_outlined,
              label: selectedGenericName!,
              onRemove: onClearGeneric,
            ),
          if (selectedMedicineType != null)
            _activeFilterChip(
              icon: Icons.category_outlined,
              label: selectedMedicineType!,
              onRemove: onClearType,
            ),
          if (sortMode != null)
            _activeFilterChip(
              icon: Icons.sort_rounded,
              label: sortMode == 'expiry'
                  ? 'Sort: Expiring Soon'
                  : sortMode == 'low_stock'
                      ? 'Sort: Low Stock First'
                      : sortMode == 'high_stock'
                          ? 'Sort: High Stock First'
                          : 'Sort: A to Z',
              onRemove: onClearSort,
            ),
        ],
      ),
    );
  }

  Widget _activeFilterChip({
    required IconData icon,
    required String label,
    required VoidCallback onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF2563EB)),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1D4ED8),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(
              Icons.close_rounded,
              size: 14,
              color: Color(0xFF3B82F6),
            ),
          ),
        ],
      ),
    );
  }
}
