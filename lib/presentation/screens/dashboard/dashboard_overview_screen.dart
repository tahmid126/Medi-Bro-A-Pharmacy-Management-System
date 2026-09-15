import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/today_progress_card.dart';
import '../../widgets/dashboard/admin_feature_card.dart';
import '../../widgets/dashboard/dashboard_action_card.dart';
import '../admin/global_medicines_screen.dart';
import '../admin/medicine_requests_screen.dart';
import '../admin/pharmacies_list_screen.dart';
import '../inventory/stock_list_screen.dart';
import '../due/due_screen.dart';
import '../draft/draft_screen.dart';
import '../contacts/contacts_page.dart';
import '../pos/pos_sale_screen.dart';
import '../purchases/purchase_entry_screen.dart';
import '../summary/summary_screen.dart';
import '../history/export_history_screen.dart';
import '../history/import_history_screen.dart';
import '../profile/profile_screen.dart';

class DashboardOverviewScreen extends StatefulWidget {
  const DashboardOverviewScreen({super.key});

  @override
  State<DashboardOverviewScreen> createState() => _DashboardOverviewScreenState();
}

class _DashboardOverviewScreenState extends State<DashboardOverviewScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final isSuperAdmin = context.read<AuthProvider>().currentProfile?.isSuperAdmin ?? false;
      if (!isSuperAdmin) {
        context.read<InventoryProvider>().loadMedicines();
      }
    });
  }

  void _navigate(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = auth.currentProfile;
    final isSuperAdmin = profile?.isSuperAdmin ?? false;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      endDrawer: const AppDrawer(),
appBar: PreferredSize(
        preferredSize: const Size.fromHeight(65),
        child: Container(
          color: AppColors.primary,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const DashboardOverviewScreen()),
                      );
                    },
                    child: Image.asset(
                      'assets/images/mb_logo.png',
                      height: 48,
                      width: 120,
                      fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Row(
                        children: const [
                          Icon(Icons.local_pharmacy_rounded, color: Colors.white, size: 28),
                          SizedBox(width: 8),
                          Text(
                            'MediBro',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                  const Spacer(),
                  if (isSuperAdmin)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade400,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.shield_rounded, size: 14, color: Colors.black87),
                          SizedBox(width: 4),
                          Text(
                            'SUPER ADMIN',
                            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                    onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: isSuperAdmin
                ? _buildSuperAdminConsole()
                : _buildPharmacyStaffDashboard(),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // SUPER ADMIN CONSOLE
  // ==========================================
  Widget _buildSuperAdminConsole() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Super Admin Console',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Platform Governance & Oversight',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade400),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.verified_user_rounded, color: Colors.amber, size: 14),
                  SizedBox(width: 4),
                  Text('ADMIN ONLY', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        GestureDetector(
          onTap: () => _navigate(const ProfileScreen()),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_rounded, color: Colors.amber, size: 32),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Welcome, Super Administrator',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'You have platform-wide authority. Store counter cashier operations are isolated from this console.',
                      style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
        const SizedBox(height: 24),

        const Text(
          'Core Management Modules',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
        const SizedBox(height: 12),

        AdminFeatureCard(
          icon: Icons.storefront_rounded,
          iconBg: const Color(0xFF0284C7),
          title: '1. Check Pharmacies',
          subtitle: 'View registered stores (name, phone, email, license, owner) and Pause or Resume pharmacy activity.',
          badgeText: 'Active & Suspended',
          badgeColor: const Color(0xFF0284C7),
          onTap: () => _navigate(const PharmaciesListScreen()),
        ),
        const SizedBox(height: 12),

        AdminFeatureCard(
          icon: Icons.public_rounded,
          iconBg: const Color(0xFF10B981),
          title: '2. Global Medicine Catalog',
          subtitle: 'Maintain master list: Add new drugs, Edit details, Safely Delete, or Make Unavailable (Hide/Show).',
          badgeText: 'Master Library',
          badgeColor: const Color(0xFF10B981),
          onTap: () => _navigate(const GlobalMedicinesScreen()),
        ),
        const SizedBox(height: 12),

        AdminFeatureCard(
          icon: Icons.mark_email_unread_rounded,
          iconBg: const Color(0xFFF59E0B),
          title: '3. Medicine Requests Queue',
          subtitle: 'Review pharmacy-submitted requests: Approve & Add to Global catalog, Edit details, or Deny with reason.',
          badgeText: 'Pending Approvals',
          badgeColor: const Color(0xFFF59E0B),
          onTap: () => _navigate(const MedicineRequestsScreen()),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ==========================================
  // PHARMACY STORE OWNER / CLERK DASHBOARD
  // ==========================================
  Widget _buildPharmacyStaffDashboard() {

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dashboard',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 14),

        const Text(
          "Today's Progress",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        TodayProgressCard(onTap: () => _navigate(const SummaryScreen())),
        const SizedBox(height: 20),

        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),

        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final int crossAxisCount = width >= 800
                ? 5
                : width >= 550
                    ? 4
                    : 3;
            final double childAspectRatio = width < 360 ? 0.82 : 0.95;

            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: childAspectRatio,
              children: [
            DashboardActionCard(
              icon: Icons.bar_chart_rounded,
              title: 'Summary',
              onTap: () => _navigate(const SummaryScreen()),
            ),
            DashboardActionCard(
              icon: Icons.medical_information_outlined,
              title: 'Medicine Library',
              onTap: () => _navigate(
                const StockListScreen(initialMode: 'library'),
              ),
            ),
            DashboardActionCard(
              icon: Icons.add_shopping_cart_rounded,
              title: 'Purchase',
              onTap: () => _navigate(const PurchaseEntryScreen()),
            ),
            DashboardActionCard(
              icon: Icons.receipt_long_rounded,
              title: 'Purchase List',
              onTap: () => _navigate(const ImportHistoryScreen()),
            ),
            DashboardActionCard(
              icon: Icons.currency_exchange_rounded,
              title: 'Sales',
              onTap: () => _navigate(const PosSaleScreen()),
            ),
            DashboardActionCard(
              icon: Icons.history_rounded,
              title: 'Sales History',
              onTap: () => _navigate(const ExportHistoryScreen()),
            ),
            DashboardActionCard(
              icon: Icons.drafts_outlined,
              title: 'Drafts',
              onTap: () => _navigate(const DraftScreen()),
            ),
            DashboardActionCard(
              icon: Icons.error_outline_rounded,
              title: 'Dues & Ledger',
              onTap: () => _navigate(const DueScreen()),
            ),
            DashboardActionCard(
              icon: Icons.contacts_rounded,
              title: 'Contacts',
              onTap: () => _navigate(const ContactsPage()),
            ),
            DashboardActionCard(
              icon: Icons.inventory_2_outlined,
              title: 'Store Stock',
              onTap: () => _navigate(
                const StockListScreen(initialMode: 'stock'),
              ),
            ),
            DashboardActionCard(
              icon: Icons.auto_awesome_rounded,
              title: 'MediBot AI',
              onTap: () {},
            ),
            DashboardActionCard(
              icon: Icons.person_outline_rounded,
              title: 'Profile',
              onTap: () => _navigate(const ProfileScreen()),
            ),
          ],
        );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}