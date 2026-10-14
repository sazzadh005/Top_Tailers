import 'package:flutter/foundation.dart';

import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../models/cart_item.dart';
import '../models/order.dart';
import '../services/mock_backend.dart';
import 'catalog_provider.dart' show LoadState;

/// Orders, customers (admin) and notifications.
class OrdersProvider extends ChangeNotifier {
  final MockBackend _backend = MockBackend.instance;

  List<AppOrder> _orders = [];
  LoadState _ordersState = LoadState.idle;

  List<AppUser> _customers = [];
  LoadState _customersState = LoadState.idle;

  List<AppNotification> _notifications = [];
  LoadState _notificationsState = LoadState.idle;

  List<AppOrder> get orders => _orders;
  LoadState get ordersState => _ordersState;

  List<AppUser> get customers => _customers;
  LoadState get customersState => _customersState;

  List<AppNotification> get notifications => _notifications;
  LoadState get notificationsState => _notificationsState;
  int get unreadCount => _notifications.where((n) => !n.read).length;

  AppOrder? byId(String id) {
    for (final o in _orders) {
      if (o.id == id) return o;
    }
    return null;
  }

  Future<void> loadOrders(AppUser user) async {
    _ordersState = LoadState.loading;
    notifyListeners();
    try {
      _orders = await _backend.getOrders(userId: user.isAdmin ? null : user.id);
      _ordersState = LoadState.ready;
    } catch (_) {
      _ordersState = LoadState.error;
    }
    notifyListeners();
  }

  Future<void> loadCustomers() async {
    _customersState = LoadState.loading;
    notifyListeners();
    try {
      _customers = await _backend.getCustomers();
      _customersState = LoadState.ready;
    } catch (_) {
      _customersState = LoadState.error;
    }
    notifyListeners();
  }

  Future<void> loadNotifications(AppUser user) async {
    _notificationsState = LoadState.loading;
    notifyListeners();
    try {
      _notifications = await _backend.getNotifications(user.id);
      _notificationsState = LoadState.ready;
    } catch (_) {
      _notificationsState = LoadState.error;
    }
    notifyListeners();
  }

  Future<void> markAllNotificationsRead(AppUser user) async {
    await _backend.markAllRead(user.id);
    _notifications = [for (final n in _notifications) n.copyWith(read: true)];
    notifyListeners();
  }

  /// Saves the cart as a Pending order. Throws on failure so the caller can
  /// keep the cart (SRS: "If network fails: error shown, cart kept").
  Future<AppOrder> placeOrder({
    required AppUser user,
    required List<CartItem> items,
    required String address,
  }) async {
    final order = await _backend.placeOrder(
      user: user,
      items: [
        for (final item in items)
          OrderItem(
            productId: item.product.id,
            productName: item.product.productName,
            price: item.product.price,
            quantity: item.quantity,
            imagePath: item.product.imagePath,
            category: item.product.category,
          ),
      ],
      address: address,
    );
    _orders = [order, ..._orders];
    notifyListeners();
    // Refresh notifications so the badge reflects the confirmation.
    loadNotifications(user);
    return order;
  }

  Future<void> cancelOrder(String orderId, {required bool byAdmin}) async {
    final updated = await _backend.cancelOrder(orderId, byAdmin: byAdmin);
    _replace(updated);
  }

  Future<void> updateStatus(String orderId, OrderStatus status) async {
    final updated = await _backend.updateOrderStatus(orderId, status);
    _replace(updated);
  }

  void _replace(AppOrder updated) {
    _orders = [
      for (final o in _orders)
        if (o.id == updated.id) updated else o,
    ];
    notifyListeners();
  }

  /// Clears per-user data on logout.
  void reset() {
    _orders = [];
    _customers = [];
    _notifications = [];
    _ordersState = LoadState.idle;
    _customersState = LoadState.idle;
    _notificationsState = LoadState.idle;
    notifyListeners();
  }
}
