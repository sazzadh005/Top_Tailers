/// Order lifecycle from the SRS: Pending -> Confirmed -> Processing ->
/// Completed, with Cancelled as a side exit.
enum OrderStatus { pending, confirmed, processing, completed, cancelled }

extension OrderStatusX on OrderStatus {
  String get label {
    switch (this) {
      case OrderStatus.pending:
        return 'Pending';
      case OrderStatus.confirmed:
        return 'Confirmed';
      case OrderStatus.processing:
        return 'Processing';
      case OrderStatus.completed:
        return 'Completed';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  /// The next forward status an administrator can move this order to.
  OrderStatus? get next {
    switch (this) {
      case OrderStatus.pending:
        return OrderStatus.confirmed;
      case OrderStatus.confirmed:
        return OrderStatus.processing;
      case OrderStatus.processing:
        return OrderStatus.completed;
      case OrderStatus.completed:
      case OrderStatus.cancelled:
        return null;
    }
  }

  bool get isFinal =>
      this == OrderStatus.completed || this == OrderStatus.cancelled;
}

class OrderItem {
  const OrderItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    this.imagePath,
    this.category = '',
  });

  final String productId;
  final String productName;
  final double price;
  final int quantity;
  final String? imagePath;
  final String category;

  double get lineTotal => price * quantity;
}

/// Mirrors the `orders` Firestore collection in the SRS
/// (userId, items[], totalPrice, address, orderDate, status).
class AppOrder {
  const AppOrder({
    required this.id,
    required this.userId,
    required this.customerName,
    required this.items,
    required this.totalPrice,
    required this.address,
    required this.orderDate,
    required this.status,
  });

  final String id;
  final String userId;
  final String customerName;
  final List<OrderItem> items;
  final double totalPrice;
  final String address;
  final DateTime orderDate;
  final OrderStatus status;

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  /// Customers may cancel only while the order is Pending (SRS).
  bool get customerCanCancel => status == OrderStatus.pending;

  /// Administrators may cancel Pending or Confirmed orders (SRS).
  bool get adminCanCancel =>
      status == OrderStatus.pending || status == OrderStatus.confirmed;

  AppOrder copyWith({OrderStatus? status}) {
    return AppOrder(
      id: id,
      userId: userId,
      customerName: customerName,
      items: items,
      totalPrice: totalPrice,
      address: address,
      orderDate: orderDate,
      status: status ?? this.status,
    );
  }
}
