import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_drawer.dart';

import '../../../data/services/due_service.dart';
import '../../widgets/due/due_card.dart';
import '../../widgets/due/due_selected_chip.dart';
import '../../widgets/due/due_empty_state.dart';
import '../../widgets/common/medi_app_bar.dart';

class DueScreen extends StatefulWidget {
  const DueScreen({super.key});

  @override
  State<DueScreen> createState() => _DueScreenState();
}

class _DueScreenState extends State<DueScreen> {
  String _filterType = 'Customer';
  late final PageController _pageController;

  final TextEditingController _filterSearchController = TextEditingController();
  String? _selectedFilterId;
  String? _selectedFilterName;
  List<Map<String, dynamic>> _filterSearchResults = [];
  bool _isSearchingFilter = false;

  // ── Overlay ──────────────────────────────────────────────────────────────────
  OverlayEntry? _filterOverlay;
  final LayerLink _filterLayerLink = LayerLink();

  List<Map<String, dynamic>> _dueList = [];
  bool _isLoadingDues = false;

  String? _expandedId;
  final Map<String, bool> _isSavingPayment = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDues();
    });
  }

  @override
  void dispose() {
    _removeFilterOverlay();
    _pageController.dispose();
    _filterSearchController.dispose();
    super.dispose();
  }

  String? get _currentPharmacyId {
    return context.read<AuthProvider>().currentProfile?.pharmacyId;
  }

  // ── Overlay Methods ──────────────────────────────────────────────────────────

  void _removeFilterOverlay() {
    _filterOverlay?.remove();
    _filterOverlay = null;
  }

  void _showFilterOverlay() {
    _removeFilterOverlay();
    if (_filterSearchResults.isEmpty) return;

    _filterOverlay = OverlayEntry(
      builder: (context) => Positioned(
        width: MediaQuery.of(context).size.width - 32,
        child: CompositedTransformFollower(
          link: _filterLayerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 52),
          child: Material(
            elevation: 12,
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _filterSearchResults.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 48),
                itemBuilder: (context, index) {
                  final item = _filterSearchResults[index];
                  final name = _filterType == 'Customer'
                      ? (item['name'] as String? ?? 'Unknown Customer')
                      : (item['company_name'] as String? ?? item['name'] as String? ?? 'Unknown Supplier');
                  final sub = (item['phone'] as String? ?? '');

                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                      child: Text(
                        name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: sub.isNotEmpty ? Text(sub) : null,
                    onTap: () => _selectFilter(item),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_filterOverlay!);
  }

  // ── Load Dues ────────────────────────────────────────────────────────────────

  Future<void> _loadDues() async {
    final pharmacyId = _currentPharmacyId;
    if (pharmacyId == null || pharmacyId.isEmpty) return;

    setState(() => _isLoadingDues = true);
    try {
      if (_filterType == 'Customer') {
        await _loadCustomerDues(pharmacyId);
      } else {
        await _loadSupplierDues(pharmacyId);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingDues = false);
        _showSnack('Failed to load dues: $e', Colors.red);
      }
    }
  }

  Future<void> _loadCustomerDues(String pharmacyId) async {
    final dues = await DueService.fetchCustomerDues(
      pharmacyId: pharmacyId,
      filterId: _selectedFilterId,
    );

    if (mounted) {
      setState(() {
        _dueList = dues;
        _isLoadingDues = false;
      });
    }
  }

  Future<void> _loadSupplierDues(String pharmacyId) async {
    final dues = await DueService.fetchSupplierDues(
      pharmacyId: pharmacyId,
      filterId: _selectedFilterId,
    );

    if (mounted) {
      setState(() {
        _dueList = dues;
        _isLoadingDues = false;
      });
    }
  }

  // ── Search ───────────────────────────────────────────────────────────────────

  Future<void> _searchFilter(String query) async {
    final pharmacyId = _currentPharmacyId;
    if (pharmacyId == null || query.trim().isEmpty) {
      _removeFilterOverlay();
      setState(() => _filterSearchResults = []);
      return;
    }

    setState(() => _isSearchingFilter = true);
    try {
      final results = await DueService.searchFilterEntities(
        pharmacyId: pharmacyId,
        filterType: _filterType,
        query: query.trim(),
      );

      if (mounted) {
        setState(() {
          _filterSearchResults = results;
          _isSearchingFilter = false;
        });
        _showFilterOverlay();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSearchingFilter = false);
      }
    }
  }

  void _selectFilter(Map<String, dynamic> item) {
    _removeFilterOverlay();
    setState(() {
      _selectedFilterId = item['id']?.toString();
      if (_filterType == 'Customer') {
        _selectedFilterName = item['name']?.toString() ?? 'Customer';
      } else {
        _selectedFilterName = (item['company_name'] as String?)?.trim().isNotEmpty == true
            ? item['company_name']
            : item['name']?.toString() ?? 'Supplier';
      }
      _filterSearchController.clear();
      _filterSearchResults = [];
    });
    _loadDues();
  }

  void _clearFilter() {
    setState(() {
      _selectedFilterId = null;
      _selectedFilterName = null;
      _filterSearchController.clear();
      _filterSearchResults = [];
    });
    _loadDues();
  }

  void _switchFilterType(String type) {
    if (_filterType == type) return;
    _removeFilterOverlay();
    setState(() {
      _filterType = type;
      _selectedFilterId = null;
      _selectedFilterName = null;
      _filterSearchController.clear();
      _filterSearchResults = [];
      _expandedId = null;
    });
    _loadDues();
  }

  // ── Save Payment ─────────────────────────────────────────────────────────────

  // ── Save Payment ─────────────────────────────────────────────────────────────

  Future<void> _savePayment(
    Map<String, dynamic> dueEntry, {
    required List<String> selectedInvoiceIds,
    required double payingAmount,
  }) async {
    final id = dueEntry['id'] as String;
    final netDue = (dueEntry['net_due'] as num?)?.toDouble() ?? 0.0;
    final paying = payingAmount;

    if (paying <= 0) {
      _showSnack('Enter a valid payment amount.', Colors.black87);
      return;
    }

    if (paying > netDue + 0.001) {
      _showSnack('Payment cannot exceed due amount.', Colors.red);
      return;
    }

    final pharmacyId = _currentPharmacyId;
    if (pharmacyId == null) {
      _showSnack('Pharmacy context missing.', Colors.red);
      return;
    }

    setState(() => _isSavingPayment[id] = true);

    try {
      await DueService.recordDuePayment(
        pharmacyId: pharmacyId,
        filterType: _filterType,
        id: id,
        paying: paying,
        netDue: netDue,
        selectedInvoiceIds: selectedInvoiceIds,
      );

      if (mounted) {
        setState(() {
          _isSavingPayment[id] = false;
          _expandedId = null;
        });
        _showSnack('Payment saved successfully! \u2705', AppColors.success);
        await _loadDues();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingPayment[id] = false);
        _showSnack('Payment failed: $e', Colors.red);
      }
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  String _fmt(double v) => v.toStringAsFixed(2);

  double get _totalDue => _dueList.fold(0.0, (s, e) => s + (e['net_due'] as double));

  // ── Due List Section ─────────────────────────────────────────────────────────

  Widget _buildDueListSection() {
    return _isLoadingDues
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _loadDues,
            child: _dueList.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.45,
                        child: DueEmptyState(filterType: _filterType),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 80),
                    itemCount: _dueList.length,
                    itemBuilder: (context, index) {
                      final entry = _dueList[index];
                      final id = entry['id'] as String;
                      final isExpanded = _expandedId == id;

                      return DueCard(
                        entry: entry,
                        filterType: _filterType,
                        pharmacyId: _currentPharmacyId ?? '',
                        isExpanded: isExpanded,
                        isSaving: _isSavingPayment[id] ?? false,
                        onTap: () {
                          setState(() {
                            if (isExpanded) {
                              _expandedId = null;
                            } else {
                              _expandedId = id;
                            }
                          });
                        },
                        onConfirm: ({
                          required List<String> selectedInvoiceIds,
                          required double payingAmount,
                        }) => _savePayment(
                          entry,
                          selectedInvoiceIds: selectedInvoiceIds,
                          payingAmount: payingAmount,
                        ),
                      );
                    },
                  ),
          );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: MediAppBar(title: 'Due Payments'),
      endDrawer: const AppDrawer(),
      body: Column(
        children: [
          // ── Curved container — seamless AppBar extension ──────────────
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Tab Toggle ──────────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: ['Customer', 'Company'].map((type) {
                      final selected = _filterType == type;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            _switchFilterType(type);
                            _pageController.animateToPage(
                              type == 'Customer' ? 0 : 1,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selected ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.08),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  type == 'Customer' ? Icons.person_outline : Icons.business_outlined,
                                  size: 16,
                                  color: selected ? AppColors.primary : Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  type == 'Customer' ? 'Customer Due' : 'Supplier Due',
                                  style: TextStyle(
                                    color: selected ? AppColors.primary : Colors.white,
                                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 12),

                // ── Filter Search / Selected Chip ───────────────────────
                if (_selectedFilterId != null)
                  DueSelectedChip(
                    label: _selectedFilterName ?? '',
                    icon: _filterType == 'Customer' ? Icons.person : Icons.business,
                    onClear: _clearFilter,
                  )
                else
                  CompositedTransformTarget(
                    link: _filterLayerLink,
                    child: TextField(
                      controller: _filterSearchController,
                      onChanged: _searchFilter,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: _filterType == 'Customer'
                            ? 'Search customer by name or phone...'
                            : 'Search company by name...',
                        hintStyle: const TextStyle(color: Colors.white70),
                        prefixIcon: const Icon(Icons.search, color: Colors.white70),
                        suffixIcon: _isSearchingFilter
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : _filterSearchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, color: Colors.white70, size: 18),
                                    onPressed: () {
                                      _removeFilterOverlay();
                                      _filterSearchController.clear();
                                      setState(() => _filterSearchResults = []);
                                    },
                                  )
                                : null,
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.2),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Total Due Summary Card ────────────────────────────────────
          if (!_isLoadingDues && _dueList.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _filterType == 'Customer' ? 'Total Customer Due' : 'Total Supplier Due',
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_dueList.length} ${_filterType == 'Customer' ? 'customer' : 'supplier'}${_dueList.length != 1 ? 's' : ''} with pending dues',
                              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FittedBox(
                        child: Text(
                          'TK ${_fmt(_totalDue)}',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Due List (swipeable Customer ↔ Supplier) ───────────────────
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                final newType = index == 0 ? 'Customer' : 'Company';
                _switchFilterType(newType);
              },
              children: [
                _buildDueListSection(),
                _buildDueListSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}