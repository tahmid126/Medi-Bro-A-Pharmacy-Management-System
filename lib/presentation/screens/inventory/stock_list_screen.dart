import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/medicine_packaging_helper.dart';
import '../../../../data/models/batch_model.dart';
import '../../../../data/models/medicine_model.dart';
import '../../../../data/services/inventory_service.dart';
import '../../providers/inventory_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/inventory/stock_batch_cards_sheet.dart';
import '../../widgets/inventory/stock_medicine_card.dart';
import '../admin/add_medicine_form_screen.dart';
import '../purchases/purchase_entry_screen.dart';
import '../../widgets/common/medi_app_bar.dart';
import '../../../../core/utils/error_formatter.dart';
import '../../../../data/services/supabase_service.dart';

class StockListScreen extends StatefulWidget {
  final String? initialCategory;
  final String? initialGeneric;
  final String? initialCompany;
  final String? initialType;
  final String initialMode; // 'stock' or 'library'

  const StockListScreen({
    super.key,
    this.initialCategory,
    this.initialGeneric,
    this.initialCompany,
    this.initialType,
    this.initialMode = 'stock',
  });

  @override
  State<StockListScreen> createState() => _StockListScreenState();
}

class _StockListScreenState extends State<StockListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _companySearchController = TextEditingController();

  late String _viewMode; // 'stock' (Shop Stock) vs 'library' (Medicine Library)

  String? _selectedCompany;
  String? _selectedGenericName;
  String? _selectedMedicineType;
  String? _sortMode; // 'expiry', 'low_stock', 'high_stock', 'a_z'

  OverlayEntry? _companyOverlay;
  final LayerLink _companyLayerLink = LayerLink();
  List<String> _companySearchResults = [];

  List<Map<String, dynamic>> _globalMedicines = [];
  bool _isLoadingGlobal = false;
  String? _expandedMedicineKey;

  @override
  void initState() {
    super.initState();
    _viewMode = widget.initialMode;
    _selectedGenericName = widget.initialGeneric;
    _selectedMedicineType = widget.initialType;
    _selectedCompany = widget.initialCompany;
    if (_selectedCompany != null) {
      _companySearchController.text = _selectedCompany!;
    }

    _fetchGlobalMedicines();
  }

  @override
  void dispose() {
    _removeCompanyOverlay();
    _searchController.dispose();
    _companySearchController.dispose();
    super.dispose();
  }

  Future<void> _fetchGlobalMedicines() async {
    setState(() => _isLoadingGlobal = true);
    try {
      final list = await InventoryService().fetchGlobalMedicines();
      if (mounted) {
        setState(() {
          _globalMedicines = list;
          _isLoadingGlobal = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingGlobal = false);
      }
    }
  }

  Map<String, dynamic> _findMatchingGlobalMedicine(MedicineModel med) {
    if (_globalMedicines.isEmpty) return {};
    return MedicinePackagingHelper.findMatchingGlobalMedicine(
      med,
      _globalMedicines,
    );
  }

  Map<String, dynamic> _prepareMedDataForEdit(MedicineModel med) {
    final medData = med.toJson();
    final gm = _findMatchingGlobalMedicine(med);
    if (gm.isNotEmpty) {
      if (medData['global_id'] == null || medData['global_id'].toString().isEmpty) {
        medData['global_id'] = gm['id']?.toString();
      }
      if (medData['id'] == null || medData['id'].toString().isEmpty) {
        medData['id'] = 'global_${gm['id']}';
      }
    }
    if (med.batches.isNotEmpty && med.primaryActiveBatch != null && med.primaryActiveBatch!.mrp > 0) {
      medData['mrp_price'] = med.primaryActiveBatch!.mrp;
    } else if (med.catalogPrice != null && med.catalogPrice! > 0) {
      medData['mrp_price'] = med.catalogPrice!;
    } else if (gm.isNotEmpty) {
      final gPrice = (gm['default_mrp'] as num?)?.toDouble() ??
          (gm['mrp'] as num?)?.toDouble() ??
          double.tryParse(gm['default_mrp']?.toString() ?? gm['mrp']?.toString() ?? '');
      if (gPrice != null && gPrice > 0) {
        medData['mrp_price'] = gPrice;
        medData['default_mrp'] = gPrice;
      }
    }
    final packInfo = MedicinePackagingHelper.getPackagingInfo(med: med, matchingGlobalMedicine: gm);
    if (medData['pieces_per_strip'] == null || (medData['pieces_per_strip'] as num? ?? 0) <= 1) {
      medData['pieces_per_strip'] = packInfo['pps'];
    }
    if (medData['strips_per_box'] == null || (medData['strips_per_box'] as num? ?? 0) <= 1) {
      medData['strips_per_box'] = packInfo['spb'];
    }
    if (medData['weight'] == null || medData['weight'].toString().trim().isEmpty) {
      medData['weight'] = packInfo['weight'];
    }
    if (gm.isNotEmpty) {
      if (medData['strength'] == null || medData['strength'].toString().trim().isEmpty) {
        medData['strength'] = gm['strength'];
      }
      if (medData['company'] == null || medData['company'].toString().trim().isEmpty) {
        medData['company'] = gm['company'];
      }
      if (medData['generic_name'] == null || medData['generic_name'].toString().trim().isEmpty) {
        medData['generic_name'] = gm['generic_name'];
      }
    }

    // If strength represents physical weight or equals resolved weight, clean it so strength is blank
    final resolvedWeight = (medData['weight'] ?? '').toString().trim().toLowerCase().replaceAll(RegExp(r'[\(\)\[\]]'), '');
    final currentStrength = (medData['strength'] ?? '').toString().trim().replaceAll(RegExp(r'[\(\)\[\]]'), '');
    if (currentStrength.isNotEmpty) {
      final cleanS = currentStrength.toLowerCase();
      if (resolvedWeight.isNotEmpty && (cleanS == resolvedWeight || cleanS == resolvedWeight.replaceAll(' ', ''))) {
        medData['strength'] = '';
      } else if (RegExp(r'^\d+(?:\.\d+)?\s*(?:ml|gm|g|l|kg|pads?|sachets?|tubes?|drops?|spray)$', caseSensitive: false).hasMatch(currentStrength)) {
        if (resolvedWeight.isEmpty) {
          medData['weight'] = currentStrength;
        }
        medData['strength'] = '';
      }
    }
    return medData;
  }

  // --- Company Dropdown / Autocomplete Overlay ---
  void _searchCompany(String query) {
    final inventory = context.read<InventoryProvider>();
    final Set<String> companySet = {};
    for (final m in inventory.medicines) {
      if (m.company != null && m.company!.trim().isNotEmpty) {
        companySet.add(m.company!.trim());
      }
    }
    for (final gm in _globalMedicines) {
      final c = gm['company']?.toString().trim();
      if (c != null && c.isNotEmpty) {
        companySet.add(c);
      }
    }

    if (query.trim().isEmpty) {
      _companySearchResults = companySet.toList()..sort();
    } else {
      _companySearchResults = companySet
          .where((c) => c.toLowerCase().contains(query.toLowerCase()))
          .toList()
        ..sort();
    }

    if (_companySearchResults.isNotEmpty) {
      _showCompanyOverlay();
    } else {
      _removeCompanyOverlay();
    }
  }

  void _showCompanyOverlay() {
    _removeCompanyOverlay();
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    _companyOverlay = OverlayEntry(
      builder: (ctx) => Positioned(
        width: 220,
        child: CompositedTransformFollower(
          link: _companyLayerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 48),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: _companySearchResults.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final comp = _companySearchResults[i];
                  return ListTile(
                    dense: true,
                    title: Text(comp, style: const TextStyle(fontSize: 13)),
                    onTap: () {
                      setState(() {
                        _selectedCompany = comp;
                        _companySearchController.text = comp;
                      });
                      _removeCompanyOverlay();
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_companyOverlay!);
  }

  void _removeCompanyOverlay() {
    _companyOverlay?.remove();
    _companyOverlay = null;
  }

  void _clearCompanyFilter() {
    _removeCompanyOverlay();
    setState(() {
      _selectedCompany = null;
      _companySearchController.clear();
      _expandedMedicineKey = null;
    });
  }

  // --- Filtering & Sorting Logic ---
  List<MedicineModel> _getFilteredMedicines(List<MedicineModel> all) {
    List<MedicineModel> source = [];

    if (_viewMode == 'stock') {
      // 1. Group duplicates and consolidate batches
      final Map<String, MedicineModel> consolidated = {};
      for (final m in all) {
        final key = '${m.brandName.trim().toLowerCase()}|${m.dosageForm.trim().toLowerCase()}';
        if (!consolidated.containsKey(key)) {
          consolidated[key] = m;
        } else {
          final existing = consolidated[key]!;
          final Map<String, BatchModel> batchMap = {};
          for (final b in existing.batches) {
            final bKey = '${b.batchNumber.trim().toLowerCase()}|${b.expiryDate.toIso8601String().split('T').first}';
            batchMap[bKey] = b;
          }
          for (final b in m.batches) {
            final bKey = '${b.batchNumber.trim().toLowerCase()}|${b.expiryDate.toIso8601String().split('T').first}';
            if (batchMap.containsKey(bKey)) {
              final eb = batchMap[bKey]!;
              batchMap[bKey] = BatchModel(
                id: eb.id,
                pharmacyId: eb.pharmacyId,
                medicineId: eb.medicineId,
                batchNumber: eb.batchNumber,
                expiryDate: eb.expiryDate,
                purchasePrice: eb.purchasePrice,
                sellingPrice: eb.sellingPrice,
                mrp: eb.mrp,
                stockQty: eb.stockQty + b.stockQty,
              );
            } else {
              batchMap[bKey] = b;
            }
          }
          consolidated[key] = MedicineModel(
            id: existing.id,
            pharmacyId: existing.pharmacyId,
            globalId: existing.globalId ?? m.globalId,
            brandName: existing.brandName,
            genericName: existing.genericName ?? m.genericName,
            dosageForm: existing.dosageForm,
            strength: existing.strength ?? m.strength,
            company: existing.company ?? m.company,
            category: existing.category ?? m.category,
            rackLocation: existing.rackLocation ?? m.rackLocation,
            unit: existing.unit,
            minStockAlert: existing.minStockAlert,
            isActive: existing.isActive,
            batches: batchMap.values.toList(),
            piecesPerStrip: existing.piecesPerStrip ?? m.piecesPerStrip,
            stripsPerBox: existing.stripsPerBox ?? m.stripsPerBox,
            weight: existing.weight ?? m.weight,
            catalogPrice: existing.catalogPrice ?? m.catalogPrice,
          );
        }
      }
      source = consolidated.values.toList();
    } else {
      // Medicine Library mode: Master catalog from global_medicines + local pharmacy stock overlay
      final Map<String, MedicineModel> localStockMap = {};
      for (final m in all) {
        final key = '${m.brandName.trim().toLowerCase()}|${m.dosageForm.trim().toLowerCase()}';
        if (!localStockMap.containsKey(key)) {
          localStockMap[key] = m;
        } else {
          // Consolidate batches if local has duplicate records
          final existing = localStockMap[key]!;
          final combinedBatches = [...existing.batches, ...m.batches];
          localStockMap[key] = existing.copyWith(batches: combinedBatches);
        }
      }

      final Set<String> processedKeys = {};
      final Set<String> processedIds = {};
      for (final gm in _globalMedicines) {
        final gId = gm['id']?.toString() ?? '';
        final bName = (gm['brand_name'] ?? '').toString().trim();
        final dForm = (gm['dosage_form'] ?? '').toString().trim();
        final key = '${bName.toLowerCase()}|${dForm.toLowerCase()}';
        
        // Prevent duplicate cards if database or sync returned duplicates
        if ((gId.isNotEmpty && processedIds.contains(gId)) || processedKeys.contains(key)) {
          continue;
        }
        if (gId.isNotEmpty) processedIds.add(gId);
        processedKeys.add(key);

        final local = localStockMap[key];
        final List<BatchModel> batches = local?.batches ?? [];

        final lBrand = local?.brandName.trim();
        final lGen = local?.genericName?.trim();
        final lForm = local?.dosageForm.trim();
        final lStr = local?.strength?.trim();
        final lComp = local?.company?.trim();
        final lUnit = local?.unit.trim();

        final dummyMed = MedicineModel(
          id: local?.id ?? '',
          pharmacyId: local?.pharmacyId ?? '',
          globalId: gm['id']?.toString(),
          brandName: (lBrand != null && lBrand.isNotEmpty) ? lBrand : bName,
          genericName: (lGen != null && lGen.isNotEmpty)
              ? lGen
              : (gm['generic_name'] as String?),
          dosageForm: (lForm != null && lForm.isNotEmpty)
              ? lForm
              : dForm,
          strength: (lStr != null && lStr.isNotEmpty)
              ? lStr
              : (gm['strength'] as String?),
          company: (lComp != null && lComp.isNotEmpty)
              ? lComp
              : (gm['company'] as String?),
          category: local?.category ?? (gm['category'] as String?),
          rackLocation: local?.rackLocation,
          unit: (lUnit != null && lUnit.isNotEmpty && lUnit != 'Pcs')
              ? lUnit
              : (gm['default_unit'] as String? ?? local?.unit ?? 'Piece'),
          minStockAlert: local?.minStockAlert ?? 10,
          isActive: true,
          batches: batches,
          piecesPerStrip: local?.piecesPerStrip,
          stripsPerBox: local?.stripsPerBox,
          weight: local?.weight,
          catalogPrice: local?.catalogPrice,
        );
        final packInfo = MedicinePackagingHelper.getPackagingInfo(med: dummyMed, matchingGlobalMedicine: gm);
        int? pps = packInfo['pps'];
        int? spb = packInfo['spb'];
        String? wt = packInfo['weight'];

        source.add(
          MedicineModel(
            id: local?.id ?? '',
            pharmacyId: local?.pharmacyId ?? '',
            globalId: gm['id']?.toString(),
            brandName: dummyMed.brandName,
            genericName: dummyMed.genericName,
            dosageForm: dummyMed.dosageForm,
            strength: dummyMed.strength,
            company: dummyMed.company,
            category: dummyMed.category,
            rackLocation: dummyMed.rackLocation,
            unit: dummyMed.unit,
            minStockAlert: dummyMed.minStockAlert,
            isActive: true,
            batches: batches,
            piecesPerStrip: pps,
            stripsPerBox: spb,
            weight: wt,
            catalogPrice: (local?.catalogPrice != null && local!.catalogPrice! > 0)
                ? local.catalogPrice
                : ((gm['default_mrp'] as num?)?.toDouble() ??
                    (gm['mrp'] as num?)?.toDouble() ??
                    double.tryParse(gm['default_mrp']?.toString() ?? gm['mrp']?.toString() ?? '')),
          ),
        );
      }

      // Add local medicines not matched in global library (avoid duplicates)
      for (final m in all) {
        final key = '${m.brandName.trim().toLowerCase()}|${m.dosageForm.trim().toLowerCase()}';
        if (!processedKeys.contains(key) && (m.globalId == null || !processedIds.contains(m.globalId))) {
          processedKeys.add(key);
          source.add(m);
        }
      }
    }

    final query = _searchController.text.trim().toLowerCase();
    final filtered = source.where((m) {
      if (m.isActive == false) return false;
      if (_viewMode == 'stock' && m.pharmacyId.isEmpty) return false;

      if (query.isNotEmpty) {
        final matchBrand = m.brandName.toLowerCase().contains(query);
        final matchGeneric = m.genericName?.toLowerCase().contains(query) ?? false;
        final matchStrength = m.strength?.toLowerCase().contains(query) ?? false;
        if (!matchBrand && !matchGeneric && !matchStrength) return false;
      }

      if (_selectedCompany != null && _selectedCompany!.isNotEmpty) {
        if (m.company == null ||
            m.company!.toLowerCase() != _selectedCompany!.toLowerCase()) {
          return false;
        }
      }

      if (_selectedGenericName != null && _selectedGenericName!.isNotEmpty) {
        if (m.genericName == null ||
            m.genericName!.toLowerCase() != _selectedGenericName!.toLowerCase()) {
          return false;
        }
      }

      if (_selectedMedicineType != null && _selectedMedicineType!.isNotEmpty) {
        if (m.dosageForm.toLowerCase() != _selectedMedicineType!.toLowerCase()) {
          return false;
        }
      }

      return true;
    }).toList();

    // Sort only in stock mode
    if (_viewMode == 'stock' && _sortMode != null) {
      if (_sortMode == 'expiry') {
        filtered.sort((a, b) {
          final expA = a.primaryActiveBatch?.expiryDate;
          final expB = b.primaryActiveBatch?.expiryDate;
          if (expA == null && expB == null) return 0;
          if (expA == null) return 1;
          if (expB == null) return -1;
          return expA.compareTo(expB);
        });
      } else if (_sortMode == 'low_stock') {
        filtered.sort((a, b) => a.totalStock.compareTo(b.totalStock));
      } else if (_sortMode == 'high_stock') {
        filtered.sort((a, b) => b.totalStock.compareTo(a.totalStock));
      } else if (_sortMode == 'a_z') {
        filtered.sort((a, b) => a.brandName.compareTo(b.brandName));
      }
    }

    return filtered;
  }

  // --- Quick Sort Chip Widget (Exact Original Styling) ---
  Widget _sortChip({
    required String mode,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _sortMode == mode;
    return GestureDetector(
      onTap: () {
        _removeCompanyOverlay();
        setState(() {
          _sortMode = isSelected ? null : mode;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? AppColors.primary : Colors.white,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.primary : Colors.white,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Active Filter Chip Widget ---
  Widget _activeFilterChip({
    required IconData icon,
    required String label,
    required VoidCallback onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, color: Colors.white70, size: 14),
          ),
        ],
      ),
    );
  }

  // --- Batch Cards Bottom Sheet ---
  void _openBatchCardsSheet(MedicineModel med) {
    final gm = _findMatchingGlobalMedicine(med);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StockBatchCardsSheet(
        medicine: med,
        matchingGlobalMedicine: gm,
        onAddBatch: () {
          Navigator.pop(sheetCtx);
          _openAddBatchDialog(med);
        },
      ),
    );
  }

  // --- Direct Purchase Entry Navigation (Replaces mini popup) ---
  void _openAddBatchDialog(MedicineModel med) {
    _removeCompanyOverlay();
    final invProvider = context.read<InventoryProvider>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseEntryScreen(initialMedicine: med),
      ),
    ).then((_) {
      if (mounted) {
        invProvider.loadMedicines();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final filteredList = _getFilteredMedicines(inventory.medicines);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: MediAppBar(
        title: _viewMode == 'stock' ? 'Store Stock' : 'Medicine Library',
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded, color: Colors.white, size: 22),
            onPressed: () {},
            tooltip: 'Search',
          ),
        ],
      ),
      endDrawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _removeCompanyOverlay();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddMedicineFormScreen(isGlobalCatalog: false)),
          ).then((_) => inventory.loadMedicines());
        },
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'Add Medicine',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: GestureDetector(
        onTap: _removeCompanyOverlay,
        child: SafeArea(
          child: Column(
            children: [
              // --- Curved Header Container (Exact Authentic Original UI) ---
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Row 1: Search Medicine or Generic
                      TextField(
                        controller: _searchController,
                        onChanged: (v) {
                          _removeCompanyOverlay();
                          setState(() {
                            _expandedMedicineKey = null;
                          });
                        },
                        style: const TextStyle(color: Color(0xFF1E293B)),
                        decoration: InputDecoration(
                          hintText: "Search medicine or generic name...",
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: AppColors.primary,
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, color: Colors.grey),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                    FocusScope.of(context).unfocus();
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Row 2: Company Filter + View Mode Switcher
                      Row(
                        children: [
                          // Company Search / Selected Company Chip
                          Expanded(
                            flex: 11,
                            child: CompositedTransformTarget(
                              link: _companyLayerLink,
                              child: _selectedCompany != null
                                  ? Container(
                                      height: 44,
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.business_rounded,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              _selectedCompany!,
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
                                            child: const Icon(
                                              Icons.close,
                                              color: Colors.white70,
                                              size: 18,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : TextField(
                                      controller: _companySearchController,
                                      onChanged: _searchCompany,
                                      style: const TextStyle(color: Colors.white, fontSize: 13),
                                      decoration: InputDecoration(
                                        hintText: "Filter by Company",
                                        hintStyle: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.business_rounded,
                                          color: Colors.white70,
                                          size: 17,
                                        ),
                                        suffixIcon: _companySearchController.text.isNotEmpty
                                            ? IconButton(
                                                icon: const Icon(
                                                  Icons.clear,
                                                  color: Colors.white70,
                                                  size: 16,
                                                ),
                                                onPressed: _clearCompanyFilter,
                                              )
                                            : null,
                                        filled: true,
                                        fillColor: Colors.white.withValues(alpha: 0.2),
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 0,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(width: 8),

                          // Mode Switcher Dropdown (Shop Stock vs Medicine Library)
                          Expanded(
                            flex: 9,
                            child: Container(
                              height: 44,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _viewMode,
                                  isExpanded: true,
                                  dropdownColor: AppColors.primary,
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'stock',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.inventory_2_rounded,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                          SizedBox(width: 5),
                                          Flexible(
                                            child: Text(
                                              'Shop Stock',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'library',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.local_pharmacy_rounded,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                          SizedBox(width: 5),
                                          Flexible(
                                            child: Text(
                                              'Medicine Library',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      _removeCompanyOverlay();
                                      setState(() {
                                        _viewMode = val;
                                        _expandedMedicineKey = null;
                                        if (val == 'library') {
                                          _sortMode = null;
                                        }
                                      });
                                      if (val == 'library') {
                                        _fetchGlobalMedicines();
                                      }
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Row 3: Filter Chips / Sort Bar (ONLY SHOWN WHEN SHOP STOCK IS SELECTED)
                      if (_viewMode == 'stock') ...[
                        const SizedBox(height: 10),
                        SingleChildScrollView(
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
                        ),
                      ],

                      // Row 4: Active Filter Tags
                      if (_selectedGenericName != null ||
                          _selectedMedicineType != null ||
                          (_viewMode == 'stock' && _sortMode != null)) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (_selectedGenericName != null)
                              _activeFilterChip(
                                icon: Icons.science_outlined,
                                label: _selectedGenericName!,
                                onRemove: () {
                                  setState(() => _selectedGenericName = null);
                                },
                              ),
                            if (_selectedMedicineType != null)
                              _activeFilterChip(
                                icon: Icons.category_outlined,
                                label: _selectedMedicineType!,
                                onRemove: () {
                                  setState(() => _selectedMedicineType = null);
                                },
                              ),
                            if (_viewMode == 'stock' && _sortMode != null)
                              _activeFilterChip(
                                icon: Icons.sort_rounded,
                                label: _sortMode == 'expiry'
                                    ? 'Sort: Expiring Soon'
                                    : _sortMode == 'low_stock'
                                        ? 'Sort: Low Stock First'
                                        : _sortMode == 'high_stock'
                                            ? 'Sort: High Stock First'
                                            : 'Sort: A to Z',
                                onRemove: () {
                                  setState(() => _sortMode = null);
                                },
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // --- Main Medicines List ---
              Expanded(
                child: (inventory.isLoading || (_viewMode == 'library' && _isLoadingGlobal))
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      )
                    : filteredList.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _viewMode == 'stock'
                                      ? Icons.inventory_2_outlined
                                      : Icons.local_pharmacy_outlined,
                                  size: 56,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _viewMode == 'stock'
                                      ? 'No stock found in shop'
                                      : 'No medicines found in library',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (_selectedCompany != null ||
                                    _selectedGenericName != null ||
                                    _selectedMedicineType != null ||
                                    _searchController.text.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  TextButton.icon(
                                    onPressed: () {
                                      _removeCompanyOverlay();
                                      setState(() {
                                        _selectedCompany = null;
                                        _selectedGenericName = null;
                                        _selectedMedicineType = null;
                                        _sortMode = null;
                                        _searchController.clear();
                                        _companySearchController.clear();
                                      });
                                    },
                                    icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                                    label: const Text('Clear All Filters'),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async {
                    await context.read<InventoryProvider>().loadMedicines();
                    await _fetchGlobalMedicines();
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: filteredList.length,
                            itemBuilder: (context, index) {
                              final med = filteredList[index];
                              final gm = _findMatchingGlobalMedicine(med);
                              final itemKey = med.id.isNotEmpty
                                  ? med.id
                                  : (med.globalId != null && med.globalId!.isNotEmpty
                                      ? med.globalId!
                                      : '${med.brandName.trim().toLowerCase()}_${med.dosageForm.trim().toLowerCase()}');
                              final isItemExpanded = _expandedMedicineKey == itemKey;

                              return StockMedicineCard(
                                medicine: med,
                                matchingGlobalMedicine: gm,
                                viewMode: _viewMode,
                                isExpanded: isItemExpanded,
                                onToggleExpand: () {
                                  _removeCompanyOverlay();
                                  setState(() {
                                    if (_expandedMedicineKey == itemKey) {
                                      _expandedMedicineKey = null;
                                    } else {
                                      _expandedMedicineKey = itemKey;
                                    }
                                  });
                                },
                                onTap: () {
                                  _removeCompanyOverlay();
                                  setState(() => _expandedMedicineKey = null);
                                  _openBatchCardsSheet(med);
                                },
                                onAddBatch: () {
                                  _removeCompanyOverlay();
                                  setState(() => _expandedMedicineKey = null);
                                  _openAddBatchDialog(med);
                                },
                                onEdit: () async {
                                  _removeCompanyOverlay();
                                  setState(() => _expandedMedicineKey = null);
                                  final medData = _prepareMedDataForEdit(med);
                                  final isGlobal = med.globalId != null && med.globalId!.isNotEmpty;
                                  final res = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AddMedicineFormScreen(
                                        medicineData: medData,
                                        isGlobalCatalog: false,
                                        isSuggestionMode: isGlobal,
                                      ),
                                    ),
                                  );
                                  if (res == true && context.mounted) {
                                    context.read<InventoryProvider>().loadMedicines();
                                    _fetchGlobalMedicines();
                                  }
                                },
                                onSuggestEdit: () async {
                                  _removeCompanyOverlay();
                                  setState(() => _expandedMedicineKey = null);
                                  final medData = _prepareMedDataForEdit(med);
                                  final res = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AddMedicineFormScreen(
                                        medicineData: medData,
                                        isGlobalCatalog: false,
                                        isSuggestionMode: true,
                                      ),
                                    ),
                                  );
                                  if (res == true && context.mounted) {
                                    context.read<InventoryProvider>().loadMedicines();
                                    _fetchGlobalMedicines();
                                  }
                                },
                                onDelete: () {
                                  _removeCompanyOverlay();
                                  setState(() => _expandedMedicineKey = null);
                                  _confirmAndDeleteLocalMedicine(med);
                                },
                                onCompanyTap: (comp) {
                                  _removeCompanyOverlay();
                                  setState(() {
                                    _selectedCompany = comp;
                                    _companySearchController.text = comp;
                                  });
                                },
                                onGenericTap: (gen) {
                                  _removeCompanyOverlay();
                                  setState(() {
                                    _selectedGenericName = gen;
                                  });
                                },
                                onTypeTap: (type) {
                                  _removeCompanyOverlay();
                                  setState(() {
                                    _selectedMedicineType = type;
                                  });
                                },
                              );
                            },
                          ),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndDeleteLocalMedicine(MedicineModel med) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Medicine'),
          ],
        ),
        content: Text('Are you sure you want to delete "${med.brandName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final supabase = SupabaseService.instance.client;

    try {
      // 1. Check if batches exist with non-zero stock
      final hasActiveStock = med.batches.any((b) => b.stockQty > 0);

      // 2. Check if transactions (sale_items or purchase_items) exist
      bool hasTransactions = false;
      try {
        final saleItems = await supabase
            .from('sale_items')
            .select('id')
            .eq('medicine_id', med.id)
            .limit(1);
        if (saleItems.isNotEmpty) hasTransactions = true;
      } catch (_) {}

      if (!hasTransactions) {
        try {
          final purchaseItems = await supabase
              .from('purchase_items')
              .select('id')
              .eq('medicine_id', med.id)
              .limit(1);
          if (purchaseItems.isNotEmpty) hasTransactions = true;
        } catch (_) {}
      }

      if (hasTransactions || hasActiveStock) {
        // Safe delete (archive / deactivate) to preserve accounting and ledger history
        await supabase
            .from('medicines')
            .update({'is_active': false})
            .eq('id', med.id);

        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text('"${med.brandName}" has transaction records. It has been safely deactivated & archived. ℹ️'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      } else {
        // Hard delete: completely clean deletion
        await supabase.from('batches').delete().eq('medicine_id', med.id);

        try {
          await supabase
              .from('medicine_requests')
              .delete()
              .ilike('notes', '%LocalMedId:${med.id}%');
        } catch (_) {}

        await supabase.from('medicines').delete().eq('id', med.id);

        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text('"${med.brandName}" permanently deleted. ✅'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }

      // Reload inventory
      if (mounted) {
        context.read<InventoryProvider>().loadMedicines();
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to delete: ${ErrorFormatter.format(e)}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
