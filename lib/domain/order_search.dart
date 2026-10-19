import '../models/order.dart';
import '../models/payment.dart';

/// Filters for searching orders. Shared by the customer and admin screens;
/// the repository decides which orders the viewer may see at all.
class OrderSearchQuery {
  const OrderSearchQuery({
    this.text = '',
    this.status,
    this.paymentStatus,
    this.from,
    this.to,
  });

  final String text;
  final OrderStatus? status;
  final PaymentStatus? paymentStatus;
  final DateTime? from;
  final DateTime? to;

  bool get isEmpty =>
      text.trim().isEmpty && status == null && paymentStatus == null && from == null && to == null;

  OrderSearchQuery copyWith({
    String? text,
    OrderStatus? status,
    bool clearStatus = false,
    PaymentStatus? paymentStatus,
    bool clearPayment = false,
    DateTime? from,
    DateTime? to,
    bool clearDates = false,
  }) {
    return OrderSearchQuery(
      text: text ?? this.text,
      status: clearStatus ? null : (status ?? this.status),
      paymentStatus: clearPayment ? null : (paymentStatus ?? this.paymentStatus),
      from: clearDates ? null : (from ?? this.from),
      to: clearDates ? null : (to ?? this.to),
    );
  }
}

class OrderSearch {
  OrderSearch._();

  static String? validate(OrderSearchQuery q) {
    if (q.text.length > 60) return 'Search text is too long';
    final from = q.from;
    final to = q.to;
    if (from != null && to != null && from.isAfter(to)) {
      return 'The start date must be before the end date';
    }
    return null;
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  /// [includeCustomerName] is true only in the admin scope, so customer-facing
  /// search never matches on other people's names.
  static bool matches(
    AppOrder order,
    OrderSearchQuery q, {
    required bool includeCustomerName,
  }) {
    if (q.status != null && order.status != q.status) return false;
    if (q.paymentStatus != null && order.payment.status != q.paymentStatus) {
      return false;
    }
    final from = q.from;
    if (from != null) {
      final start = DateTime(from.year, from.month, from.day);
      if (order.orderDate.isBefore(start)) return false;
    }
    final to = q.to;
    if (to != null) {
      final end = DateTime(to.year, to.month, to.day).add(const Duration(days: 1));
      if (!order.orderDate.isBefore(end)) return false;
    }

    final tokens = q.text
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return true;

    final buffer = StringBuffer()
      ..write(' ${order.id} ${order.reference} ${order.contactPhone} ')
      ..write(_digits(order.contactPhone))
      ..write(' ${order.status.label} ${order.payment.status.label} ')
      ..write(' ${order.payment.method.label} ${order.payment.statusLabel} ');
    if (includeCustomerName) buffer.write(' ${order.customerName} ');
    for (final item in order.items) {
      buffer.write(' ${item.productName} ${item.productCode} ');
    }
    final haystack = buffer.toString().toLowerCase();
    return tokens.every(haystack.contains);
  }

  static List<AppOrder> filter(
    Iterable<AppOrder> orders,
    OrderSearchQuery q, {
    required bool includeCustomerName,
  }) {
    final list = orders
        .where((o) => matches(o, q, includeCustomerName: includeCustomerName))
        .toList();
    list.sort((a, b) => b.orderDate.compareTo(a.orderDate));
    return list;
  }
}
