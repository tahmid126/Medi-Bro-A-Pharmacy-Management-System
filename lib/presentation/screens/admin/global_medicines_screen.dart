import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/medicine_packaging_helper.dart';
import '../../../data/models/medicine_model.dart';
import '../../../data/services/admin_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common/medi_app_bar.dart';
import '../../widgets/inventory/stock_medicine_card.dart';
import 'add_medicine_form_screen.dart';

class GlobalMedicinesScreen extends StatefulWidget {
  const GlobalMedicinesScreen({super.key});

  @override
  State<GlobalMedicinesScreen> createState() => _GlobalMedicinesScreenState();
}

class _GlobalMedicinesScreenState extends State<GlobalMedicinesScreen> {
  final AdminService _adminService = AdminService.instance;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _medicines = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _availabilityFilter = 'all'; // 'all', 'available', 'unavailable'

  @override
  void initState() {
    super.initState();
    _fetchGlobalMedicines();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchGlobalMedicines() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final data = await _adminService.fetchGlobalMedicines(
        searchQuery: _searchQuery,
        availabilityFilter: _availabilityFilter,
      );

      if (!mounted) return;
      setState(() {
        _medicines = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading catalog: ${ErrorFormatter.format(e)}'), backgroundColor: Colors.red),
      );
    }
  }

  void _openAddGlobalMedicine() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddMedicineFormScreen(isGlobalCatalog: true)),
    );
    if (result == true) {
      _fetchGlobalMedicines();
    }
  }

  void _openEditGlobalMedicine(Map<String, dynamic> med) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddMedicineFormScreen(medicineData: med, isGlobalCatalog: true)),
    );
    if (result == true) {
      _fetchGlobalMedicines();
    }
  }

  Future<void> _toggleAvailability(Map<String, dynamic> med) async {
    final bool current = med['is_available'] ?? true;
    try {
      await _adminService.toggleMedicineAvailability(
        medicineId: med['id'],
        isCurrentlyAvailable: current,
      );

      setState(() {
        med['is_available'] = !current;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${med['brand_name']} is now marked as ${!current ? "Available" : "Unavailable"}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> med) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Medicine?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${med['brand_name']}" from the Global Catalog?\n\n'
          'Note: This cannot be undone.',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _adminService.deleteGlobalMedicine(med['id']);

        setState(() {
          _medicines.removeWhere((item) => item['id'] == med['id']);
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${med['brand_name']} deleted successfully'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      endDrawer: const AppDrawer(),
appBar: const MediAppBar(title: 'Global Medicine Library'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddGlobalMedicine,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Drug', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // Filter & Search Controls
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    setState(() => _searchQuery = val);
                    _fetchGlobalMedicines();
                  },
                  decoration: InputDecoration(
                    hintText: 'Search brand, generic, manufacturer...',
                    prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _filterChip('All', 'all'),
                    const SizedBox(width: 8),
                    _filterChip('Available', 'available'),
                    const SizedBox(width: 8),
                    _filterChip('Unavailable', 'unavailable'),
                  ],
                ),
              ],
            ),
          ),

          // Count & Information bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${_medicines.length} items',
                  style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600),
                ),
                const Text(
                  'Super Admin Master Catalog',
                  style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // Medicine List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _medicines.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.medication_outlined, size: 56, color: Colors.grey),
                            SizedBox(height: 12),
                            Text('No medicines found', style: TextStyle(fontSize: 16, color: Colors.grey)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _fetchGlobalMedicines,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _medicines.length,
                        itemBuilder: (context, idx) {
                          final med = _medicines[idx];
                          final isAvailable = med['is_available'] ?? true;

                          final packInfoResult = MedicinePackagingHelper.getPackagingInfo(
                            matchingGlobalMedicine: med,
                          );

                          final medicineModel = MedicineModel(
                            id: med['id']?.toString() ?? '',
                            pharmacyId: '',
                            globalId: med['id']?.toString(),
                            brandName: med['brand_name'] ?? '',
                            genericName: med['generic_name'],
                            dosageForm: (med['dosage_form'] as String?)?.trim() ?? '',
                            strength: med['strength'],
                            company: med['company'] ?? med['company_name'],
                            unit: med['default_unit'] ?? 'Pcs',
                            isActive: isAvailable,
                            piecesPerStrip: packInfoResult['pps'],
                            stripsPerBox: packInfoResult['spb'],
                            weight: packInfoResult['weight'],
                          );

                          return StockMedicineCard(
                            medicine: medicineModel,
                            matchingGlobalMedicine: med,
                            viewMode: 'admin',
                            showAddStock: false,
                            onTap: () => _openEditGlobalMedicine(med),
                            onGenericTap: (gen) {
                              _searchController.text = gen;
                              setState(() => _searchQuery = gen);
                              _fetchGlobalMedicines();
                            },
                            onCompanyTap: (comp) {
                              _searchController.text = comp;
                              setState(() => _searchQuery = comp);
                              _fetchGlobalMedicines();
                            },
                            onTypeTap: (type) {
                              _searchController.text = type;
                              setState(() => _searchQuery = type);
                              _fetchGlobalMedicines();
                            },
                            bottomActions: Row(
                              children: [
                                // Available Status Badge (Hide button er age)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isAvailable ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isAvailable ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isAvailable ? Icons.check_circle_outline_rounded : Icons.cancel_outlined,
                                        size: 13,
                                        color: isAvailable ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isAvailable ? 'Available' : 'Unavailable',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isAvailable ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(),

                                // Hide / Unhide Button
                                OutlinedButton.icon(
                                  onPressed: () => _toggleAvailability(med),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    visualDensity: VisualDensity.compact,
                                    side: BorderSide(
                                      color: isAvailable ? Colors.orange.shade300 : Colors.green.shade300,
                                    ),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: Icon(
                                    isAvailable ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                    size: 15,
                                    color: isAvailable ? Colors.orange.shade800 : Colors.green.shade800,
                                  ),
                                  label: Text(
                                    isAvailable ? 'Hide' : 'Unhide',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: isAvailable ? Colors.orange.shade800 : Colors.green.shade800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Edit Button
                                ElevatedButton.icon(
                                  onPressed: () => _openEditGlobalMedicine(med),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                    foregroundColor: AppColors.primary,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    visualDensity: VisualDensity.compact,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.edit_outlined, size: 15),
                                  label: const Text(
                                    'Edit',
                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 4),

                                // Delete Button
                                IconButton(
                                  onPressed: () => _confirmDelete(med),
                                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 19),
                                  tooltip: 'Delete Medicine',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _availabilityFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _availabilityFilter = value);
          _fetchGlobalMedicines();
        }
      },
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      backgroundColor: Colors.grey.shade100,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}