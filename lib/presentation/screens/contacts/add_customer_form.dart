import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../data/services/supabase_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common/medi_app_bar.dart';

class AddCustomerForm extends StatefulWidget {
  final Map<String, dynamic>? data;

  const AddCustomerForm({super.key, this.data});

  @override
  State<AddCustomerForm> createState() => _AddCustomerFormState();
}

class _AddCustomerFormState extends State<AddCustomerForm> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = SupabaseService.instance.client;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _isSaving = false;
  bool get _isEditMode => widget.data != null;

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      _nameCtrl.text = widget.data!['name'] ?? widget.data!['customer_name'] ?? '';
      _phoneCtrl.text = widget.data!['phone'] ?? '';
      _addressCtrl.text = widget.data!['address'] ?? '';
      _emailCtrl.text = widget.data!['email'] ?? '';
      _notesCtrl.text = widget.data!['notes'] ?? '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _emailCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final auth = context.read<AuthProvider>();
      final pharmacyId = auth.currentProfile?.pharmacyId;

      if (pharmacyId == null || pharmacyId.isEmpty) {
        throw Exception('Pharmacy ID not found. Please log in again.');
      }

      final payload = {
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'address': _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'pharmacy_id': pharmacyId,
      };

      Map<String, dynamic>? resultCustomer;
      if (_isEditMode) {
        final id = widget.data!['id'] ?? widget.data!['customer_id'];
        final res = await _supabase
            .from(SupabaseConstants.customersTable)
            .update(payload)
            .eq('id', id)
            .select()
            .maybeSingle();
        resultCustomer = res;
      } else {
        final res = await _supabase
            .from(SupabaseConstants.customersTable)
            .insert(payload)
            .select()
            .single();
        resultCustomer = res;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditMode ? 'Customer updated! ✅' : 'Customer added! ✅'),
          backgroundColor: AppColors.primary,
        ),
      );

      Navigator.pop(context, resultCustomer ?? true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MediAppBar(title: _isEditMode ? 'Edit Customer' : 'Add Customer'),
      endDrawer: const AppDrawer(),
body: SingleChildScrollView(
        child: Column(
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
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildField(
                      _nameCtrl,
                      'Customer Name *',
                      Icons.person,
                      required: true,
                    ),
                    _buildField(
                      _phoneCtrl,
                      'Phone Number',
                      Icons.phone,
                      keyboardType: TextInputType.phone,
                    ),
                    _buildField(
                      _addressCtrl,
                      'Address',
                      Icons.location_on,
                    ),
                    _buildField(
                      _emailCtrl,
                      'Email (Optional)',
                      Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    _buildField(
                      _notesCtrl,
                      'Notes (Optional)',
                      Icons.notes_rounded,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 30),
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
                                _isEditMode ? 'Update Customer' : 'Save Customer',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool required = false,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: AppColors.primary),
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        ),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
            : null,
      ),
    );
  }
}
