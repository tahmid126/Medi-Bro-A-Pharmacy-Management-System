import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../data/services/dashboard_service.dart';
import '../providers/auth_provider.dart';

class TodayProgressCard extends StatefulWidget {
  final VoidCallback? onTap;

  const TodayProgressCard({super.key, this.onTap});

  @override
  State<TodayProgressCard> createState() => _TodayProgressCardState();
}

class _TodayProgressCardState extends State<TodayProgressCard> {
  final DashboardService _service = DashboardService.instance;

  double todaySales = 0.0;
  double todayRevenue = 0.0;
  double salesTarget = 10000.0;
  double revenueTarget = 2000.0;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMetrics();
  }

  Future<void> _fetchMetrics() async {
    final pharmacyId = context.read<AuthProvider>().currentPharmacy?.id ?? '';
    final metrics = await _service.fetchTodayMetrics(pharmacyId: pharmacyId);

    if (mounted) {
      setState(() {
        todaySales = metrics.todaySales;
        todayRevenue = metrics.todayRevenue;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double salesProgress = salesTarget > 0 ? (todaySales / salesTarget).clamp(0.0, 1.0) : 0.0;
    final double revenueProgress = revenueTarget > 0 ? (todayRevenue / revenueTarget).clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFFF8FAFC), Color(0xFFF0FDFA)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              // Left: Circular Progress Indicators
              Expanded(
                flex: 5,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildCircleProgress(
                      'Sales',
                      salesProgress,
                      const Color(0xFF6366F1),
                    ),
                    _buildCircleProgress(
                      'Revenue',
                      revenueProgress,
                      AppColors.primary,
                    ),
                  ],
                ),
              ),

              // Middle Divider
              Container(
                width: 1,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.grey.shade300,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Right: Metric Details
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildValueRow(
                      Icons.calendar_today_rounded,
                      DateFormat('dd MMM yyyy').format(DateTime.now()),
                      Colors.red.shade600,
                      13.5,
                    ),
                    const SizedBox(height: 10),
                    _buildValueRow(
                      Icons.shopping_cart_rounded,
                      '৳${todaySales.toStringAsFixed(0)}',
                      const Color(0xFF6366F1),
                      16,
                    ),
                    const SizedBox(height: 10),
                    _buildValueRow(
                      Icons.trending_up_rounded,
                      '৳${todayRevenue.toStringAsFixed(0)}',
                      AppColors.primary,
                      16,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCircleProgress(String label, double progress, Color color) {
    final pct = (progress * 100).toStringAsFixed(0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 58,
          height: 58,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 58,
                height: 58,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 5.5,
                  color: color,
                  backgroundColor: Colors.grey.shade200,
                ),
              ),
              Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildValueRow(IconData icon, String text, Color color, double fontSize) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}