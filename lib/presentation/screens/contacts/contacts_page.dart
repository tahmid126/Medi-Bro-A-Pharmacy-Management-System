import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_drawer.dart';
import 'add_company_form.dart';
import 'add_customer_form.dart';

import '../../../data/services/contacts_service.dart';
import '../../widgets/contacts/customer_card.dart';
import '../../widgets/contacts/company_card.dart';
import '../../widgets/contacts/contacts_empty_state.dart';
import '../../widgets/common/medi_app_bar.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {

  String _tab = 'Customer';
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _list = [];
  bool _isLoading = false;
  String? _expandedId;
  final Map<String, List<Map<String, dynamic>>> _companyContacts = {};

  // Company search dropdown
  List<Map<String, dynamic>> _searchDropdown = [];
  Map<String, dynamic>? _globalOnlyResult;
  bool _isSearching = false;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _switchTab(String type) {
    if (_tab == type) return;
    setState(() {
      _tab = type;
      _expandedId = null;
      _searchController.clear();
      _searchDropdown = [];
      _globalOnlyResult = null;
    });
    _load();
  }

  Future<void> _load({String query = ''}) async {
    setState(() => _isLoading = true);
    try {
      final auth = context.read<AuthProvider>();
      final pharmacyId = auth.currentProfile?.pharmacyId;

      if (pharmacyId == null || pharmacyId.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      if (_tab == 'Customer') {
        final data = await ContactsService.fetchCustomers(
          pharmacyId: pharmacyId,
          query: query,
        );
        if (mounted) {
          setState(() {
            _list = data;
            _isLoading = false;
          });
        }
      } else {
        final result = await ContactsService.fetchSuppliersGroupedByCompany(
          pharmacyId: pharmacyId,
          query: query,
        );
        if (mounted) {
          setState(() {
            _companyContacts.clear();
            _companyContacts.addAll(result.companyContacts);
            _list = result.uniqueCompanies;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnack('Failed to load: $e', Colors.red);
      }
    }
  }

  Future<void> _onSearch(String query) async {
    final trimmed = query.trim();
    if (_tab == 'Customer') {
      _load(query: trimmed);
      return;
    }

    if (trimmed.isEmpty) {
      setState(() {
        _searchDropdown = [];
        _globalOnlyResult = null;
        _isSearching = false;
      });
      _load();
      return;
    }

    setState(() => _isSearching = true);

    try {

      // 1. Search existing company contacts in this shop
      final inMyContacts = _list.where((c) {
        final name = (c['company_name'] ?? '').toString().toLowerCase();
        return name.contains(trimmed.toLowerCase());
      }).toList();

      // 2. Search global catalog for potential new companies via ContactsService
      Map<String, dynamic>? globalOnly;
      final globalCompanies = await ContactsService.searchGlobalCompanies(trimmed);
      for (final gName in globalCompanies) {
        final alreadyInShop = inMyContacts.any((c) =>
            (c['company_name'] ?? '').toString().toLowerCase() == gName.toLowerCase());
        if (!alreadyInShop) {
          globalOnly = {'company_name': gName, 'is_local': false};
          break;
        }
      }

      if (mounted) {
        setState(() {
          _searchDropdown = inMyContacts;
          _globalOnlyResult = globalOnly;
          _isSearching = false;
        });
      }

      _load(query: trimmed);
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _deleteCustomer(String id) async {
    try {
      await ContactsService.deleteCustomer(id);
      _showSnack('Customer deleted', Colors.orange);
      _load(query: _searchController.text);
    } catch (e) {
      _showSnack('Delete failed: $e', Colors.red);
    }
  }

  Future<void> _deleteCompanyContacts(Map<String, dynamic> company) async {
    try {
      final auth = context.read<AuthProvider>();
      final pharmacyId = auth.currentProfile?.pharmacyId;
      final cName = company['company_name']?.toString() ?? '';

      if (pharmacyId != null && cName.isNotEmpty) {
        await ContactsService.deleteCompanyContacts(
          pharmacyId: pharmacyId,
          companyName: cName,
        );
      }

      _showSnack('Company contacts deleted', Colors.orange);
      _load(query: _searchController.text);
    } catch (e) {
      _showSnack('Delete failed: $e', Colors.red);
    }
  }

  Future<void> _deleteSingleSupplier(String id) async {
    try {
      await ContactsService.deleteSingleSupplier(id);
      _showSnack('Contact deleted', Colors.orange);
      _load(query: _searchController.text);
    } catch (e) {
      _showSnack('Delete failed: $e', Colors.red);
    }
  }

  void _confirmDelete(
    String id,
    String name, {
    bool isCompany = false,
    Map<String, dynamic>? companyData,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete $name?'),
        content: Text(
          isCompany
              ? 'This will delete all your contacts under this company.'
              : 'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (isCompany && companyData != null) {
                _deleteCompanyContacts(companyData);
              } else {
                _deleteCustomer(id);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MediAppBar(title: 'Contacts'),
      endDrawer: const AppDrawer(),
      body: Column(
        children: [
          // --- Seamless Curved Primary Header ---
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
                // 1. Tab Toggle (Customer vs Company)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: ['Customer', 'Company'].map((type) {
                      final selected = _tab == type;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_tab != type) {
                              _switchTab(type);
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
                                  type == 'Customer' ? 'Customers' : 'Companies',
                                  style: TextStyle(
                                    color: selected ? AppColors.primary : Colors.white,
                                    fontWeight: selected ? FontWeight.bold : FontWeight.w600,
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

                // 2. Search Bar + Add Button
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearch,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: _tab == 'Customer'
                              ? 'Search by name, phone or address...'
                              : 'Search company name...',
                          hintStyle: const TextStyle(color: Colors.white60),
                          prefixIcon: const Icon(Icons.search, color: Colors.white70),
                          suffixIcon: _isSearching
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  ),
                                )
                              : _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, color: Colors.white70, size: 18),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {
                                          _searchDropdown = [];
                                          _globalOnlyResult = null;
                                        });
                                        _load();
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
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _tab == 'Customer'
                                ? const AddCustomerForm()
                                : const AddCompanyForm(),
                          ),
                        ).then((result) {
                          if (result != null && result != false) {
                            _searchController.clear();
                            setState(() {
                              _searchDropdown = [];
                              _globalOnlyResult = null;
                            });
                            _load();
                          }
                        });
                      },
                      child: Container(
                        height: 48,
                        width: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                        ),
                        child: const Icon(
                          Icons.person_add_alt_1_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),

                // 3. Search Dropdown Quick Action (Company Tab)
                if (_tab == 'Company' && _searchController.text.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  if (_globalOnlyResult != null)
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddCompanyForm(preSelectedCompany: _globalOnlyResult),
                          ),
                        ).then((result) {
                          if (result == true) {
                            _searchController.clear();
                            setState(() {
                              _searchDropdown = [];
                              _globalOnlyResult = null;
                            });
                            _load();
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.add_business_rounded, color: Colors.white, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Add "${_globalOnlyResult!['company_name']}" as new company',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
                          ],
                        ),
                      ),
                    ),

                  if (_globalOnlyResult == null && _searchDropdown.isEmpty && !_isSearching)
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddCompanyForm(preSelectedLocalName: _searchController.text.trim()),
                          ),
                        ).then((result) {
                          if (result == true) {
                            _searchController.clear();
                            setState(() {
                              _searchDropdown = [];
                              _globalOnlyResult = null;
                            });
                            _load();
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.add_circle_outline, color: Colors.white, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Add "${_searchController.text}" as new contact',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),

          // --- Contact List (swipeable Customer ↔ Company) ---
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                final newType = index == 0 ? 'Customer' : 'Company';
                _switchTab(newType);
              },
              children: [
                _buildContactsListSection(),
                _buildContactsListSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactsListSection() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _load(query: _searchController.text),
      child: _list.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: ContactsEmptyState(tab: _tab),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: _list.length,
              itemBuilder: (context, index) {
                final item = _list[index];
                if (_tab == 'Customer') {
                  return CustomerCard(
                    data: item,
                    isExpanded: _expandedId == item['id'],
                    onTap: () => setState(() {
                      _expandedId = _expandedId == item['id'] ? null : item['id'];
                    }),
                    onEdit: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AddCustomerForm(data: item)),
                      ).then((result) {
                        if (result == true) _load(query: _searchController.text);
                      });
                    },
                    onDelete: () => _confirmDelete(
                      item['id'].toString(),
                      item['name'] ?? 'this customer',
                    ),
                  );
                } else {
                  // Company card
                  final cardKey = item['company_name'] as String;
                  final contacts = _companyContacts[cardKey] ?? [];

                  return CompanyCard(
                    data: item,
                    contacts: contacts,
                    isExpanded: _expandedId == cardKey,
                    onTap: () => setState(() {
                      _expandedId = _expandedId == cardKey ? null : cardKey;
                    }),
                    onEdit: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AddCompanyForm(data: item)),
                      ).then((result) {
                        if (result == true) _load(query: _searchController.text);
                      });
                    },
                    onDelete: () => _confirmDelete(
                      cardKey,
                      item['company_name'] ?? 'this company',
                      isCompany: true,
                      companyData: item,
                    ),
                    onAddContact: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddCompanyForm(
                            data: item,
                            addContactOnly: true,
                            preSelectedLocalName: cardKey,
                          ),
                        ),
                      ).then((result) {
                        if (result == true) _load(query: _searchController.text);
                      });
                    },
                    onEditContact: (contact) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddCompanyForm(
                            data: item,
                            editContactData: contact,
                          ),
                        ),
                      ).then((result) {
                        if (result == true) _load(query: _searchController.text);
                      });
                    },
                    onDeleteContact: (contactId) => _deleteSingleSupplier(contactId),
                  );
                }
              },
            ),
    );
  }
}
