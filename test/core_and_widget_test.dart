import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_tailers_/core/validators.dart';
import 'package:top_tailers_/domain/pricing.dart';
import 'package:top_tailers_/main.dart';
import 'package:top_tailers_/models/measurements.dart';
import 'package:top_tailers_/models/order.dart';
import 'package:top_tailers_/widgets/price_breakdown_card.dart';

import 'support.dart';

void main() {
  group('Validators', () {
    test('Bangladeshi mobile numbers', () {
      for (final ok in ['01712345678', '+8801712345678', '8801912345678', '017 1234 5678', '017-1234-5678']) {
        expect(Validators.phone(ok), isNull, reason: ok);
      }
      for (final bad in ['', '12345', '0121234567', '02712345678', '017123456789', 'abc']) {
        expect(Validators.phone(bad), isNotNull, reason: bad);
      }
    });

    test('email, password, address, voucher code, price', () {
      expect(Validators.email('a@b.co'), isNull);
      expect(Validators.email('nope'), isNotNull);
      expect(Validators.password('12345'), isNotNull);
      expect(Validators.password('123456'), isNull);
      expect(Validators.address('short'), isNotNull);
      expect(Validators.address('House 1, Road 2'), isNull);
      expect(Validators.voucherCode(''), isNotNull);
      expect(Validators.voucherCode('DEMO10'), isNull);
      expect(Validators.voucherCode('bad code!'), isNotNull);
      expect(Validators.price('0'), isNotNull);
      expect(Validators.price('-1'), isNotNull);
      expect(Validators.price('450.50'), isNull);
      expect(Validators.price('abc'), isNotNull);
    });

    test('product codes', () {
      expect(Validators.productCode('FAB-COT-001'), isNull);
      expect(Validators.productCode('fab-cot-001'), isNull); // normalized to upper case when saved
      expect(Validators.productCode(''), isNotNull);
      expect(Validators.productCode('A'), isNotNull);
      expect(Validators.productCode('FAB--001'), isNotNull);
      expect(Validators.productCode('FAB 001'), isNotNull);
    });
  });

  group('Measurements', () {
    test('range validation per field', () {
      expect(MeasurementField.chest.validate(''), isNull); // optional
      expect(MeasurementField.chest.validate('98'), isNull);
      expect(MeasurementField.chest.validate('98.5'), isNull);
      expect(MeasurementField.chest.validate('5'), isNotNull);
      expect(MeasurementField.chest.validate('500'), isNotNull);
      expect(MeasurementField.chest.validate('abc'), isNotNull);
      expect(MeasurementField.neck.validate('38'), isNull);
    });

    test('fromText ignores blanks and invalid entries', () {
      final m = BodyMeasurements.fromText({
        MeasurementField.chest: '98',
        MeasurementField.waist: '',
        MeasurementField.hip: 'x',
      });
      expect(m.values.length, 1);
      expect(m[MeasurementField.chest], 98);
      expect(BodyMeasurements.toText(98), '98');
      expect(BodyMeasurements.toText(98.5), '98.5');
    });
  });

  group('Order rules', () {
    test('status flow and cancel rules follow the SRS', () {
      expect(OrderStatus.pending.next, OrderStatus.confirmed);
      expect(OrderStatus.processing.next, OrderStatus.completed);
      expect(OrderStatus.completed.next, isNull);
      expect(OrderStatus.cancelled.next, isNull);
      expect(makeOrder(status: OrderStatus.pending).customerCanCancel, isTrue);
      expect(makeOrder(status: OrderStatus.confirmed).customerCanCancel, isFalse);
      expect(makeOrder(status: OrderStatus.confirmed).adminCanCancel, isTrue);
      expect(makeOrder(status: OrderStatus.processing).adminCanCancel, isFalse);
    });
  });

  group('Widgets', () {
    testWidgets('price breakdown lists every component and the final total', (tester) async {
      const breakdown = PriceBreakdown(
        subtotalMinor: 200000,
        productDiscountMinor: 10000,
        customerDiscountMinor: 0,
        voucherDiscountMinor: 20000,
        deliveryMinor: 6000,
        voucherCode: 'DEMO10',
        source: OrderDiscountSource.voucher,
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PriceBreakdownCard(breakdown: breakdown))),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Items subtotal'), findsOneWidget);
      expect(find.text('Product discounts'), findsOneWidget);
      expect(find.text('Voucher (DEMO10)'), findsOneWidget);
      expect(find.text('Delivery charge'), findsOneWidget);
      expect(find.text('Total payable'), findsOneWidget);
      expect(find.text('Customer discount'), findsNothing); // zero lines are hidden
      expect(breakdown.totalMinor, 176000);
    });

    testWidgets('app shows the splash, then the sign-in screen', (tester) async {
      await tester.pumpWidget(TopTailersApp(services: testServices()));
      expect(find.text('Top Tailers & Fabrics'), findsOneWidget); // splash
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump();
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Register'), findsOneWidget);
    });
  });
}
