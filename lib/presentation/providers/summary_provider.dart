import 'package:flutter/foundation.dart';
import '../../data/models/summary_model.dart';
import '../../data/services/summary_service.dart';

class SummaryProvider extends ChangeNotifier {
  final SummaryService _service = SummaryService.instance;

  bool _isLoading = true;
  bool _isCustomersLoading = false;
  bool _isProductsLoading = false;

  SummaryMetrics _metrics = SummaryMetrics.empty();
  List<RankedCustomer> _topCustomers = [];
  List<RankedProduct> _topProducts = [];

  double _salesTarget = 15000.0;
  double _revenueTarget = 5000.0;

  String _salesPeriod = 'Daily'; // 'Daily', 'Weekly', 'Monthly'
  String _engagementPeriod = 'Daily'; // 'Daily', 'Weekly', 'Monthly'
  String _customerPeriod = 'Weekly'; // 'Weekly', 'Monthly'
  String _productPeriod = 'Weekly'; // 'Weekly', 'Monthly'

  bool _customersExpanded = false;
  bool _productsExpanded = false;

  // ── Getters ───────────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  bool get isCustomersLoading => _isCustomersLoading;
  bool get isProductsLoading => _isProductsLoading;

  SummaryMetrics get metrics => _metrics;
  List<RankedCustomer> get topCustomers => _topCustomers;
  List<RankedProduct> get topProducts => _topProducts;

  double get salesTarget => _salesTarget;
  double get revenueTarget => _revenueTarget;

  String get salesPeriod => _salesPeriod;
  String get engagementPeriod => _engagementPeriod;
  String get customerPeriod => _customerPeriod;
  String get productPeriod => _productPeriod;

  bool get customersExpanded => _customersExpanded;
  bool get productsExpanded => _productsExpanded;

  double get salesProgress =>
      (_salesTarget > 0 ? _metrics.todaySales / _salesTarget : 0.0)
          .clamp(0.0, 1.0);

  double get revenueProgress =>
      (_revenueTarget > 0 ? _metrics.todayRevenue / _revenueTarget : 0.0)
          .clamp(0.0, 1.0);

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> loadAll(String pharmacyId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final targets = await _service.loadTargets();
      _salesTarget = targets['sales_target'] ?? 15000.0;
      _revenueTarget = targets['revenue_target'] ?? 5000.0;

      final results = await Future.wait([
        _service.fetchSummaryMetrics(pharmacyId: pharmacyId),
        _service.fetchTopCustomers(
          pharmacyId: pharmacyId,
          period: _customerPeriod,
        ),
        _service.fetchTopProducts(
          pharmacyId: pharmacyId,
          period: _productPeriod,
        ),
      ]);

      _metrics = results[0] as SummaryMetrics;
      _topCustomers = results[1] as List<RankedCustomer>;
      _topProducts = results[2] as List<RankedProduct>;
    } catch (e) {
      debugPrint('[SummaryProvider] loadAll error: ');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSalesPeriod(String period) {
    if (_salesPeriod == period) return;
    _salesPeriod = period;
    notifyListeners();
  }

  void setEngagementPeriod(String period) {
    if (_engagementPeriod == period) return;
    _engagementPeriod = period;
    notifyListeners();
  }

  Future<void> setCustomerPeriod(String pharmacyId, String period) async {
    if (_customerPeriod == period) return;
    _customerPeriod = period;
    _isCustomersLoading = true;
    notifyListeners();

    try {
      _topCustomers = await _service.fetchTopCustomers(
        pharmacyId: pharmacyId,
        period: _customerPeriod,
      );
    } catch (e) {
      debugPrint('[SummaryProvider] setCustomerPeriod error: ');
    } finally {
      _isCustomersLoading = false;
      notifyListeners();
    }
  }

  Future<void> setProductPeriod(String pharmacyId, String period) async {
    if (_productPeriod == period) return;
    _productPeriod = period;
    _isProductsLoading = true;
    notifyListeners();

    try {
      _topProducts = await _service.fetchTopProducts(
        pharmacyId: pharmacyId,
        period: _productPeriod,
      );
    } catch (e) {
      debugPrint('[SummaryProvider] setProductPeriod error: ');
    } finally {
      _isProductsLoading = false;
      notifyListeners();
    }
  }

  void toggleCustomersExpanded() {
    _customersExpanded = !_customersExpanded;
    notifyListeners();
  }

  void toggleProductsExpanded() {
    _productsExpanded = !_productsExpanded;
    notifyListeners();
  }

  Future<void> updateTargets({
    required double newSalesTarget,
    required double newRevenueTarget,
  }) async {
    _salesTarget = newSalesTarget;
    _revenueTarget = newRevenueTarget;
    notifyListeners();

    await _service.saveTargets(
      salesTarget: newSalesTarget,
      revenueTarget: newRevenueTarget,
    );
  }
}
