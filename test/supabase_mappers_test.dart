// Contract tests: the Dart mappers must parse REAL output of the backend's SQL
// functions. The fixtures in test/fixtures are captured by
// backend/tests/export_fixtures.mjs from the actual database functions, so a
// change to either side that breaks the contract fails here.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:top_tailers_/data/supabase/json_mappers.dart';
import 'package:top_tailers_/domain/discount.dart';
import 'package:top_tailers_/models/app_user.dart';
import 'package:top_tailers_/models/cancellation.dart';
import 'package:top_tailers_/models/measurements.dart';
import 'package:top_tailers_/models/order.dart';
import 'package:top_tailers_/models/payment.dart';
import 'package:top_tailers_/models/requests.dart';

Object? readFixture(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());
Json fixtureObject(String name) => asJson(readFixture(name));
List<Json> fixtureList(String name) => asJsonList(readFixture(name));

void main() {
  group('products', () {
    test('a full product maps images, variants, specs and discount', () {
      final p = productFromJson(fixtureObject('product'));
      expect(p.code, 'FIX-001');
      expect(p.priceMinor, 45000);
      expect(p.unit, 'yard');
      expect(p.imagePaths.single, startsWith('https://res.cloudinary.com/'));
      expect(p.imagePublicIds.single, 'toptailers/products/fixture-1');
      expect(p.sizes, ['M', 'L']);
      expect(p.colors.single.name, 'Sand');
      expect(p.colors.single.argb, 0xFFD8C3A0);
      expect(p.specs['Material'], 'Cotton');
      expect(p.discount!.enabled, isTrue);
      expect(p.discount!.kind, DiscountKind.fixed);
      expect(p.discount!.value, 5000);
      expect(p.isFeatured, isTrue);
    });

    test('a page of products keeps paging metadata', () {
      final page = productPageFromJson(fixtureObject('product_page'));
      expect(page.items.length, 3);
      expect(page.page, 1);
      expect(page.hasMore, isTrue);
      expect(page.total, greaterThan(3));
    });

    test('home content maps every shelf and the public offers', () {
      final h = homeFromJson(fixtureObject('home'));
      expect(h.banners.length, 2);
      expect(h.banners.first.title, 'Festive Fabrics');
      expect(h.banners.first.category, 'Fabrics');
      expect(h.banners.first.voucherCode, 'DEMOFAB15');
      expect(h.banners.last.voucherCode, isNull);
      expect(h.featured, isNotEmpty);
      expect(h.services.every((p) => p.category == 'Tailoring'), isTrue);
      expect(h.discounted.every((p) => p.discount?.enabled ?? false), isTrue);
      expect(h.offers.map((o) => o.code).toSet(), {'DEMO10', 'DEMOFAB15'});
    });

    test('a voucher maps its rules', () {
      final v = voucherFromJson(fixtureObject('voucher'));
      expect(v.code, 'DEMOFAB15');
      expect(v.kind, DiscountKind.percent);
      expect(v.value, 15);
      expect(v.categories, {'Fabrics'});
      expect(v.isActive, isTrue);
      expect(v.expiresAt, isNull);
    });

    test('a product round-trips to the save payload the server expects', () {
      final p = productFromJson(fixtureObject('product'));
      final body = productToJson(p);
      expect(body['id'], p.id);
      expect(body['priceMinor'], 45000);
      expect((body['discount'] as Map)['kind'], 'fixed');
      expect(body['imagePublicIds'], ['toptailers/products/fixture-1']);
      expect((body['colors'] as List).single, {'name': 'Sand', 'argb': 0xFFD8C3A0});
      final draft = productToJson(p.copyWith());
      expect(draft.containsKey('id'), isFalse, reason: 'a new product has no id yet');
    });
  });

  group('users and discounts', () {
    test('the profile carries measurements and role', () {
      final u = userFromJson(fixtureObject('user'));
      expect(u.role, UserRole.customer);
      expect(u.email, 'rahim@example.com');
      expect(u.phone, '01712345678');
      expect(u.measurements[MeasurementField.chest], 98.5);
      expect(u.measurements[MeasurementField.waist], 86.0);
    });

    test('the customer list carries server-calculated spending', () {
      final completed = orderFromJson(fixtureObject('order_completed'));
      final customers = fixtureList('customers').map(customerSummaryFromJson).toList();
      final rahim = customers.firstWhere((c) => c.user.email == 'rahim@example.com');
      expect(rahim.orderCount, 3);
      // Only the Completed + paid order counts: not the cancelled one, not the unconfirmed online one.
      expect(rahim.lifetimeSpendingMinor, completed.totalMinor);
      final nusrat = customers.firstWhere((c) => c.user.email == 'nusrat@example.com');
      expect(nusrat.orderCount, 0);
      expect(nusrat.lifetimeSpendingMinor, 0);
    });

    test('a customer discount maps', () {
      final d = customerDiscountFromJson(fixtureObject('customer_discount'));
      expect(d.kind, DiscountKind.percent);
      expect(d.value, 8);
      expect(d.active, isTrue);
      expect(d.note, 'regular customer');
    });
  });

  group('orders', () {
    test('a completed cash-on-delivery tailoring order keeps its full snapshot', () {
      final o = orderFromJson(fixtureObject('order_completed'));
      expect(o.status, OrderStatus.completed);
      expect(o.reference, startsWith('TTF-'));
      expect(o.note, 'Fixture order');
      expect(o.items.length, 2);
      expect(o.items.map((i) => i.productCode), containsAll(['TLR-SHT-201', 'ACC-BTN-301']));
      expect(o.payment.method, PaymentMethod.cod);
      expect(o.payment.provider, PaymentProvider.none);
      expect(o.payment.status, PaymentStatus.successful, reason: 'completing COD confirms the payment');
      expect(o.measurements!.source, MeasurementSource.profile);
      expect(o.measurements!.measurements[MeasurementField.chest], 98.5);
      expect(o.history.map((e) => e.status), [
        OrderStatus.pending, OrderStatus.confirmed, OrderStatus.processing, OrderStatus.completed,
      ]);
      expect(o.cancellation, isNull);
      expect(o.customerDiscountMinor, greaterThan(0), reason: 'the customer discount was applied server-side');
      expect(o.voucherDiscountMinor, 0);
      expect(
        o.subtotalMinor - o.productDiscountMinor - o.customerDiscountMinor - o.voucherDiscountMinor + o.deliveryMinor,
        o.totalMinor,
      );
    });

    test('a cancelled order exposes who cancelled it and why', () {
      final o = orderFromJson(fixtureObject('order_cancelled'));
      expect(o.status, OrderStatus.cancelled);
      final c = o.cancellation!;
      expect(c.cancelledBy, CancelActor.customer);
      expect(c.reason, 'Ordered by mistake');
      expect(c.note, 'Fixture note');
      expect(c.cancelledByName, 'Rahim Uddin');
      expect(o.history.map((e) => e.status), [OrderStatus.pending, OrderStatus.cancelled]);
    });

    test('an online order paid through the verified path shows the AamarPay record', () {
      final o = orderFromJson(fixtureObject('order_online_paid'));
      expect(o.payment.method, PaymentMethod.online);
      expect(o.payment.provider, PaymentProvider.aamarpay);
      expect(o.payment.status, PaymentStatus.successful);
      expect(o.payment.transactionRef, 'PG-FIXTURE');
      expect(o.status, OrderStatus.pending, reason: 'payment does not change the order status');
    });

    test('the order list maps every order', () {
      final orders = fixtureList('order_list').map(orderFromJson).toList();
      expect(orders.length, 3);
      expect(orders.map((o) => o.reference).toSet().length, 3);
    });

    test('the place-order payload never carries prices, only ids, quantities and the expected total', () {
      const request = PlaceOrderRequest(
        userId: 'u1',
        customerName: 'Rahim',
        contactPhone: '01712345678',
        shippingAddress: 'House 12, Road 4, Gazipur',
        note: 'Call first',
        voucherCode: 'DEMO10',
        paymentMethod: PaymentMethod.online,
        expectedTotalMinor: 46000,
        idempotencyKey: 'abc',
        items: [
          OrderLineRequest(productId: 'p1', quantity: 2, colorName: 'White', size: 'M'),
          OrderLineRequest(productId: 'p2', quantity: 1),
        ],
      );
      final body = orderRequestToJson(request);
      expect(body['paymentMethod'], 'online');
      expect(body['expectedTotalMinor'], 46000);
      expect(body['voucherCode'], 'DEMO10');
      final items = body['items'] as List;
      expect(items[0], {'productId': 'p1', 'quantity': 2, 'colorName': 'White', 'size': 'M'});
      expect(items[1], {'productId': 'p2', 'quantity': 1});
      expect(body.toString(), isNot(contains('unitMinor')));
      expect(body.toString(), isNot(contains('priceMinor')));
      expect(body.containsKey('idempotencyKey'), isFalse, reason: 'the key travels as its own parameter');
      expect(body['measurements'], isNull);
    });
  });

  group('engagement', () {
    test('feedback, suggestion, restock and notification fixtures map', () {
      final f = feedbackFromJson(fixtureList('feedback_list').single);
      expect(f.rating, 5);
      expect(f.productName, 'Shirt Stitching Service');
      final s = suggestionFromJson(fixtureList('suggestions').single);
      expect(s.title, 'Muslin fabric');
      expect(s.status, RequestStatus.received);
      final r = restockFromJson(fixtureList('restocks').single);
      expect(r.productCode, 'FAB-VEL-005');
      expect(r.status, RequestStatus.received);
      final notes = fixtureList('notifications').map(notificationFromJson).toList();
      expect(notes, isNotEmpty);
      expect(notes.every((n) => n.createdAt != null), isTrue);
    });
  });

  test('date-only formatting for the order-search filters', () {
    expect(dateOnly(DateTime(2026, 3, 7)), '2026-03-07');
    expect(dateOnly(null), isNull);
  });
}
