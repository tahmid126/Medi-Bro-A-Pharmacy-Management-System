import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class DatePickerHelper {
  static Future<void> pickMonthYear({
    required BuildContext context,
    required DateTime initialDate,
    required ValueChanged<DateTime> onSelected,
  }) async {
    int selectedYear = initialDate.year;
    int selectedMonth = initialDate.month;

    await showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final int minYear = DateTime.now().year - 1;
            final int maxYear = DateTime.now().year + 8;
            final List<String> months = [
              'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
              'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
            ];

            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Expiry Month & Year', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              content: SizedBox(
                width: 280,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Year selector row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: selectedYear > minYear
                              ? () => setDialogState(() => selectedYear--)
                              : null,
                        ),
                        Text(
                          '$selectedYear',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: selectedYear < maxYear
                              ? () => setDialogState(() => selectedYear++)
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Month Grid (4x3)
                    GridView.count(
                      crossAxisCount: 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.5,
                      children: List.generate(12, (i) {
                        final bool isSelected = selectedMonth == i + 1;
                        return GestureDetector(
                          onTap: () {
                            setDialogState(() => selectedMonth = i + 1);
                          },
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.primary : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              months[i],
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: isSelected ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final newDate = DateTime(selectedYear, selectedMonth, 1);
                    onSelected(newDate);
                    Navigator.pop(dialogCtx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Set Expiry'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
