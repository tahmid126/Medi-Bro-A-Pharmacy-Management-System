import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/summary_provider.dart';
import '../../widgets/common/medi_app_bar.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/summary/circular_kpi_gauge.dart';
import '../../widgets/summary/summary_bar_chart.dart';
import '../../widgets/summary/summary_line_chart.dart';
import '../../widgets/summary/summary_ranked_row.dart';
import '../../widgets/summary/summary_section_card.dart';
import '../../widgets/summary/summary_stat_box.dart';
import '../../widgets/summary/summary_target_dialog.dart';

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  void _loadData() {
    final pharmacyId =
        context.read<AuthProvider>().currentPharmacy?.id ?? '';
    context.read<SummaryProvider>().loadAll(pharmacyId);
  }

  void _showTargetDialog(SummaryProvider provider) {
    showDialog(
      context: context,
      builder: (_) => SummaryTargetDialog(
        currentSalesTarget: provider.salesTarget,
        currentRevenueTarget: provider.revenueTarget,
        onSave: (sales, revenue) async {
          await provider.updateTargets(
            newSalesTarget: sales,
            newRevenueTarget: revenue,
          );
        },
      ),
    );
  }

  String _fmt(double v) => NumberFormat('#,##0.##', 'en').format(v);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SummaryProvider>();
    final pharmacyId =
        context.watch<AuthProvider>().currentPharmacy?.id ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      endDrawer: const AppDrawer(),
      appBar: MediAppBar(
        title: 'Summary & Analytics',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: Colors.white),
            tooltip: 'Set Goals & Targets',
            onPressed: () => _showTargetDialog(provider),
          ),

        ],
      ),
      body: provider.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async => _loadData(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSalesSection(provider),
                    const SizedBox(height: 20),
                    _buildEngagementSection(provider),
                    const SizedBox(height: 20),
                    _buildTopCustomersSection(provider, pharmacyId),
                    const SizedBox(height: 20),
                    _buildTopProductsSection(provider, pharmacyId),
                  ],
                ),
              ),
            ),
    );
  }

  // ── Period Toggle ─────────────────────────────────────────────────────────

  Widget _buildPeriodToggle({
    required String current,
    required List<String> options,
    required ValueChanged<String> onChanged,
    Color activeColor = const Color(0xFF6C63FF),
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: options.map((p) {
          final selected = current == p;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Text(
                  p,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? activeColor : Colors.grey.shade600,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Section 1: Sales & Revenue ────────────────────────────────────────────

  Widget _buildSalesSection(SummaryProvider provider) {
    return SummarySectionCard(
      title: 'Sales & Revenue',
      icon: Icons.bar_chart_rounded,
      iconColor: const Color(0xFF6C63FF),
      headerTrailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF368DF7), Color(0xFF10B981)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF368DF7).withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          DateFormat('d MMM yyyy').format(DateTime.now()),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildPeriodToggle(
            current: provider.salesPeriod,
            options: const ['Daily', 'Weekly', 'Monthly'],
            onChanged: (p) => provider.setSalesPeriod(p),
            activeColor: const Color(0xFF6C63FF),
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: provider.salesPeriod == 'Daily'
                ? _buildDailySalesView(provider)
                : provider.salesPeriod == 'Weekly'
                    ? _buildWeeklySalesView(provider)
                    : _buildMonthlySalesView(provider),
          ),
        ],
      ),
    );
  }

  Widget _buildDailySalesView(SummaryProvider provider) {
    return Row(
      children: [
        Expanded(
          child: CircularKpiGauge(
            label: "Today's Sales",
            value: provider.metrics.todaySales,
            progress: provider.salesProgress,
            color: const Color(0xFF6C63FF),
            target: provider.salesTarget,
            onTargetTap: () => _showTargetDialog(provider),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: CircularKpiGauge(
            label: "Today's Revenue",
            value: provider.metrics.todayRevenue,
            progress: provider.revenueProgress,
            color: const Color(0xFF10B981),
            target: provider.revenueTarget,
            onTargetTap: () => _showTargetDialog(provider),
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklySalesView(SummaryProvider provider) {
    return Column(
      children: [
        SummaryBarChart(
          title: 'Weekly Sales (per day)',
          data: provider.metrics.weeklySales,
          labels: provider.metrics.weekDayLabels,
          color: const Color(0xFF6C63FF),
        ),
        const SizedBox(height: 22),
        SummaryBarChart(
          title: 'Weekly Revenue (per day)',
          data: provider.metrics.weeklyRevenue,
          labels: provider.metrics.weekDayLabels,
          color: const Color(0xFF10B981),
        ),
      ],
    );
  }

  Widget _buildMonthlySalesView(SummaryProvider provider) {
    return Column(
      children: [
        SummaryLineChart(
          title: 'Monthly Sales (per week)',
          data: provider.metrics.monthlySales,
          labels: provider.metrics.weekLabels,
          color: const Color(0xFF6C63FF),
        ),
        const SizedBox(height: 22),
        SummaryLineChart(
          title: 'Monthly Revenue (per week)',
          data: provider.metrics.monthlyRevenue,
          labels: provider.metrics.weekLabels,
          color: const Color(0xFF10B981),
        ),
      ],
    );
  }

  // ── Section 2: Customer Engagement ────────────────────────────────────────

  Widget _buildEngagementSection(SummaryProvider provider) {
    return SummarySectionCard(
      title: 'Customer Engagement',
      icon: Icons.people_alt_rounded,
      iconColor: const Color(0xFFF59E0B),
      child: Column(
        children: [
          _buildPeriodToggle(
            current: provider.engagementPeriod,
            options: const ['Daily', 'Weekly', 'Monthly'],
            onChanged: (p) => provider.setEngagementPeriod(p),
            activeColor: const Color(0xFFF59E0B),
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: provider.engagementPeriod == 'Daily'
                ? Row(
                    children: [
                      Expanded(
                        child: SummaryStatBox(
                          label: 'Customers Today',
                          value: '${provider.metrics.todayCustomers}',
                          icon: Icons.people_rounded,
                          color: const Color(0xFFF59E0B),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: SummaryStatBox(
                          label: 'Avg. per Customer',
                          value: '৳${_fmt(provider.metrics.avgSpendPerCustomer)}',
                          icon: Icons.receipt_long_rounded,
                          color: const Color(0xFF6C63FF),
                        ),
                      ),
                    ],
                  )
                : provider.engagementPeriod == 'Weekly'
                    ? SummaryBarChart(
                        title: 'Unique Customers per Day',
                        data: provider.metrics.weeklyCustomers
                            .map((e) => e.toDouble())
                            .toList(),
                        labels: provider.metrics.weekDayLabels,
                        color: const Color(0xFFF59E0B),
                        isCurrency: false,
                      )
                    : SummaryBarChart(
                        title: 'Unique Customers per Week',
                        data: provider.metrics.monthlyCustomers
                            .map((e) => e.toDouble())
                            .toList(),
                        labels: provider.metrics.weekLabels,
                        color: const Color(0xFFF59E0B),
                        isCurrency: false,
                      ),
          ),
        ],
      ),
    );
  }

  // ── Section 3: Top Customers ──────────────────────────────────────────────

  Widget _buildTopCustomersSection(
    SummaryProvider provider,
    String pharmacyId,
  ) {
    final visibleCount = provider.customersExpanded ? 15 : 5;
    final visible = provider.topCustomers.take(visibleCount).toList();

    return SummarySectionCard(
      title: 'Top Customers',
      icon: Icons.emoji_events_rounded,
      iconColor: const Color(0xFFF59E0B),
      headerTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['Weekly', 'Monthly'].map((p) {
          final sel = provider.customerPeriod == p;
          return GestureDetector(
            onTap: () => provider.setCustomerPeriod(pharmacyId, p),
            child: Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: sel ? const Color(0xFFF59E0B) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                p,
                style: TextStyle(
                  color: sel ? Colors.white : Colors.grey.shade600,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }).toList(),
      ),
      child: provider.isCustomersLoading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFF59E0B)),
              ),
            )
          : visible.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.people_outline,
                            size: 32, color: Colors.grey.shade300),
                        const SizedBox(height: 6),
                        Text(
                          'No customer transactions recorded in this period',
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    ...visible.map((c) {
                      final subtitle = c.phone.isNotEmpty
                          ? c.phone
                          : (c.notes.isNotEmpty ? c.notes : 'Registered Customer');
                      return SummaryRankedRow(
                        rank: c.rank,
                        title: c.name,
                        subtitle: subtitle,
                        value: '৳${_fmt(c.totalSpent)}',
                        badge: c.currentDue > 0
                            ? 'Due ৳${_fmt(c.currentDue)}'
                            : null,
                        badgeColor: Colors.redAccent,
                      );
                    }),
                    if (provider.topCustomers.length > 5)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: InkWell(
                          onTap: () => provider.toggleCustomersExpanded(),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              provider.customersExpanded
                                  ? '▲  Show Less'
                                  : '▼  View More (${provider.topCustomers.length - 5} more)',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFD97706),
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  // ── Section 4: Top Products ───────────────────────────────────────────────

  Widget _buildTopProductsSection(
    SummaryProvider provider,
    String pharmacyId,
  ) {
    final visibleCount = provider.productsExpanded ? 15 : 5;
    final visible = provider.topProducts.take(visibleCount).toList();

    return SummarySectionCard(
      title: 'Top Selling Products',
      icon: Icons.medication_rounded,
      iconColor: const Color(0xFFEF4444),
      headerTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['Weekly', 'Monthly'].map((p) {
          final sel = provider.productPeriod == p;
          return GestureDetector(
            onTap: () => provider.setProductPeriod(pharmacyId, p),
            child: Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: sel ? const Color(0xFFEF4444) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                p,
                style: TextStyle(
                  color: sel ? Colors.white : Colors.grey.shade600,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }).toList(),
      ),
      child: provider.isProductsLoading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFEF4444)),
              ),
            )
          : visible.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.medication_outlined,
                            size: 32, color: Colors.grey.shade300),
                        const SizedBox(height: 6),
                        Text(
                          'No product sales recorded in this period',
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    ...visible.map((p) {
                      final subtitle = [p.dosageForm, p.strength]
                          .where((s) => s.isNotEmpty)
                          .join(' · ');
                      return SummaryRankedRow(
                        rank: p.rank,
                        title: p.brandName,
                        subtitle: subtitle,
                        value: '৳${_fmt(p.totalRevenue)}',
                        badge: '${p.quantitySold} sold',
                        badgeColor: const Color(0xFF6C63FF),
                      );
                    }),
                    if (provider.topProducts.length > 5)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: InkWell(
                          onTap: () => provider.toggleProductsExpanded(),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              provider.productsExpanded
                                  ? '▲  Show Less'
                                  : '▼  View More (${provider.topProducts.length - 5} more)',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFDC2626),
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
