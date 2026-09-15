import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class PurchaseSupplierSection extends StatelessWidget {
  final TextEditingController searchController;
  final String? selectedSupplierId;
  final String? selectedSupplierName;
  final String? selectedSupplierPhone;
  final double previousDue;
  final bool isFetchingDue;
  final bool isSearching;
  final List<Map<String, dynamic>> searchResults;
  final ValueChanged<String> onSearch;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final VoidCallback onClear;

  const PurchaseSupplierSection({
    super.key,
    required this.searchController,
    required this.selectedSupplierId,
    required this.selectedSupplierName,
    this.selectedSupplierPhone,
    required this.previousDue,
    required this.isFetchingDue,
    required this.isSearching,
    required this.searchResults,
    required this.onSearch,
    required this.onSelect,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedSupplierName != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primary,
              child: Text(
                selectedSupplierName!.substring(0, 1).toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedSupplierName!,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        'Previous Due: ',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      isFetchingDue
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.5),
                            )
                          : Text(
                              '\u09f3${previousDue.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: previousDue > 0 ? Colors.red.shade700 : Colors.green.shade700,
                              ),
                            ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.grey),
              onPressed: onClear,
              tooltip: 'Change Supplier',
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: searchController,
          onChanged: onSearch,
          decoration: InputDecoration(
            hintText: 'Search company / supplier (e.g. Square, Incepta)...',
            prefixIcon: const Icon(Icons.domain_rounded, color: AppColors.primary, size: 20),
            suffixIcon: isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: onClear,
                      )
                    : null,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        if (searchResults.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3)),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: searchResults.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 44),
              itemBuilder: (context, idx) {
                final s = searchResults[idx];
                final currentDue = (s['current_due'] as num?)?.toDouble() ?? 0.0;
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: Text(
                      (s['name'] as String).substring(0, 1).toUpperCase(),
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  title: Text(
                    s['name'],
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  subtitle: currentDue > 0
                      ? Text(
                          'Previous Due: \u09f3${currentDue.toStringAsFixed(2)}',
                          style: TextStyle(color: Colors.red.shade600, fontSize: 11),
                        )
                      : null,
                  trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
                  onTap: () => onSelect(s),
                );
              },
            ),
          ),
      ],
    );
  }
}
