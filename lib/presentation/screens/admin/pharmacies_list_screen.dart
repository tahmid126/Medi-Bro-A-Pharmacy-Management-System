import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/services/admin_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common/medi_app_bar.dart';

class PharmaciesListScreen extends StatefulWidget {
  const PharmaciesListScreen({super.key});

  @override
  State<PharmaciesListScreen> createState() => _PharmaciesListScreenState();
}

class _PharmaciesListScreenState extends State<PharmaciesListScreen> {
  final AdminService _adminService = AdminService.instance;

  List<Map<String, dynamic>> _pharmacies = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchPharmacies();
  }

  Future<void> _fetchPharmacies() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final data = await _adminService.fetchPharmacies(searchQuery: _searchQuery);

      if (!mounted) return;
      setState(() {
        _pharmacies = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading pharmacies: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _togglePharmacyStatus(Map<String, dynamic> pharmacy) async {
    final String currentStatus = pharmacy['status'] ?? 'active';
    final bool isCurrentlyActive = currentStatus == 'active';
    final String nextStatus = isCurrentlyActive ? 'suspended' : 'active';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isCurrentlyActive ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
              color: isCurrentlyActive ? Colors.orange : const Color(0xFF10B981),
            ),
            const SizedBox(width: 8),
            Text(
              isCurrentlyActive ? 'Pause Pharmacy Activity?' : 'Resume Pharmacy Activity?',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          isCurrentlyActive
              ? 'Pausing "${pharmacy['name']}" will temporarily suspend store access.\n\nYou can resume access at any time.'
              : 'Resume store operational access for "${pharmacy['name']}"?',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isCurrentlyActive ? Colors.orange.shade700 : const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            child: Text(isCurrentlyActive ? 'Pause Access' : 'Resume Access'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _adminService.updatePharmacyStatus(
          pharmacyId: pharmacy['id'],
          nextStatus: nextStatus,
        );

        setState(() {
          pharmacy['status'] = nextStatus;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${pharmacy['name']} status updated to: ${nextStatus.toUpperCase()}',
            ),
            backgroundColor: isCurrentlyActive ? Colors.orange.shade800 : const Color(0xFF10B981),
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
  }

  void _showPharmacyDetailsModal(Map<String, dynamic> pharmacy) {
    final profile = pharmacy['profiles'] != null && (pharmacy['profiles'] as List).isNotEmpty
        ? pharmacy['profiles'][0]
        : null;

    final String name = pharmacy['name'] ?? 'Unnamed Store';
    final String address = pharmacy['address'] ?? 'No address provided';
    final String phone = pharmacy['phone'] ?? 'N/A';
    final String email = pharmacy['email'] ?? 'No email provided';
    final String drugLicense = pharmacy['license_no'] ?? pharmacy['drug_license_no'] ?? 'Not registered';
    final String status = pharmacy['status'] ?? 'active';
    final String plan = (pharmacy['plan_type'] ?? 'free_trial').toString().toUpperCase();
    final String createdAt = pharmacy['created_at'] != null
        ? DateFormat('dd MMMM yyyy, hh:mm a').format(DateTime.parse(pharmacy['created_at']).toLocal())
        : 'Unknown';

    final String ownerName = profile?['full_name'] ?? 'Not specified';
    final String ownerPhone = profile?['phone'] ?? phone;
    final String ownerRole = (profile?['role'] ?? 'owner').toString().toUpperCase();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.storefront_rounded, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('Joined: $createdAt', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                _buildStatusBadge(status),
              ],
            ),
            const Divider(height: 24),

            const Text('STORE DETAILS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            _detailRow(Icons.receipt_long_rounded, 'Drug License No.', drugLicense),
            _detailRow(Icons.pin_drop_outlined, 'Store Address', address),
            _detailRow(Icons.phone_outlined, 'Store Phone', phone),
            _detailRow(Icons.email_outlined, 'Store Email', email),
            _detailRow(Icons.card_membership_rounded, 'Subscription', plan),

            const SizedBox(height: 14),
            const Text('ACCOUNT OWNER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            _detailRow(Icons.person_outline_rounded, 'Owner Name', ownerName),
            _detailRow(Icons.phone_android_rounded, 'Owner Direct Phone', ownerPhone),
            _detailRow(Icons.shield_outlined, 'System Role', ownerRole),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _togglePharmacyStatus(pharmacy);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: status == 'active' ? Colors.orange.shade700 : const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: Icon(status == 'active' ? Icons.pause_circle_outline : Icons.play_circle_outline),
                label: Text(
                  status == 'active' ? 'Pause / Suspend Activity' : 'Resume Activity',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final bool isActive = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isActive ? Colors.green.shade300 : Colors.red.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? Icons.check_circle : Icons.pause_circle_filled,
            size: 13,
            color: isActive ? Colors.green.shade700 : Colors.red.shade700,
          ),
          const SizedBox(width: 4),
          Text(
            isActive ? 'Active' : 'Suspended',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isActive ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1E293B)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      endDrawer: const AppDrawer(),
appBar: const MediAppBar(title: 'Registered Pharmacies'),
      body: Column(
        children: [
          // Search Box
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: TextField(
              onChanged: (val) {
                setState(() => _searchQuery = val);
                _fetchPharmacies();
              },
              decoration: InputDecoration(
                hintText: 'Search pharmacy by name, phone or address...',
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
          ),

          // Count bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Pharmacies: ${_pharmacies.length}',
                  style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600),
                ),
                const Text(
                  'Super Admin Oversight',
                  style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // Pharmacy List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _pharmacies.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.store_mall_directory_outlined, size: 56, color: Colors.grey),
                            SizedBox(height: 12),
                            Text('No registered pharmacies found', style: TextStyle(fontSize: 16, color: Colors.grey)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _fetchPharmacies,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _pharmacies.length,
                        itemBuilder: (context, idx) {
                          final pharm = _pharmacies[idx];
                          final status = pharm['status'] ?? 'active';
                          final bool isActive = status == 'active';

                          return Card(
                            elevation: 1.5,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: isActive ? Colors.grey.shade200 : Colors.red.shade200,
                              ),
                            ),
                            child: InkWell(
                              onTap: () => _showPharmacyDetailsModal(pharm),
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.storefront_rounded, color: AppColors.primary, size: 22),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                pharm['name'] ?? 'Unnamed Pharmacy',
                                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                              ),
                                              Text(
                                                pharm['address'] ?? 'Address not set',
                                                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        _buildStatusBadge(status),
                                      ],
                                    ),
                                    const Divider(height: 20),

                                    // Drug License & Contact info
                                    Row(
                                      children: [
                                        Icon(Icons.receipt_long_outlined, size: 14, color: Colors.grey.shade600),
                                        const SizedBox(width: 4),
                                        Text(
                                          'License: ${pharm['license_no'] ?? pharm['drug_license_no'] ?? 'N/A'}',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                                        ),
                                        const SizedBox(width: 14),
                                        Icon(Icons.phone_outlined, size: 14, color: Colors.grey.shade600),
                                        const SizedBox(width: 4),
                                        Text(
                                          pharm['phone'] ?? 'No phone',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Owner: ${(pharm['profiles'] != null && (pharm['profiles'] as List).isNotEmpty) ? pharm['profiles'][0]['full_name'] ?? 'Owner' : 'Owner'}',
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              'View Details',
                                              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
                                            ),
                                            const SizedBox(width: 2),
                                            const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.primary, size: 12),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
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
}