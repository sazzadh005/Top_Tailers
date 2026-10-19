import 'package:flutter_test/flutter_test.dart';
import 'package:top_tailers_/app/app_services.dart';
import 'package:top_tailers_/core/app_exception.dart';
import 'package:top_tailers_/domain/discount.dart';
import 'package:top_tailers_/domain/order_search.dart';
import 'package:top_tailers_/domain/pricing.dart';
import 'package:top_tailers_/models/app_user.dart';
import 'package:top_tailers_/models/cancellation.dart';
import 'package:top_tailers_/models/catalog_query.dart';
import 'package:top_tailers_/models/feedback.dart';
import 'package:top_tailers_/models/measurements.dart';
import 'package:top_tailers_/models/order.dart';
import 'package:top_tailers_/models/payment.dart';
import 'package:top_tailers_/models/product.dart';
import 'package:top_tailers_/models/requests.dart';

import 'support.dart';

Matcher throwsApp = throwsA(isA<AppException>());

/// Places an order for the Button & Thread Set (p14, 250.00 each, no discount).
Future<AppOrder> placeButtons(
  AppServices s,
  AppUser user, {
  required String phone,
  int qty = 2,
  String? voucher,
  int? expectedTotal,
  PaymentMethod method = PaymentMethod.cod,
  OrderMeasurementSnapshot? measurements,
  String productId = 'p14',
}) {
  return s.orders.placeOrder(
    PlaceOrderRequest(
      userId: user.id,
      customerName: user.name,
      items: [OrderLineRequest(productId: productId, quantity: qty)],
      contactPhone: phone,
      shippingAddress: user.address,
      voucherCode: voucher,
      paymentMethod: method,
      measurements: measurements,
      expectedTotalMinor: expectedTotal ?? 25000 * qty,
    ),
  );
}

void main() {
  group('Catalog', () {
    test('search matches name, description, category and product code', () async {
      final s = testServices();
      Future<List<String>> ids(String text, {String? category, bool inStock = false}) async {
        final r = await s.catalog.searchProducts(
          ProductQuery(text: text, category: category, inStockOnly: inStock, pageSize: 50),
        );
        return r.items.map((p) => p.id).toList()..sort();
      }

      expect(await ids('cotton'), ['p1', 'p8']);
      expect(await ids('COTTON'), ['p1', 'p8']);
      expect(await ids('FAB-VEL-005'), ['p5']);
      expect(await ids('tlr-'), ['p10', 'p11', 'p12', 'p13']);
      expect(await ids('', category: 'Tailoring'), ['p10', 'p11', 'p12', 'p13']);
      expect((await ids('', category: 'Fabrics', inStock: true)).length, 5);
      expect(await ids('no such thing'), isEmpty);
    });

    test('sorting and paging', () async {
      final s = testServices();
      final cheapest = await s.catalog.searchProducts(
        const ProductQuery(sort: ProductSort.priceLow, pageSize: 3),
      );
      expect(cheapest.items.first.id, 'p15');
      expect(cheapest.hasMore, isTrue);

      final page1 = await s.catalog.searchProducts(const ProductQuery(pageSize: 8));
      final page2 = await s.catalog.searchProducts(const ProductQuery(pageSize: 8, page: 2));
      expect(page1.items.length, 8);
      expect(page1.hasMore, isTrue);
      expect(page2.items.length, 7);
      expect(page2.hasMore, isFalse);
      expect(page1.total, 15);
      final overlap = page1.items.map((p) => p.id).toSet().intersection(page2.items.map((p) => p.id).toSet());
      expect(overlap, isEmpty);
    });

    test('product codes are unique: duplicates rejected on create and edit', () async {
      final s = testServices();
      final base = (await s.catalog.getProduct('p1'))!;
      final draft = Product(
        id: '',
        code: 'fab-cot-001', // same code, different case
        productName: 'Another',
        description: 'x',
        priceMinor: 10000,
        category: 'Fabrics',
        availability: true,
        createdAt: kNow,
      );
      await expectLater(s.catalog.createProduct(draft), throwsApp);
      expect(await s.catalog.isCodeTaken('FAB-COT-001'), isTrue);
      expect(await s.catalog.isCodeTaken('FAB-COT-001', exceptProductId: 'p1'), isFalse);

      final created = await s.catalog.createProduct(draft.copyWith(code: 'fab-new-900'));
      expect(created.code, 'FAB-NEW-900');
      await expectLater(
        s.catalog.updateProduct(created.copyWith(code: base.code)),
        throwsApp,
      );
    });

    test('invalid discounts are rejected', () async {
      final s = testServices();
      final p = (await s.catalog.getProduct('p9'))!; // 1650.00
      for (final bad in [
        const ProductDiscount(enabled: true, kind: DiscountKind.percent, value: 100),
        const ProductDiscount(enabled: true, kind: DiscountKind.percent, value: 0),
        const ProductDiscount(enabled: true, kind: DiscountKind.fixed, value: 165000),
      ]) {
        await expectLater(s.catalog.updateProduct(p.copyWith(discount: bad)), throwsApp);
      }
      final ok = await s.catalog.updateProduct(
        p.copyWith(discount: const ProductDiscount(enabled: true, kind: DiscountKind.percent, value: 20)),
      );
      expect(ok.effectivePriceMinor, 132000);
      expect(ok.hasDiscount, isTrue);
    });

    test('home content separates featured, services and discounted products', () async {
      final s = testServices();
      final home = await s.catalog.getHome();
      expect(home.featured.every((p) => p.isFabric), isTrue);
      expect(home.services.every((p) => p.category == 'Tailoring'), isTrue);
      expect(home.discounted.every((p) => p.hasDiscount), isTrue);
      expect(home.discounted, isNotEmpty);
      expect(home.offers.every((v) => v.isPublic), isTrue);
      expect(home.offers.any((v) => v.code == 'DEMOEXPIRED'), isFalse);
    });
  });

  group('Orders: snapshots', () {
    test('different orders keep their own contact numbers', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      final a = await placeButtons(s, rahim, phone: '01912345678');
      final b = await placeButtons(s, rahim, phone: '01812345678');
      expect(a.contactPhone, '01912345678');
      expect(b.contactPhone, '01812345678');
      expect(rahim.phone, '01712345678'); // profile untouched by ordering
    });

    test('changing the profile phone later does not change an existing order', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      final order = await placeButtons(s, rahim, phone: '01912345678');
      await s.auth.updateProfile(rahim.copyWith(phone: '01611112222'));
      final again = await loginAs(s, kRahim);
      expect(again.phone, '01611112222');

      final orders = await s.orders.searchOrders(const OrderSearchQuery(), viewer: again);
      final stored = orders.firstWhere((o) => o.id == order.id);
      expect(stored.contactPhone, '01912345678');
    });

    test('profile measurement edits do not change an order snapshot', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      final snapshot = OrderMeasurementSnapshot(
        measurements: const BodyMeasurements({MeasurementField.chest: 101, MeasurementField.neck: 39}),
        source: MeasurementSource.enteredForOrder,
        capturedAt: kNow,
      );
      final order = await placeButtons(
        s, rahim,
        phone: '01912345678', qty: 1, productId: 'p10', expectedTotal: 80000,
        measurements: snapshot,
      );

      await s.auth.updateMeasurements(
        rahim.id,
        const BodyMeasurements({MeasurementField.chest: 120}),
        actor: rahim,
      );
      final refreshed = await loginAs(s, kRahim);
      expect(refreshed.measurements[MeasurementField.chest], 120);

      final orders = await s.orders.searchOrders(const OrderSearchQuery(), viewer: refreshed);
      final stored = orders.firstWhere((o) => o.id == order.id);
      expect(stored.measurements!.measurements[MeasurementField.chest], 101);
      expect(stored.measurements!.measurements[MeasurementField.neck], 39);
    });

    test('different orders can carry different measurements, incl. for another person', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      Future<AppOrder> place(double chest, MeasurementSource src, {String? who}) => placeButtons(
            s, rahim,
            phone: '01912345678', qty: 1, productId: 'p10', expectedTotal: 80000,
            measurements: OrderMeasurementSnapshot(
              measurements: BodyMeasurements({MeasurementField.chest: chest}),
              source: src,
              forPerson: who,
              capturedAt: kNow,
            ),
          );
      final a = await place(95, MeasurementSource.profile);
      final b = await place(110, MeasurementSource.otherPerson, who: 'Karim');
      expect(a.measurements!.measurements[MeasurementField.chest], 95);
      expect(b.measurements!.measurements[MeasurementField.chest], 110);
      expect(b.measurements!.forPerson, 'Karim');
    });

    test('tailoring order without measurements is rejected', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      await expectLater(
        placeButtons(s, rahim, phone: '01912345678', qty: 1, productId: 'p10', expectedTotal: 80000),
        throwsApp,
      );
    });

    test('only the admin and the owner can change measurements', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      final nusrat = await loginAs(s, kNusrat);
      final admin = await loginAs(s, kAdmin);
      const m = BodyMeasurements({MeasurementField.waist: 80});
      await expectLater(s.auth.updateMeasurements(rahim.id, m, actor: nusrat), throwsApp);
      expect((await s.auth.updateMeasurements(rahim.id, m, actor: admin)).measurements[MeasurementField.waist], 80);
      await expectLater(s.auth.getCustomers(actor: rahim), throwsApp);
    });
  });

  group('Orders: pricing integrity', () {
    test('stored breakdown equals what the client calculated', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      final voucher = (await s.vouchers.findByCode('demo10'))!;
      final p = (await s.catalog.getProduct('p14'))!;
      final expected = PricingService.compute(
        [PricedLine(category: p.category, listUnitMinor: p.priceMinor, unitMinor: p.effectivePriceMinor, quantity: 2)],
        voucher: voucher,
        now: kNow,
      );
      final order = await placeButtons(
        s, rahim,
        phone: '01912345678', voucher: expected.voucherCode, expectedTotal: expected.totalMinor,
      );
      expect(order.subtotalMinor, expected.subtotalMinor);
      expect(order.voucherDiscountMinor, 5000);
      expect(order.totalMinor, 45000);
      expect(order.voucherCode, 'DEMO10');
    });

    test('a stale client total is rejected', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      await expectLater(placeButtons(s, rahim, phone: '01912345678', expectedTotal: 1), throwsApp);
    });

    test('expired and unknown vouchers are rejected at order time', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      await expectLater(placeButtons(s, rahim, phone: '01912345678', voucher: 'DEMOEXPIRED'), throwsApp);
      await expectLater(placeButtons(s, rahim, phone: '01912345678', voucher: 'NOPE'), throwsApp);
    });

    test('customer discount applies only to the eligible customer', () async {
      final s = testServices();
      final nusrat = await loginAs(s, kNusrat); // active 8%
      final rahim = await loginAs(s, kRahim); // none
      final forNusrat = await placeButtons(s, nusrat, phone: '01911223344', expectedTotal: 46000);
      expect(forNusrat.customerDiscountMinor, 4000);
      expect(forNusrat.totalMinor, 46000);
      final forRahim = await placeButtons(s, rahim, phone: '01712345678');
      expect(forRahim.customerDiscountMinor, 0);
      expect(forRahim.totalMinor, 50000);

      // Inactive discounts do not apply (Tanvir's is switched off).
      final tanvir = await loginAs(s, kTanvir);
      final forTanvir = await placeButtons(s, tanvir, phone: '01611998877');
      expect(forTanvir.customerDiscountMinor, 0);
    });

    test('invalid contact number or empty cart is rejected', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      await expectLater(placeButtons(s, rahim, phone: '12345'), throwsApp);
      await expectLater(
        s.orders.placeOrder(PlaceOrderRequest(
          userId: rahim.id,
          customerName: rahim.name,
          items: const [],
          contactPhone: '01712345678',
          shippingAddress: rahim.address,
          paymentMethod: PaymentMethod.cod,
          expectedTotalMinor: 0,
        )),
        throwsApp,
      );
    });

    test('unavailable products cannot be ordered', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      await expectLater(
        placeButtons(s, rahim, phone: '01712345678', productId: 'p5', expectedTotal: 150000, qty: 1),
        throwsApp,
      );
    });
  });

  group('Payments', () {
    test('order placement and payment completion are separate facts', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      final order = await placeButtons(s, rahim, phone: '01712345678', method: PaymentMethod.online);
      expect(order.status, OrderStatus.pending);
      expect(order.payment.status, PaymentStatus.pending);
      expect(order.payment.method, PaymentMethod.online);
      expect(order.canPayOnline, isTrue);

      final paid = await s.orders.updatePayment(order.id, PaymentStatus.successful);
      expect(paid.payment.status, PaymentStatus.successful);
      expect(paid.payment.isDemo, isTrue);
      expect(paid.payment.statusLabel, 'Paid (demo)');
      expect(paid.status, OrderStatus.pending); // fulfilment unchanged
      expect(paid.canPayOnline, isFalse);
    });

    test('failed and cancelled attempts can be retried', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      final order = await placeButtons(s, rahim, phone: '01712345678', method: PaymentMethod.online);
      final failed = await s.orders.updatePayment(order.id, PaymentStatus.failed);
      expect(failed.payment.status, PaymentStatus.failed);
      expect(failed.canPayOnline, isTrue);
      final cancelled = await s.orders.updatePayment(order.id, PaymentStatus.cancelled);
      expect(cancelled.payment.status, PaymentStatus.cancelled);
      final ok = await s.orders.updatePayment(order.id, PaymentStatus.successful);
      expect(ok.payment.status, PaymentStatus.successful);
      await expectLater(s.orders.updatePayment(order.id, PaymentStatus.failed), throwsApp);
    });

    test('COD orders have no online payment and are confirmed on delivery', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      final admin = await loginAs(s, kAdmin);
      final order = await placeButtons(s, rahim, phone: '01712345678');
      expect(order.payment.provider, PaymentProvider.none);
      expect(order.payment.statusLabel, 'Pay on delivery');
      await expectLater(s.orders.updatePayment(order.id, PaymentStatus.successful), throwsApp);

      await s.orders.updateStatus(order.id, OrderStatus.confirmed);
      await s.orders.updateStatus(order.id, OrderStatus.processing);
      final done = await s.orders.updateStatus(order.id, OrderStatus.completed);
      expect(done.payment.status, PaymentStatus.successful);
      expect(done.payment.statusLabel, 'Paid on delivery');

      final all = await s.orders.searchOrders(const OrderSearchQuery(), viewer: admin);
      expect(all.any((o) => o.id == order.id), isTrue);
    });

    test('status can only move forward one step at a time', () async {
      final s = testServices();
      await expectLater(s.orders.updateStatus('ORD-1002', OrderStatus.completed), throwsApp);
      final next = await s.orders.updateStatus('ORD-1002', OrderStatus.confirmed);
      expect(next.status, OrderStatus.confirmed);
      expect(next.history.last.status, OrderStatus.confirmed);
    });

    test('the demo gateway is clearly a demo and returns no redirect', () async {
      final s = testServices();
      expect(s.payments.isDemo, isTrue);
      final session = await s.payments.initiate(orderId: 'ORD-1002', amountMinor: 1000);
      expect(session.provider, PaymentProvider.demo);
      expect(session.redirectUrl, isNull);
    });
  });

  group('Cancellation', () {
    test('customer cancels a Pending order: reason and actor are recorded', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      final updated = await s.orders.cancelOrder(
        'ORD-1002',
        actor: rahim,
        reason: 'Ordered by mistake',
        note: 'Sorry',
      );
      expect(updated.status, OrderStatus.cancelled);
      final c = updated.cancellation!;
      expect(c.cancelledBy, CancelActor.customer);
      expect(c.cancelledByName, rahim.name);
      expect(c.reason, 'Ordered by mistake');
      expect(c.note, 'Sorry');
      expect(c.cancelledAt, kNow);
      // history is kept, not deleted
      expect(updated.history.map((e) => e.status), [OrderStatus.pending, OrderStatus.cancelled]);
      expect(updated.items, isNotEmpty);
    });

    test('a reason is required and duplicates are rejected', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      await expectLater(s.orders.cancelOrder('ORD-1002', actor: rahim, reason: '  '), throwsApp);
      await s.orders.cancelOrder('ORD-1002', actor: rahim, reason: 'No longer needed');
      await expectLater(
        s.orders.cancelOrder('ORD-1002', actor: rahim, reason: 'No longer needed'),
        throwsApp,
      );
    });

    test('customer cannot cancel Confirmed orders or other people\'s orders', () async {
      final s = testServices();
      final tanvir = await loginAs(s, kTanvir);
      final rahim = await loginAs(s, kRahim);
      await expectLater(s.orders.cancelOrder('ORD-1008', actor: tanvir, reason: 'x'), throwsApp); // Confirmed
      await expectLater(s.orders.cancelOrder('ORD-1002', actor: tanvir, reason: 'x'), throwsApp); // not theirs
      await expectLater(s.orders.cancelOrder('ORD-1003', actor: rahim, reason: 'x'), throwsApp); // Processing
    });

    test('admin cancels a Confirmed order with a reason; Processing is not cancellable', () async {
      final s = testServices();
      final admin = await loginAs(s, kAdmin);
      final updated = await s.orders.cancelOrder(
        'ORD-1008',
        actor: admin,
        reason: 'Item out of stock',
      );
      expect(updated.cancellation!.cancelledBy, CancelActor.shopAdmin);
      expect(updated.cancellation!.reason, 'Item out of stock');
      await expectLater(s.orders.cancelOrder('ORD-1003', actor: admin, reason: 'x'), throwsApp);
    });

    test('seed data includes one customer and one admin cancellation', () async {
      final s = testServices();
      final admin = await loginAs(s, kAdmin);
      final all = await s.orders.searchOrders(const OrderSearchQuery(status: OrderStatus.cancelled), viewer: admin);
      expect(all.map((o) => o.cancellation!.cancelledBy).toSet(), {CancelActor.customer, CancelActor.shopAdmin});
    });

    test('cancelled orders stay in search results and notify the customer', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      await s.orders.cancelOrder('ORD-1002', actor: rahim, reason: 'Ordered by mistake');
      final mine = await s.orders.searchOrders(const OrderSearchQuery(), viewer: rahim);
      expect(mine.any((o) => o.id == 'ORD-1002' && o.status == OrderStatus.cancelled), isTrue);
      final notes = await s.notifications.getVisible(rahim.id);
      expect(notes.first.title, 'Order cancelled');
    });
  });

  group('Feedback', () {
    FeedbackRepoDraft draft(AppUser u, {String order = 'ORD-1009', String product = 'p3', int rating = 5, String comment = 'Lovely fabric'}) =>
        FeedbackRepoDraft(u, order, product, rating, comment);

    test('allowed for a product in your own Completed order, once', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      final saved = await s.feedback.submit(draft(rahim).toFeedback());
      expect(saved.rating, 5);
      await expectLater(s.feedback.submit(draft(rahim).toFeedback()), throwsApp); // duplicate
      final forProduct = await s.feedback.forProduct('p3');
      expect(forProduct.length, 1);
    });

    test('rejected for non-completed orders, other users, wrong product, bad input', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      final nusrat = await loginAs(s, kNusrat);
      await expectLater(s.feedback.submit(draft(rahim, order: 'ORD-1002', product: 'p8').toFeedback()), throwsApp); // pending
      await expectLater(s.feedback.submit(draft(rahim, order: 'ORD-1003', product: 'p10').toFeedback()), throwsApp); // processing
      await expectLater(s.feedback.submit(draft(nusrat).toFeedback()), throwsApp); // not their order
      await expectLater(s.feedback.submit(draft(rahim, product: 'p1').toFeedback()), throwsApp); // not in that order
      await expectLater(s.feedback.submit(draft(rahim, rating: 0).toFeedback()), throwsApp);
      await expectLater(s.feedback.submit(draft(rahim, comment: 'ok').toFeedback()), throwsApp);
    });
  });

  group('Suggestions and restock requests', () {
    test('customers can submit both kinds and admins can update the status', () async {
      final s = testServices();
      final rahim = await loginAs(s, kRahim);
      final idea = await s.requests.submitSuggestion(ProductSuggestion(
        id: '', userId: rahim.id, userName: rahim.name,
        title: 'Muslin fabric', details: 'Light and soft', createdAt: kNow,
      ));
      expect(idea.status, RequestStatus.received);
      final restock = await s.requests.submitRestock(RestockRequest(
        id: '', userId: rahim.id, userName: rahim.name,
        productId: 'p5', productCode: '', productName: '', reason: 'Wedding', createdAt: kNow,
      ));
      expect(restock.productCode, 'FAB-VEL-005'); // filled from the catalogue

      await s.requests.setSuggestionStatus(idea.id, RequestStatus.planned);
      await s.requests.setRestockStatus(restock.id, RequestStatus.underReview);
      expect((await s.requests.suggestionsFor(rahim.id)).first.status, RequestStatus.planned);
      expect((await s.requests.restocksFor(rahim.id)).first.status, RequestStatus.underReview);
      expect((await s.requests.allSuggestions()).length, 2);
    });

    test('open duplicate restock requests are rejected', () async {
      final s = testServices();
      final nusrat = await loginAs(s, kNusrat); // already has an open request for p5
      await expectLater(
        s.requests.submitRestock(RestockRequest(
          id: '', userId: nusrat.id, userName: nusrat.name,
          productId: 'p5', productCode: '', productName: '', reason: '', createdAt: kNow,
        )),
        throwsApp,
      );
    });
  });

  group('Notifications', () {
    test('only notifications from the last 30 days are visible, newest first', () async {
      final s = testServices();
      final notes = await s.notifications.getVisible('u2');
      expect(notes.map((n) => n.id), ['n1', 'n2', 'n3', 'n4']);
      expect(notes.any((n) => n.id == 'n5' || n.id == 'n6' || n.id == 'n7'), isFalse);
    });

    test('mark all read', () async {
      final s = testServices();
      await s.notifications.markAllRead('u2');
      final notes = await s.notifications.getVisible('u2');
      expect(notes.every((n) => n.read), isTrue);
    });
  });
}

/// Small helper so feedback tests stay readable.
class FeedbackRepoDraft {
  FeedbackRepoDraft(this.user, this.orderId, this.productId, this.rating, this.comment);

  final AppUser user;
  final String orderId;
  final String productId;
  final int rating;
  final String comment;

  ProductFeedback toFeedback() => ProductFeedback(
        id: '',
        orderId: orderId,
        productId: productId,
        productName: 'x',
        userId: user.id,
        userName: user.name,
        rating: rating,
        comment: comment,
        createdAt: kNow,
      );
}
