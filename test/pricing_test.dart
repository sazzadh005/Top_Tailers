import 'package:flutter_test/flutter_test.dart';
import 'package:top_tailers_/core/format.dart';
import 'package:top_tailers_/core/money.dart';
import 'package:top_tailers_/domain/discount.dart';
import 'package:top_tailers_/domain/pricing.dart';
import 'package:top_tailers_/models/customer_discount.dart';
import 'package:top_tailers_/models/voucher.dart';

final DateTime now = DateTime(2026, 10, 18);

PricedLine line(int list, {int? unit, int qty = 1, String category = 'Fabrics'}) =>
    PricedLine(
      category: category,
      listUnitMinor: list,
      unitMinor: unit ?? list,
      quantity: qty,
    );

Voucher percent(int v, {Set<String> cats = const {}, DateTime? expires, bool active = true}) =>
    Voucher(
      code: 'T$v',
      title: 't',
      kind: DiscountKind.percent,
      value: v,
      categories: cats,
      expiresAt: expires,
      isActive: active,
    );

CustomerDiscount customer(DiscountKind k, int v, {bool active = true}) => CustomerDiscount(
      customerId: 'u',
      kind: k,
      value: v,
      active: active,
      updatedAt: now,
    );

void main() {
  group('Money', () {
    test('parses taka input to paisa without floating point', () {
      expect(Money.tryParse('450'), 45000);
      expect(Money.tryParse('450.5'), 45050);
      expect(Money.tryParse('0.07'), 7);
      expect(Money.tryParse('1,250.75'), 125075);
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse('-5'), isNull);
      expect(Money.tryParse('1.234'), isNull);
    });

    test('formats paisa', () {
      expect(formatMoney(45000), '\u09F3450');
      expect(formatMoney(45050), '\u09F3450.50');
      expect(formatMoney(123456700), '\u09F31,234,567');
    });

    test('classic float trap stays exact', () {
      // 0.1 + 0.2 style errors cannot happen with integer paisa.
      expect(Money.tryParse('0.10')! + Money.tryParse('0.20')!, Money.tryParse('0.30'));
    });
  });

  group('DiscountMath', () {
    test('percent rounds down to the paisa', () {
      expect(DiscountMath.amount(DiscountKind.percent, 10, 12345), 1234);
    });

    test('fixed discount is capped at the basis', () {
      expect(DiscountMath.amount(DiscountKind.fixed, 50000, 30000), 30000);
    });

    test('rejects invalid values', () {
      expect(DiscountMath.validateForPrice(DiscountKind.percent, 0, 10000), isNotNull);
      expect(DiscountMath.validateForPrice(DiscountKind.percent, 100, 10000), isNotNull);
      expect(DiscountMath.validateForPrice(DiscountKind.percent, 99, 10000), isNull);
      expect(DiscountMath.validateForPrice(DiscountKind.fixed, 10000, 10000), isNotNull);
      expect(DiscountMath.validateForPrice(DiscountKind.fixed, 9999, 10000), isNull);
      expect(DiscountMath.validateGeneral(DiscountKind.percent, -1), isNotNull);
    });

    test('product discount gives the resulting price', () {
      const d = ProductDiscount(enabled: true, kind: DiscountKind.percent, value: 10);
      expect(d.amountFor(45000), 4500);
      expect(d.copyWith(enabled: false).amountFor(45000), 0);
    });
  });

  group('Vouchers', () {
    final lines = [line(100000, qty: 2)];

    test('valid percent voucher', () {
      final r = VoucherRules.evaluate(percent(10), lines, now: now);
      expect(r.isValid, isTrue);
      expect(r.discountMinor, 20000);
    });

    test('expired voucher', () {
      final r = VoucherRules.evaluate(
        percent(10, expires: now.subtract(const Duration(days: 1))),
        lines,
        now: now,
      );
      expect(r.issue, VoucherIssue.expired);
    });

    test('voucher valid up to expiry instant only', () {
      final expires = now.add(const Duration(hours: 1));
      expect(VoucherRules.evaluate(percent(10, expires: expires), lines, now: now).isValid, isTrue);
      expect(VoucherRules.evaluate(percent(10, expires: expires), lines, now: expires).isValid, isFalse);
    });

    test('inactive voucher', () {
      expect(VoucherRules.evaluate(percent(10, active: false), lines, now: now).issue,
          VoucherIssue.inactive);
    });

    test('empty cart', () {
      expect(VoucherRules.evaluate(percent(10), const [], now: now).issue,
          VoucherIssue.emptyCart);
    });

    test('category restricted voucher is inapplicable to other categories', () {
      final r = VoucherRules.evaluate(
        percent(15, cats: {'Fabrics'}),
        [line(50000, category: 'Tailoring')],
        now: now,
      );
      expect(r.issue, VoucherIssue.notApplicable);
    });

    test('category restricted voucher counts only eligible lines', () {
      final r = VoucherRules.evaluate(
        percent(10, cats: {'Fabrics'}),
        [line(100000), line(100000, category: 'Tailoring')],
        now: now,
      );
      expect(r.discountMinor, 10000);
    });

    test('voucher does not apply to lines that already have a product discount', () {
      final r = VoucherRules.evaluate(
        percent(10),
        [line(100000, unit: 90000)],
        now: now,
      );
      expect(r.issue, VoucherIssue.notApplicable);
    });
  });

  group('PricingService and stacking', () {
    test('plain total', () {
      final b = PricingService.compute([line(45000, qty: 3)], now: now);
      expect(b.subtotalMinor, 135000);
      expect(b.totalMinor, 135000);
      expect(b.totalDiscountMinor, 0);
    });

    test('product discount reduces total and is reported separately', () {
      final b = PricingService.compute([line(45000, unit: 40500, qty: 3)], now: now);
      expect(b.subtotalMinor, 135000);
      expect(b.productDiscountMinor, 13500);
      expect(b.totalMinor, 121500);
    });

    test('voucher is calculated only on non-discounted lines', () {
      final b = PricingService.compute(
        [line(45000, unit: 40500), line(100000)],
        voucher: percent(10),
        now: now,
      );
      expect(b.productDiscountMinor, 4500);
      expect(b.voucherDiscountMinor, 10000); // 10% of 100000 only
      expect(b.totalMinor, 145000 - 4500 - 10000);
      expect(b.source, OrderDiscountSource.voucher);
    });

    test('customer discount and voucher never stack: larger wins', () {
      final lines = [line(100000)];
      final voucherWins = PricingService.compute(
        lines,
        voucher: percent(15),
        customerDiscount: customer(DiscountKind.percent, 8),
        now: now,
      );
      expect(voucherWins.source, OrderDiscountSource.voucher);
      expect(voucherWins.voucherDiscountMinor, 15000);
      expect(voucherWins.customerDiscountMinor, 0);
      expect(voucherWins.totalMinor, 85000);

      final customerWins = PricingService.compute(
        lines,
        voucher: percent(5),
        customerDiscount: customer(DiscountKind.percent, 8),
        now: now,
      );
      expect(customerWins.source, OrderDiscountSource.customer);
      expect(customerWins.customerDiscountMinor, 8000);
      expect(customerWins.voucherDiscountMinor, 0);
      expect(customerWins.voucherNote, isNotNull);
      expect(customerWins.totalMinor, 92000);
    });

    test('a tie goes to the customer discount, and only one is applied', () {
      final b = PricingService.compute(
        [line(100000)],
        voucher: percent(10),
        customerDiscount: customer(DiscountKind.percent, 10),
        now: now,
      );
      expect(b.source, OrderDiscountSource.customer);
      expect(b.orderDiscountMinor, 10000);
    });

    test('inactive customer discount is ignored', () {
      final b = PricingService.compute(
        [line(100000)],
        customerDiscount: customer(DiscountKind.percent, 10, active: false),
        now: now,
      );
      expect(b.customerDiscountMinor, 0);
    });

    test('removing the voucher restores the total', () {
      final lines = [line(100000, qty: 2)];
      final withVoucher = PricingService.compute(lines, voucher: percent(10), now: now);
      final without = PricingService.compute(lines, now: now);
      expect(withVoucher.totalMinor, 180000);
      expect(without.totalMinor, 200000);
    });

    test('delivery policy is applied and never negative totals', () {
      final b = PricingService.compute(
        [line(10000)],
        delivery: const DeliveryPolicy(flatChargeMinor: 6000),
        now: now,
      );
      expect(b.deliveryMinor, 6000);
      expect(b.totalMinor, 16000);

      final free = PricingService.compute(
        [line(10000)],
        delivery: const DeliveryPolicy(flatChargeMinor: 6000, freeAboveMinor: 10000),
        now: now,
      );
      expect(free.deliveryMinor, 0);

      const odd = PriceBreakdown(
        subtotalMinor: 100,
        productDiscountMinor: 0,
        customerDiscountMinor: 500,
        voucherDiscountMinor: 0,
        deliveryMinor: 0,
      );
      expect(odd.totalMinor, 0);
    });

    test('default delivery policy charges nothing (SRS defines no charge)', () {
      expect(PricingService.compute([line(10000)], now: now).deliveryMinor, 0);
    });
  });
}
