import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/utils/medicine_packaging_helper.dart';
import '../../../data/models/batch_model.dart';
import '../../../data/models/medicine_model.dart';
import '../../../data/services/pos_service.dart';
import '../../../data/services/draft_service.dart';
import '../../../data/services/supabase_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/inventory_provider.dart';
import '../contacts/add_customer_form.dart';

import '../../../data/models/export_cart_item.dart';
import '../../widgets/pos/pos_customer_section.dart';
import '../../widgets/pos/pos_quick_add_card.dart';
import '../../widgets/pos/pos_cart_item_card.dart';
import '../../widgets/pos/pos_totals_summary_card.dart';
import '../../widgets/pos/pos_payment_card.dart';
import '../../widgets/common/medi_app_bar.dart';
import '../../widgets/app_drawer.dart';

class PosSaleScreen extends StatefulWidget {
  final String? draftId;
  final String? invoiceId;
  const PosSaleScreen({super.key, this.draftId, this.invoiceId});

  @override
  State<PosSaleScreen> createState() => _PosSaleScreenState();
}

class _PosSaleScreenState extends State<PosSaleScreen> {
  final _posService = PosService();
  String? _currentDraftId;
  String? _editingInvoiceId;
  bool _isEditingPartialPayment = false;
  final Map<String, int> _oldInvoiceItemQuantities = {};
  bool _isLoadingDraft = false;
  bool _isLoadingInvoice = false;
  bool _isSavingDraft = false;
  final _client = SupabaseService.instance.client;

  // Global medicines for official MRP and packaging fallback
  List<Map<String, dynamic>> _globalMedicines = [];

  // Customer State
  final _customerSearchController = TextEditingController();
  List<Map<String, dynamic>> _customerSearchResults = [];
  bool _isSearchingCustomer = false;
  String? _selectedCustomerId;
  String? _selectedCustomerName;
  String? _selectedCustomerPhone;
  double _previousDue = 0.0;

  // Medicine Search & Overlay
  final _medSearchController = TextEditingController();
  final _medLayerLink = LayerLink();
  OverlayEntry? _medOverlay;
  List<MedicineModel> _medicineSearchResults = [];

  // Selected Medicine for Quick-Add (inline below search bar)
  MedicineModel? _selectedMedForAdd;
  Map<String, dynamic>? _selectedGlobalMedForAdd;
  int? _editingCartIndex;

  // Cart List
  final List<ExportCartItem> _cartList = [];

  // Discount State
  String _discountType = '%'; // '%' or 'Cash'
  double _discountValue = 0.0;
  final _discountController = TextEditingController(text: '0');

  // Payment State
  final _payingNowController = TextEditingController();
  final String _paymentMethod = 'cash'; // 'cash', 'bkash', 'nagad', 'card'
  final _notesCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<InventoryProvider>().loadMedicines();
      await _fetchGlobalMedicines();
      if (widget.invoiceId != null) {
        _editingInvoiceId = widget.invoiceId;
        _loadExistingInvoice(_editingInvoiceId!);
      } else if (widget.draftId != null) {
        _currentDraftId = widget.draftId;
        _loadDraft();
      }
    });
  }

  @override
  void dispose() {
    _customerSearchController.dispose();
    _medSearchController.dispose();
    _discountController.dispose();
    _payingNowController.dispose();
    _notesCtrl.dispose();
    _removeMedOverlay();
    for (var item in _cartList) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchGlobalMedicines() async {
    try {
      final data = await _client
          .from(SupabaseConstants.globalMedicinesTable)
          .select('*')
          .order('brand_name', ascending: true);
      if (mounted) {
        setState(() {
          _globalMedicines = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      debugPrint('Error loading global medicines: $e');
    }
  }

  // --- Calculations ---
  double get _subtotal {
    return _cartList.fold(0.0, (sum, item) => sum + item.lineTotal);
  }

  double get _discountAmount {
    if (_discountType == '%') {
      return _subtotal * (_discountValue / 100);
    }
    return _discountValue;
  }

  double get _finalTotal {
    final net = _subtotal - _discountAmount;
    return net > 0 ? net : 0.0;
  }

  /// Rounded Today's Bill for Payment & Due Summary:
  /// Fractions 0.1 - 0.4 round down, 0.5 - 0.9 round up (e.g. 12.1-12.4 -> 12, 12.5-12.9 -> 13)
  double get _todayBill => _finalTotal.roundToDouble();

  double get _payingNow {
    return double.tryParse(_payingNowController.text) ?? _todayBill;
  }

  double get _newDueAfterThis {
    return _previousDue + _todayBill - _payingNow;
  }

  void _syncPayingNow() {
    if (_editingInvoiceId != null && _isEditingPartialPayment) {
      return;
    }
    setState(() {
      _payingNowController.text = _todayBill.toStringAsFixed(2);
    });
  }

  // --- Effective MRP Lookup with Global Fallback ---
  Map<String, dynamic>? _matchGlobalMedicine(MedicineModel med) {
    if (_globalMedicines.isEmpty) return null;
    if (med.globalId != null && med.globalId!.isNotEmpty) {
      final m = _globalMedicines.firstWhere(
        (g) => g['id']?.toString() == med.globalId,
        orElse: () => {},
      );
      if (m.isNotEmpty) return m;
    }

    final bName = med.brandName.trim().toLowerCase();
    final dForm = med.dosageForm.trim().toLowerCase();
    final str = (med.strength ?? '').trim().toLowerCase();

    final match = _globalMedicines.firstWhere(
      (g) {
        final gb = (g['brand_name'] ?? '').toString().trim().toLowerCase();
        final gd = (g['dosage_form'] ?? '').toString().trim().toLowerCase();
        final gs = (g['strength'] ?? '').toString().trim().toLowerCase();
        return gb == bName &&
            (gd.isEmpty || dForm.isEmpty || gd == dForm) &&
            (gs.isEmpty || str.isEmpty || gs == str);
      },
      orElse: () => _globalMedicines.firstWhere(
        (g) => (g['brand_name'] ?? '').toString().trim().toLowerCase() == bName,
        orElse: () => {},
      ),
    );
    return match.isNotEmpty ? match : null;
  }

  double _getEffectiveMrp(MedicineModel med) {
    // 1. Check primary active batch
    final batch = med.primaryActiveBatch;
    if (batch != null && batch.mrp > 0) return batch.mrp;
    if (batch != null && batch.sellingPrice > 0) return batch.sellingPrice;

    // 2. Check all batches
    for (final b in med.batches) {
      if (b.mrp > 0) return b.mrp;
      if (b.sellingPrice > 0) return b.sellingPrice;
    }

    // 3. Match from global catalog by globalId or brandName
    if (_globalMedicines.isNotEmpty) {
      Map<String, dynamic>? match;
      if (med.globalId != null && med.globalId!.isNotEmpty) {
        match = _globalMedicines.firstWhere(
          (g) => g['id'] == med.globalId,
          orElse: () => {},
        );
      }
      if (match == null || match.isEmpty) {
        final bName = med.brandName.trim().toLowerCase();
        final dForm = med.dosageForm.trim().toLowerCase();
        final str = (med.strength ?? '').trim().toLowerCase();

        match = _globalMedicines.firstWhere(
          (g) {
            final gb = (g['brand_name'] ?? '').toString().trim().toLowerCase();
            final gd = (g['dosage_form'] ?? '').toString().trim().toLowerCase();
            final gs = (g['strength'] ?? '').toString().trim().toLowerCase();
            return gb == bName &&
                (gd.isEmpty || dForm.isEmpty || gd == dForm) &&
                (gs.isEmpty || str.isEmpty || gs == str);
          },
          orElse: () => _globalMedicines.firstWhere(
            (g) => (g['brand_name'] ?? '').toString().trim().toLowerCase() == bName,
            orElse: () => {},
          ),
        );
      }

      if (match.isNotEmpty) {
        final defMrp = double.tryParse(match['default_mrp']?.toString() ?? '0') ?? 0.0;
        if (defMrp > 0) return defMrp;
      }
    }

    return 0.0;
  }

  // --- Customer Search & Selection ---
  Future<void> _searchCustomer(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _customerSearchResults = []);
      return;
    }

    setState(() => _isSearchingCustomer = true);

    try {
      final auth = context.read<AuthProvider>();
      final pharmacyId = auth.currentProfile?.pharmacyId;

      final res = await _client
          .from(SupabaseConstants.customersTable)
          .select()
          .eq('pharmacy_id', pharmacyId ?? '')
          .or('name.ilike.%$q%,phone.ilike.%$q%,address.ilike.%$q%')
          .limit(8);

      final List<Map<String, dynamic>> list = [];
      for (final c in res as List) {
        list.add({
          'id': c['id'],
          'name': (c['name'] ?? '').toString().trim(),
          'phone': c['phone'],
          'address': c['address'],
          'current_due': (c['current_due'] as num?)?.toDouble() ?? 0.0,
        });
      }

      if (mounted) {
        setState(() {
          _customerSearchResults = list;
          _isSearchingCustomer = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSearchingCustomer = false);
    }
  }

  void _selectCustomer(Map<String, dynamic> customer) {
    setState(() {
      _selectedCustomerId = customer['id'] as String?;
      _selectedCustomerName = (customer['name'] ?? '').toString();
      _selectedCustomerPhone = customer['phone'] as String?;
      _previousDue = (customer['current_due'] as num?)?.toDouble() ?? 0.0;
      _customerSearchController.clear();
      _customerSearchResults = [];
    });

    if (_selectedCustomerId != null) {
      _fetchCustomerDue(_selectedCustomerId!);
    }
    _syncPayingNow();
  }

  Future<void> _fetchCustomerDue(String customerId, {double excludeOldDue = 0.0}) async {
    try {
      final res = await _client
          .from(SupabaseConstants.customersTable)
          .select('current_due')
          .eq('id', customerId)
          .maybeSingle();

      if (mounted && res != null) {
        setState(() {
          final rawDue = (res['current_due'] as num?)?.toDouble() ?? 0.0;
          _previousDue = (rawDue - excludeOldDue).clamp(0.0, double.infinity);
        });
      }
    } catch (_) {}
  }

  void _clearSelectedCustomer() {
    setState(() {
      _selectedCustomerId = null;
      _selectedCustomerName = null;
      _selectedCustomerPhone = null;
      _previousDue = 0.0;
      _customerSearchController.clear();
      _customerSearchResults = [];
    });
    _syncPayingNow();
  }

  // --- Floating Medicine Search Overlay ---
  void _removeMedOverlay() {
    _medOverlay?.remove();
    _medOverlay = null;
  }

  void _showMedOverlay() {
    _removeMedOverlay();
    if (_medicineSearchResults.isEmpty) return;

    _medOverlay = OverlayEntry(
      builder: (context) => Positioned(
        width: MediaQuery.of(context).size.width > 600
            ? 550
            : MediaQuery.of(context).size.width - 32,
        child: CompositedTransformFollower(
          link: _medLayerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 52),
          child: Material(
            elevation: 12,
            borderRadius: BorderRadius.circular(14),
            color: Colors.white,
            clipBehavior: Clip.antiAlias,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue.shade100),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: _medicineSearchResults.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 14, endIndent: 14),
                itemBuilder: (context, idx) {
                  final med = _medicineSearchResults[idx];
                  final int stock = med.totalStock;
                  final double mrp = _getEffectiveMrp(med);
                  final companyName = (med.company ?? '').trim();

                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            med.brandName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF1E293B)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            med.dosageForm,
                            style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (med.strength != null && med.strength!.isNotEmpty) ...[
                          const SizedBox(width: 5),
                          Text(
                            med.strength!,
                            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                          ),
                        ],
                        if (med.weight != null && med.weight!.isNotEmpty) ...[
                          const SizedBox(width: 5),
                          Text(
                            med.weight!,
                            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        // Line 2: Generic (left, expands) & MRP (extreme right)
                        Row(
                          children: [
                            if (med.genericName != null && med.genericName!.isNotEmpty)
                              Expanded(
                                child: Text(
                                  med.genericName!,
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                            else
                              const Spacer(),
                            const SizedBox(width: 8),
                            Text(
                              'MRP: ৳${mrp.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF2563EB)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        // Line 3: Company / Manufacturer, Stock beside company, and Rack in blue
                        Row(
                          children: [
                            Icon(Icons.business_rounded, size: 12, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                companyName.isNotEmpty ? companyName : 'Unknown Manufacturer',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.blue.shade800,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('•', style: TextStyle(color: Colors.grey.shade400)),
                            const SizedBox(width: 6),
                            Text(
                              'Stock: $stock ${med.unit}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: stock > 0 ? const Color(0xFF10B981) : Colors.red.shade600,
                              ),
                            ),
                            if (med.rackLocation != null && med.rackLocation!.trim().isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text('•', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                              const SizedBox(width: 6),
                              Icon(Icons.shelves, size: 12, color: Colors.blue.shade700),
                              const SizedBox(width: 3),
                              Text(
                                'Rack: ${med.rackLocation!.trim()}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Select +',
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                    onTap: () {
                      _selectMedicineForAdd(med);
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_medOverlay!);
  }

  void _searchMedicines(String query) {
    final rawQ = query.trim().toLowerCase();
    if (rawQ.isEmpty) {
      _removeMedOverlay();
      setState(() => _medicineSearchResults = []);
      return;
    }

    final queryTokens = rawQ.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final inventory = context.read<InventoryProvider>();
    final allMeds = inventory.medicines;

    final filtered = allMeds.where((m) {
      final brand = m.brandName.toLowerCase();
      final generic = (m.genericName ?? '').toLowerCase();
      final company = (m.company ?? '').toLowerCase();
      final strength = (m.strength ?? '').toLowerCase();

      return queryTokens.every((token) =>
          brand.contains(token) ||
          generic.contains(token) ||
          company.contains(token) ||
          strength.contains(token));
    }).take(10).toList();

    setState(() {
      _medicineSearchResults = filtered;
    });

    if (filtered.isNotEmpty) {
      _showMedOverlay();
    } else {
      _removeMedOverlay();
    }
  }

  // --- Select Medicine for Quick-Add Card ---
  void _selectMedicineForAdd(MedicineModel med) {
    _removeMedOverlay();
    _medSearchController.clear();
    final globalMatch = _matchGlobalMedicine(med);

    setState(() {
      _selectedMedForAdd = med;
      _selectedGlobalMedForAdd = globalMatch;
      _editingCartIndex = null;
    });
  }

  void _startEditCartItem(int index) {
    if (index < 0 || index >= _cartList.length) return;
    final item = _cartList[index];
    setState(() {
      _editingCartIndex = index;
      _selectedMedForAdd = item.medicine;
      _selectedGlobalMedForAdd = _matchGlobalMedicine(item.medicine);
    });
  }

  void _confirmAddOrUpdateCartItem(ExportCartItem entry) {
    setState(() {
      if (_editingCartIndex != null && _editingCartIndex! < _cartList.length) {
        _cartList[_editingCartIndex!].dispose();
        _cartList[_editingCartIndex!] = entry;
        _editingCartIndex = null;
      } else {
        final existingIndex = _cartList.indexWhere(
          (item) => item.medicine.id == entry.medicine.id && item.unitType == entry.unitType,
        );
        if (existingIndex >= 0) {
          _cartList[existingIndex].dispose();
          _cartList[existingIndex] = entry;
        } else {
          _cartList.add(entry);
        }
      }
      _selectedMedForAdd = null;
      _selectedGlobalMedForAdd = null;
    });
    _syncPayingNow();
  }

  // --- Save / Complete Sale with Due, Stock & Loss Checks ---
  Future<void> _saveSale() async {
    if (_cartList.isEmpty) {
      _showMsg('Please add at least one medicine to the cart');
      return;
    }

    final auth = context.read<AuthProvider>();
    final pharmacyId = auth.currentProfile?.pharmacyId;
    if (pharmacyId == null || pharmacyId.isEmpty) {
      _showMsg('Pharmacy ID not found. Please log in again.');
      return;
    }

    // 1. INSUFFICIENT STOCK CHECK (Cannot sell more than in stock, accounting for old invoice items in edit mode):
    final stockExceededItems = _cartList.where((i) {
      final oldQty = _editingInvoiceId != null ? (_oldInvoiceItemQuantities[i.medicine.id] ?? 0) : 0;
      final effectiveAvailable = i.medicine.totalStock + oldQty;
      return i.effectiveUnits > effectiveAvailable;
    }).toList();

    if (stockExceededItems.isNotEmpty) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text('Insufficient Stock'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cannot sell more than available stock! The following items exceed stock:',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              ...stockExceededItems.map((item) {
                final oldQty = _editingInvoiceId != null ? (_oldInvoiceItemQuantities[item.medicine.id] ?? 0) : 0;
                final effectiveAvailable = item.medicine.totalStock + oldQty;
                final short = item.effectiveUnits - effectiveAvailable;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                      Expanded(
                        child: Text(
                          '${item.medicine.brandName}: In cart: ${item.effectiveUnits} ${item.medicine.unit}, Available stock: $effectiveAvailable ${item.medicine.unit} (Shortage: $short ${item.medicine.unit})',
                          style: TextStyle(fontSize: 12.5, color: Colors.red.shade900, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 10),
              Text(
                'Please reduce quantity in cart before completing the sale.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK / Adjust Cart'),
            ),
          ],
        ),
      );
      return;
    }

    final double paying = _payingNow.clamp(0.0, double.infinity);
    final double invoiceDue = _todayBill - paying > 0 ? _todayBill - paying : 0.0;
    final double due = invoiceDue;

    // 2. DUE VALIDATION CHECK:
    // If there is any due, customer contact MUST be selected!
    if (due > 0 && (_selectedCustomerId == null || _selectedCustomerId!.isEmpty)) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Text('Customer Contact Required'),
            ],
          ),
          content: Text(
            'This sale has an unpaid due of ৳${due.toStringAsFixed(2)}.\n\n'
            'Due transactions cannot be recorded for a Walking Customer.\n\n'
            'Please select an existing customer from the search bar above, or click "+ New" to add this customer.',
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.person_add_rounded, size: 16),
              label: const Text('Add Customer Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                final newCust = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddCustomerForm()),
                );
                if (newCust != null && newCust is Map<String, dynamic>) {
                  _selectCustomer(newCust);
                }
              },
            ),
          ],
        ),
      );
      return;
    }

    // 3. LOSS / MARGIN PROTECTION CHECK:
    // Check if total selling revenue is lower than total buying cost
    final double totalBuyingCost = _cartList.fold(
      0.0,
      (sum, item) => sum + (item.singleUnitCost * item.effectiveUnits),
    );
    final double totalSellingRevenue = _todayBill;

    if (totalBuyingCost > 0 && totalSellingRevenue < totalBuyingCost) {
      final lossAmount = totalBuyingCost - totalSellingRevenue;
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text('Potential Loss Warning'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total Selling Price (৳${totalSellingRevenue.toStringAsFixed(2)}) is lower than Total Buying Cost (৳${totalBuyingCost.toStringAsFixed(2)}).',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.red),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.trending_down_rounded, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Estimated Loss: ৳${lossAmount.toStringAsFixed(2)}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade900, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Are you sure you want to proceed with this sale, or would you like to review the prices and discount?',
                style: TextStyle(fontSize: 13, color: Colors.black87),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Review Cart / Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Proceed Anyway'),
            ),
          ],
        ),
      );

      if (proceed != true) return;
    }

    setState(() => _isSaving = true);

    try {
      final List<Map<String, dynamic>> itemsPayload = [];
      for (var item in _cartList) {
        final unitPricePerPiece = item.effectiveUnits > 0 ? (item.lineTotal / item.effectiveUnits) : 0.0;
        itemsPayload.add({
          'medicine_id': item.medicine.id,
          'batch_id': item.batch?.id,
          'medicine_name': item.medicine.brandName,
          'batch_number': item.batch?.batchNumber,
          'expiry_date': item.batch?.expiryDate.toIso8601String().split('T').first,
          'quantity': item.effectiveUnits,
          'unit_price': unitPricePerPiece,
          'mrp': item.singleUnitMrp,
          'purchase_price': item.singleUnitCost,
          'total_price': item.lineTotal,
        });
      }

      final List<Map<String, dynamic>> itemsDetail = _cartList.map((item) {
        return {
          'medicine_id': item.medicine.id,
          'medicine_name': item.medicine.brandName,
          'batch_id': item.batch?.id,
          'batch_number': item.batch?.batchNumber,
          'raw_quantity': item.quantity,
          'unit_type': item.unitType,
          'unit_selling_price': item.unitSellingPrice,
          'single_unit_mrp': item.singleUnitMrp,
          'single_unit_cost': item.singleUnitCost,
          'discount_percent': item.discountPercent,
          'discount_mode': item.discountMode,
          'pieces_per_strip': item.piecesPerStrip,
          'strips_per_box': item.stripsPerBox,
          'line_total': item.lineTotal,
        };
      }).toList();

      final String serializedNotes = jsonEncode({
        'user_notes': _notesCtrl.text.trim(),
        'discount_type': _discountType,
        'discount_value': _discountValue,
        'discount_percent': _discountType == '%' ? _discountValue : null,
        'discount_amount': _discountAmount,
        'subtotal': _subtotal,
        'items_detail': itemsDetail,
      });

      if (_editingInvoiceId != null) {
        await _posService.updateSaleInvoiceWithItems(
          invoiceId: _editingInvoiceId!,
          customerId: _selectedCustomerId,
          customerName: _selectedCustomerName ?? 'Walking Customer',
          customerPhone: _selectedCustomerPhone,
          subtotal: _subtotal,
          discountType: _discountType == '%' ? 'percent' : 'fixed',
          discountAmount: _discountAmount,
          grandTotal: _todayBill,
          paidAmount: paying,
          dueAmount: due,
          paymentMethod: _paymentMethod,
          notes: serializedNotes,
          items: itemsPayload,
        );

        if (!mounted) return;
        await context.read<InventoryProvider>().loadMedicines();

        if (!mounted) return;
        setState(() => _isSaving = false);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sale invoice updated successfully!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        Navigator.pop(context, true);
        return;
      }

      final invoice = await _posService.recordSale(
        pharmacyId: pharmacyId,
        customerId: _selectedCustomerId,
        customerName: _selectedCustomerName ?? 'Walking Customer',
        customerPhone: _selectedCustomerPhone,
        subtotal: _subtotal,
        discountType: _discountType == '%' ? 'percent' : 'fixed',
        discountAmount: _discountAmount,
        grandTotal: _todayBill,
        paidAmount: paying,
        dueAmount: due,
        paymentMethod: _paymentMethod,
        notes: serializedNotes,
        items: itemsPayload,
      );

      if (!mounted) return;
      await context.read<InventoryProvider>().loadMedicines();

      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _cartList.clear();
        _discountValue = 0.0;
        _discountController.text = '0';
        _payingNowController.clear();
        _clearSelectedCustomer();
      });

      if (_currentDraftId != null) {
        await DraftService.deleteExportDraft(_currentDraftId!);
        _currentDraftId = null;
      }

      final invoiceNo = invoice['invoice_number'] ?? 'Sale';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sale #$invoiceNo recorded successfully! ✅'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingDraft = false);
        setState(() => _isSaving = false);
        _showMsg('Failed to record sale: $e');
      }
    }
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade600),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingDraft || _isLoadingInvoice) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: MediAppBar(title: _isLoadingInvoice ? 'Loading Invoice...' : 'Loading Draft...'),
        body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      endDrawer: const AppDrawer(),
      appBar: MediAppBar(
        title: _editingInvoiceId != null
            ? 'Edit Invoice'
            : (_currentDraftId != null ? 'Continue Draft' : 'Sales'),
        actions: [
          if (_cartList.isNotEmpty)
            TextButton.icon(
              onPressed: _isSavingDraft ? null : _saveDraft,
              icon: _isSavingDraft
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save_outlined, color: Colors.white, size: 17),
              label: Text(
                _isSavingDraft ? "Saving..." : "Save Draft",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Header extension matching authentic UI
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: (_editingInvoiceId != null || _currentDraftId != null)
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _editingInvoiceId != null ? Icons.edit : Icons.edit_note,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _editingInvoiceId != null
                                  ? "Editing Confirmed Invoice"
                                  : "Editing Draft",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : const SizedBox(height: 14),
          ),

          // 2. Scrollable Body
          Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Customer Search & Quick Add ---
                    PosCustomerSection(
                      searchController: _customerSearchController,
                      selectedCustomerId: _selectedCustomerId,
                      selectedCustomerName: _selectedCustomerName,
                      selectedCustomerPhone: _selectedCustomerPhone,
                      previousDue: _previousDue,
                      isSearchingCustomer: _isSearchingCustomer,
                      searchResults: _customerSearchResults,
                      onSearch: _searchCustomer,
                      onSelect: _selectCustomer,
                      onClear: _clearSelectedCustomer,
                      onCustomerAdded: () {
                        _searchCustomer('');
                      },
                    ),
                    const SizedBox(height: 14),

                    // --- Medicine Search Bar ---
                    _buildMedicineSearchBar(),

                    // --- Inline Quick-Add Card (Shown when a medicine is selected or editing cart item) ---
                    if (_selectedMedForAdd != null) ...[
                      const SizedBox(height: 12),
                      PosQuickAddCard(
                        medicine: _selectedMedForAdd!,
                        matchingGlobalMedicine: _selectedGlobalMedForAdd,
                        initialEntry: (_editingCartIndex != null && _editingCartIndex! < _cartList.length)
                            ? _cartList[_editingCartIndex!]
                            : null,
                        onCancel: () {
                          setState(() {
                            _selectedMedForAdd = null;
                            _selectedGlobalMedForAdd = null;
                            _editingCartIndex = null;
                          });
                        },
                        onConfirm: _confirmAddOrUpdateCartItem,
                      ),
                    ],

                    const SizedBox(height: 14),

                    // --- Cart Items Header & List ---
                    _buildCartSection(),
                    const SizedBox(height: 16),

                    // --- Summary & Payment Cards ---
                    if (_cartList.isNotEmpty) ...[
                      PosTotalsSummaryCard(
                        subtotal: _subtotal,
                        discountType: _discountType,
                        discountValue: _discountValue,
                        discountController: _discountController,
                        discountAmount: _discountAmount,
                        finalTotal: _finalTotal,
                        onDiscountTypeChanged: (type) {
                          setState(() {
                            _discountType = type;
                            _syncPayingNow();
                          });
                        },
                        onDiscountValueChanged: (val) {
                          setState(() {
                            _discountValue = val;
                            _syncPayingNow();
                          });
                        },
                        onChanged: () {
                          setState(() {
                            _syncPayingNow();
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      PosPaymentCard(
                        previousDue: _previousDue,
                        todayBill: _todayBill,
                        newDueAfterThis: _newDueAfterThis,
                        payingNowController: _payingNowController,
                        isSaving: _isSaving,
                        onPayFull: () {
                          setState(() {
                            final fullAmount = _previousDue > 0 ? (_previousDue + _todayBill) : _todayBill;
                            _payingNowController.text = fullAmount.toStringAsFixed(2);
                          });
                        },
                        onCompleteSale: _saveSale,
                        onChanged: () {
                          setState(() {});
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }


  Widget _buildMedicineSearchBar() {
    return CompositedTransformTarget(
      link: _medLayerLink,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.blue.shade200),
          boxShadow: [
            BoxShadow(color: AppColors.primary.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3)),
          ],
        ),
        child: TextField(
          controller: _medSearchController,
          onChanged: _searchMedicines,
          decoration: InputDecoration(
            hintText: 'Search medicine by brand, generic, or company...',
            hintStyle: TextStyle(fontSize: 13.5, color: Colors.grey.shade500),
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary, size: 22),
            suffixIcon: _medSearchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _medSearchController.clear();
                      _removeMedOverlay();
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
    );
  }

  // --- 4. Cart List Section ---
  Widget _buildCartSection() {
    if (_cartList.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            const Text(
              'Your cart is empty',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF334155)),
            ),
            const SizedBox(height: 4),
            Text(
              'Search and select a medicine from above to add to cart.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.shopping_cart_outlined, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Sales Cart (${_cartList.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            if (_cartList.isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    for (final item in _cartList) {
                      item.dispose();
                    }
                    _cartList.clear();
                    _selectedMedForAdd = null;
                    _selectedGlobalMedForAdd = null;
                    _editingCartIndex = null;
                    _syncPayingNow();
                  });
                },
                icon: const Icon(Icons.delete_sweep_outlined, size: 16, color: Colors.red),
                label: const Text('Clear Cart', style: TextStyle(color: Colors.red, fontSize: 12)),
              ),
          ],
        ),
        const Divider(),
        ..._cartList.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return PosCartItemCard(
            index: i + 1,
            item: item,
            isEditing: _editingCartIndex == i,
            onEdit: () => _startEditCartItem(i),
            onRemove: () {
              setState(() {
                if (_editingCartIndex == i) {
                  _editingCartIndex = null;
                  _selectedMedForAdd = null;
                  _selectedGlobalMedForAdd = null;
                } else if (_editingCartIndex != null && _editingCartIndex! > i) {
                  _editingCartIndex = _editingCartIndex! - 1;
                }
                _cartList[i].dispose();
                _cartList.removeAt(i);
                _syncPayingNow();
              });
            },
          );
        }),
      ],
    );
  }




  // ─── Load Existing Invoice (Edit Mode) ──────────────────────────────────

  Future<void> _loadExistingInvoice(String invoiceId) async {
    setState(() => _isLoadingInvoice = true);
    try {
      final inv = await _posService.fetchInvoiceById(invoiceId);
      if (inv == null) {
        setState(() => _isLoadingInvoice = false);
        _showMsg('Invoice not found');
        return;
      }

      final double oldDue = (inv['due_amount'] as num?)?.toDouble() ?? 0.0;
      final custId = inv['customer_id'] as String?;
      final custName = inv['customer_name'] as String?;
      final custPhone = inv['customer_phone'] as String?;
      if (custId != null && custId.isNotEmpty) {
        _selectedCustomerId = custId;
        _selectedCustomerName = custName;
        _selectedCustomerPhone = custPhone;
        _customerSearchController.text = custName ?? '';
        await _fetchCustomerDue(custId, excludeOldDue: oldDue);
      } else if (custName != null && custName.isNotEmpty) {
        _selectedCustomerName = custName;
        _selectedCustomerPhone = custPhone;
        _customerSearchController.text = custName;
      }

      final String rawNotes = inv['notes']?.toString() ?? '';
      String userNotes = rawNotes;
      List<dynamic>? savedDetails;
      String? savedDiscountType;
      double? savedDiscountValue;
      if (rawNotes.startsWith('{') && rawNotes.endsWith('}')) {
        try {
          final decoded = jsonDecode(rawNotes);
          if (decoded is Map<String, dynamic>) {
            userNotes = decoded['user_notes']?.toString() ?? '';
            savedDetails = decoded['items_detail'] as List<dynamic>?;
            savedDiscountType = decoded['discount_type']?.toString();
            savedDiscountValue = (decoded['discount_value'] as num?)?.toDouble() ??
                (decoded['discount_percent'] as num?)?.toDouble();
          }
        } catch (_) {}
      }

      if (!mounted) return;
      final items = (inv['invoice_items'] as List?) ?? [];
      final allMeds = context.read<InventoryProvider>().medicines;
      final List<ExportCartItem> loadedCart = [];
      _oldInvoiceItemQuantities.clear();

      for (var rawItem in items) {
        final itemMap = Map<String, dynamic>.from(rawItem as Map);
        final medId = itemMap['medicine_id']?.toString() ?? '';
        final int oldQty = (itemMap['quantity'] as num?)?.toInt() ?? 0;
        if (medId.isNotEmpty) {
          _oldInvoiceItemQuantities[medId] = (_oldInvoiceItemQuantities[medId] ?? 0) + oldQty;
        }
        MedicineModel? med;
        if (allMeds.isNotEmpty) {
          try {
            med = allMeds.firstWhere((m) => m.id == medId);
          } catch (_) {}
        }

        if (med == null) {
          final medName = itemMap['medicine_name']?.toString() ?? 'Medicine';
          med = MedicineModel(
            id: medId,
            pharmacyId: inv['pharmacy_id']?.toString() ?? '',
            brandName: medName,
            genericName: '',
            dosageForm: 'Tablet',
            strength: '',
            weight: '',
            piecesPerStrip: 10,
            stripsPerBox: 10,
          );
        }

        final batchNo = itemMap['batch_number']?.toString();
        BatchModel? matchedBatch;
        if (batchNo != null && batchNo.isNotEmpty) {
          try {
            matchedBatch = med.batches.firstWhere((b) => b.batchNumber == batchNo);
          } catch (_) {}
        }
        matchedBatch ??= med.primaryActiveBatch;

        // Check if saved items_detail exists from invoice notes
        Map<String, dynamic>? matchingDetail;
        if (savedDetails != null && savedDetails.isNotEmpty) {
          for (final d in savedDetails) {
            if (d is Map &&
                d['medicine_id']?.toString() == medId &&
                (batchNo == null || batchNo.isEmpty || d['batch_number']?.toString() == batchNo)) {
              matchingDetail = Map<String, dynamic>.from(d);
              break;
            }
          }
        }

        if (matchingDetail != null) {
          final int rawQty = (matchingDetail['raw_quantity'] as num?)?.toInt() ?? 1;
          final String uType = matchingDetail['unit_type']?.toString() ?? 'Unit';
          final double uPrice = (matchingDetail['unit_selling_price'] as num?)?.toDouble() ??
              (matchingDetail['single_unit_mrp'] as num?)?.toDouble() ??
              0.0;
          final double discPct = (matchingDetail['discount_percent'] as num?)?.toDouble() ?? 0.0;
          final String discM = matchingDetail['discount_mode']?.toString() ?? '%';
          final double itemMrp = (matchingDetail['single_unit_mrp'] as num?)?.toDouble() ??
              (itemMap['mrp'] as num?)?.toDouble() ??
              (matchedBatch?.mrp ?? 0.0);
          final double itemCost = (matchingDetail['single_unit_cost'] as num?)?.toDouble() ??
              (itemMap['purchase_price'] as num?)?.toDouble() ??
              (matchedBatch?.purchasePrice ?? 0.0);
          final int pps = (matchingDetail['pieces_per_strip'] as num?)?.toInt() ?? (med.piecesPerStrip ?? 1);
          final int spb = (matchingDetail['strips_per_box'] as num?)?.toInt() ?? (med.stripsPerBox ?? 1);

          loadedCart.add(
            ExportCartItem(
              medicine: med,
              batch: matchedBatch,
              quantity: rawQty,
              unitType: uType,
              singleUnitMrp: itemMrp,
              singleUnitCost: itemCost,
              unitSellingPrice: uPrice,
              discountPercent: discPct,
              discountMode: discM,
              piecesPerStrip: pps,
              stripsPerBox: spb,
            ),
          );
        } else {
          final packInfo = MedicinePackagingHelper.getPackagingInfo(med: med);
          final int? ppsNullable = packInfo['pps'];
          final int? spbNullable = packInfo['spb'];
          final int pps = ppsNullable ?? 0;
          final int spb = spbNullable ?? 0;
          final bool hasTwoTier = pps > 0 && spb > 0;
          final int boxSize = hasTwoTier ? (spb * pps) : (pps > 1 ? pps : (spb > 1 ? spb : 1));

          final int totalUnits = (itemMap['quantity'] as num?)?.toInt() ?? 1;
          final double singleUnitPrice = (itemMap['unit_price'] as num?)?.toDouble() ?? 0.0;
          final double singleUnitCost = (itemMap['purchase_price'] as num?)?.toDouble() ?? 0.0;
          final double singleUnitMrp = (itemMap['mrp'] as num?)?.toDouble() ?? singleUnitPrice;

          String unitType = 'Unit';
          int displayQty = totalUnits;
          double displaySellingPrice = singleUnitPrice;

          if (boxSize > 1 && totalUnits % boxSize == 0) {
            unitType = 'Box';
            displayQty = totalUnits ~/ boxSize;
            displaySellingPrice = singleUnitPrice * boxSize;
          } else if (hasTwoTier && pps > 1 && totalUnits % pps == 0) {
            unitType = 'Strip';
            displayQty = totalUnits ~/ pps;
            displaySellingPrice = singleUnitPrice * pps;
          }

          loadedCart.add(
            ExportCartItem(
              medicine: med,
              batch: matchedBatch,
              quantity: displayQty,
              unitType: unitType,
              singleUnitMrp: singleUnitMrp,
              singleUnitCost: singleUnitCost,
              unitSellingPrice: displaySellingPrice,
              piecesPerStrip: pps,
              stripsPerBox: spb,
            ),
          );
        }
      }

      final double discAmt = (inv['discount_amount'] as num?)?.toDouble() ?? 0.0;
      final double paidAmt = (inv['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final double oldGrandTotal = (inv['grand_total'] as num?)?.toDouble() ?? 0.0;

      _isEditingPartialPayment = (paidAmt < oldGrandTotal - 0.01);

      setState(() {
        _cartList.clear();
        _cartList.addAll(loadedCart);
        _discountType = savedDiscountType ?? (inv['discount_type'] == 'percent' ? '%' : 'Cash');
        _discountValue = savedDiscountValue ?? discAmt;
        _discountController.text = _discountValue > 0
            ? (_discountValue.truncateToDouble() == _discountValue
                ? _discountValue.toStringAsFixed(0)
                : _discountValue.toStringAsFixed(2))
            : '0';
        _payingNowController.text = paidAmt > 0 ? paidAmt.toStringAsFixed(2) : '';
        _notesCtrl.text = userNotes;
        _isLoadingInvoice = false;
      });
    } catch (e) {
      setState(() => _isLoadingInvoice = false);
      _showMsg('Failed to load invoice: $e');
    }
  }

  Future<void> _loadDraft() async {
    if (_currentDraftId == null) return;
    setState(() => _isLoadingDraft = true);
    try {
      final draft = await DraftService.getExportDraft(_currentDraftId!);
      if (draft == null) return;

      final custId = draft['customer_id'] as String?;
      final custName = draft['customer_name'] as String? ?? draft['customer']?['customer_name'] as String?;
      final custPhone = draft['customer_phone'] as String? ?? draft['customer']?['phone'] as String?;

      if (custId != null) {
        setState(() {
          _selectedCustomerId = custId;
          _selectedCustomerName = custName;
          _selectedCustomerPhone = custPhone;
          _customerSearchController.text = custName ?? '';
        });
        await _fetchCustomerDue(custId);
      } else if (custName != null && custName.isNotEmpty) {
        setState(() {
          _selectedCustomerName = custName;
          _selectedCustomerPhone = custPhone;
          _customerSearchController.text = custName;
        });
      }

      if (!mounted) return;
      final items = draft['items'] as List? ?? [];
      final List<ExportCartItem> restoredCart = [];
      final allMeds = context.read<InventoryProvider>().medicines;

      for (final rawItem in items) {
        final itemMap = Map<String, dynamic>.from(rawItem as Map);
        MedicineModel? med;
        final medId = itemMap['medicine_id']?.toString();
        if (medId != null && allMeds.isNotEmpty) {
          try {
            med = allMeds.firstWhere((m) => m.id == medId);
          } catch (_) {}
        }
        if (med == null && itemMap['medicine_data'] != null) {
          try {
            med = MedicineModel.fromJson(Map<String, dynamic>.from(itemMap['medicine_data'] as Map));
          } catch (_) {}
        }
        if (med == null) continue;

        BatchModel? batch;
        if (itemMap['batch_data'] != null) {
          try {
            batch = BatchModel.fromJson(Map<String, dynamic>.from(itemMap['batch_data'] as Map));
          } catch (_) {}
        } else {
          batch = med.primaryActiveBatch;
        }

        final int qty = (itemMap['quantity'] as num?)?.toInt() ?? 1;
        final String unitType = itemMap['unit_type']?.toString() ?? 'Unit';
        final double singleUnitMrp = (itemMap['single_unit_mrp'] as num?)?.toDouble() ?? (batch?.mrp ?? 0.0);
        final double singleUnitCost = (itemMap['single_unit_cost'] as num?)?.toDouble() ?? (batch?.purchasePrice ?? 0.0);
        final double unitSellingPrice = (itemMap['unit_selling_price'] as num?)?.toDouble() ?? (batch?.sellingPrice ?? singleUnitMrp);
        final int piecesPerStrip = (itemMap['pieces_per_strip'] as num?)?.toInt() ?? (med.piecesPerStrip ?? 1);
        final int stripsPerBox = (itemMap['strips_per_box'] as num?)?.toInt() ?? (med.stripsPerBox ?? 1);

        restoredCart.add(
          ExportCartItem(
            medicine: med,
            batch: batch,
            quantity: qty,
            unitType: unitType,
            singleUnitMrp: singleUnitMrp,
            singleUnitCost: singleUnitCost,
            unitSellingPrice: unitSellingPrice,
            piecesPerStrip: piecesPerStrip,
            stripsPerBox: stripsPerBox,
          ),
        );
      }

      final discountType = draft['discount_type']?.toString() ?? '%';
      final discountVal = (draft['discount_value'] as num?)?.toDouble() ?? 0.0;

      setState(() {
        _cartList.clear();
        _cartList.addAll(restoredCart);
        _discountType = discountType;
        _discountValue = discountVal;
        _discountController.text = discountVal > 0
            ? (discountVal.truncateToDouble() == discountVal ? discountVal.toStringAsFixed(0) : discountVal.toStringAsFixed(2))
            : '0';
        _isLoadingDraft = false;
      });

      _syncPayingNow();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingDraft = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load draft: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveDraft() async {
    if (_cartList.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add medicines before saving a draft.'),
          backgroundColor: Colors.black,
        ),
      );
      return;
    }

    String? draftName = await _askDraftName();
    if (draftName == null) return;

    setState(() => _isSavingDraft = true);
    try {
      final items = _cartList.map((item) {
        return {
          'medicine_id': item.medicine.id,
          'medicine_data': item.medicine.toJson(),
          'batch_id': item.batch?.id,
          'batch_data': item.batch?.toJson(),
          'quantity': item.quantity,
          'unit_type': item.unitType,
          'single_unit_mrp': item.singleUnitMrp,
          'single_unit_cost': item.singleUnitCost,
          'unit_selling_price': item.unitSellingPrice,
          'pieces_per_strip': item.piecesPerStrip,
          'strips_per_box': item.stripsPerBox,
        };
      }).toList();

      final id = await DraftService.saveExportDraft(
        draftId: _currentDraftId,
        draftName: draftName,
        customerId: _selectedCustomerId,
        customerName: _selectedCustomerName,
        customerPhone: _selectedCustomerPhone,
        discountType: _discountType,
        discountValue: _discountValue,
        items: items,
      );

      setState(() {
        _currentDraftId = id;
        _isSavingDraft = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Draft saved!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isSavingDraft = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save draft failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<String?> _askDraftName() async {
    final ctrl = TextEditingController(
      text: _selectedCustomerName != null && _selectedCustomerName!.isNotEmpty
          ? '$_selectedCustomerName - Order'
          : '',
    );
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Save Draft", style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "Draft name (e.g. John – June order)",
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final name = ctrl.text.trim();
              Navigator.pop(context, name.isEmpty ? "Draft" : name);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

}