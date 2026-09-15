import 'common/avatar_helper.dart';
import '../screens/history/export_history_screen.dart';
import '../screens/history/import_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../providers/auth_provider.dart';
import '../screens/admin/global_medicines_screen.dart';
import '../screens/admin/medicine_requests_screen.dart';
import '../screens/admin/pharmacies_list_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/dashboard/dashboard_overview_screen.dart';
import '../screens/summary/summary_screen.dart';
import '../screens/inventory/stock_list_screen.dart';
import '../screens/due/due_screen.dart';
import '../screens/draft/draft_screen.dart';
import '../screens/pos/pos_sale_screen.dart';
import '../screens/purchases/purchase_entry_screen.dart';
import '../screens/contacts/contacts_page.dart';
import '../screens/profile/profile_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  void _navigate(BuildContext context, Widget page) {
    Navigator.pop(context); // close drawer
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = auth.currentProfile;
    final pharmacy = auth.currentPharmacy;
    final isSuperAdmin = profile?.isSuperAdmin ?? false;

    final drawerWidth = MediaQuery.of(context).size.width > 600
        ? 340.0
        : MediaQuery.of(context).size.width * 0.82;

    return Drawer(
      width: drawerWidth,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          bottomLeft: Radius.circular(28),
        ),
      ),
      child: Column(
        children: [
          // Header in AppColors.primary
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 50, 20, 24),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Close button top right
                Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // User profile avatar & details - clickable to navigate to Profile
                InkWell(
                  onTap: () => _navigate(context, const ProfileScreen()),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: Colors.white,
                              backgroundImage: getAvatarImageProvider(profile?.avatarUrl),
                              child: (profile?.avatarUrl == null || profile!.avatarUrl!.isEmpty)
                                  ? Text(
                                      (profile?.fullName != null && profile!.fullName.isNotEmpty)
                                          ? profile.fullName[0].toUpperCase()
                                          : (isSuperAdmin ? 'A' : 'M'),
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            if (isSuperAdmin)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    color: Colors.amber,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.shield_rounded, size: 12, color: Colors.black),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      profile?.fullName ?? (isSuperAdmin ? 'Super Admin' : 'Pharmacy Owner'),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 17,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isSuperAdmin) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade300,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'ADMIN',
                                        style: TextStyle(
                                          color: Colors.black87,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                isSuperAdmin
                                    ? 'Platform Super Administrator'
                                    : (pharmacy?.name ?? 'My Pharmacy'),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    'View & Edit Profile',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.85),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    color: Colors.white.withValues(alpha: 0.85),
                                    size: 10,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Scrollable Menu Options
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: isSuperAdmin
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- SUPER ADMIN ONLY MENU ---
                        _sectionHeader('SUPER ADMIN CONSOLE'),
                        _drawerTile(
                          icon: Icons.dashboard_rounded,
                          title: 'Admin Dashboard',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (_) => const DashboardOverviewScreen()),
                            );
                          },
                        ),
                        _drawerTile(
                          icon: Icons.storefront_rounded,
                          title: 'Check Pharmacies',
                          subtitle: 'Details, Status, Pause / Resume',
                          isSpecialBadge: true,
                          onTap: () => _navigate(context, const PharmaciesListScreen()),
                        ),
                        _drawerTile(
                          icon: Icons.public_rounded,
                          title: 'Global Medicines List',
                          subtitle: 'Add, Edit, Delete, Make Unavailable',
                          isSpecialBadge: true,
                          onTap: () => _navigate(context, const GlobalMedicinesScreen()),
                        ),
                        _drawerTile(
                          icon: Icons.mark_email_unread_rounded,
                          title: 'Medicine Requests Queue',
                          subtitle: 'Approve, Edit, Deny Requests',
                          isSpecialBadge: true,
                          onTap: () => _navigate(context, const MedicineRequestsScreen()),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- STORE OWNER / STAFF MENU ---
                        _sectionHeader('OVERVIEW'),
                        _drawerTile(
                          icon: Icons.home_rounded,
                          title: 'Dashboard',
                          isActive: true,
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (_) => const DashboardOverviewScreen()),
                            );
                          },
                        ),
                        _drawerTile(
                          icon: Icons.bar_chart_rounded,
                          title: 'Summary & Analytics',
                          onTap: () => _navigate(
                            context,
                            const SummaryScreen(),
                          ),
                        ),

                        // MEDICINES & STOCK
                        _sectionHeader('MEDICINES & CATALOG'),
                        _drawerTile(
                          icon: Icons.medical_information_outlined,
                          title: 'Medicine Library',
                          onTap: () => _navigate(
                            context,
                            const StockListScreen(initialMode: 'library'),
                          ),
                        ),
                        _drawerTile(
                          icon: Icons.inventory_2_outlined,
                          title: 'Store Stock',
                          onTap: () => _navigate(
                            context,
                            const StockListScreen(initialMode: 'stock'),
                          ),
                        ),

                        // TRANSACTIONS
                        _sectionHeader('TRANSACTIONS'),
                        _drawerTile(
                          icon: Icons.currency_exchange_rounded,
                          title: 'Sales (POS)',
                          onTap: () => _navigate(context, const PosSaleScreen()),
                        ),
                        _drawerTile(
                          icon: Icons.history_rounded,
                          title: 'Sales History',
                          onTap: () => _navigate(context, const ExportHistoryScreen()),
                        ),
                        _drawerTile(
                          icon: Icons.add_shopping_cart_rounded,
                          title: 'Purchase Entry',
                          onTap: () => _navigate(context, const PurchaseEntryScreen()),
                        ),
                        _drawerTile(
                          icon: Icons.receipt_long_rounded,
                          title: 'Purchase History',
                          onTap: () => _navigate(context, const ImportHistoryScreen()),
                        ),
                        _drawerTile(
                          icon: Icons.error_outline_rounded,
                          title: 'Dues & Ledger',
                          onTap: () => _navigate(context, const DueScreen()),
                        ),
                        _drawerTile(
                          icon: Icons.contacts_rounded,
                          title: 'Contacts',
                          subtitle: 'Customers & Suppliers',
                          onTap: () => _navigate(context, const ContactsPage()),
                        ),
                        _drawerTile(
                          icon: Icons.drafts_outlined,
                          title: 'Drafts',
                          onTap: () => _navigate(context, const DraftScreen()),
                        ),
                      ],
                    ),
            ),
          ),

          // Bottom Section (Settings & Logout) with theme-matching background
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDFA), // AppColors.primarySurface (soft soothing teal theme)
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              border: Border(
                top: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  width: 1.2,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              bottom: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _drawerTile(
                    icon: Icons.person_outline_rounded,
                    title: 'My Profile',
                    subtitle: 'Account & Store Settings',
                    onTap: () => _navigate(context, const ProfileScreen()),
                  ),
                  _drawerTile(
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    onTap: () => Navigator.pop(context),
                  ),
                  _drawerTile(
                    icon: Icons.logout_rounded,
                    title: 'Logout',
                    iconColor: Colors.red.shade600,
                    textColor: Colors.red.shade600,
                    onTap: () async {
                      final nav = Navigator.of(context, rootNavigator: true);
                      nav.pop(); // close drawer
                      await context.read<AuthProvider>().logout();
                      nav.pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6, left: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _drawerTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool isActive = false,
    bool isSpecialBadge = false,
    Color? iconColor,
    Color? textColor,
  }) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: Icon(
        icon,
        color: iconColor ?? (isActive ? AppColors.primary : (isSpecialBadge ? Colors.teal.shade700 : Colors.grey.shade700)),
        size: 22,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: textColor ?? (isActive ? AppColors.primary : (isSpecialBadge ? const Color(0xFF0F766E) : Colors.black87)),
          fontWeight: (isActive || isSpecialBadge) ? FontWeight.bold : FontWeight.w500,
          fontSize: 14,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            )
          : null,
      trailing: isSpecialBadge
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'ADMIN',
                style: TextStyle(color: Colors.amber.shade900, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            )
          : (isActive
              ? Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                )
              : null),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tileColor: isActive ? AppColors.primary.withValues(alpha: 0.08) : (isSpecialBadge ? Colors.teal.shade50 : null),
      onTap: onTap,
    );
  }
}
