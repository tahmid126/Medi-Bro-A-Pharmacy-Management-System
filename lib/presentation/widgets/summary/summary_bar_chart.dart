import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class SummaryBarChart extends StatelessWidget {
  final String title;
  final List<double> data;
  final List<String> labels;
  final Color color;
  final bool isCurrency;

  const SummaryBarChart({
    super.key,
    required this.title,
    required this.data,
    required this.labels,
    required this.color,
    this.isCurrency = true,
  });

  

  @override
  Widget build(BuildContext context) {
    final hasData = data.any((v) => v > 0);
    final maxVal = data.isEmpty
        ? 100.0
        : data.reduce((a, b) => a > b ? a : b);
    final maxY = (maxVal * 1.3).clamp(10.0, double.infinity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (hasData)
              Text(
                isCurrency ? 'Total: ৳' : 'Total: ',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (!hasData)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.bar_chart_outlined, size: 32, color: Colors.grey.shade300),
                  const SizedBox(height: 6),
                  Text(
                    'No transaction recorded for this period',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 170,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                minY: 0,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: Colors.grey.shade100,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (v, _) {
                        if (v == 0) return const SizedBox();
                        String label;
                        if (v >= 1000) {
                          label = 'k';
                        } else {
                          label = v.toInt().toString();
                        }
                        return Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade400,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= labels.length) {
                          return const SizedBox();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            labels[i],
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                barGroups: data.asMap().entries.map((e) {
                  final val = e.value;
                  final isEmpty = val <= 0;
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: isEmpty ? 0.3 : val,
                        width: 18,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                        gradient: isEmpty
                            ? null
                            : LinearGradient(
                                colors: [
                                  color.withValues(alpha: 0.65),
                                  color,
                                ],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              ),
                        color: isEmpty ? Colors.grey.shade200 : null,
                      ),
                    ],
                  );
                }).toList(),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF1E293B),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      
                      final formatted = isCurrency ? '৳' : ' customers';
                      return BarTooltipItem(
                        formatted,
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
