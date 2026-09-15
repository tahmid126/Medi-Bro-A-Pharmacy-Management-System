import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HistoryFilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final String searchHint;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final List<Map<String, dynamic>> searchResults;
  final ValueChanged<Map<String, dynamic>> onSelectSearchResult;
  final DateTime? selectedDate;
  final ValueChanged<DateTime?> onDateSelected;
  final String selectedStatus;
  final List<String> statusOptions;
  final ValueChanged<String> onStatusChanged;
  final bool hasActiveFilters;
  final VoidCallback onClearAllFilters;

  const HistoryFilterBar({
    super.key,
    required this.searchController,
    required this.searchHint,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.searchResults,
    required this.onSelectSearchResult,
    required this.selectedDate,
    required this.onDateSelected,
    required this.selectedStatus,
    required this.statusOptions,
    required this.onStatusChanged,
    required this.hasActiveFilters,
    required this.onClearAllFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Search Input
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: searchHint,
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: onClearSearch,
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.teal),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Date picker
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) {
                    onDateSelected(picked);
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: selectedDate != null ? Colors.teal.shade50 : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selectedDate != null ? Colors.teal : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 15,
                        color: selectedDate != null ? Colors.teal : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        selectedDate != null ? DateFormat('dd MMM').format(selectedDate!) : 'Date',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selectedDate != null ? FontWeight.bold : FontWeight.normal,
                          color: selectedDate != null ? Colors.teal : Colors.black87,
                        ),
                      ),
                      if (selectedDate != null) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => onDateSelected(null),
                          child: const Icon(Icons.close, size: 14, color: Colors.teal),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Status Dropdown
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                  color: Colors.grey.shade50,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedStatus,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    items: statusOptions
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) onStatusChanged(val);
                    },
                  ),
                ),
              ),
              if (hasActiveFilters) ...[
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.filter_alt_off, size: 20, color: Colors.red),
                  tooltip: 'Clear All Filters',
                  onPressed: onClearAllFilters,
                ),
              ],
            ],
          ),
          // Dropdown suggestions if typing
          if (searchResults.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: searchResults.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                itemBuilder: (ctx, i) {
                  final item = searchResults[i];
                  return ListTile(
                    dense: true,
                    title: Text(
                      item['name']?.toString() ?? '',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    onTap: () => onSelectSearchResult(item),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
