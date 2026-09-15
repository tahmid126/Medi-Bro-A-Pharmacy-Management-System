class SummaryMetrics {
  final double todaySales;
  final double todayRevenue;
  final int todayCustomers;
  final double avgSpendPerCustomer;

  final List<double> weeklySales;
  final List<double> weeklyRevenue;
  final List<int> weeklyCustomers;
  final List<String> weekDayLabels;

  final List<double> monthlySales;
  final List<double> monthlyRevenue;
  final List<int> monthlyCustomers;
  final List<String> weekLabels;

  const SummaryMetrics({
    required this.todaySales,
    required this.todayRevenue,
    required this.todayCustomers,
    required this.avgSpendPerCustomer,
    required this.weeklySales,
    required this.weeklyRevenue,
    required this.weeklyCustomers,
    required this.weekDayLabels,
    required this.monthlySales,
    required this.monthlyRevenue,
    required this.monthlyCustomers,
    required this.weekLabels,
  });

  factory SummaryMetrics.empty() {
    return SummaryMetrics(
      todaySales: 0.0,
      todayRevenue: 0.0,
      todayCustomers: 0,
      avgSpendPerCustomer: 0.0,
      weeklySales: List.filled(7, 0.0),
      weeklyRevenue: List.filled(7, 0.0),
      weeklyCustomers: List.filled(7, 0),
      weekDayLabels: const ['D1', 'D2', 'D3', 'D4', 'D5', 'D6', 'Today'],
      monthlySales: List.filled(4, 0.0),
      monthlyRevenue: List.filled(4, 0.0),
      monthlyCustomers: List.filled(4, 0),
      weekLabels: const ['Wk 1', 'Wk 2', 'Wk 3', 'Wk 4'],
    );
  }
}

class RankedCustomer {
  final String id;
  final String name;
  final String phone;
  final String notes;
  final double totalSpent;
  final double currentDue;
  final int rank;

  const RankedCustomer({
    required this.id,
    required this.name,
    required this.phone,
    required this.notes,
    required this.totalSpent,
    required this.currentDue,
    required this.rank,
  });
}

class RankedProduct {
  final String id;
  final String brandName;
  final String dosageForm;
  final String strength;
  final int quantitySold;
  final double totalRevenue;
  final double grossProfit;
  final int rank;

  const RankedProduct({
    required this.id,
    required this.brandName,
    required this.dosageForm,
    required this.strength,
    required this.quantitySold,
    required this.totalRevenue,
    required this.grossProfit,
    required this.rank,
  });
}
