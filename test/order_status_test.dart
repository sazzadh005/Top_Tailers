import 'package:flutter_test/flutter_test.dart';
import 'package:top_tailers_/models/order.dart';

AppOrder _order(OrderStatus status) => AppOrder(
      id: 'ORD-1',
      userId: 'u',
      customerName: 'Test',
      items: const [],
      totalPrice: 0,
      address: 'Somewhere',
      orderDate: DateTime(2026, 10, 1),
      status: status,
    );

void main() {
  test('status flow moves Pending -> Confirmed -> Processing -> Completed', () {
    expect(OrderStatus.pending.next, OrderStatus.confirmed);
    expect(OrderStatus.confirmed.next, OrderStatus.processing);
    expect(OrderStatus.processing.next, OrderStatus.completed);
    expect(OrderStatus.completed.next, isNull);
    expect(OrderStatus.cancelled.next, isNull);
  });

  test('customers can cancel only Pending orders', () {
    expect(_order(OrderStatus.pending).customerCanCancel, isTrue);
    expect(_order(OrderStatus.confirmed).customerCanCancel, isFalse);
    expect(_order(OrderStatus.processing).customerCanCancel, isFalse);
  });

  test('admins can cancel Pending or Confirmed orders', () {
    expect(_order(OrderStatus.pending).adminCanCancel, isTrue);
    expect(_order(OrderStatus.confirmed).adminCanCancel, isTrue);
    expect(_order(OrderStatus.processing).adminCanCancel, isFalse);
    expect(_order(OrderStatus.completed).adminCanCancel, isFalse);
  });
}
