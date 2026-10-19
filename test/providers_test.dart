import 'package:flutter_test/flutter_test.dart';
import 'package:top_tailers_/core/app_exception.dart';
import 'package:top_tailers_/domain/pricing.dart';
import 'package:top_tailers_/models/cart_item.dart';
import 'package:top_tailers_/models/catalog_query.dart';
import 'package:top_tailers_/models/order.dart';
import 'package:top_tailers_/models/payment.dart';
import 'package:top_tailers_/providers/auth_provider.dart';
import 'package:top_tailers_/providers/cart_provider.dart';
import 'package:top_tailers_/providers/catalog_provider.dart';
import 'package:top_tailers_/providers/orders_provider.dart';
import 'package:top_tailers_/providers/wishlist_provider.dart';

import 'support.dart';

void main() {
  group('CatalogProvider (existing search preserved)', () {
    test('search, clear, category and paging', () async {
      final s = testServices();
      final c = CatalogProvider(s.catalog, searchDelay: Duration.zero);
      await c.loadFirstPage();
      expect(c.state, LoadState.ready);
      expect(c.items.length, 8);
      expect(c.hasMore, isTrue);
      expect(c.total, 15);

      c.setQuery('cotton');
      await pumpEventQueue();
      expect(c.items.map((p) => p.id).toSet(), {'p1', 'p8'});
      expect(c.hasActiveFilters, isTrue);

      c.setQuery('');
      await pumpEventQueue();
      expect(c.total, 15);

      await c.loadMore();
      expect(c.items.length, 15);
      expect(c.hasMore, isFalse);

      c.setCategory('Tailoring');
      await pumpEventQueue();
      expect(c.total, 4);

      c.clearFilters();
      await pumpEventQueue();
      expect(c.hasActiveFilters, isFalse);
      expect(c.total, 15);
    });

    test('search by product code works for admins', () async {
      final s = testServices();
      final c = CatalogProvider(s.catalog, searchDelay: Duration.zero);
      c.setQuery('FAB-SLK-002');
      await pumpEventQueue();
      expect(c.items.map((p) => p.id), ['p2']);
    });

    test('sort and in-stock filter', () async {
      final s = testServices();
      final c = CatalogProvider(s.catalog, searchDelay: Duration.zero);
      c.setSort(ProductSort.priceHigh);
      await pumpEventQueue();
      expect(c.items.first.effectivePriceMinor >= c.items.last.effectivePriceMinor, isTrue);
      c.setInStockOnly(true);
      await pumpEventQueue();
      expect(c.items.every((p) => p.availability), isTrue);
    });

    test('recently viewed keeps the newest first without duplicates', () async {
      final s = testServices();
      final c = CatalogProvider(s.catalog, searchDelay: Duration.zero);
      final a = (await s.catalog.getProduct('p1'))!;
      final b = (await s.catalog.getProduct('p2'))!;
      c.markViewed(a);
      c.markViewed(b);
      c.markViewed(a);
      expect(c.recentlyViewed.map((p) => p.id), ['p1', 'p2']);
    });

    test('reset clears state', () async {
      final s = testServices();
      final c = CatalogProvider(s.catalog, searchDelay: Duration.zero);
      await c.loadFirstPage();
      c.reset();
      expect(c.items, isEmpty);
      expect(c.state, LoadState.idle);
    });
  });

  group('CartProvider', () {
    CartProvider makeCart(dynamic s) => CartProvider(s.vouchers, s.discounts, clock: () => kNow);

    test('same product with different variants is a separate line', () async {
      final s = testServices();
      final cart = makeCart(s);
      final p = (await s.catalog.getProduct('p1'))!;
      cart.add(p, colorName: 'White');
      cart.add(p, colorName: 'Sand');
      cart.add(p, colorName: 'White', quantity: 2);
      expect(cart.items.length, 2);
      expect(cart.count, 4);
      expect(cart.quantityOf('p1'), 4);
    });

    test('quantity changes and removal keep totals consistent', () async {
      final s = testServices();
      final cart = makeCart(s);
      final p = (await s.catalog.getProduct('p14'))!;
      cart.add(p);
      final key = cart.items.first.key;
      cart.setQuantity(key, 3);
      expect(cart.breakdown.totalMinor, 75000);
      cart.setQuantity(key, 0);
      expect(cart.isEmpty, isTrue);
      expect(cart.breakdown.totalMinor, 0);
    });

    test('unavailable products are refused', () async {
      final s = testServices();
      final cart = makeCart(s);
      final velvet = (await s.catalog.getProduct('p5'))!;
      expect(cart.add(velvet), isFalse);
      expect(cart.isEmpty, isTrue);
    });

    test('discounted product shows list price, discount and payable total', () async {
      final s = testServices();
      final cart = makeCart(s);
      cart.add((await s.catalog.getProduct('p1'))!, quantity: 3, colorName: 'White');
      final b = cart.breakdown;
      expect(b.subtotalMinor, 135000);
      expect(b.productDiscountMinor, 13500);
      expect(b.totalMinor, 121500);
    });

    test('voucher apply and remove recalculate the total', () async {
      final s = testServices();
      final cart = makeCart(s);
      cart.add((await s.catalog.getProduct('p14'))!, quantity: 2);
      expect(cart.breakdown.totalMinor, 50000);

      final ok = await cart.applyVoucher('demo10');
      expect(ok.ok, isTrue);
      expect(cart.breakdown.voucherDiscountMinor, 5000);
      expect(cart.breakdown.totalMinor, 45000);

      cart.removeVoucher();
      expect(cart.voucher, isNull);
      expect(cart.breakdown.totalMinor, 50000);
    });

    test('empty, unknown, expired, inactive and inapplicable vouchers give messages', () async {
      final s = testServices();
      final cart = makeCart(s);
      expect((await cart.applyVoucher('  ')).ok, isFalse);
      expect((await cart.applyVoucher('DEMO10')).message, contains('cart')); // empty cart

      cart.add((await s.catalog.getProduct('p14'))!);
      expect((await cart.applyVoucher('NOPE')).ok, isFalse);
      expect((await cart.applyVoucher('DEMOEXPIRED')).message, contains('expired'));
      expect((await cart.applyVoucher('DEMOOFF')).message, contains('not active'));
      final wrongCategory = await cart.applyVoucher('DEMOFAB15'); // fabrics only
      expect(wrongCategory.ok, isFalse);
      expect(cart.voucher, isNull);
    });

    test('voucher does not apply to an already-discounted item', () async {
      final s = testServices();
      final cart = makeCart(s);
      cart.add((await s.catalog.getProduct('p1'))!, colorName: 'White'); // 10% product discount
      final r = await cart.applyVoucher('DEMO10');
      expect(r.ok, isFalse);
      expect(cart.breakdown.voucherDiscountMinor, 0);
    });

    test('removing the item that made a voucher eligible drops the discount', () async {
      final s = testServices();
      final cart = makeCart(s);
      cart.add((await s.catalog.getProduct('p14'))!);
      await cart.applyVoucher('DEMO10');
      expect(cart.breakdown.voucherDiscountMinor, 2500);
      cart.remove(cart.items.first.key);
      expect(cart.breakdown.totalMinor, 0);
      expect(cart.breakdown.voucherDiscountMinor, 0);
    });

    test('customer discount and voucher do not stack', () async {
      final s = testServices();
      final cart = makeCart(s);
      await cart.attachCustomer('u3'); // 8% customer discount
      cart.add((await s.catalog.getProduct('p14'))!); // 25000
      expect(cart.breakdown.customerDiscountMinor, 2000);

      await cart.applyVoucher('DEMO10'); // 10% = 2500 beats 8% = 2000
      var b = cart.breakdown;
      expect(b.source, OrderDiscountSource.voucher);
      expect(b.customerDiscountMinor, 0);
      expect(b.totalMinor, 22500);

      cart.removeVoucher();
      b = cart.breakdown;
      expect(b.source, OrderDiscountSource.customer);
      expect(b.totalMinor, 23000);
    });

    test('customer discount applies only to the matching customer', () async {
      final s = testServices();
      final cart = makeCart(s);
      await cart.attachCustomer('u2'); // Rahim has none
      cart.add((await s.catalog.getProduct('p14'))!);
      expect(cart.breakdown.customerDiscountMinor, 0);
    });

    test('clear empties the cart and drops the voucher', () async {
      final s = testServices();
      final cart = makeCart(s);
      cart.add((await s.catalog.getProduct('p14'))!);
      await cart.applyVoucher('DEMO10');
      cart.clear();
      expect(cart.isEmpty, isTrue);
      expect(cart.voucher, isNull);
    });

    test('needsMeasurements is true only for tailoring services', () async {
      final s = testServices();
      final cart = makeCart(s);
      cart.add((await s.catalog.getProduct('p14'))!);
      expect(cart.needsMeasurements, isFalse);
      cart.add((await s.catalog.getProduct('p10'))!);
      expect(cart.needsMeasurements, isTrue);
    });
  });

  group('OrdersProvider', () {
    test('customer sees own orders and can search them', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      final o = OrdersProvider(s.orders, s.payments, searchDelay: Duration.zero);
      await o.load(rahim);
      expect(o.orders.length, 4);

      o.setText('1003');
      await pumpEventQueue();
      expect(o.orders.map((x) => x.id), ['ORD-1003']);

      o.clearSearch();
      await pumpEventQueue();
      expect(o.orders.length, 4);

      o.setText('Nusrat'); // another customer's name: nothing, ever
      await pumpEventQueue();
      expect(o.orders, isEmpty);
    });

    test('admin search by customer name, product code, status and payment status', () async {
      final s = testServices();
      final admin = await loginAs(s, kAdmin);
      final o = OrdersProvider(s.orders, s.payments, searchDelay: Duration.zero);
      await o.load(admin);
      expect(o.orders.length, 9);

      o.setText('nusrat');
      await pumpEventQueue();
      expect(o.orders.length, 2);

      o.setText('FAB-LIN-004');
      await pumpEventQueue();
      expect(o.orders.map((x) => x.id), ['ORD-1005']);

      o.clearSearch();
      o.setStatus(OrderStatus.cancelled);
      await pumpEventQueue();
      expect(o.orders.length, 2);

      o.clearSearch();
      o.setPaymentStatus(PaymentStatus.failed);
      await pumpEventQueue();
      expect(o.orders.map((x) => x.id), ['ORD-1005']);
    });

    test('invalid date range surfaces a validation error', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      final o = OrdersProvider(s.orders, s.payments, searchDelay: Duration.zero);
      await o.load(rahim);
      o.setDateRange(DateTime(2026, 10, 10), DateTime(2026, 10, 1));
      await pumpEventQueue();
      expect(o.state, LoadState.error);
      expect(o.error, isNotNull);
    });

    test('place order stores the contact number on the order and keeps it', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      final o = OrdersProvider(s.orders, s.payments, searchDelay: Duration.zero);
      await o.load(rahim);
      final product = (await s.catalog.getProduct('p14'))!;
      final item = CartItem(product: product, quantity: 2);
      final breakdown = PricingService.compute([item.toPricedLine()], now: kNow);

      final order = await o.placeOrder(
        user: rahim,
        items: [item],
        breakdown: breakdown,
        contactPhone: '01912345678',
        address: rahim.address,
        note: 'Call first',
        method: PaymentMethod.cod,
      );
      expect(order.contactPhone, '01912345678');
      expect(order.totalMinor, breakdown.totalMinor); // checkout total == confirmation total
      expect(order.note, 'Call first');
      expect(o.byId(order.id), isNotNull);
      expect(o.orders.first.id, order.id);
    });

    test('cancel through the provider records who and why', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      final o = OrdersProvider(s.orders, s.payments, searchDelay: Duration.zero);
      await o.load(rahim);
      await o.cancelOrder('ORD-1002', reason: 'Ordered by mistake');
      expect(o.byId('ORD-1002')!.cancellation!.reason, 'Ordered by mistake');
      await expectLater(
        o.cancelOrder('ORD-1002', reason: 'again'),
        throwsA(isA<AppException>()),
      );
    });

    test('online payment goes through the replaceable gateway', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      final o = OrdersProvider(s.orders, s.payments, searchDelay: Duration.zero);
      await o.load(rahim);
      expect(o.isDemoGateway, isTrue);
      final order = o.byId('ORD-1002')!;
      final session = await o.startOnlinePayment(order);
      expect(session.orderId, 'ORD-1002');
      await o.recordPayment('ORD-1002', PaymentStatus.failed);
      expect(o.byId('ORD-1002')!.payment.status, PaymentStatus.failed);
      expect(o.byId('ORD-1002')!.status, OrderStatus.pending);
    });
  });

  group('AuthProvider and WishlistProvider', () {
    test('login failure, success and logout', () async {
      final s = testServices();
      final a = AuthProvider(s.auth, splash: Duration.zero);
      await expectLater(a.login('customer@example.com', 'wrong'), throwsA(isA<AppException>()));
      expect(a.user, isNull);
      await a.login(kRahim, 'Customer@123');
      expect(a.user!.name, 'Rahim Uddin');
      expect(a.isAdmin, isFalse);
      a.logout();
      expect(a.user, isNull);
      await a.login(kAdmin, 'Admin@123');
      expect(a.isAdmin, isTrue);
    });

    test('registration saves optional measurements and rejects duplicate emails', () async {
      final s = testServices();
      final a = AuthProvider(s.auth, splash: Duration.zero);
      await a.register(
        name: 'New Customer',
        email: 'new@example.com',
        phone: '01712345600',
        address: 'Road 1, Gazipur',
        password: 'secret1',
      );
      expect(a.user!.measurements.isEmpty, isTrue);
      await expectLater(
        a.register(
          name: 'Dup',
          email: 'NEW@example.com',
          phone: '01712345601',
          address: 'Road 2, Gazipur',
          password: 'secret1',
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('wishlist toggles and persists per user', () async {
      final s = testServices();
      final w = WishlistProvider(s.wishlist, s.catalog);
      await w.load('u2');
      final p = (await s.catalog.getProduct('p1'))!;
      await w.toggle(p);
      expect(w.isSaved('p1'), isTrue);
      expect(w.products.map((x) => x.id), ['p1']);

      final again = WishlistProvider(s.wishlist, s.catalog);
      await again.load('u2');
      expect(again.isSaved('p1'), isTrue);
      final other = WishlistProvider(s.wishlist, s.catalog);
      await other.load('u3');
      expect(other.isSaved('p1'), isFalse);

      await w.toggle(p);
      expect(w.isSaved('p1'), isFalse);
    });
  });
}
