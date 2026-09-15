import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../data/services/supabase_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common/medi_app_bar.dart';

class _ContactEntry {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController phoneCtrl = TextEditingController();
  final TextEditingController deptCtrl = TextEditingController();
  final TextEditingController notesCtrl = TextEditingController();

  void dispose() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    deptCtrl.dispose();
    notesCtrl.dispose();
  }
}

class AddCompanyForm extends StatefulWidget {
  final Map<String, dynamic>? data; // edit mode company data
  final bool addContactOnly; // add contact only mode
  final Map<String, dynamic>? editContactData; // contact edit mode
  final Map<String, dynamic>? preSelectedCompany; // pre-selected company
  final String? preSelectedLocalName; // pre-selected company name

  const AddCompanyForm({
    super.key,
    this.data,
    this.addContactOnly = false,
    this.editContactData,
    this.preSelectedCompany,
    this.preSelectedLocalName,
  });

  @override
  State<AddCompanyForm> createState() => _AddCompanyFormState();
}

class _AddCompanyFormState extends State<AddCompanyForm> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = SupabaseService.instance.client;

  final _companyNameCtrl = TextEditingController();
  final List<_ContactEntry> _contacts = [];

  List<String> _searchResults = [];
  bool _isSearching = false;
  bool _showDropdown = false;
  bool _isLocalCompany = false;
  bool _isSaving = false;

  final FocusNode _companyFocus = FocusNode();

  bool get _isEditMode =>
      widget.data != null && widget.editContactData == null && !widget.addContactOnly;

  @override
  void initState() {
    super.initState();

    if (_isEditMode) {
      _companyNameCtrl.text = widget.data!['company_name'] ?? '';
      _isLocalCompany = widget.data!['is_local'] == true;
    }

    if (widget.preSelectedCompany != null) {
      _companyNameCtrl.text = widget.preSelectedCompany!['company_name'] ?? '';
    }

    if (widget.preSelectedLocalName != null) {
      _companyNameCtrl.text = widget.preSelectedLocalName!;
      _isLocalCompany = true;
    }

    if (widget.editContactData != null) {
      final c = _ContactEntry();
      c.nameCtrl.text = widget.editContactData!['name'] ?? '';
      c.phoneCtrl.text = widget.editContactData!['phone'] ?? '';
      c.deptCtrl.text = widget.editContactData!['department'] ??
          widget.editContactData!['email'] ??
          '';
      c.notesCtrl.text = widget.editContactData!['notes'] ??
          widget.editContactData!['address'] ??
          '';
      _contacts.add(c);
      _companyNameCtrl.text = widget.editContactData!['company_name'] ??
          widget.editContactData!['contact_company_name'] ??
          '';
    } else {
      _contacts.add(_ContactEntry());
    }

    _companyFocus.addListener(() {
      if (!_companyFocus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _showDropdown = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _companyNameCtrl.dispose();
    _companyFocus.dispose();
    for (final c in _contacts) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _onCompanyTyped(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = [];
        _showDropdown = false;
        _isLocalCompany = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _showDropdown = true;
    });

    try {
      final Set<String> matchedCompanies = {};

      // 1. Search existing suppliers in this pharmacy
      final auth = context.read<AuthProvider>();
      final pharmacyId = auth.currentProfile?.pharmacyId;

      if (pharmacyId != null) {
        final supplierRows = await _supabase
            .from(SupabaseConstants.suppliersTable)
            .select('company_name')
            .eq('pharmacy_id', pharmacyId)
            .ilike('company_name', '%$trimmed%')
            .limit(8);

        for (final r in (supplierRows as List)) {
          final cn = r['company_name']?.toString().trim();
          if (cn != null && cn.isNotEmpty) matchedCompanies.add(cn);
        }
      }

      // 2. Also search global medicines catalog for company names
      final globalRows = await _supabase
          .from(SupabaseConstants.globalMedicinesTable)
          .select('company')
          .ilike('company', '%$trimmed%')
          .limit(8);

      for (final r in (globalRows as List)) {
        final cn = r['company']?.toString().trim();
        if (cn != null && cn.isNotEmpty) matchedCompanies.add(cn);
      }

      if (mounted) {
        setState(() {
          _searchResults = matchedCompanies.toList()..sort();
          _isSearching = false;
          _showDropdown = true;
          _isLocalCompany = _searchResults.isEmpty;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _selectFromDropdown(String companyName) {
    setState(() {
      _companyNameCtrl.text = companyName;
      _searchResults = [];
      _showDropdown = false;
      _isLocalCompany = false;
    });
    _companyFocus.unfocus();
  }

  void _addContactRow() => setState(() => _contacts.add(_ContactEntry()));

  void _removeContactRow(int index) {
    setState(() {
      _contacts[index].dispose();
      _contacts.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final company = _companyNameCtrl.text.trim();
    if (company.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a company name'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final auth = context.read<AuthProvider>();
      final pharmacyId = auth.currentProfile?.pharmacyId;

      if (pharmacyId == null || pharmacyId.isEmpty) {
        throw Exception('Pharmacy ID not found. Please log in again.');
      }

      // 1. Single contact edit mode
      if (widget.editContactData != null) {
        final contactId = widget.editContactData!['id'].toString();
        final c = _contacts.first;
        await _supabase.from(SupabaseConstants.suppliersTable).update({
          'company_name': company,
          'name': c.nameCtrl.text.trim(),
          'phone': c.phoneCtrl.text.trim().isEmpty ? null : c.phoneCtrl.text.trim(),
          'email': c.deptCtrl.text.trim().isEmpty ? null : c.deptCtrl.text.trim(),
          'address': c.notesCtrl.text.trim().isEmpty ? null : c.notesCtrl.text.trim(),
        }).eq('id', contactId);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact updated! ✅'), backgroundColor: AppColors.primary),
        );
        Navigator.pop(context, true);
        return;
      }

      // 2. Edit Company Name for all existing records
      if (_isEditMode && widget.data != null) {
        final oldName = widget.data!['company_name']?.toString() ?? '';
        if (oldName.isNotEmpty && oldName != company) {
          await _supabase
              .from(SupabaseConstants.suppliersTable)
              .update({'company_name': company})
              .eq('pharmacy_id', pharmacyId)
              .eq('company_name', oldName);
        }
      }

      // 3. Insert new contacts
      for (final c in _contacts) {
        final name = c.nameCtrl.text.trim();
        if (name.isEmpty) continue;

        await _supabase.from(SupabaseConstants.suppliersTable).insert({
          'pharmacy_id': pharmacyId,
          'company_name': company,
          'name': name,
          'phone': c.phoneCtrl.text.trim().isEmpty ? null : c.phoneCtrl.text.trim(),
          'email': c.deptCtrl.text.trim().isEmpty ? null : c.deptCtrl.text.trim(),
          'address': c.notesCtrl.text.trim().isEmpty ? null : c.notesCtrl.text.trim(),
          'current_due': 0.0,
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.addContactOnly
              ? 'Contact added! ✅'
              : _isEditMode
                  ? 'Updated! ✅'
                  : 'Company & Contacts saved! ✅'),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }


  String get _pageTitle {
    if (widget.addContactOnly) return 'Add Contact';
        if (_isEditMode) return 'Edit Company';
        return 'New Contact / Company';
      }
  @override
  Widget build(BuildContext context) {
    final bool companyNameLocked = widget.addContactOnly ||
        widget.preSelectedCompany != null ||
        widget.preSelectedLocalName != null;

    return Scaffold(
      appBar: MediAppBar(title: _pageTitle),
      endDrawer: const AppDrawer(),
      body: GestureDetector(
        onTap: () {
          _companyFocus.unfocus();
          setState(() => _showDropdown = false);
        },
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Curved primary container — seamless extension of AppBar
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: const SizedBox.shrink(),
              ),

              Padding(
                padding: const EdgeInsets.all(18),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- 1. Company Name Field ---
                      const Text(
                        'Company Details',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                      ),
                      const SizedBox(height: 8),

                      TextFormField(
                        controller: _companyNameCtrl,
                        focusNode: _companyFocus,
                        readOnly: companyNameLocked,
                        onChanged: _onCompanyTyped,
                        decoration: InputDecoration(
                          labelText: 'Company Name *',
                          hintText: 'e.g. Square, Beximco, Incepta...',
                          prefixIcon: const Icon(Icons.business_rounded, color: AppColors.primary),
                          suffixIcon: _isSearching
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                  ),
                                )
                              : (_isLocalCompany && !companyNameLocked
                                  ? const Tooltip(
                                      message: 'Local custom company',
                                      child: Icon(Icons.info_outline, color: Colors.orange, size: 20),
                                    )
                                  : null),
                          filled: true,
                          fillColor: companyNameLocked ? Colors.grey.shade200 : Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Company name is required' : null,
                      ),

                      // Company Autocomplete Dropdown
                      if (_showDropdown && _searchResults.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: _searchResults.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final name = _searchResults[i];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.apartment_rounded, color: AppColors.primary, size: 20),
                                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                                onTap: () => _selectFromDropdown(name),
                              );
                            },
                          ),
                        ),

                      const SizedBox(height: 24),

                      // --- 2. Contact Persons Section Header ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Representatives / Contacts',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                          ),
                          if (widget.editContactData == null)
                            TextButton.icon(
                              onPressed: _addContactRow,
                              icon: const Icon(Icons.add_rounded, size: 18, color: AppColors.primary),
                              label: const Text(
                                '+ Add More',
                                style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // List of Contact Entries
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _contacts.length,
                        itemBuilder: (context, index) {
                          final c = _contacts[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_contacts.length > 1)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Contact #${index + 1}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close_rounded, size: 18, color: Colors.redAccent),
                                        onPressed: () => _removeContactRow(index),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                    ],
                                  ),
                                if (_contacts.length > 1) const SizedBox(height: 10),

                                // Contact Person Name
                                _buildTextField(
                                  controller: c.nameCtrl,
                                  label: 'Contact Person Name *',
                                  icon: Icons.person_rounded,
                                  isRequired: true,
                                ),
                                const SizedBox(height: 12),

                                // Phone
                                _buildTextField(
                                  controller: c.phoneCtrl,
                                  label: 'Phone Number',
                                  icon: Icons.phone_rounded,
                                  keyboardType: TextInputType.phone,
                                ),
                                const SizedBox(height: 12),

                                // Department / Designation
                                _buildTextField(
                                  controller: c.deptCtrl,
                                  label: 'Department / Designation (e.g. MPO, Manager)',
                                  icon: Icons.badge_rounded,
                                ),
                                const SizedBox(height: 12),

                                // Notes
                                _buildTextField(
                                  controller: c.notesCtrl,
                                  label: 'Notes / Address',
                                  icon: Icons.notes_rounded,
                                  maxLines: 2,
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 20),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 3,
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  widget.editContactData != null
                                      ? 'Update Contact'
                                      : _isEditMode
                                          ? 'Update Company'
                                          : 'Save Contacts',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isRequired = false,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      ),
      validator: isRequired
          ? (v) => (v == null || v.trim().isEmpty) ? 'This field is required' : null
          : null,
    );
  }
}
