import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_colors.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../../core/utils/quantity_display_helper.dart';
import '../../../data/services/history_service.dart';
import '../../../data/services/invoice_pdf_service.dart';
import '../../widgets/history/export_history_card.dart';
import '../../widgets/history/history_delete_dialog.dart';
import '../pos/pos_sale_screen.dart';
import '../../widgets/common/medi_app_bar.dart';

class ExportHistoryScreen extends StatefulWidget {
  const ExportHistoryScreen({super.key});

  @override
  State<ExportHistoryScreen> createState() => _ExportHistoryScreenState();
}

class _ExportHistoryScreenState extends State<ExportHistoryScreen> {
  final HistoryService _historyService = HistoryService();

  // Search & Filters
  final TextEditingController _customerSearchController = TextEditingController();
  String? _selectedCustomerId;
  String? _selectedCustomerName;
  List<Map<String, dynamic>> _customerSearchResults = [];

  DateTime? _selectedDate;
  String _selectedStatus = 'All Status';
  final List<String> _statusOptions = ['All Status', 'PAID', 'PARTIAL', 'DUE', 'RETURNED'];

  // State
  List<Map<String, dynamic>> _invoices = [];
  bool _isLoading = true;
  String? _processingInvoiceId;

  @override
  void initState() {
    super.initState();
    _fetchInvoices();
  }

  @override
  void dispose() {
    _customerSearchController.dispose();
    super.dispose();
  }

  Future<void> _fetchInvoices() async {
    setState(() => _isLoading = true);
    try {
      final pharmacyId = context.read<AuthProvider>().currentPharmacy?.id;
      if (pharmacyId == null) {
        setState(() => _isLoading = false);
        return;
      }
      final data = await _historyService.fetchInvoices(pharmacyId);
      if (mounted) {
        setState(() {
          _invoices = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching invoices: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load export history: $e')),
        );
      }
    }
  }

  Future<void> _searchCustomer(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _customerSearchResults = [];
      });
      return;
    }

    final pharmacyId = context.read<AuthProvider>().currentPharmacy?.id ?? '';
    final results = await _historyService.searchCustomers(
      pharmacyId: pharmacyId,
      query: q,
      loadedInvoices: _invoices,
    );

    if (mounted) {
      setState(() => _customerSearchResults = results);
    }
  }

  void _selectCustomer(Map<String, dynamic> c) {
    setState(() {
      _selectedCustomerId = c['id']?.toString();
      _selectedCustomerName = (c['raw_name'] ?? c['name'])?.toString();
      _customerSearchController.clear();
      _customerSearchResults = [];
    });
  }

  void _clearCustomerFilter() {
    setState(() {
      _selectedCustomerId = null;
      _selectedCustomerName = null;
      _customerSearchController.clear();
      _customerSearchResults = [];
    });
  }

  void _clearAllFilters() {
    setState(() {
      _selectedCustomerId = null;
      _selectedCustomerName = null;
      _customerSearchController.clear();
      _customerSearchResults = [];
      _selectedDate = null;
      _selectedStatus = 'All Status';
    });
  }

  bool get _hasActiveFilters =>
      _selectedCustomerId != null ||
      _selectedCustomerName != null ||
      _customerSearchController.text.isNotEmpty ||
      _selectedDate != null ||
      _selectedStatus != 'All Status';

  List<Map<String, dynamic>> get _filteredInvoices {
    return _invoices.where((inv) {
      // 1. Customer filter
      if (_selectedCustomerName != null && _selectedCustomerName!.isNotEmpty) {
        final target = _selectedCustomerName!.toLowerCase().trim();
        final cName = (inv['customer_name'] ?? '').toString().toLowerCase().trim();
        final cId = inv['customer_id']?.toString() ?? '';
        final matchesId = _selectedCustomerId != null &&
            _selectedCustomerId!.isNotEmpty &&
            cId == _selectedCustomerId;
        final matchesName = cName == target ||
            cName.contains(target) ||
            target.contains(cName);
        if (!matchesId && !matchesName) return false;
      } else if (_customerSearchController.text.trim().isNotEmpty) {
        final q = _customerSearchController.text.trim().toLowerCase();
        final cName = (inv['customer_name'] ?? '').toString().toLowerCase();
        final cPhone = (inv['customer_phone'] ?? '').toString().toLowerCase();
        final invNo = (inv['invoice_number'] ?? '').toString().toLowerCase();
        final items = List<Map<String, dynamic>>.from(inv['invoice_items'] ?? []);
        final hasMatchingItem = items.any((item) {
          final mName = (item['medicine_name'] ?? '').toString().toLowerCase();
          return mName.contains(q);
        });
        if (!cName.contains(q) &&
            !cPhone.contains(q) &&
            !invNo.contains(q) &&
            !hasMatchingItem) {
          return false;
        }
      }

      // 2. Date filter
      if (_selectedDate != null) {
        try {
          final dStr = inv['created_at'] ?? inv['invoice_date'];
          final date = DateTime.parse(dStr.toString()).toLocal();
          if (date.year != _selectedDate!.year ||
              date.month != _selectedDate!.month ||
              date.day != _selectedDate!.day) {
            return false;
          }
        } catch (_) {
          return false;
        }
      }

      // 3. Payment Status filter
      final grandTotal = (inv['grand_total'] as num?)?.toDouble() ?? 0.0;
      final paidAmount = (inv['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final dueAmount = (inv['due_amount'] as num?)?.toDouble() ?? (grandTotal - paidAmount);
      final rawStatus = (inv['status']?.toString() ?? '').toLowerCase();

      if (_selectedStatus == 'RETURNED') {
        if (rawStatus != 'returned') return false;
      } else if (_selectedStatus == 'PAID') {
        if (dueAmount > 0.001 || rawStatus == 'returned') return false;
      } else if (_selectedStatus == 'PARTIAL') {
        if (paidAmount <= 0 || dueAmount <= 0.001 || rawStatus == 'returned') return false;
      } else if (_selectedStatus == 'DUE') {
        if (dueAmount <= 0.001 || rawStatus == 'returned') return false;
      }

      return true;
    }).toList();
  }

  double _calculateTodayTotal(List<Map<String, dynamic>> exports) {
    final base = _selectedDate ?? DateTime.now();
    final dayStart = DateTime(base.year, base.month, base.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return exports.fold(0.0, (sum, item) {
      try {
        final dStr = item['created_at'] ?? item['invoice_date'];
        final date = DateTime.parse(dStr.toString()).toLocal();
        if (date.isAfter(dayStart) && date.isBefore(dayEnd)) {
          return sum + ((item['grand_total'] as num?)?.toDouble() ?? 0.0);
        }
      } catch (_) {}
      return sum;
    });
  }

  double _calculateSummaryTotal(List<Map<String, dynamic>> exports) {
    if (_selectedCustomerName != null && _selectedDate == null) {
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final monthEnd = DateTime(now.year, now.month, now.day + 1);
      return exports.fold(0.0, (sum, item) {
        try {
          final dStr = item['created_at'] ?? item['invoice_date'];
          final date = DateTime.parse(dStr.toString()).toLocal();
          if (date.isAfter(monthStart) && date.isBefore(monthEnd)) {
            return sum + ((item['grand_total'] as num?)?.toDouble() ?? 0.0);
          }
        } catch (_) {}
        return sum;
      });
    }
    return _calculateTodayTotal(exports);
  }

  Future<void> _deleteInvoice(String invoiceId, String invoiceNo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => HistoryDeleteDialog(
        title: 'Delete Sale Invoice #$invoiceNo',
        contentText:
            'This will delete the sale record and return all items back into batch stock. '
            'Are you sure you want to proceed?',
      ),
    );

    if (confirm != true || !mounted) return;

    final pharmacyId = context.read<AuthProvider>().currentPharmacy?.id;
    if (pharmacyId == null) return;

    setState(() => _processingInvoiceId = invoiceId);
    try {
      await _historyService.deleteInvoiceWithReversal(
        invoiceId: invoiceId,
        pharmacyId: pharmacyId,
      );

      // Refresh local inventory in background
      if (mounted) {
        context.read<InventoryProvider>().loadMedicines();
        setState(() {
          _invoices.removeWhere((i) => i['id']?.toString() == invoiceId);
          _processingInvoiceId = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invoice #$invoiceNo deleted & stock reverted.'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting invoice: $e');
      if (mounted) {
        setState(() => _processingInvoiceId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _printPdf(Map<String, dynamic> inv) async {
    final invProvider = Provider.of<InventoryProvider>(context, listen: false);
    final medMap = {for (final m in invProvider.medicines) m.id: m};

    final items = (inv['invoice_items'] as List? ?? []).map((item) {
      final medId = item['medicine_id']?.toString() ?? '';
      final med = medMap[medId];
      final int totalUnits = (item['quantity'] as num?)?.toInt() ?? 1;
      final double totalPrice = (item['total_price'] as num?)?.toDouble() ?? 0.0;
      final fmt = QuantityDisplayHelper.format(
        totalUnits: totalUnits,
        totalPrice: totalPrice,
        piecesPerStrip: med?.piecesPerStrip,
        stripsPerBox: med?.stripsPerBox,
        dosageForm: med?.dosageForm,
        medicineUnit: med?.unit,
      );

      return {
        'medicine_name': item['medicine_name'] ?? 'Item',
        'batch_number': item['batch_number'] ?? '',
        'quantity': fmt.quantityDisplay,
        'unit_price': fmt.unitRate,
        'total_price': totalPrice,
        'dosage_form': med?.dosageForm ?? '',
        'strength': med?.strength ?? '',
      };
    }).toList();

    await InvoicePdfService.printInvoice(
      context: context,
      exportData: {
        'id': inv['id'],
        'invoice_number': inv['invoice_number'] ?? 'INV',
        'customer_name': inv['customer_name'] ?? 'Walk-in Customer',
        'customer_phone': inv['customer_phone'] ?? '',
        'created_at': inv['created_at'] ?? inv['invoice_date'],
        'grand_total': inv['grand_total'],
        'paid_amount': inv['paid_amount'],
        'due_amount': inv['due_amount'],
        'discount_amount': inv['discount_amount'],
        'payment_status': (inv['due_amount'] as num? ?? 0) <= 0.01 ? 'PAID' : 'DUE',
        'items': items,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final invProvider = Provider.of<InventoryProvider>(context, listen: false);
    final medMap = {for (final m in invProvider.medicines) m.id: m};

    final filtered = _filteredInvoices;
    final summaryTotal = _calculateSummaryTotal(filtered);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: MediAppBar(
        title: 'Sales History',
        
      ),
      endDrawer: const AppDrawer(),
floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PosSaleScreen()),
          ).then((_) => _fetchInvoices());
        },
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.point_of_sale_rounded, color: Colors.white),
        label: const Text(
          'New Sale',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // â”€â”€ Curved blue container with customer search & date stepper â”€â”€â”€â”€â”€
          Container(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 17),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Customer search or selected customer chip
                    Expanded(
                      child: _selectedCustomerName != null
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.person,
                                      color: Colors.white, size: 16),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _selectedCustomerName ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _clearCustomerFilter,
                                    child: const Icon(Icons.close,
                                        color: Colors.white70, size: 18),
                                  ),
                                ],
                              ),
                            )
                          : TextField(
                              controller: _customerSearchController,
                              onChanged: _searchCustomer,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: "Filter by Customer",
                                hintStyle: const TextStyle(color: Colors.white70),
                                prefixIcon: const Icon(Icons.search,
                                    color: Colors.white70, size: 18),
                                suffixIcon: _customerSearchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear,
                                            color: Colors.white70, size: 16),
                                        onPressed: _clearCustomerFilter,
                                      )
                                    : null,
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.2),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 0),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                    ),

                    const SizedBox(width: 8),

                    // Date filter with prev/next stepper
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () {
                            final base = _selectedDate ?? DateTime.now();
                            setState(() => _selectedDate =
                                base.subtract(const Duration(days: 1)));
                          },
                          child: Container(
                            height: 44,
                            width: 32,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(12),
                                bottomLeft: Radius.circular(12),
                              ),
                            ),
                            child: const Icon(Icons.chevron_left,
                                color: Colors.white, size: 20),
                          ),
                        ),
                        GestureDetector(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setState(() => _selectedDate = picked);
                            }
                          },
                          child: Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: _selectedDate != null
                                  ? Colors.white.withValues(alpha: 0.35)
                                  : Colors.white.withValues(alpha: 0.2),
                              border: Border.symmetric(
                                vertical: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.2)),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.calendar_month,
                                    color: Colors.white, size: 16),
                                const SizedBox(width: 5),
                                Text(
                                  _selectedDate != null
                                      ? DateFormat('dd MMM').format(_selectedDate!)
                                      : 'Date',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (_selectedDate != null) ...[
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () => setState(() => _selectedDate = null),
                                    child: const Icon(Icons.close,
                                        color: Colors.white70, size: 14),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            final base = _selectedDate ?? DateTime.now();
                            final next = base.add(const Duration(days: 1));
                            if (next.isAfter(DateTime.now())) return;
                            setState(() => _selectedDate = next);
                          },
                          child: Container(
                            height: 44,
                            width: 32,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(12),
                                bottomRight: Radius.circular(12),
                              ),
                            ),
                            child: const Icon(Icons.chevron_right,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Search results dropdown
                if (_customerSearchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _customerSearchResults.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 48),
                      itemBuilder: (context, index) {
                        final customer = _customerSearchResults[index];
                        final cName = (customer['name'] ?? customer['customer_name'] ?? 'Customer').toString();
                        final phone = (customer['phone'] ?? '').toString();
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                            child: Text(
                              cName.isNotEmpty ? cName.substring(0, 1).toUpperCase() : 'C',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          title: Text(
                            cName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: phone.isNotEmpty
                              ? Text(
                                  phone,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                )
                              : null,
                          onTap: () => _selectCustomer(customer),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // â”€â”€ Summary Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.today, color: AppColors.primary, size: 24),
                ),
                title: Text(
                  _selectedCustomerName != null && _selectedDate != null
                      ? _selectedCustomerName!
                      : _selectedCustomerName != null
                          ? _selectedCustomerName!
                          : _selectedDate != null
                              ? DateFormat('dd MMM yyyy').format(_selectedDate!)
                              : "Today's Export",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  _selectedCustomerName != null && _selectedDate != null
                      ? "Total sold by ${_selectedCustomerName!} on ${DateFormat('dd MMM').format(_selectedDate!)}"
                      : _selectedCustomerName != null
                          ? "Total sold to ${_selectedCustomerName!} this month (${DateFormat('MMM yyyy').format(DateTime.now())})"
                          : _selectedDate != null
                              ? "Total amount on this day"
                              : "Total amount sold today",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                trailing: Text(
                  "৳${summaryTotal.toStringAsFixed(2)}",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),

          // â”€â”€ Status Filter Chips Row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _statusOptions.map((status) {
                  final isSelected = _selectedStatus == status;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(status),
                      selected: isSelected,
                      selectedColor: AppColors.primary.withValues(alpha: 0.15),
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(
                        color: isSelected ? AppColors.primary : Colors.grey.shade700,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      side: BorderSide(
                        color: isSelected ? AppColors.primary : Colors.grey.shade300,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _selectedStatus = status);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // â”€â”€ Invoice List â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long_outlined,
                                size: 56, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'No export/sales history found.',
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 15),
                            ),
                            if (_hasActiveFilters) ...[
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _clearAllFilters,
                                child: const Text('Clear Filters',
                                    style: TextStyle(color: AppColors.primary)),
                              ),
                            ],
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchInvoices,
                        color: AppColors.primary,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final inv = filtered[i];
                            final invoiceId = inv['id']?.toString() ?? '';
                            return ExportHistoryCard(
                              invoice: inv,
                              medMap: medMap,
                              onEdit: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PosSaleScreen(
                                      invoiceId: invoiceId,
                                    ),
                                  ),
                                ).then((_) => _fetchInvoices());
                              },
                              onPrint: () => _printPdf(inv),
                              onDelete: () => _deleteInvoice(
                                invoiceId,
                                inv['invoice_number'] ?? 'INV',
                              ),
                              isProcessing:
                                  _processingInvoiceId == invoiceId,
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
