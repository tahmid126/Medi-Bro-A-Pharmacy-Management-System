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
import '../../widgets/history/import_history_card.dart';
import '../../widgets/history/purchase_payment_dialog.dart';
import '../../widgets/history/history_delete_dialog.dart';
import '../../../data/models/medicine_model.dart';
import '../purchases/purchase_entry_screen.dart';
import '../../widgets/common/medi_app_bar.dart';

class ImportHistoryScreen extends StatefulWidget {
  const ImportHistoryScreen({super.key});

  @override
  State<ImportHistoryScreen> createState() => _ImportHistoryScreenState();
}

class _ImportHistoryScreenState extends State<ImportHistoryScreen> {
  final HistoryService _historyService = HistoryService();

  // Search & Filters
  final TextEditingController _companySearchController = TextEditingController();
  String? _selectedSupplierId;
  String? _selectedCompanyName;
  List<Map<String, dynamic>> _companySearchResults = [];

  DateTime? _selectedDate;
  String _selectedStatus = 'All Status';
  final List<String> _statusOptions = ['All Status', 'PAID', 'PARTIAL', 'CREDIT'];
  late final PageController _pageController;

  // State
  List<Map<String, dynamic>> _purchases = [];
  bool _isLoading = true;
  String? _processingPurchaseId;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _statusOptions.indexOf(_selectedStatus));
    _fetchPurchases();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _companySearchController.dispose();
    super.dispose();
  }

  Future<void> _fetchPurchases() async {
    setState(() => _isLoading = true);
    try {
      final pharmacyId = context.read<AuthProvider>().currentPharmacy?.id;
      if (pharmacyId == null) {
        setState(() => _isLoading = false);
        return;
      }
      final data = await _historyService.fetchPurchases(pharmacyId);
      if (mounted) {
        setState(() {
          _purchases = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching purchases: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load import history: $e')),
        );
      }
    }
  }

  Future<void> _searchCompany(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _companySearchResults = [];
      });
      return;
    }

    final pharmacyId = context.read<AuthProvider>().currentPharmacy?.id ?? '';
    final localMedicines = context.read<InventoryProvider>().medicines;

    final results = await _historyService.searchCompanies(
      pharmacyId: pharmacyId,
      query: q,
      loadedPurchases: _purchases,
      localMedicines: localMedicines,
    );

    if (mounted) {
      setState(() => _companySearchResults = results);
    }
  }

  void _selectCompany(Map<String, dynamic> c) {
    setState(() {
      _selectedSupplierId = c['id']?.toString();
      _selectedCompanyName = (c['raw_name'] ?? c['name'])?.toString();
      _companySearchController.clear();
      _companySearchResults = [];
    });
  }

  void _clearCompanyFilter() {
    setState(() {
      _selectedSupplierId = null;
      _selectedCompanyName = null;
      _companySearchController.clear();
      _companySearchResults = [];
    });
  }

  void _clearAllFilters() {
    setState(() {
      _selectedSupplierId = null;
      _selectedCompanyName = null;
      _companySearchController.clear();
      _companySearchResults = [];
      _selectedDate = null;
      _selectedStatus = 'All Status';
    });
  }

  bool get _hasActiveFilters =>
      _selectedSupplierId != null ||
      _selectedCompanyName != null ||
      _companySearchController.text.isNotEmpty ||
      _selectedDate != null ||
      _selectedStatus != 'All Status';

  List<Map<String, dynamic>> _getPurchasesForStatus(String status) {
    return _purchases.where((pur) {
      // 1. Company filter
      if (_selectedCompanyName != null && _selectedCompanyName!.isNotEmpty) {
        final target = _selectedCompanyName!.toLowerCase().trim();
        final suppName = (pur['supplier_name'] ?? '').toString().toLowerCase().trim();
        final suppId = pur['supplier_id']?.toString() ?? '';
        final matchesId = _selectedSupplierId != null &&
            _selectedSupplierId!.isNotEmpty &&
            suppId == _selectedSupplierId;
        final matchesName = suppName == target ||
            suppName.contains(target) ||
            target.contains(suppName);
        if (!matchesId && !matchesName) return false;
      } else if (_companySearchController.text.trim().isNotEmpty) {
        final q = _companySearchController.text.trim().toLowerCase();
        final suppName = (pur['supplier_name'] ?? '').toString().toLowerCase();
        final purNo = (pur['purchase_number'] ?? '').toString().toLowerCase();
        final items = List<Map<String, dynamic>>.from(pur['purchase_items'] ?? []);
        final hasMatchingItem = items.any((item) {
          final mName = (item['medicine_name'] ?? '').toString().toLowerCase();
          return mName.contains(q);
        });
        if (!suppName.contains(q) && !purNo.contains(q) && !hasMatchingItem) return false;
      }

      // 2. Date filter
      if (_selectedDate != null) {
        try {
          final dStr = pur['created_at'] ?? pur['purchase_date'];
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
      final grandTotal = (pur['grand_total'] as num?)?.toDouble() ?? 0.0;
      final paidAmount = (pur['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final dueAmount = (pur['due_amount'] as num?)?.toDouble() ?? (grandTotal - paidAmount);

      if (status == 'PAID') {
        if (dueAmount > 0.001) return false;
      } else if (status == 'PARTIAL') {
        if (paidAmount <= 0 || dueAmount <= 0.001) return false;
      } else if (status == 'CREDIT') {
        if (dueAmount <= 0.001) return false;
      }

      return true;
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredPurchases => _getPurchasesForStatus(_selectedStatus);

  double _calculateTodayTotal(List<Map<String, dynamic>> imports) {
    final base = _selectedDate ?? DateTime.now();
    final dayStart = DateTime(base.year, base.month, base.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return imports.fold(0.0, (sum, item) {
      try {
        final dStr = item['created_at'] ?? item['purchase_date'];
        final date = DateTime.parse(dStr.toString()).toLocal();
        if (date.isAfter(dayStart) && date.isBefore(dayEnd)) {
          return sum + ((item['grand_total'] as num?)?.toDouble() ?? 0.0);
        }
      } catch (_) {}
      return sum;
    });
  }

  double _calculateSummaryTotal(List<Map<String, dynamic>> imports) {
    if (_selectedCompanyName != null && _selectedDate == null) {
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final monthEnd = DateTime(now.year, now.month, now.day + 1);
      return imports.fold(0.0, (sum, item) {
        try {
          final dStr = item['created_at'] ?? item['purchase_date'];
          final date = DateTime.parse(dStr.toString()).toLocal();
          if (date.isAfter(monthStart) && date.isBefore(monthEnd)) {
            return sum + ((item['grand_total'] as num?)?.toDouble() ?? 0.0);
          }
        } catch (_) {}
        return sum;
      });
    }
    return _calculateTodayTotal(imports);
  }

  Future<void> _showPaymentDialog(Map<String, dynamic> pur) async {
    final purchaseId = pur['id']?.toString() ?? '';
    await showDialog(
      context: context,
      builder: (ctx) => PurchasePaymentDialog(
        purchase: pur,
        onConfirmPayment: (amount, method) async {
          await _historyService.recordPurchasePayment(
            purchaseId: purchaseId,
            paymentAmount: amount,
            paymentMethod: method,
          );
          if (mounted) {
            await _fetchPurchases();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Payment recorded successfully.'),
                backgroundColor: AppColors.primary,
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _deletePurchase(String purchaseId, String purchaseNo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => HistoryDeleteDialog(
        title: 'Delete Purchase #$purchaseNo',
        contentText:
            'This will permanently delete this purchase record and remove its stock batches. '
            'This action cannot be undone if stock was already sold. Are you sure?',
      ),
    );

    if (confirm != true || !mounted) return;

    final pharmacyId = context.read<AuthProvider>().currentPharmacy?.id;
    if (pharmacyId == null) return;

    setState(() => _processingPurchaseId = purchaseId);
    try {
      await _historyService.deletePurchaseWithValidation(
        purchaseId: purchaseId,
        pharmacyId: pharmacyId,
      );

      // Refresh local inventory in background
      if (mounted) {
        context.read<InventoryProvider>().loadMedicines();
        setState(() {
          _purchases.removeWhere((p) => p['id']?.toString() == purchaseId);
          _processingPurchaseId = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Purchase #$purchaseNo deleted successfully.'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting purchase: $e');
      if (mounted) {
        setState(() => _processingPurchaseId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _printPdf(Map<String, dynamic> pur) async {
    final invProvider = Provider.of<InventoryProvider>(context, listen: false);
    final medMap = {for (final m in invProvider.medicines) m.id: m};

    final items = (pur['purchase_items'] as List? ?? []).map((item) {
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
        'id': pur['id'],
        'invoice_number': pur['purchase_number'] ?? 'PUR',
        'customer_name': 'Supplier: ${pur['supplier_name'] ?? 'Supplier'}',
        'created_at': pur['created_at'] ?? pur['purchase_date'],
        'grand_total': pur['grand_total'],
        'paid_amount': pur['paid_amount'],
        'due_amount': pur['due_amount'],
        'discount_amount': pur['discount_amount'],
        'payment_status': (pur['due_amount'] as num? ?? 0) <= 0.01 ? 'PAID' : 'DUE',
        'items': items,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final invProvider = Provider.of<InventoryProvider>(context, listen: false);
    final medMap = {for (final m in invProvider.medicines) m.id: m};

    final filtered = _filteredPurchases;
    final summaryTotal = _calculateSummaryTotal(filtered);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: MediAppBar(
        title: 'Purchase History',
        
      ),
      endDrawer: const AppDrawer(),
floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PurchaseEntryScreen()),
          ).then((_) => _fetchPurchases());
        },
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white),
        label: const Text(
          'New Import',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // â”€â”€ Curved blue container with company search & date stepper â”€â”€â”€â”€â”€
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
                    // Company search
                    Expanded(
                      child: _selectedCompanyName != null
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.domain,
                                      color: Colors.white, size: 16),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _selectedCompanyName ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _clearCompanyFilter,
                                    child: const Icon(Icons.close,
                                        color: Colors.white70, size: 18),
                                  ),
                                ],
                              ),
                            )
                          : TextField(
                              controller: _companySearchController,
                              onChanged: _searchCompany,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: "Filter by Company",
                                hintStyle: const TextStyle(color: Colors.white70),
                                prefixIcon: const Icon(Icons.search,
                                    color: Colors.white70, size: 18),
                                suffixIcon: _companySearchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear,
                                            color: Colors.white70, size: 16),
                                        onPressed: _clearCompanyFilter,
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
                if (_companySearchResults.isNotEmpty)
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
                      itemCount: _companySearchResults.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 48),
                      itemBuilder: (context, index) {
                        final company = _companySearchResults[index];
                        final cName = (company['name'] ?? company['company_name'] ?? '').toString();
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                            child: Text(
                              cName.isNotEmpty
                                  ? cName.substring(0, 1).toUpperCase()
                                  : 'C',
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
                          onTap: () => _selectCompany(company),
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
                  _selectedCompanyName != null && _selectedDate != null
                      ? _selectedCompanyName!
                      : _selectedCompanyName != null
                          ? _selectedCompanyName!
                          : _selectedDate != null
                              ? DateFormat('dd MMM yyyy').format(_selectedDate!)
                              : "Today's Import",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  _selectedCompanyName != null && _selectedDate != null
                      ? "Total imported on ${DateFormat('dd MMM').format(_selectedDate!)} by $_selectedCompanyName"
                      : _selectedCompanyName != null
                          ? "Total imported this month (${DateFormat('MMM yyyy').format(DateTime.now())})"
                          : _selectedDate != null
                              ? "Total amount on this day"
                              : "Total amount imported today",
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
                        if (val) {
                          setState(() => _selectedStatus = status);
                          final idx = _statusOptions.indexOf(status);
                          if (idx != -1 && _pageController.hasClients) {
                            _pageController.animateToPage(
                              idx,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ── Purchase List (Swipeable tabs) ─────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : PageView.builder(
                    controller: _pageController,
                    itemCount: _statusOptions.length,
                    onPageChanged: (idx) {
                      setState(() {
                        _selectedStatus = _statusOptions[idx];
                      });
                    },
                    itemBuilder: (ctx, pageIdx) {
                      final statusForPage = _statusOptions[pageIdx];
                      final list = _getPurchasesForStatus(statusForPage);
                      return _buildPurchaseList(list, medMap);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseList(
    List<Map<String, dynamic>> list,
    Map<String, MedicineModel> medMap,
  ) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'No import history found.',
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
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchPurchases,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 10),
        itemCount: list.length,
        itemBuilder: (ctx, i) {
          final pur = list[i];
          final purchaseId = pur['id']?.toString() ?? '';
          return ImportHistoryCard(
            purchase: pur,
            medMap: medMap,
            onEdit: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PurchaseEntryScreen(
                    purchaseId: purchaseId,
                  ),
                ),
              ).then((_) => _fetchPurchases());
            },
            onPayment: () => _showPaymentDialog(pur),
            onPrint: () => _printPdf(pur),
            onDelete: () => _deletePurchase(
              purchaseId,
              pur['purchase_number'] ?? 'PUR',
            ),
            isProcessing:
                _processingPurchaseId == purchaseId,
          );
        },
      ),
    );
  }
}
