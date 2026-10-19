import '../../core/app_exception.dart';
import '../../core/validators.dart';
import '../../domain/notification_retention.dart';
import '../../domain/order_search.dart';
import '../../domain/pricing.dart';
import '../../models/app_notification.dart';
import '../../models/app_user.dart';
import '../../models/cancellation.dart';
import '../../models/order.dart';
import '../../models/payment.dart';
import '../../models/voucher.dart';
import '../../repositories/repositories.dart';
import 'mock_store.dart';

/// Imitates a server that does NOT trust client prices: it looks products up
/// again, re-evaluates the voucher and customer discount, and rejects the
/// order if the client's expected total no longer matches.
class MockOrderRepository implements OrderRepository {
  MockOrderRepository(this._store);

  final MockStore _store;

  static const int maxQuantity = 20;

  Voucher? _voucher(String? code) {
    if (code == null) return null;
    final key = code.trim().toUpperCase();
    for (final v in _store.vouchers) {
      if (v.code == key) return v;
    }
    return null;
  }

  @override
  Future<AppOrder> placeOrder(PlaceOrderRequest r) async {
    await _store.wait(2);
    if (r.items.isEmpty) throw AppException('Your cart is empty.');
    final phoneError = Validators.phone(r.contactPhone);
    if (phoneError != null) throw AppException('Contact number: $phoneError');
    final addressError = Validators.address(r.shippingAddress);
    if (addressError != null) throw AppException(addressError);

    final items = <OrderItem>[];
    final lines = <PricedLine>[];
    var needsMeasurements = false;
    for (final line in r.items) {
      final product = _store.productById(line.productId);
      if (product == null || !product.availability) {
        throw AppException(
          '"${product?.productName ?? 'An item'}" is no longer available. Please update your cart.',
        );
      }
      if (line.quantity < 1 || line.quantity > maxQuantity) {
        throw AppException('Invalid quantity for "${product.productName}".');
      }
      if (line.colorName != null &&
          !product.colors.any((c) => c.name == line.colorName)) {
        throw AppException('Selected colour is no longer offered for "${product.productName}".');
      }
      if (line.size != null && !product.sizes.contains(line.size)) {
        throw AppException('Selected size is no longer offered for "${product.productName}".');
      }
      if (product.requiresMeasurements) needsMeasurements = true;
      items.add(OrderItem(
        productId: product.id,
        productCode: product.code,
        productName: product.productName,
        listUnitMinor: product.priceMinor,
        unitMinor: product.effectivePriceMinor,
        quantity: line.quantity,
        imagePath: product.imagePath,
        category: product.category,
        unit: product.unit,
        colorName: line.colorName,
        size: line.size,
      ));
      lines.add(PricedLine(
        category: product.category,
        listUnitMinor: product.priceMinor,
        unitMinor: product.effectivePriceMinor,
        quantity: line.quantity,
      ));
    }
    if (needsMeasurements && (r.measurements == null || r.measurements!.measurements.isEmpty)) {
      throw AppException('Measurements are required for tailoring services.');
    }

    final now = _store.now();
    Voucher? voucher;
    if (r.voucherCode != null) {
      voucher = _voucher(r.voucherCode);
      if (voucher == null) throw AppException('Voucher ${r.voucherCode} is not valid any more.');
      final evaluation = VoucherRules.evaluate(voucher, lines, now: now);
      if (!evaluation.isValid) throw AppException(evaluation.message);
    }

    final breakdown = PricingService.compute(
      lines,
      voucher: voucher,
      customerDiscount: _store.customerDiscounts[r.userId],
      now: now,
    );
    if (breakdown.totalMinor != r.expectedTotalMinor) {
      throw AppException(
        'Prices or discounts changed since you reviewed your cart. Please check the new total and try again.',
      );
    }

    final id = 'ORD-${_store.newId('')}';
    final order = AppOrder(
      id: id,
      reference: _store.mockReference(id, now),
      userId: r.userId,
      customerName: r.customerName,
      contactPhone: r.contactPhone.trim(),
      shippingAddress: r.shippingAddress.trim(),
      note: r.note.trim(),
      measurements: r.measurements,
      items: items,
      subtotalMinor: breakdown.subtotalMinor,
      productDiscountMinor: breakdown.productDiscountMinor,
      customerDiscountMinor: breakdown.customerDiscountMinor,
      voucherDiscountMinor: breakdown.voucherDiscountMinor,
      deliveryMinor: breakdown.deliveryMinor,
      totalMinor: breakdown.totalMinor,
      voucherCode: breakdown.voucherCode,
      payment: PaymentRecord(
        id: 'PAY-$id',
        method: r.paymentMethod,
        status: PaymentStatus.pending,
        amountMinor: breakdown.totalMinor,
        provider: r.paymentMethod == PaymentMethod.cod
            ? PaymentProvider.none
            : PaymentProvider.demo,
        updatedAt: now,
      ),
      status: OrderStatus.pending,
      orderDate: now,
      history: [OrderEvent(status: OrderStatus.pending, at: now)],
    );
    _store.orders.insert(0, order);
    _store.notify(
      r.userId,
      'Order placed',
      'Your order ${order.id} was received and is waiting for confirmation.',
    );
    return order;
  }

  @override
  Future<List<AppOrder>> searchOrders(
    OrderSearchQuery query, {
    required AppUser viewer,
  }) async {
    await _store.wait();
    final error = OrderSearch.validate(query);
    if (error != null) throw AppException(error);
    // Authorization scope: customers never see anyone else's orders.
    final scope = viewer.isAdmin
        ? _store.orders
        : _store.orders.where((o) => o.userId == viewer.id);
    return OrderSearch.filter(scope, query, includeCustomerName: viewer.isAdmin);
  }

  AppOrder _get(String id) {
    final index = _store.orderIndex(id);
    if (index < 0) throw AppException('Order not found.');
    return _store.orders[index];
  }

  void _put(AppOrder order) {
    _store.orders[_store.orderIndex(order.id)] = order;
  }

  @override
  Future<AppOrder> cancelOrder(
    String orderId, {
    required AppUser actor,
    required String reason,
    String note = '',
  }) async {
    await _store.wait();
    final order = _get(orderId);
    if (order.status == OrderStatus.cancelled) {
      throw AppException('This order has already been cancelled.');
    }
    if (reason.trim().isEmpty) throw AppException('Please give a cancellation reason.');
    if (actor.isAdmin) {
      if (!order.adminCanCancel) {
        throw AppException('Only Pending or Confirmed orders can be cancelled.');
      }
    } else {
      if (order.userId != actor.id) throw AppException('You can only cancel your own orders.');
      if (!order.customerCanCancel) {
        throw AppException('You can cancel an order only while it is Pending.');
      }
    }
    final now = _store.now();
    final updated = order.copyWith(
      status: OrderStatus.cancelled,
      history: [...order.history, OrderEvent(status: OrderStatus.cancelled, at: now)],
      cancellation: CancellationRecord(
        cancelledBy: actor.isAdmin ? CancelActor.shopAdmin : CancelActor.customer,
        cancelledByName: actor.name,
        reason: reason.trim(),
        note: note.trim(),
        cancelledAt: now,
      ),
    );
    _put(updated);
    _store.notify(
      order.userId,
      'Order cancelled',
      actor.isAdmin
          ? 'Your order ${order.id} was cancelled by the shop. Reason: ${reason.trim()}.'
          : 'Your order ${order.id} has been cancelled.',
    );
    return updated;
  }

  @override
  Future<AppOrder> updateStatus(String orderId, OrderStatus status) async {
    await _store.wait();
    final order = _get(orderId);
    if (order.status.next != status) {
      throw AppException(
        'An order cannot move from ${order.status.label} to ${status.label}.',
      );
    }
    final now = _store.now();
    var payment = order.payment;
    // COD cash is collected on delivery, so completing a COD order confirms it.
    if (status == OrderStatus.completed &&
        payment.method == PaymentMethod.cod &&
        payment.status != PaymentStatus.successful) {
      payment = payment.copyWith(status: PaymentStatus.successful, updatedAt: now);
    }
    final updated = order.copyWith(
      status: status,
      payment: payment,
      history: [...order.history, OrderEvent(status: status, at: now)],
    );
    _put(updated);
    _store.notify(
      order.userId,
      'Order ${status.label}',
      status == OrderStatus.completed
          ? 'Your order ${order.id} is Completed. Share your feedback from the order page.'
          : 'Your order ${order.id} is now ${status.label}.',
    );
    return updated;
  }

  @override
  Future<AppOrder> updatePayment(
    String orderId,
    PaymentStatus status, {
    PaymentProvider provider = PaymentProvider.demo,
    String? transactionRef,
  }) async {
    await _store.wait();
    final order = _get(orderId);
    if (order.payment.method != PaymentMethod.online) {
      throw AppException('Only online payments can be updated this way.');
    }
    if (order.payment.status == PaymentStatus.successful) {
      throw AppException('This order is already paid.');
    }
    if (order.status == OrderStatus.cancelled) {
      throw AppException('This order was cancelled.');
    }
    final updated = order.copyWith(
      payment: order.payment.copyWith(
        status: status,
        provider: provider,
        transactionRef: transactionRef,
        updatedAt: _store.now(),
      ),
    );
    _put(updated);
    return updated;
  }
}

class MockNotificationRepository implements NotificationRepository {
  MockNotificationRepository(this._store);

  final MockStore _store;

  @override
  Future<List<AppNotification>> getVisible(String userId) async {
    await _store.wait();
    final mine = _store.notifications.where((n) => n.userId == userId);
    return NotificationRetention.visible(mine, _store.now());
  }

  @override
  Future<void> markAllRead(String userId) async {
    for (var i = 0; i < _store.notifications.length; i++) {
      final n = _store.notifications[i];
      if (n.userId == userId && !n.read) {
        _store.notifications[i] = n.copyWith(read: true);
      }
    }
  }
}
