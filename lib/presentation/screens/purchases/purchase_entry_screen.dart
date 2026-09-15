import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/utils/medicine_packaging_helper.dart';
import '../../providers/auth_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../../data/models/medicine_model.dart';
import '../../../data/models/batch_model.dart';
import '../../../data/models/purchase_model.dart';
import '../../../data/services/purchase_service.dart';
import '../../../data/services/draft_service.dart';
import '../../../data/services/supabase_service.dart';

import '../../../data/models/purchase_cart_item.dart';
import '../../widgets/purchases/purchase_supplier_section.dart';
import '../../widgets/purchases/purchase_quick_add_card.dart';
import '../../widgets/purchases/purchase_cart_item_card.dart';
import '../../widgets/purchases/purchase_totals_summary_card.dart';
import '../../widgets/purchases/purchase_payment_card.dart';
import '../../widgets/common/medi_app_bar.dart';
import '../../widgets/app_drawer.dart';

class PurchaseEntryScreen extends StatefulWidget {
  final String? draftId;
  final String? purchaseId;
  final MedicineModel? initialMedicine;
  const PurchaseEntryScreen({super.key, this.draftId, this.purchaseId, this.initialMedicine});

  @override
  State<PurchaseEntryScreen> createState() => _PurchaseEntryScreenState();
}

class _PurchaseEntryScreenState extends State<PurchaseEntryScreen> {
  final _purchaseService = PurchaseService();
  String? _currentDraftId;
  String? _editingPurchaseId;
  bool _isEditingPartialPayment = false;
  bool _isLoadingDraft = false;
  bool _isLoadingPurchase = false;
  bool _isSavingDraft = false;
  final _client = SupabaseService.instance.client;

  // Supplier state
  final _supplierSearchController = TextEditingController();
  List<Map<String, dynamic>> _supplierSearchResults = [];
  bool _isSearchingSupplier = false;
  String? _selectedSupplierId;
  String? _selectedSupplierName;
  double _previousDue = 0.0;
  bool _isFetchingDue = false;

  // Medicine Search & Overlay
  final _medSearchController = TextEditingController();
  final _medLayerLink = LayerLink();
  OverlayEntry? _medOverlay;
  List<Map<String, dynamic>> _globalMedicines = [];
  List<Map<String, dynamic>> _medicineSearchResults = [];

  // Selected Medicine for Quick-Add (inline below search bar)
  Map<String, dynamic>? _selectedMedForAdd;
  int? _editingCartIndex;

  List<String> get _availableRacks {
    final inventory = context.read<InventoryProvider>();
    final racks = <String>{};
    for (var m in inventory.medicines) {
      if (m.rackLocation != null && m.rackLocation!.trim().isNotEmpty) {
        racks.add(m.rackLocation!.trim());
      }
    }
    for (var c in _cartList) {
      if (c.rackLocation != null && c.rackLocation!.trim().isNotEmpty) {
        racks.add(c.rackLocation!.trim());
      }
    }
    final sorted = racks.toList()..sort();
    return sorted;
  }

  // Cart List
  final List<CartItemEntry> _cartList = [];

  // Discount & Payment
  String _discountType = '%'; // '%' or 'Cash'
  double _discountValue = 0.0;
  final _discountController = TextEditingController(text: '0');
  final _payingNowController = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<InventoryProvider>().loadMedicines();
      await _fetchGlobalMedicines();
      if (widget.purchaseId != null) {
        _editingPurchaseId = widget.purchaseId;
        _loadExistingPurchase(_editingPurchaseId!);
      } else if (widget.draftId != null) {
        _currentDraftId = widget.draftId;
        _loadDraft();
      } else if (widget.initialMedicine != null) {
        _openInitialMedicine(widget.initialMedicine!);
      }
    });
  }

  @override
  void dispose() {
    _removeMedOverlay();
    _supplierSearchController.dispose();
    _medSearchController.dispose();
    _discountController.dispose();
    _payingNowController.dispose();
    _notesCtrl.dispose();
    for (final item in _cartList) {
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
    if (_editingPurchaseId != null && _isEditingPartialPayment) {
      return;
    }
    setState(() {
      _payingNowController.text = _todayBill.toStringAsFixed(2);
    });
  }

  // --- Supplier Search ---
  Future<void> _searchSupplier(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _supplierSearchResults = []);
      return;
    }

    setState(() => _isSearchingSupplier = true);
    try {
      final supplierData = await _client
          .from(SupabaseConstants.suppliersTable)
          .select('id, name, current_due, phone')
          .ilike('name', '%$q%')
          .limit(6);

      final List<Map<String, dynamic>> combined = [];
      final Set<String> seenNames = {};

      for (final s in supplierData as List) {
        final name = (s['name'] ?? '').toString().trim();
        seenNames.add(name.toLowerCase());
        combined.add({
          'id': s['id'],
          'name': name,
          'current_due': (s['current_due'] as num?)?.toDouble() ?? 0.0,
          'phone': s['phone'],
        });
      }

      // Also match companies from global catalog
      for (final gm in _globalMedicines) {
        final comp = (gm['company'] ?? '').toString().trim();
        if (comp.isNotEmpty &&
            comp.toLowerCase().contains(q) &&
            !seenNames.contains(comp.toLowerCase())) {
          seenNames.add(comp.toLowerCase());
          combined.add({
            'id': null,
            'name': comp,
            'current_due': 0.0,
          });
          if (combined.length >= 10) break;
        }
      }

      if (mounted) {
        setState(() {
          _supplierSearchResults = combined;
          _isSearchingSupplier = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSearchingSupplier = false);
    }
  }

  void _selectSupplier(Map<String, dynamic> supplier) async {
    final sId = supplier['id'] as String?;
    final sName = supplier['name'] as String;

    setState(() {
      _selectedSupplierId = sId;
      _selectedSupplierName = sName;
      _previousDue = (supplier['current_due'] as num?)?.toDouble() ?? 0.0;
      _supplierSearchController.clear();
      _supplierSearchResults = [];
    });

    if (sId != null) {
      _fetchSupplierDue(sId);
    }
    _syncPayingNow();
  }

  Future<void> _fetchSupplierDue(String supplierId, {double excludeOldDue = 0.0}) async {
    setState(() => _isFetchingDue = true);
    try {
      final res = await _client
          .from(SupabaseConstants.suppliersTable)
          .select('current_due')
          .eq('id', supplierId)
          .maybeSingle();

      if (mounted && res != null) {
        setState(() {
          final rawDue = (res['current_due'] as num?)?.toDouble() ?? 0.0;
          _previousDue = (rawDue - excludeOldDue).clamp(0.0, double.infinity);
          _isFetchingDue = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isFetchingDue = false);
    }
  }

  void _clearSelectedSupplier() {
    setState(() {
      _selectedSupplierId = null;
      _selectedSupplierName = null;
      _previousDue = 0.0;
      _supplierSearchController.clear();
      _supplierSearchResults = [];
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
              constraints: const BoxConstraints(maxHeight: 280),
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
                  final item = _medicineSearchResults[idx];
                  final int stock = item['stock'] ?? 0;
                  final double mrp = (item['mrp'] as num?)?.toDouble() ?? 0.0;

                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            item['brand_name'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF1E293B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (item['dosage_form'] != null && item['dosage_form'].toString().isNotEmpty) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              item['dosage_form'],
                              style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                        if (item['strength'] != null && item['strength'].toString().isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            item['strength'],
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                          ),
                        ],
                        if (item['weight'] != null && item['weight'].toString().isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            item['weight'],
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Row(
                      children: [
                        Text(
                          'MRP: ৳${mrp.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF2563EB)),
                        ),
                        const SizedBox(width: 8),
                        Text('â€¢', style: TextStyle(color: Colors.grey.shade400)),
                        const SizedBox(width: 8),
                        Text(
                          'Stock: $stock ${item['unit']}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: stock > 0 ? const Color(0xFF10B981) : Colors.red.shade600,
                          ),
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
                        'Select',
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                    onTap: () {
                      _selectMedicineForQuickAdd(item);
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

    // Support multi-word search like 'fexo syr', 'fexo 120', 'napa 500'
    final queryTokens = rawQ.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    final inventory = context.read<InventoryProvider>();
    final List<Map<String, dynamic>> results = [];
    final Set<String> matchedKeys = {};

    String makeKey(String brand, String dosage, String? strength, String? weight) {
      return '${brand.trim().toLowerCase()}|${dosage.trim().toLowerCase()}|${(strength ?? '').trim().toLowerCase()}|${(weight ?? '').trim().toLowerCase()}';
    }

    bool matchesQuery(String brand, String? generic, String dosage, String? strength, String? weight) {
      final text = '$brand ${generic ?? ''} $dosage ${strength ?? ''} ${weight ?? ''}'.toLowerCase();
      return queryTokens.every((token) => text.contains(token));
    }

    // 1. Match from current pharmacy stock
    for (final m in inventory.medicines) {
      if (matchesQuery(m.brandName, m.genericName, m.dosageForm, m.strength, m.weight)) {
        final key = makeKey(m.brandName, m.dosageForm, m.strength, m.weight);
        matchedKeys.add(key);

        // Check global medicine for official packaging & MRP
        final gm = _globalMedicines.firstWhere(
          (g) {
            final gBrand = (g['brand_name'] ?? '').toString().trim().toLowerCase();
            final gDosage = (g['dosage_form'] ?? '').toString().trim().toLowerCase();
            final gStrength = (g['strength'] ?? '').toString().trim().toLowerCase();
            return gBrand == m.brandName.trim().toLowerCase() &&
                (gDosage.isEmpty || m.dosageForm.isEmpty || gDosage == m.dosageForm.trim().toLowerCase()) &&
                (gStrength.isEmpty || (m.strength ?? '').isEmpty || gStrength == (m.strength ?? '').trim().toLowerCase());
          },
          orElse: () => _globalMedicines.firstWhere(
            (g) => (g['brand_name'] ?? '').toString().trim().toLowerCase() == m.brandName.trim().toLowerCase(),
            orElse: () => {},
          ),
        );
        final packInfo = MedicinePackagingHelper.getPackagingInfo(med: m, matchingGlobalMedicine: gm);
        final int? gmPps = packInfo['pps'];
        final int? gmSpb = packInfo['spb'];
        final double libMrp = packInfo['libraryMrp'] ?? 0.0;

        final active = m.primaryActiveBatch;
        final double effectiveMrp = libMrp > 0 ? libMrp : (active?.mrp ?? 0.0);
        double buyRate = 0.0;
        if (m.batches.isNotEmpty) {
          final sortedBatches = List<BatchModel>.from(m.batches)
            ..sort((a, b) => b.expiryDate.compareTo(a.expiryDate));
          buyRate = sortedBatches.first.purchasePrice;
        }
        if (buyRate <= 0.0) {
          buyRate = active?.purchasePrice ?? 0.0;
        }

        results.add({
          'is_local': true,
          'medicine_model': m,
          'brand_name': m.brandName,
          'generic_name': m.genericName,
          'dosage_form': m.dosageForm,
          'strength': m.strength,
          'weight': m.weight ?? gm['weight'],
          'stock': m.totalStock,
          'unit': m.unit,
          'pieces_per_strip': gmPps,
          'strips_per_box': gmSpb,
          'purchase_price': buyRate,
          'mrp': effectiveMrp,
        });
        if (results.length >= 12) break;
      }
    }

    // 2. Match from global catalog
    for (final gm in _globalMedicines) {
      if (gm['is_available'] == false) continue;
      final bName = (gm['brand_name'] ?? '').toString().trim();
      final gName = (gm['generic_name'] ?? '').toString().trim();
      final dForm = (gm['dosage_form'] ?? '').toString().trim();
      final str = (gm['strength'] ?? '').toString().trim();
      final wt = (gm['weight'] ?? '').toString().trim();

      final key = makeKey(bName, dForm, str, wt);
      if (!matchedKeys.contains(key) && matchesQuery(bName, gName, dForm, str, wt)) {
        matchedKeys.add(key);
        final defaultMrp = double.tryParse(gm['default_mrp']?.toString() ?? '0') ?? 0.0;
        final dummyMed = MedicineModel(
          id: 'global_${gm['id']}',
          pharmacyId: '',
          globalId: gm['id'],
          brandName: bName,
          genericName: gm['generic_name'],
          dosageForm: dForm,
          strength: str.isNotEmpty ? str : null,
          company: gm['company'],
          unit: gm['default_unit'] ?? 'Piece',
          minStockAlert: 10,
          batches: const [],
          piecesPerStrip: null,
          stripsPerBox: null,
          weight: wt.isNotEmpty ? wt : null,
        );
        final packInfo = MedicinePackagingHelper.getPackagingInfo(med: dummyMed, matchingGlobalMedicine: gm);
        final int? pps = packInfo['pps'];
        final int? spb = packInfo['spb'];
        final String? effectiveWt = packInfo['weight'] ?? (wt.isNotEmpty ? wt : null);

        final medModel = MedicineModel(
          id: 'global_${gm['id']}',
          pharmacyId: '',
          globalId: gm['id'],
          brandName: bName,
          genericName: gm['generic_name'],
          dosageForm: dForm,
          strength: str.isNotEmpty ? str : null,
          company: gm['company'],
          unit: gm['default_unit'] ?? 'Piece',
          minStockAlert: 10,
          batches: const [],
          piecesPerStrip: pps,
          stripsPerBox: spb,
          weight: effectiveWt,
        );

        results.add({
          'is_local': false,
          'medicine_model': medModel,
          'brand_name': bName,
          'generic_name': gm['generic_name'],
          'dosage_form': dForm,
          'strength': str.isNotEmpty ? str : null,
          'weight': wt.isNotEmpty ? wt : null,
          'stock': 0,
          'unit': gm['default_unit'] ?? 'Pcs',
          'pieces_per_strip': pps,
          'strips_per_box': spb,
          'purchase_price': 0.0,
          'mrp': defaultMrp,
        });
        if (results.length >= 14) break;
      }
    }

    setState(() {
      _medicineSearchResults = results;
    });

    _showMedOverlay();
  }
  void _openInitialMedicine(MedicineModel med) {
    final gm = _globalMedicines.firstWhere(
      (g) {
        final gBrand = (g['brand_name'] ?? '').toString().trim().toLowerCase();
        final gDosage = (g['dosage_form'] ?? '').toString().trim().toLowerCase();
        final gStrength = (g['strength'] ?? '').toString().trim().toLowerCase();
        return gBrand == med.brandName.trim().toLowerCase() &&
            (gDosage.isEmpty || med.dosageForm.isEmpty || gDosage == med.dosageForm.trim().toLowerCase()) &&
            (gStrength.isEmpty || (med.strength ?? '').isEmpty || gStrength == (med.strength ?? '').trim().toLowerCase());
      },
      orElse: () => _globalMedicines.firstWhere(
        (g) => (g['brand_name'] ?? '').toString().trim().toLowerCase() == med.brandName.trim().toLowerCase(),
        orElse: () => {},
      ),
    );

    final packInfo = MedicinePackagingHelper.getPackagingInfo(med: med, matchingGlobalMedicine: gm);
    final int? pps = packInfo['pps'];
    final int? spb = packInfo['spb'];
    final double libMrp = double.tryParse(gm['default_mrp']?.toString() ?? '0') ?? 0.0;
    final active = med.primaryActiveBatch;
    final double effectiveMrp = libMrp > 0 ? libMrp : (active?.mrp ?? 0.0);
    double buyRate = 0.0;
    if (med.batches.isNotEmpty) {
      final sorted = List<BatchModel>.from(med.batches)
        ..sort((a, b) => b.expiryDate.compareTo(a.expiryDate));
      buyRate = sorted.first.purchasePrice;
    }
    if (buyRate <= 0.0) {
      buyRate = active?.purchasePrice ?? 0.0;
    }

    final item = {
      'is_local': true,
      'medicine_model': med,
      'brand_name': med.brandName,
      'generic_name': med.genericName,
      'dosage_form': med.dosageForm,
      'strength': med.strength,
      'weight': med.weight ?? gm['weight'],
      'stock': med.totalStock,
      'unit': med.unit,
      'pieces_per_strip': pps,
      'strips_per_box': spb,
      'purchase_price': buyRate,
      'mrp': effectiveMrp,
    };

    _selectMedicineForQuickAdd(item);
  }

  void _selectMedicineForQuickAdd(Map<String, dynamic> item) async {
    _removeMedOverlay();
    setState(() {
      _selectedMedForAdd = item;
      _editingCartIndex = null;
      _medSearchController.clear();
      _medicineSearchResults = [];
    });
  }

  void _startEditCartItem(int index) {
    _removeMedOverlay();
    final cartItem = _cartList[index];
    final med = cartItem.medicine;
    final itemMap = {
      'is_local': true,
      'medicine_model': med,
      'brand_name': med.brandName,
      'generic_name': med.genericName,
      'dosage_form': med.dosageForm,
      'strength': med.strength,
      'weight': med.weight,
      'stock': med.totalStock,
      'unit': med.unit,
      'pieces_per_strip': cartItem.piecesPerStrip,
      'strips_per_box': cartItem.stripsPerBox,
      'purchase_price': cartItem.unitPurchasePrice,
      'mrp': cartItem.mrp,
      'rack': cartItem.rackLocation,
    };

    setState(() {
      _editingCartIndex = index;
      _selectedMedForAdd = itemMap;
    });
  }

  void _confirmAddOrUpdateCartItem(CartItemEntry entry) {
    setState(() {
      if (_editingCartIndex != null && _editingCartIndex! < _cartList.length) {
        // Update existing item in place
        _cartList[_editingCartIndex!].dispose();
        _cartList[_editingCartIndex!] = entry;
        _editingCartIndex = null;
      } else {
        // Check if an item with identical medicine, dosage, strength, weight, batch already exists
        final existingIndex = _cartList.indexWhere(
          (c) =>
              c.medicine.brandName.trim().toLowerCase() == entry.medicine.brandName.trim().toLowerCase() &&
              c.medicine.dosageForm.trim().toLowerCase() == entry.medicine.dosageForm.trim().toLowerCase() &&
              (c.medicine.strength ?? '').trim().toLowerCase() == (entry.medicine.strength ?? '').trim().toLowerCase() &&
              (c.medicine.weight ?? '').trim().toLowerCase() == (entry.medicine.weight ?? '').trim().toLowerCase() &&
              c.batchNumber.trim().toLowerCase() == entry.batchNumber.trim().toLowerCase() &&
              c.unitType == entry.unitType &&
              c.bonusUnitType == entry.bonusUnitType,
        );

        if (existingIndex >= 0) {
          _cartList[existingIndex].quantity += entry.quantity;
          _cartList[existingIndex].bonusQuantity += entry.bonusQuantity;
          _cartList[existingIndex].qtyController.text = _cartList[existingIndex].quantity.toString();
        } else {
          _cartList.add(entry);
        }
      }

      // Reset inline quick add state
      _selectedMedForAdd = null;
      _editingCartIndex = null;
      _syncPayingNow();
    });
  }

  // â”€â”€â”€ Draft Management â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€


  // â”€â”€â”€ Load Existing Purchase (Edit Mode) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _loadExistingPurchase(String purchaseId) async {
    setState(() => _isLoadingPurchase = true);
    try {
      final purchase = await _purchaseService.fetchPurchaseById(purchaseId);
      if (purchase == null) {
        setState(() => _isLoadingPurchase = false);
        _showMsg('Purchase not found');
        return;
      }

      final double oldDue = (purchase['due_amount'] as num?)?.toDouble() ?? 0.0;
      final suppId = purchase['supplier_id'] as String?;
      final suppName = purchase['supplier_name'] as String?;
      if (suppId != null && suppId.isNotEmpty) {
        _selectedSupplierId = suppId;
        _selectedSupplierName = suppName;
        _supplierSearchController.text = suppName ?? '';
        await _fetchSupplierDue(suppId, excludeOldDue: oldDue);
      } else if (suppName != null && suppName.isNotEmpty) {
        _selectedSupplierName = suppName;
        _supplierSearchController.text = suppName;
      }

      if (!mounted) return;
      final items = (purchase['purchase_items'] as List?) ?? [];
      final allMeds = context.read<InventoryProvider>().medicines;
      final List<CartItemEntry> loadedCart = [];

      final String rawNotes = purchase['notes']?.toString() ?? '';
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

      for (var rawItem in items) {
        final itemMap = Map<String, dynamic>.from(rawItem as Map);
        final medId = itemMap['medicine_id']?.toString() ?? '';
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
            pharmacyId: purchase['pharmacy_id']?.toString() ?? '',
            brandName: medName,
            genericName: '',
            dosageForm: 'Tablet',
            strength: '',
            weight: '',
            piecesPerStrip: 10,
            stripsPerBox: 10,
          );
        }

        final packInfo = MedicinePackagingHelper.getPackagingInfo(med: med);
        final int? pps = packInfo['pps'];
        final int? spb = packInfo['spb'];
        final bool hasTwoTier = pps != null && pps > 0 && spb != null && spb > 0;
        final int boxSize = hasTwoTier ? (spb * pps) : (pps != null && pps > 1 ? pps : (spb != null && spb > 1 ? spb : 1));

        final int totalUnits = (itemMap['quantity'] as num?)?.toInt() ?? 1;
        final double singleUnitPrice = (itemMap['purchase_price'] as num?)?.toDouble() ?? 0.0;

        String unitType = 'Unit';
        int displayQty = totalUnits;
        double displayUnitPrice = singleUnitPrice;

        if (boxSize > 1 && totalUnits % boxSize == 0) {
          unitType = 'Box';
          displayQty = totalUnits ~/ boxSize;
          displayUnitPrice = singleUnitPrice * boxSize;
        } else if (hasTwoTier && pps > 1 && totalUnits % pps == 0) {
          unitType = 'Strip';
          displayQty = totalUnits ~/ pps;
          displayUnitPrice = singleUnitPrice * pps;
        }

        final batchNo = itemMap['batch_number']?.toString() ?? 'BATCH-01';
        final expDate = DateTime.tryParse(itemMap['expiry_date']?.toString() ?? '') ?? DateTime.now().add(const Duration(days: 365));

        // Check if saved items_detail exists from purchase notes
        Map<String, dynamic>? matchingDetail;
        if (savedDetails != null && savedDetails.isNotEmpty) {
          for (final d in savedDetails) {
            if (d is Map && d['medicine_id']?.toString() == medId && d['batch_number']?.toString() == batchNo) {
              matchingDetail = Map<String, dynamic>.from(d);
              break;
            }
          }
        }

        if (matchingDetail != null) {
          final int rawQty = (matchingDetail['raw_quantity'] as num?)?.toInt() ?? 1;
          final int bonusQty = (matchingDetail['bonus_quantity'] as num?)?.toInt() ?? 0;
          final String uType = matchingDetail['unit_type']?.toString() ?? 'Unit';
          final String bUnitType = matchingDetail['bonus_unit_type']?.toString() ?? uType;
          final double uPrice = (matchingDetail['unit_purchase_price'] as num?)?.toDouble() ?? displayUnitPrice;
          final double discPct = (matchingDetail['discount_percent'] as num?)?.toDouble() ?? 12.0;
          final String discM = matchingDetail['discount_mode']?.toString() ?? '%';
          final double itemMrp = (matchingDetail['mrp'] as num?)?.toDouble() ?? (itemMap['selling_price'] as num?)?.toDouble() ?? 0.0;
          final String? itemRack = matchingDetail['rack_location']?.toString() ?? med.rackLocation;

          loadedCart.add(
            CartItemEntry(
              medicine: med,
              batchNumber: batchNo,
              expiryDate: expDate,
              quantity: rawQty,
              bonusQuantity: bonusQty,
              unitType: uType,
              bonusUnitType: bUnitType,
              unitPurchasePrice: uPrice,
              mrp: itemMrp,
              discountPercent: discPct,
              discountMode: discM,
              piecesPerStrip: pps ?? 0,
              stripsPerBox: spb ?? 0,
              rackLocation: itemRack,
            ),
          );
          continue;
        }

        loadedCart.add(
          CartItemEntry(
            medicine: med,
            batchNumber: batchNo,
            expiryDate: expDate,
            quantity: displayQty,
            unitType: unitType,
            bonusUnitType: unitType,
            unitPurchasePrice: displayUnitPrice,
            mrp: (itemMap['selling_price'] as num?)?.toDouble() ?? 0.0,
            piecesPerStrip: pps ?? 0,
            stripsPerBox: spb ?? 0,
          ),
        );
      }

      final double discAmt = (purchase['discount_amount'] as num?)?.toDouble() ?? 0.0;
      final double paidAmt = (purchase['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final double oldGrandTotal = (purchase['grand_total'] as num?)?.toDouble() ?? 0.0;
      final double oldSubtotal = (purchase['total_amount'] as num?)?.toDouble() ?? (oldGrandTotal + discAmt);

      _isEditingPartialPayment = (paidAmt < oldGrandTotal - 0.01);

      String finalDiscType = savedDiscountType ?? '%';
      double finalDiscVal = savedDiscountValue ?? 0.0;
      if (savedDiscountType == null) {
        if (discAmt > 0 && oldSubtotal > 0) {
          final computedPct = (discAmt / oldSubtotal) * 100;
          if ((computedPct - computedPct.round()).abs() < 0.02 && computedPct.round() > 0) {
            finalDiscType = '%';
            finalDiscVal = computedPct.roundToDouble();
          } else {
            finalDiscType = 'Cash';
            finalDiscVal = discAmt;
          }
        } else {
          finalDiscType = '%';
          finalDiscVal = 0.0;
        }
      }

      setState(() {
        _cartList.clear();
        _cartList.addAll(loadedCart);
        _discountType = finalDiscType;
        _discountValue = finalDiscVal;
        _discountController.text = finalDiscVal > 0
            ? (finalDiscVal.truncateToDouble() == finalDiscVal ? finalDiscVal.toStringAsFixed(0) : finalDiscVal.toStringAsFixed(2))
            : '0';
        _payingNowController.text = paidAmt > 0 ? paidAmt.toStringAsFixed(2) : '';
        _notesCtrl.text = userNotes;
        _isLoadingPurchase = false;
      });
    } catch (e) {
      setState(() => _isLoadingPurchase = false);
      _showMsg('Failed to load purchase: $e');
    }
  }

  Future<void> _loadDraft() async {
    if (_currentDraftId == null) return;
    setState(() => _isLoadingDraft = true);
    try {
      final draft = await DraftService.getImportDraft(_currentDraftId!);
      if (draft == null) {
        setState(() => _isLoadingDraft = false);
        return;
      }

      final suppId = draft['supplier_id'] as String?;
      final suppName = draft['supplier_name'] as String? ?? draft['supplier']?['company_name'] as String?;

      if (suppId != null) {
        setState(() {
          _selectedSupplierId = suppId;
          _selectedSupplierName = suppName;
          _supplierSearchController.text = suppName ?? '';
        });
        await _fetchSupplierDue(suppId);
      } else if (suppName != null && suppName.isNotEmpty) {
        setState(() {
          _selectedSupplierName = suppName;
          _supplierSearchController.text = suppName;
        });
      }

      if (!mounted) return;
      final items = draft['items'] as List? ?? [];
      final List<CartItemEntry> restoredCart = [];

      for (final rawItem in items) {
        final itemMap = Map<String, dynamic>.from(rawItem as Map);
        MedicineModel? med;
        final medId = itemMap['medicine_id']?.toString();
        final allMeds = context.read<InventoryProvider>().medicines;
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

        final batchNumber = itemMap['batch_number']?.toString() ?? 'BATCH-01';
        final expiryDate = DateTime.tryParse(itemMap['expiry_date']?.toString() ?? '') ?? DateTime.now().add(const Duration(days: 365));
        final qty = (itemMap['quantity'] as num?)?.toInt() ?? 1;
        final unitType = itemMap['unit_type']?.toString() ?? 'Unit';
        final retailPrice = (itemMap['retail_price'] as num?)?.toDouble() ?? 0.0;
        final mrp = (itemMap['mrp'] as num?)?.toDouble() ?? 0.0;
        final piecesPerStrip = (itemMap['pieces_per_strip'] as num?)?.toInt() ?? (med.piecesPerStrip ?? 1);
        final stripsPerBox = (itemMap['strips_per_box'] as num?)?.toInt() ?? (med.stripsPerBox ?? 1);

        restoredCart.add(
          CartItemEntry(
            medicine: med,
            batchNumber: batchNumber,
            expiryDate: expiryDate,
            quantity: qty,
            bonusQuantity: (itemMap['bonus_quantity'] as num?)?.toInt() ?? 0,
            unitType: unitType,
            bonusUnitType: itemMap['bonus_unit_type']?.toString() ?? unitType,
            unitPurchasePrice: retailPrice,
            mrp: mrp,
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
      setState(() => _isLoadingDraft = false);
      if (mounted) {
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
          'batch_number': item.batchNumber,
          'expiry_date': item.expiryDate.toIso8601String(),
          'quantity': item.quantity,
          'bonus_quantity': item.bonusQuantity,
          'bonus_unit_type': item.bonusUnitType,
          'unit_type': item.unitType,
          'retail_price': item.unitPurchasePrice,
          'mrp': item.mrp,
          'pieces_per_strip': item.piecesPerStrip,
          'strips_per_box': item.stripsPerBox,
        };
      }).toList();

      final id = await DraftService.saveImportDraft(
        draftId: _currentDraftId,
        draftName: draftName,
        supplierId: _selectedSupplierId,
        supplierName: _selectedSupplierName,
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
      text: _selectedSupplierName != null && _selectedSupplierName!.isNotEmpty
          ? '$_selectedSupplierName - Order'
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
            hintText: "Draft name (e.g. ABC Pharma â€“ June order)",
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

  Future<void> _savePurchase() async {
    if (_cartList.isEmpty) {
      _showMsg('Please add at least one medicine to the cart');
      return;
    }

    final auth = context.read<AuthProvider>();
    final pharmacyId = auth.currentPharmacy?.id ?? '';
    if (pharmacyId.isEmpty) {
      _showMsg('Pharmacy session not found');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final invProvider = context.read<InventoryProvider>();

      final List<PurchaseItemModel> purchaseItems = [];
      for (final item in _cartList) {
        String localMedId = item.medicine.id;
        if (item.medicine.pharmacyId.isEmpty || item.medicine.id.startsWith('global_')) {
          final addedMed = await _ensureLocalMedicineExists(pharmacyId, item.medicine, item.piecesPerStrip, item.stripsPerBox);
          localMedId = addedMed.id;
        }

        final double purchaseRate = item.effectiveSingleUnitBuyPrice;
        final double sellingRate = item.mrp > 0 ? item.mrp : purchaseRate;

        purchaseItems.add(
          PurchaseItemModel(
            medicineId: localMedId,
            medicineName: item.medicine.brandName,
            dosageForm: item.medicine.dosageForm,
            strength: item.medicine.strength,
            weight: item.medicine.weight,
            batchNumber: item.batchNumber,
            expiryDate: item.expiryDate,
            quantity: item.effectiveUnits,
            rawQuantity: item.quantity,
            unitType: item.unitType,
            piecesPerStrip: item.piecesPerStrip,
            stripsPerBox: item.stripsPerBox,
            purchasePrice: purchaseRate,
            sellingPrice: sellingRate,
            mrp: item.mrp > 0 ? item.mrp : sellingRate,
            totalPrice: item.lineTotal,
            rackLocation: item.rackLocation ?? item.medicine.rackLocation,
          ),
        );
      }

      final double paying = _payingNow.clamp(0.0, double.infinity);
      final double due = _todayBill - paying > 0 ? _todayBill - paying : 0.0;

      final List<Map<String, dynamic>> itemsDetail = _cartList.map((item) {
        return {
          'medicine_id': item.medicine.id,
          'batch_number': item.batchNumber,
          'raw_quantity': item.quantity,
          'bonus_quantity': item.bonusQuantity,
          'unit_type': item.unitType,
          'bonus_unit_type': item.bonusUnitType,
          'unit_purchase_price': item.unitPurchasePrice,
          'effective_unit_price': item.effectiveUnitBuyPrice,
          'effective_single_cost': item.effectiveSingleUnitBuyPrice,
          'mrp': item.mrp,
          'discount_percent': item.discountPercent,
          'discount_mode': item.discountMode,
          'pieces_per_strip': item.piecesPerStrip,
          'strips_per_box': item.stripsPerBox,
          'rack_location': item.rackLocation,
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

      if (_editingPurchaseId != null) {
        await _purchaseService.updatePurchaseWithItems(
          purchaseId: _editingPurchaseId!,
          supplierId: _selectedSupplierId,
          supplierName: _selectedSupplierName,
          totalAmount: _subtotal,
          discountAmount: _discountAmount,
          grandTotal: _todayBill,
          paidAmount: paying,
          dueAmount: due,
          notes: serializedNotes,
          items: purchaseItems,
        );

        await invProvider.loadMedicines();

        if (!mounted) return;
        setState(() => _isSaving = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purchase updated successfully!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        Navigator.pop(context, true);
        return;
      }

      await _purchaseService.recordPurchase(
        pharmacyId: pharmacyId,
        supplierId: _selectedSupplierId,
        supplierName: _selectedSupplierName,
        totalAmount: _subtotal,
        discountAmount: _discountAmount,
        grandTotal: _todayBill,
        paidAmount: paying,
        dueAmount: due,
        notes: serializedNotes,
        items: purchaseItems,
      );

      await invProvider.loadMedicines();

      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _cartList.clear();
        _discountValue = 0.0;
        _discountController.text = '0';
        _payingNowController.clear();
        _clearSelectedSupplier();
      });

      if (_currentDraftId != null) {
        await DraftService.deleteImportDraft(_currentDraftId!);
        _currentDraftId = null;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stock In / Purchase recorded successfully! ✅'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showMsg('Failed to save purchase: $e');
      }
    }
  }

  Future<MedicineModel> _ensureLocalMedicineExists(
    String pharmacyId,
    MedicineModel gm,
    int pps,
    int spb,
  ) async {
    var query = _client
        .from(SupabaseConstants.medicinesTable)
        .select()
        .eq('pharmacy_id', pharmacyId)
        .ilike('brand_name', gm.brandName.trim());

    if (gm.dosageForm.trim().isNotEmpty) {
      query = query.ilike('dosage_form', gm.dosageForm.trim());
    }
    if (gm.strength != null && gm.strength!.trim().isNotEmpty) {
      query = query.ilike('strength', gm.strength!.trim());
    }

    final List existingList = await query.limit(1);

    if (existingList.isNotEmpty) {
      final existing = MedicineModel.fromJson(existingList.first);
      return MedicineModel(
        id: existing.id,
        pharmacyId: existing.pharmacyId,
        globalId: existing.globalId,
        brandName: existing.brandName,
        genericName: existing.genericName,
        dosageForm: existing.dosageForm,
        strength: existing.strength,
        company: existing.company,
        category: existing.category,
        rackLocation: existing.rackLocation,
        unit: existing.unit,
        minStockAlert: existing.minStockAlert,
        isActive: existing.isActive,
        batches: existing.batches,
        piecesPerStrip: existing.piecesPerStrip ?? pps,
        stripsPerBox: existing.stripsPerBox ?? spb,
        weight: existing.weight ?? gm.weight,
      );
    }

    String? realGlobalId = gm.globalId;
    if (realGlobalId == null || realGlobalId.isEmpty) {
      if (gm.id.startsWith('global_')) {
        realGlobalId = gm.id.replaceFirst('global_', '');
      }
    }
    final bool isValidUuid = realGlobalId != null && RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(realGlobalId);

    final Map<String, dynamic> insertData = {
      'pharmacy_id': pharmacyId,
      'brand_name': gm.brandName.trim(),
      'generic_name': gm.genericName?.trim(),
      'dosage_form': gm.dosageForm.trim(),
      'strength': gm.strength?.trim(),
      'company': gm.company?.trim(),
      'unit': gm.unit.trim().isNotEmpty ? gm.unit.trim() : 'Pcs',
      'min_stock_alert': 10,
    };
    if (isValidUuid) {
      insertData['global_id'] = realGlobalId;
    }

    final res = await _client.from(SupabaseConstants.medicinesTable).insert(insertData).select().single();

    return MedicineModel(
      id: res['id'] as String,
      pharmacyId: res['pharmacy_id'] as String? ?? pharmacyId,
      globalId: res['global_id'] as String? ?? (isValidUuid ? realGlobalId : null),
      brandName: res['brand_name'] as String? ?? gm.brandName,
      genericName: res['generic_name'] as String? ?? gm.genericName,
      dosageForm: res['dosage_form'] as String? ?? gm.dosageForm,
      strength: res['strength'] as String? ?? gm.strength,
      company: res['company'] as String? ?? gm.company,
      category: res['category'] as String?,
      rackLocation: res['rack_location'] as String?,
      unit: res['unit'] as String? ?? gm.unit,
      minStockAlert: (res['min_stock_alert'] as num?)?.toInt() ?? 10,
      isActive: res['is_active'] as bool? ?? true,
      batches: const [],
      piecesPerStrip: pps,
      stripsPerBox: spb,
      weight: gm.weight,
    );
  }
  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<bool> _confirmLeave() async {
    if (_cartList.isEmpty && _selectedSupplierName == null && _medSearchController.text.isEmpty && _editingPurchaseId == null && _currentDraftId == null) {
      return true;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Leave Import Page?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: const Text(
          'You have unsaved items or details in your import entry. Are you sure you want to leave? Unsaved changes will be lost.',
          style: TextStyle(fontSize: 14, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Yes', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingDraft || _isLoadingPurchase) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: MediAppBar(title: _isLoadingPurchase ? 'Loading Purchase...' : 'Loading Draft...'),
        body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await _confirmLeave();
        if (leave && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        endDrawer: const AppDrawer(),
        appBar: MediAppBar(
          title: _currentDraftId != null ? 'Continue Draft' : 'Stock In / Purchase Entry',
          onBack: () async {
            final leave = await _confirmLeave();
            if (leave && context.mounted) {
              Navigator.of(context).pop();
            }
          },
          actions: [
            if (_cartList.isNotEmpty)
              TextButton.icon(
              onPressed: _isSavingDraft ? null : _saveDraft,
              icon: _isSavingDraft
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save_outlined, color: Colors.white, size: 17),
              label: Text(
                _isSavingDraft ? "Saving..." : "Save Draft",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
              ),
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Header extension with draft / edit badge matching authentic UI
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: (_editingPurchaseId != null || _currentDraftId != null)
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
                              _editingPurchaseId != null ? Icons.edit : Icons.edit_note,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _editingPurchaseId != null
                                  ? "Editing Confirmed Import"
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

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- 1. Supplier / Company Section ---
                  PurchaseSupplierSection(
                    searchController: _supplierSearchController,
                    selectedSupplierId: _selectedSupplierId,
                    selectedSupplierName: _selectedSupplierName,
                                        previousDue: _previousDue,
                    isFetchingDue: _isFetchingDue,
                    isSearching: _isSearchingSupplier,
                    searchResults: _supplierSearchResults,
                    onSearch: _searchSupplier,
                    onSelect: _selectSupplier,
                    onClear: _clearSelectedSupplier,
                  ),

                  const SizedBox(height: 16),

                  // --- 2. Medicine Search Section (with Floating Overlay) ---
                  _buildMedicineSearchSection(),

                  // --- 3. Inline Quick-Add Card (Shown when a medicine is selected or editing cart item) ---
                  if (_selectedMedForAdd != null) ...[
                    const SizedBox(height: 12),
                    PurchaseQuickAddCard(
                      item: _selectedMedForAdd!,
                      medicine: _selectedMedForAdd!['medicine_model'] as MedicineModel,
                      initialEntry: (_editingCartIndex != null && _editingCartIndex! < _cartList.length)
                          ? _cartList[_editingCartIndex!]
                          : null,
                      availableRacks: _availableRacks,
                      onCancel: () {
                        setState(() {
                          _selectedMedForAdd = null;
                          _editingCartIndex = null;
                        });
                      },
                      onConfirm: _confirmAddOrUpdateCartItem,
                    ),
                  ],

                  const SizedBox(height: 20),

                  // --- 4. Cart Header ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.shopping_cart_outlined, color: AppColors.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Import Cart (${_cartList.length})',
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

                  // --- Cart Items or Empty State ---
                  if (_cartList.isEmpty)
                    Container(
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
                            'Search and select a medicine from above to add stock.',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._cartList.asMap().entries.map((entry) {
                      final i = entry.key;
                      final item = entry.value;
                      return PurchaseCartItemCard(
                        index: i + 1,
                        item: item,
                        isEditing: _editingCartIndex == i,
                        onEdit: () => _startEditCartItem(i),
                        onRemove: () {
                          setState(() {
                            if (_editingCartIndex == i) {
                              _editingCartIndex = null;
                              _selectedMedForAdd = null;
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

                  if (_cartList.isNotEmpty) ...[
                    const SizedBox(height: 20),

                    // --- Summary & Payment Cards ---
                    PurchaseTotalsSummaryCard(
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

                    PurchasePaymentCard(
                      previousDue: _previousDue,
                      todayBill: _todayBill,
                      newDueAfterThis: _newDueAfterThis,
                      payingNowController: _payingNowController,
                      onPayFull: () {
                        setState(() {
                          _syncPayingNow();
                        });
                      },
                      onChanged: () {
                        setState(() {});
                      },
                    ),

                    const SizedBox(height: 20),

                    // --- 8. Confirm / Save Button ---
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _savePurchase,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.check_circle_outline_rounded, size: 22),
                        label: Text(
                          _isSaving ? (_editingPurchaseId != null ? 'Updating Purchase...' : 'Saving Stock In...') : (_editingPurchaseId != null ? 'Update Purchase' : 'Confirm & Save Stock In'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }

  // --- Widgets ---



  // Medicine search bar with CompositedTransformTarget
  Widget _buildMedicineSearchSection() {
    return CompositedTransformTarget(
      link: _medLayerLink,
      child: TextField(
        controller: _medSearchController,
        onChanged: _searchMedicines,
        decoration: InputDecoration(
          hintText: 'Search medicine name to add to stock...',
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary, size: 22),
          suffixIcon: _medSearchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _removeMedOverlay();
                    _medSearchController.clear();
                    setState(() => _medicineSearchResults = []);
                  },
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
    );
  }

  // Inline Quick-Add Card (shown right below the search bar, NO separate dialog!)



  // --- Cart Item Card ---
  
}