import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/customer_discount.dart';
import '../models/customer_summary.dart';
import '../models/measurements.dart';
import '../repositories/repositories.dart';
import 'load_state.dart';

/// Admin-only customer management: list, measurements and customer-specific
/// discounts.
class CustomersProvider extends ChangeNotifier {
  CustomersProvider(this._auth, this._discounts);

  final AuthRepository _auth;
  final DiscountRepository _discounts;

  AppUser? _admin;
  List<CustomerSummary> _summaries = [];
  Map<String, CustomerDiscount> _discountMap = {};
  LoadState _state = LoadState.idle;
  String? _error;

  List<AppUser> get customers => [for (final s in _summaries) s.user];

  /// Order count and Lifetime Spending as calculated by the server.
  CustomerSummary? summaryFor(String customerId) {
    for (final s in _summaries) {
      if (s.user.id == customerId) return s;
    }
    return null;
  }
  LoadState get state => _state;
  String? get error => _error;

  CustomerDiscount? discountFor(String customerId) => _discountMap[customerId];
  List<CustomerDiscount> get discounts => _discountMap.values.toList();

  AppUser? byId(String id) {
    return summaryFor(id)?.user;
  }

  Future<void> load(AppUser admin) async {
    _admin = admin;
    _state = LoadState.loading;
    _error = null;
    notifyListeners();
    try {
      final summaries = await _auth.getCustomerSummaries(actor: admin);
      final discounts = await _discounts.listCustomerDiscounts();
      _summaries = summaries;
      _discountMap = {for (final d in discounts) d.customerId: d};
      _state = LoadState.ready;
    } catch (e) {
      _error = e.toString();
      _state = LoadState.error;
    }
    notifyListeners();
  }

  Future<void> saveDiscount(CustomerDiscount discount) async {
    final saved = await _discounts.saveCustomerDiscount(discount);
    _discountMap = {..._discountMap, saved.customerId: saved};
    notifyListeners();
  }

  Future<void> removeDiscount(String customerId) async {
    await _discounts.removeCustomerDiscount(customerId);
    _discountMap = {..._discountMap}..remove(customerId);
    notifyListeners();
  }

  Future<void> updateMeasurements(String customerId, BodyMeasurements m) async {
    final admin = _admin;
    if (admin == null) return;
    final updated = await _auth.updateMeasurements(customerId, m, actor: admin);
    _summaries = [for (final s in _summaries) s.user.id == customerId ? s.withUser(updated) : s];
    notifyListeners();
  }

  void reset() {
    _admin = null;
    _summaries = [];
    _discountMap = {};
    _state = LoadState.idle;
    notifyListeners();
  }
}
