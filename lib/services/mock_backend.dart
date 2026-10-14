import '../core/app_exception.dart';
import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../models/order.dart';
import '../models/product.dart';

/// In-memory stand-in for the Firebase backend described in the SRS
/// (Authentication, Cloud Firestore, Storage, Cloud Messaging).
///
/// Every public method is async and returns after a short delay so the UI's
/// loading states behave like they would against a network service. To go
/// live, replace the bodies of these methods with Firebase calls; the
/// providers and screens do not need to change.
///
/// Demo accounts:
///   admin@toptailers.com    / Admin@123
///   customer@example.com    / Customer@123
class MockBackend {
  MockBackend._() {
    _seed();
  }

  static final MockBackend instance = MockBackend._();

  int _sequence = 1000;
  String _newId(String prefix) => '$prefix${_sequence++}';

  final Map<String, String> _passwords = {};
  final List<AppUser> _users = [];
  final List<Product> _products = [];
  final List<AppOrder> _orders = [];
  final List<AppNotification> _notifications = [];

  Future<void> _latency([int milliseconds = 450]) =>
      Future<void>.delayed(Duration(milliseconds: milliseconds));

  void _seed() {
    final now = DateTime.now();

    const admin = 'u1';
    const customer = 'u2';
    _users.addAll([
      AppUser(
        id: admin,
        name: 'Shop Administrator',
        email: 'admin@toptailers.com',
        phone: '01800000000',
        address: 'Top Tailers & Fabrics, Main Road, Gazipur',
        role: UserRole.admin,
        createdAt: now.subtract(const Duration(days: 90)),
      ),
      AppUser(
        id: customer,
        name: 'Rahim Uddin',
        email: 'customer@example.com',
        phone: '01712345678',
        address: 'House 12, Road 4, Gazipur Sadar, Gazipur',
        role: UserRole.customer,
        createdAt: now.subtract(const Duration(days: 30)),
      ),
    ]);
    _passwords[admin] = 'Admin@123';
    _passwords[customer] = 'Customer@123';

    _products.addAll(const [
      Product(
        id: 'p1',
        productName: 'Premium Cotton Fabric (per yard)',
        description:
            'Soft, breathable 100% cotton fabric that is ideal for shirts, panjabis and everyday wear. Colour-fast and easy to stitch.',
        price: 450,
        category: 'Fabrics',
        availability: true,
      ),
      Product(
        id: 'p2',
        productName: 'Silk Blend Fabric (per yard)',
        description:
            'A smooth silk blend with a gentle sheen, perfect for festive wear and formal occasions.',
        price: 1200,
        category: 'Fabrics',
        availability: true,
      ),
      Product(
        id: 'p3',
        productName: 'Wool Suiting Fabric (per yard)',
        description:
            'Fine wool suiting with a crisp drape. A classic choice for blazers, trousers and waistcoats.',
        price: 1800,
        category: 'Fabrics',
        availability: true,
      ),
      Product(
        id: 'p4',
        productName: 'Linen Shirt Fabric (per yard)',
        description:
            'Lightweight linen that stays cool in warm weather. Naturally textured with a relaxed finish.',
        price: 650,
        category: 'Fabrics',
        availability: true,
      ),
      Product(
        id: 'p5',
        productName: 'Velvet Fabric (per yard)',
        description:
            'Rich, deep-pile velvet for winter and wedding wear. Currently out of stock.',
        price: 1500,
        category: 'Fabrics',
        availability: false,
      ),
      Product(
        id: 'p6',
        productName: "Men's Formal Shirt",
        description:
            'Ready-made formal shirt in a tailored fit, finished with reinforced stitching and mother-of-pearl style buttons.',
        price: 1450,
        category: 'Readymade',
        availability: true,
      ),
      Product(
        id: 'p7',
        productName: 'Cotton Panjabi',
        description:
            'Classic cotton panjabi with hand-finished collar detail. Comfortable for daily and festive wear.',
        price: 1800,
        category: 'Readymade',
        availability: true,
      ),
      Product(
        id: 'p8',
        productName: 'Shirt Stitching Service',
        description:
            'Professional stitching of your own fabric into a shirt by our experienced tailors.',
        price: 800,
        category: 'Tailoring',
        availability: true,
      ),
      Product(
        id: 'p9',
        productName: 'Button & Thread Set',
        description:
            'Assorted buttons and matching threads for repairs and finishing touches.',
        price: 250,
        category: 'Accessories',
        availability: true,
      ),
    ]);

    _orders.addAll([
      AppOrder(
        id: 'ORD-1001',
        userId: customer,
        customerName: 'Rahim Uddin',
        items: const [
          OrderItem(
            productId: 'p1',
            productName: 'Premium Cotton Fabric (per yard)',
            price: 450,
            quantity: 3,
            category: 'Fabrics',
          ),
        ],
        totalPrice: 1350,
        address: 'House 12, Road 4, Gazipur Sadar, Gazipur',
        orderDate: now.subtract(const Duration(days: 12)),
        status: OrderStatus.completed,
      ),
      AppOrder(
        id: 'ORD-1002',
        userId: customer,
        customerName: 'Rahim Uddin',
        items: const [
          OrderItem(
            productId: 'p7',
            productName: 'Cotton Panjabi',
            price: 1800,
            quantity: 1,
            category: 'Readymade',
          ),
          OrderItem(
            productId: 'p9',
            productName: 'Button & Thread Set',
            price: 250,
            quantity: 2,
            category: 'Accessories',
          ),
        ],
        totalPrice: 2300,
        address: 'House 12, Road 4, Gazipur Sadar, Gazipur',
        orderDate: now.subtract(const Duration(days: 1)),
        status: OrderStatus.pending,
      ),
    ]);

    _notifications.add(
      AppNotification(
        id: 'n1',
        userId: customer,
        title: 'Welcome to Top Tailers & Fabrics',
        body: 'Browse our fabrics and ready-made collection and place your first order.',
        createdAt: now.subtract(const Duration(days: 30)),
        read: true,
      ),
    );
  }

  // ---------------------------------------------------------------- Account

  Future<AppUser> login(String email, String password) async {
    await _latency();
    final key = email.trim().toLowerCase();
    for (final user in _users) {
      if (user.email.toLowerCase() == key && _passwords[user.id] == password) {
        return user;
      }
    }
    throw AppException('Invalid email or password.');
  }

  Future<AppUser> register({
    required String name,
    required String email,
    required String phone,
    required String address,
    required String password,
  }) async {
    await _latency();
    final key = email.trim().toLowerCase();
    if (_users.any((u) => u.email.toLowerCase() == key)) {
      throw AppException('An account with this email already exists.');
    }
    final user = AppUser(
      id: _newId('u'),
      name: name.trim(),
      email: key,
      phone: phone.trim(),
      address: address.trim(),
      role: UserRole.customer,
      createdAt: DateTime.now(),
    );
    _users.add(user);
    _passwords[user.id] = password;
    _notifications.add(
      AppNotification(
        id: _newId('n'),
        userId: user.id,
        title: 'Welcome to Top Tailers & Fabrics',
        body: 'Your account is ready. Start browsing our collection.',
        createdAt: DateTime.now(),
      ),
    );
    return user;
  }

  /// Always succeeds from the caller's point of view so that the response
  /// does not reveal which emails are registered.
  Future<void> sendPasswordReset(String email) async {
    await _latency();
  }

  Future<AppUser> updateProfile(AppUser updated) async {
    await _latency();
    final index = _users.indexWhere((u) => u.id == updated.id);
    if (index < 0) throw AppException('Account not found.');
    _users[index] = updated;
    return updated;
  }

  Future<List<AppUser>> getCustomers() async {
    await _latency();
    final list = _users.where((u) => u.role == UserRole.customer).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  // ---------------------------------------------------------------- Catalog

  Future<List<Product>> getProducts() async {
    await _latency();
    return List<Product>.unmodifiable(_products);
  }

  Future<Product> addProduct(Product draft) async {
    await _latency();
    final product = Product(
      id: _newId('p'),
      productName: draft.productName,
      description: draft.description,
      price: draft.price,
      category: draft.category,
      availability: draft.availability,
      imagePath: draft.imagePath,
    );
    _products.insert(0, product);
    return product;
  }

  Future<Product> updateProduct(Product product) async {
    await _latency();
    final index = _products.indexWhere((p) => p.id == product.id);
    if (index < 0) throw AppException('This product no longer exists.');
    _products[index] = product;
    return product;
  }

  Future<void> deleteProduct(String id) async {
    await _latency();
    _products.removeWhere((p) => p.id == id);
  }

  // ----------------------------------------------------------------- Orders

  Future<AppOrder> placeOrder({
    required AppUser user,
    required List<OrderItem> items,
    required String address,
  }) async {
    await _latency(700);
    if (items.isEmpty) throw AppException('Your cart is empty.');

    var total = 0.0;
    for (final item in items) {
      final index = _products.indexWhere((p) => p.id == item.productId);
      if (index < 0 || !_products[index].availability) {
        throw AppException(
          '"${item.productName}" is no longer available. Please update your cart.',
        );
      }
      total += _products[index].price * item.quantity;
    }

    final order = AppOrder(
      id: 'ORD-${_sequence++}',
      userId: user.id,
      customerName: user.name,
      items: items,
      totalPrice: total,
      address: address.trim(),
      orderDate: DateTime.now(),
      status: OrderStatus.pending,
    );
    _orders.insert(0, order);
    _notify(
      user.id,
      'Order placed',
      'Your order ${order.id} was received and is waiting for confirmation.',
    );
    return order;
  }

  /// Administrators receive every order; customers receive only their own.
  Future<List<AppOrder>> getOrders({String? userId}) async {
    await _latency();
    final list = _orders.where((o) => userId == null || o.userId == userId).toList();
    list.sort((a, b) => b.orderDate.compareTo(a.orderDate));
    return list;
  }

  Future<AppOrder> cancelOrder(String orderId, {required bool byAdmin}) async {
    await _latency();
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index < 0) throw AppException('Order not found.');
    final order = _orders[index];
    final allowed = byAdmin ? order.adminCanCancel : order.customerCanCancel;
    if (!allowed) {
      throw AppException(
        byAdmin
            ? 'Only Pending or Confirmed orders can be cancelled.'
            : 'You can cancel an order only while it is Pending.',
      );
    }
    final updated = order.copyWith(status: OrderStatus.cancelled);
    _orders[index] = updated;
    _notify(
      order.userId,
      'Order cancelled',
      'Your order ${order.id} has been cancelled.',
    );
    return updated;
  }

  Future<AppOrder> updateOrderStatus(String orderId, OrderStatus status) async {
    await _latency();
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index < 0) throw AppException('Order not found.');
    final order = _orders[index];
    if (order.status.next != status) {
      throw AppException(
        'An order cannot move from ${order.status.label} to ${status.label}.',
      );
    }
    final updated = order.copyWith(status: status);
    _orders[index] = updated;
    _notify(
      order.userId,
      'Order ${status.label}',
      'Your order ${order.id} is now ${status.label}.',
    );
    return updated;
  }

  // ---------------------------------------------------------- Notifications

  void _notify(String userId, String title, String body) {
    _notifications.insert(
      0,
      AppNotification(
        id: _newId('n'),
        userId: userId,
        title: title,
        body: body,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<List<AppNotification>> getNotifications(String userId) async {
    await _latency(250);
    final list = _notifications.where((n) => n.userId == userId).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> markAllRead(String userId) async {
    for (var i = 0; i < _notifications.length; i++) {
      if (_notifications[i].userId == userId && !_notifications[i].read) {
        _notifications[i] = _notifications[i].copyWith(read: true);
      }
    }
  }
}
