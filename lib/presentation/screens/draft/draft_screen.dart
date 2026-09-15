import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/services/supabase_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/services/draft_service.dart';
import '../../widgets/app_drawer.dart';
import '../pos/pos_sale_screen.dart';
import '../purchases/purchase_entry_screen.dart';

import '../../widgets/draft/draft_card.dart';
import '../../widgets/draft/draft_selected_chip.dart';
import '../../widgets/draft/draft_empty_state.dart';
import '../../widgets/common/medi_app_bar.dart';

class DraftScreen extends StatefulWidget {
  const DraftScreen({super.key});

  @override
  State<DraftScreen> createState() => _DraftScreenState();
}

// Typedef to ensure backward compatibility if referenced as ExportDraft
typedef ExportDraft = DraftScreen;

class _DraftScreenState extends State<DraftScreen> {
  final _client = SupabaseService.instance.client;

  // Tab: 'Customer' = export drafts, 'Company' = import drafts
  String _filterType = 'Customer';

  // Search state
  final TextEditingController _filterSearchController = TextEditingController();
  String? _selectedFilterId;
  String? _selectedFilterName;
  List<Map<String, dynamic>> _filterSearchResults = [];
  bool _isSearchingFilter = false;

  // Draft list
  List<Map<String, dynamic>> _drafts = [];
  bool _isLoadingDrafts = false;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadDrafts();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _filterSearchController.dispose();
    super.dispose();
  }

  void _switchFilterType(String type) {
    if (_filterType == type) return;
    setState(() {
      _filterType = type;
      _selectedFilterId = null;
      _selectedFilterName = null;
      _filterSearchController.clear();
      _filterSearchResults = [];
    });
    _loadDrafts();
  }

  // ── Load Drafts ──────────────────────────────────────────────────────────────

  Future<void> _loadDrafts() async {
    setState(() => _isLoadingDrafts = true);
    try {
      if (_filterType == 'Customer') {
        final data = await DraftService.getExportDrafts(
          customerId: _selectedFilterId,
          filterName: _selectedFilterName,
          searchQuery: _filterSearchController.text,
        );
        if (mounted) {
          setState(() {
            _drafts = data;
            _isLoadingDrafts = false;
          });
        }
      } else {
        final data = await DraftService.getImportDrafts(
          supplierId: _selectedFilterId,
          filterName: _selectedFilterName,
          searchQuery: _filterSearchController.text,
        );
        if (mounted) {
          setState(() {
            _drafts = data;
            _isLoadingDrafts = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingDrafts = false);
        _showSnack('Failed to load drafts: $e', Colors.red);
      }
    }
  }

  // ── Filter Search ────────────────────────────────────────────────────────────

  Future<void> _searchFilter(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() => _filterSearchResults = []);
      _loadDrafts();
      return;
    }
    setState(() => _isSearchingFilter = true);
    _loadDrafts(); // Live filter list below simultaneously

    try {
      final seenNames = <String>{};
      final results = <Map<String, dynamic>>[];

      if (_filterType == 'Customer') {
        // 1. Gather from existing export drafts first
        final drafts = await DraftService.getExportDrafts();
        for (final d in drafts) {
          final cName = (d['customer_name'] ?? d['customer']?['customer_name'] ?? '').toString().trim();
          final phone = (d['customer_phone'] ?? d['customer']?['phone'] ?? '').toString().trim();
          if (cName.isNotEmpty &&
              (cName.toLowerCase().contains(trimmed.toLowerCase()) || phone.contains(trimmed)) &&
              !seenNames.contains(cName.toLowerCase())) {
            seenNames.add(cName.toLowerCase());
            results.add({
              'id': d['customer_id'],
              'name': cName,
              'phone': phone,
            });
          }
        }

        // 2. Query customers table
        try {
          final data = await _client
              .from('customers')
              .select('id, name, phone')
              .or('name.ilike.%$trimmed%,phone.ilike.%$trimmed%')
              .limit(10);
          for (final c in data as List) {
            final name = (c['name'] ?? '').toString().trim();
            if (name.isNotEmpty && !seenNames.contains(name.toLowerCase())) {
              seenNames.add(name.toLowerCase());
              results.add({
                'id': c['id'],
                'name': name,
                'phone': (c['phone'] ?? '').toString(),
              });
            }
          }
        } catch (_) {}

      } else {
        // --- COMPANY TAB ---
        // 1. Gather from existing import drafts first
        final drafts = await DraftService.getImportDrafts();
        for (final d in drafts) {
          final compName = (d['supplier_name'] ?? d['supplier']?['company_name'] ?? '').toString().trim();
          if (compName.isNotEmpty &&
              compName.toLowerCase().contains(trimmed.toLowerCase()) &&
              !seenNames.contains(compName.toLowerCase())) {
            seenNames.add(compName.toLowerCase());
            results.add({
              'id': d['supplier_id'],
              'company_name': compName,
              'name': compName,
            });
          }
        }

        // 2. Query suppliers table (Strict deduplication to prevent duplicate names!)
        try {
          final data = await _client
              .from('suppliers')
              .select('id, name, company_name')
              .or('name.ilike.%$trimmed%,company_name.ilike.%$trimmed%')
              .limit(15);
          for (final s in data as List) {
            final compName = (s['company_name'] ?? s['name'] ?? '').toString().trim();
            if (compName.isNotEmpty && !seenNames.contains(compName.toLowerCase())) {
              seenNames.add(compName.toLowerCase());
              results.add({
                'id': s['id'],
                'company_name': compName,
                'name': compName,
              });
            }
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _filterSearchResults = results;
          _isSearchingFilter = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSearchingFilter = false);
    }
  }

  void _selectFilter(Map<String, dynamic> item) {
    setState(() {
      if (_filterType == 'Customer') {
        _selectedFilterId = item['id']?.toString() ?? item['customer_id']?.toString();
        _selectedFilterName = (item['name'] ?? item['customer_name'] ?? '').toString().trim();
      } else {
        _selectedFilterId = item['id']?.toString() ?? item['company_id']?.toString();
        _selectedFilterName = (item['company_name'] ?? item['name'] ?? '').toString().trim();
      }
      _filterSearchController.clear();
      _filterSearchResults = [];
    });
    _loadDrafts();
  }

  void _clearFilter() {
    setState(() {
      _selectedFilterId = null;
      _selectedFilterName = null;
      _filterSearchController.clear();
      _filterSearchResults = [];
    });
    _loadDrafts();
  }

  // ── Delete Draft ─────────────────────────────────────────────────────────────

  Future<void> _deleteDraft(String draftId) async {
    try {
      if (_filterType == 'Customer') {
        await DraftService.deleteExportDraft(draftId);
      } else {
        await DraftService.deleteImportDraft(draftId);
      }
      _showSnack('Draft deleted successfully! \u2705', Colors.orange);
      _loadDrafts();
    } catch (e) {
      _showSnack('Delete failed: $e', Colors.red);
    }
  }

  void _showDeleteDialog(String draftId, String draftName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Delete Draft", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Delete "$draftName"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteDraft(draftId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return 'Recent';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return DateFormat('MMM dd, yyyy \u2022 hh:mm a').format(dt);
    } catch (_) {
      return 'Recent';
    }
  }

  dynamic _itemsCount(Map<String, dynamic> draft) {
    if (draft['items_count'] != null) return draft['items_count'];
    if (draft['items'] is List) return (draft['items'] as List).length;
    final key = _filterType == 'Customer'
        ? 'export_draft_items'
        : 'import_draft_items';
    final raw = draft[key];
    if (raw is List && raw.isNotEmpty) return raw.first['count'];
    return 0;
  }

  String? _draftSubName(Map<String, dynamic> draft) {
    if (_filterType == 'Customer') {
      if (draft['customer_name'] != null && draft['customer_name'].toString().isNotEmpty) {
        return draft['customer_name'].toString();
      }
      final c = draft['customer'] as Map<String, dynamic>?;
      return (c?['customer_name'] ?? c?['name']) as String?;
    } else {
      if (draft['supplier_name'] != null && draft['supplier_name'].toString().isNotEmpty) {
        return draft['supplier_name'].toString();
      }
      final s = draft['supplier'] as Map<String, dynamic>?;
      return (s?['company_name'] ?? s?['name']) as String?;
    }
  }

  IconData get _subIcon =>
      _filterType == 'Customer' ? Icons.person_outline : Icons.business_outlined;

  IconData get _cardIcon => _filterType == 'Customer'
      ? Icons.receipt_long_outlined
      : Icons.inventory_2_outlined;

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: MediAppBar(title: 'Drafts'),
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
                            if (_filterType != type) {
                              _switchFilterType(type);
                              _pageController.animateToPage(
                                type == 'Customer' ? 0 : 1,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            }
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
                                )
                              ]
                                  : [],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  type == 'Customer'
                                      ? Icons.person_outline
                                      : Icons.business_outlined,
                                  size: 16,
                                  color: selected ? AppColors.primary : Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  type == 'Customer' ? 'Export' : 'Import',
                                  style: TextStyle(
                                    color: selected ? AppColors.primary : Colors.white,
                                    fontWeight: selected
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    fontSize: 12,
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
                  DraftSelectedChip(
                    label: _selectedFilterName ?? '',
                    icon: _filterType == 'Customer'
                        ? Icons.person
                        : Icons.business,
                    onClear: _clearFilter,
                  )
                else ...[
                  // Search bar
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _filterSearchController,
                          onChanged: _searchFilter,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: _filterType == 'Customer'
                                ? "Search customer by name or phone..."
                                : "Search company by name...",
                            hintStyle: const TextStyle(color: Colors.white60),
                            prefixIcon: const Icon(Icons.search, color: Colors.white70),
                            suffixIcon: _isSearchingFilter
                                ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              ),
                            )
                                : _filterSearchController.text.isNotEmpty
                                ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.white70, size: 18),
                              onPressed: () {
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
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 12),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ── Dropdown results ──────────────────────────────────
                  if (_filterSearchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
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
                        itemCount: _filterSearchResults.length,
                        separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 48),
                        itemBuilder: (context, index) {
                          final item = _filterSearchResults[index];
                          final name = _filterType == 'Customer'
                              ? (item['name'] ?? item['customer_name'] ?? '').toString()
                              : (item['company_name'] ?? item['name'] ?? '').toString();
                          final sub = _filterType == 'Customer'
                              ? (item['phone'] ?? '').toString()
                              : '';
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                              child: Text(
                                name.isNotEmpty
                                    ? name.substring(0, 1).toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            title: Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14)),
                            subtitle: sub.isNotEmpty ? Text(sub) : null,
                            onTap: () => _selectFilter(item),
                          );
                        },
                      ),
                    ),
                ],
              ],
            ),
          ),

          // ── Draft List (swipeable Export ↔ Import) ───────────────────
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                final newType = index == 0 ? 'Customer' : 'Company';
                _switchFilterType(newType);
              },
              children: [
                _buildDraftListSection(),
                _buildDraftListSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftListSection() {
    if (_isLoadingDrafts) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadDrafts,
      child: _drafts.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: DraftEmptyState(
                    filterType: _filterType,
                    cardIcon: _cardIcon,
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: _drafts.length,
              itemBuilder: (context, index) {
                final draft = _drafts[index];
                return DraftCard(
                  draft: draft,
                  draftName: draft['draft_name'] ?? 'Untitled Draft',
                  subName: _draftSubName(draft),
                  subIcon: _subIcon,
                  cardIcon: _cardIcon,
                  itemsCount: _itemsCount(draft),
                  formattedDate: _formatDate(draft['created_at']?.toString()),
                  onTap: () {
                    if (_filterType == 'Customer') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PosSaleScreen(
                            draftId: draft['draft_id'],
                          ),
                        ),
                      ).then((_) => _loadDrafts());
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PurchaseEntryScreen(
                            draftId: draft['draft_id'],
                          ),
                        ),
                      ).then((_) => _loadDrafts());
                    }
                  },
                  onDelete: () => _showDeleteDialog(
                    draft['draft_id'],
                    draft['draft_name'] ?? 'Draft',
                  ),
                );
              },
            ),
    );
  }
}