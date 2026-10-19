import 'package:flutter_test/flutter_test.dart';
import 'package:top_tailers_/domain/notification_retention.dart';
import 'package:top_tailers_/domain/order_search.dart';
import 'package:top_tailers_/domain/spending.dart';
import 'package:top_tailers_/models/app_notification.dart';
import 'package:top_tailers_/models/order.dart';
import 'package:top_tailers_/models/payment.dart';

import 'support.dart';

AppNotification note(String id, DateTime? at) => AppNotification(
      id: id,
      userId: 'u2',
      title: id,
      body: '',
      createdAt: at,
    );

void main() {
  group('Notification retention (30 days)', () {
    final now = DateTime(2026, 10, 18, 12);

    test('younger than 30 days is visible', () {
      expect(NotificationRetention.isVisible(note('a', now.subtract(const Duration(days: 29))), now), isTrue);
    });

    test('exactly 30 days old is visible', () {
      expect(NotificationRetention.isVisible(note('a', now.subtract(const Duration(days: 30))), now), isTrue);
    });

    test('older than 30 days is hidden', () {
      final justOver = now.subtract(const Duration(days: 30, seconds: 1));
      expect(NotificationRetention.isVisible(note('a', justOver), now), isFalse);
      expect(NotificationRetention.isVisible(note('b', now.subtract(const Duration(days: 31))), now), isFalse);
    });

    test('missing timestamp is hidden safely', () {
      expect(NotificationRetention.isVisible(note('a', null), now), isFalse);
    });

    test('timestamp in the future does not crash and stays visible', () {
      expect(NotificationRetention.isVisible(note('a', now.add(const Duration(hours: 2))), now), isTrue);
    });

    test('list is filtered and sorted newest first', () {
      final all = [
        note('old', now.subtract(const Duration(days: 45))),
        note('mid', now.subtract(const Duration(days: 10))),
        note('new', now.subtract(const Duration(hours: 1))),
        note('none', null),
        note('edge', now.subtract(const Duration(days: 30))),
      ];
      final ids = NotificationRetention.visible(all, now).map((n) => n.id).toList();
      expect(ids, ['new', 'mid', 'edge']);
    });

    test('age is calculated against the supplied time, not a fixed date', () {
      final n = note('a', DateTime(2026, 1, 1));
      expect(NotificationRetention.isVisible(n, DateTime(2026, 1, 20)), isTrue);
      expect(NotificationRetention.isVisible(n, DateTime(2026, 3, 1)), isFalse);
    });

    test('tolerant parsing of unreadable timestamps', () {
      final n = AppNotification.fromMap({'id': 'x', 'userId': 'u', 'title': 't', 'body': 'b', 'createdAt': 'not a date'});
      expect(n.createdAt, isNull);
      final ok = AppNotification.fromMap({'id': 'x', 'userId': 'u', 'title': 't', 'body': 'b', 'createdAt': '2026-10-01T10:00:00'});
      expect(ok.createdAt, DateTime(2026, 10, 1, 10));
    });
  });

  group('Lifetime spending', () {
    test('counts only Completed orders with confirmed payment', () {
      final orders = [
        makeOrder(id: 'a', total: 10000, status: OrderStatus.completed, payment: PaymentStatus.successful),
        makeOrder(id: 'b', total: 20000, status: OrderStatus.completed, payment: PaymentStatus.successful, method: PaymentMethod.online),
        makeOrder(id: 'c', total: 40000, status: OrderStatus.cancelled, payment: PaymentStatus.successful),
        makeOrder(id: 'd', total: 80000, status: OrderStatus.completed, payment: PaymentStatus.pending, method: PaymentMethod.online),
        makeOrder(id: 'e', total: 160000, status: OrderStatus.completed, payment: PaymentStatus.failed, method: PaymentMethod.online),
        makeOrder(id: 'f', total: 320000, status: OrderStatus.processing, payment: PaymentStatus.successful, method: PaymentMethod.online),
        makeOrder(id: 'g', total: 640000, status: OrderStatus.pending, payment: PaymentStatus.pending),
      ];
      expect(SpendingCalculator.lifetimeSpendingMinor(orders), 30000);
    });

    test('does not double count an order that appears twice', () {
      final o = makeOrder(id: 'a', total: 10000, status: OrderStatus.completed, payment: PaymentStatus.successful);
      expect(SpendingCalculator.lifetimeSpendingMinor([o, o]), 10000);
      expect(SpendingCalculator.orderCount([o, o]), 1);
    });

    test('COD order counts once its payment is confirmed on completion', () {
      final unpaid = makeOrder(id: 'a', total: 5000, status: OrderStatus.completed, payment: PaymentStatus.pending);
      final paid = unpaid.copyWith(payment: unpaid.payment.copyWith(status: PaymentStatus.successful));
      expect(SpendingCalculator.lifetimeSpendingMinor([unpaid]), 0);
      expect(SpendingCalculator.lifetimeSpendingMinor([paid]), 5000);
    });

    test('seed data: figures match hand calculation', () async {
      final s = testServices();
      final admin = await loginAs(s, kAdmin);
      final all = await s.orders.searchOrders(const OrderSearchQuery(), viewer: admin);
      int spent(String user) => SpendingCalculator.lifetimeSpendingMinor(all.where((o) => o.userId == user));
      expect(spent('u2'), 121500 + 320000); // ORD-1001 + ORD-1009
      expect(spent('u3'), 220800); // ORD-1004 (ORD-1005 payment failed, excluded)
      expect(spent('u4'), 0); // cancelled and confirmed only
    });
  });

  group('Order search', () {
    final orders = [
      makeOrder(id: 'ORD-1', reference: 'TTF-261001-AAAA', phone: '01712345678', date: DateTime(2026, 10, 1, 10)),
      makeOrder(
        id: 'ORD-2',
        userId: 'u3',
        customerName: 'Nusrat Jahan',
        reference: 'TTF-261010-BBBB',
        phone: '01911223344',
        status: OrderStatus.completed,
        method: PaymentMethod.online,
        payment: PaymentStatus.failed,
        date: DateTime(2026, 10, 10, 10),
        items: const [
          OrderItem(
            productId: 'p10',
            productCode: 'TLR-SHT-201',
            productName: 'Shirt Stitching Service',
            listUnitMinor: 80000,
            unitMinor: 80000,
            quantity: 1,
            category: 'Tailoring',
          ),
        ],
      ),
    ];

    List<String> ids(OrderSearchQuery q, {bool admin = true}) =>
        OrderSearch.filter(orders, q, includeCustomerName: admin).map((o) => o.id).toList();

    test('by order id or reference', () {
      expect(ids(const OrderSearchQuery(text: 'ord-2')), ['ORD-2']);
      expect(ids(const OrderSearchQuery(text: 'TTF-261001')), ['ORD-1']);
    });

    test('by product code and product name', () {
      expect(ids(const OrderSearchQuery(text: 'TLR-SHT-201')), ['ORD-2']);
      expect(ids(const OrderSearchQuery(text: 'stitching')), ['ORD-2']);
      expect(ids(const OrderSearchQuery(text: 'fab-cot-001')), ['ORD-1']);
    });

    test('by mobile number, ignoring formatting', () {
      expect(ids(const OrderSearchQuery(text: '01911223344')), ['ORD-2']);
      expect(ids(const OrderSearchQuery(text: '0191')), ['ORD-2']);
    });

    test('by status and payment status', () {
      expect(ids(const OrderSearchQuery(status: OrderStatus.completed)), ['ORD-2']);
      expect(ids(const OrderSearchQuery(paymentStatus: PaymentStatus.failed)), ['ORD-2']);
      expect(ids(const OrderSearchQuery(text: 'completed')), ['ORD-2']);
    });

    test('customer name matches only in the admin scope', () {
      expect(ids(const OrderSearchQuery(text: 'nusrat')), ['ORD-2']);
      expect(ids(const OrderSearchQuery(text: 'nusrat'), admin: false), isEmpty);
    });

    test('date range is inclusive of both days', () {
      final q = OrderSearchQuery(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 1));
      expect(ids(q), ['ORD-1']);
      final wide = OrderSearchQuery(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 10));
      expect(ids(wide), ['ORD-2', 'ORD-1']);
    });

    test('multiple words must all match', () {
      expect(ids(const OrderSearchQuery(text: 'nusrat stitching')), ['ORD-2']);
      expect(ids(const OrderSearchQuery(text: 'nusrat cotton')), isEmpty);
    });

    test('validation', () {
      expect(OrderSearch.validate(OrderSearchQuery(from: DateTime(2026, 10, 5), to: DateTime(2026, 10, 1))), isNotNull);
      expect(OrderSearch.validate(OrderSearchQuery(text: 'x' * 61)), isNotNull);
      expect(OrderSearch.validate(const OrderSearchQuery(text: 'ok')), isNull);
    });

    test('repository enforces access scope', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      final admin = await loginAs(s, kAdmin);

      final mine = await s.orders.searchOrders(const OrderSearchQuery(), viewer: rahim);
      expect(mine.every((o) => o.userId == rahim.id), isTrue);
      expect(mine.length, 4);

      // A customer searching for another customer's data sees nothing.
      final peek = await s.orders.searchOrders(const OrderSearchQuery(text: 'Nusrat'), viewer: rahim);
      expect(peek, isEmpty);
      final peekById = await s.orders.searchOrders(const OrderSearchQuery(text: 'ORD-1004'), viewer: rahim);
      expect(peekById, isEmpty);

      final all = await s.orders.searchOrders(const OrderSearchQuery(), viewer: admin);
      expect(all.length, 9);
      final byCode = await s.orders.searchOrders(const OrderSearchQuery(text: 'FAB-LIN-004'), viewer: admin);
      expect(byCode.map((o) => o.id), ['ORD-1005']);
    });
  });
}
