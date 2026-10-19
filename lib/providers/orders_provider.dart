import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/order_search.dart';
import '../domain/pricing.dart';
import '../models/app_user.dart';
import '../models/cart_item.dart';
import '../models/measurements.dart';
import '../models/order.dart';
import '../models/payment.dart';
import '../repositories/repositories.dart';
import 'load_state.dart';

/// Orders for the signed-in viewer (customer: own orders, admin: all), with
/// shared search/filter logic, cancellation, status changes and payments.
class OrdersProvider extends ChangeNotifier {
  OrdersProvider(
    this._orders,
    this._gateway, {
    this.searchDelay = const Duration(milliseconds: 300),
  });

  final OrderRepository _orders;
  final PaymentGateway _gateway;
  final Duration searchDelay;

  AppUser? _viewer;
  List<AppOrder> _results = [];
  final Map<String, AppOrder> _known = {};
  LoadState _state = LoadState.idle;
  String? _error;
  OrderSearchQuery _query = const OrderSearchQuery();
  Timer? _debounce;
  int _token = 0;
  bool _disposed = false;

  /// Orders matching the current search/filters.
  List<AppOrder> get orders => _results;
  LoadState get state => _state;
  String? get error => _error;
  OrderSearchQuery get query => _query;
  bool get isDemoGateway => _gateway.isDemo;
  String get gatewayName => _gateway.displayName;

  /// Every order loaded so far (used for admin statistics such as spending).
  List<AppOrder> get knownOrders => _known.values.toList();

  AppOrder? byId(String id) => _known[id];

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  void _remember(Iterable<AppOrder> orders) {
    for (final o in orders) {
      _known[o.id] = o;
    }
  }

  Future<void> load(AppUser viewer) async {
    _viewer = viewer;
    await _runSearch();
  }

  Future<void> refresh() => _runSearch();

  Future<void> _runSearch() async {
    final viewer = _viewer;
    if (viewer == null) return;
    final problem = OrderSearch.validate(_query);
    if (problem != null) {
      _error = problem;
      _state = LoadState.error;
      _safeNotify();
      return;
    }
    final token = ++_token;
    _state = LoadState.loading;
    _error = null;
    _safeNotify();
    try {
      final result = await _orders.searchOrders(_query, viewer: viewer);
      if (token != _token) return;
      _results = result;
      _remember(result);
      _state = LoadState.ready;
    } catch (e) {
      if (token != _token) return;
      _error = e.toString();
      _state = LoadState.error;
    }
    _safeNotify();
  }

  // ------------------------------------------------------------ search/filter

  void setText(String text) {
    if (text == _query.text) return;
    _query = _query.copyWith(text: text);
    _debounce?.cancel();
    if (searchDelay == Duration.zero) {
      _runSearch();
    } else {
      _debounce = Timer(searchDelay, _runSearch);
    }
    _safeNotify();
  }

  void setStatus(OrderStatus? status) {
    _query = _query.copyWith(status: status, clearStatus: status == null);
    _runSearch();
  }

  void setPaymentStatus(PaymentStatus? status) {
    _query = _query.copyWith(paymentStatus: status, clearPayment: status == null);
    _runSearch();
  }

  void setDateRange(DateTime? from, DateTime? to) {
    _query = from == null && to == null
        ? _query.copyWith(clearDates: true)
        : OrderSearchQuery(
            text: _query.text,
            status: _query.status,
            paymentStatus: _query.paymentStatus,
            from: from,
            to: to,
          );
    _runSearch();
  }

  void clearSearch() {
    _debounce?.cancel();
    _query = const OrderSearchQuery();
    _runSearch();
  }

  // ------------------------------------------------------------------ orders

  /// Saves the cart as a Pending order. Throws on failure so the caller can
  /// keep the cart (SRS: "If network fails: error shown, cart kept").
  Future<AppOrder> placeOrder({
    required AppUser user,
    required List<CartItem> items,
    required PriceBreakdown breakdown,
    required String contactPhone,
    required String address,
    String note = '',
    OrderMeasurementSnapshot? measurements,
    required PaymentMethod method,
  }) async {
    final order = await _orders.placeOrder(
      PlaceOrderRequest(
        userId: user.id,
        customerName: user.name,
        items: [
          for (final i in items)
            OrderLineRequest(
              productId: i.product.id,
              quantity: i.quantity,
              colorName: i.colorName,
              size: i.size,
            ),
        ],
        contactPhone: contactPhone,
        shippingAddress: address,
        note: note,
        measurements: measurements,
        voucherCode: breakdown.voucherCode,
        paymentMethod: method,
        expectedTotalMinor: breakdown.totalMinor,
      ),
    );
    _known[order.id] = order;
    _results = [order, ..._results];
    _safeNotify();
    return order;
  }

  Future<void> cancelOrder(
    String orderId, {
    required String reason,
    String note = '',
  }) async {
    final actor = _viewer;
    if (actor == null) return;
    final updated = await _orders.cancelOrder(
      orderId,
      actor: actor,
      reason: reason,
      note: note,
    );
    _replace(updated);
  }

  Future<void> updateStatus(String orderId, OrderStatus status) async {
    _replace(await _orders.updateStatus(orderId, status));
  }

  /// Starts an online payment with the configured gateway. In this phase the
  /// gateway is a demonstration; success must never be assumed.
  Future<PaymentSession> startOnlinePayment(AppOrder order) {
    return _gateway.initiate(orderId: order.id, amountMinor: order.totalMinor);
  }

  /// Records the outcome of an online payment attempt. With a real gateway
  /// this comes from the backend after it verifies the provider's callback.
  Future<void> recordPayment(
    String orderId,
    PaymentStatus status, {
    PaymentProvider provider = PaymentProvider.demo,
    String? transactionRef,
  }) async {
    final updated = await _orders.updatePayment(
      orderId,
      status,
      provider: provider,
      transactionRef: transactionRef,
    );
    _replace(updated);
  }

  void _replace(AppOrder updated) {
    _known[updated.id] = updated;
    _results = [for (final o in _results) o.id == updated.id ? updated : o];
    _safeNotify();
  }

  /// Clears per-user data on logout.
  void reset() {
    _debounce?.cancel();
    _viewer = null;
    _results = [];
    _known.clear();
    _query = const OrderSearchQuery();
    _state = LoadState.idle;
    _error = null;
    _token++;
    _safeNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
