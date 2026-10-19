import '../models/customer_discount.dart';
import '../models/voucher.dart';
import 'discount.dart';

/// A priced line, independent of whether it comes from the cart or an order.
/// [listUnitMinor] is the catalogue price, [unitMinor] the price after any
/// product discount.
class PricedLine {
  const PricedLine({
    required this.category,
    required this.listUnitMinor,
    required this.unitMinor,
    required this.quantity,
  });

  final String category;
  final int listUnitMinor;
  final int unitMinor;
  final int quantity;

  int get listTotalMinor => listUnitMinor * quantity;
  int get totalMinor => unitMinor * quantity;
  bool get hasProductDiscount => unitMinor < listUnitMinor;
}

enum VoucherIssue { empty, notFound, inactive, expired, notApplicable, emptyCart }

/// Result of checking a voucher against a basket.
class VoucherEvaluation {
  const VoucherEvaluation.valid(this.discountMinor)
      : issue = null,
        message = '';
  const VoucherEvaluation.invalid(this.issue, this.message) : discountMinor = 0;

  final int discountMinor;
  final VoucherIssue? issue;
  final String message;

  bool get isValid => issue == null;
}

/// Order-level discounts only apply to lines that have NO product discount, so
/// the same item is never discounted twice.
int _eligibleBase(List<PricedLine> lines, Set<String> categories) {
  var sum = 0;
  for (final line in lines) {
    if (line.hasProductDiscount) continue;
    if (categories.isNotEmpty && !categories.contains(line.category)) continue;
    sum += line.totalMinor;
  }
  return sum;
}

/// Pure voucher rules. A backend can later become the authority.
class VoucherRules {
  VoucherRules._();

  static VoucherEvaluation evaluate(
    Voucher voucher,
    List<PricedLine> lines, {
    required DateTime now,
  }) {
    if (!voucher.isActive) {
      return const VoucherEvaluation.invalid(
        VoucherIssue.inactive,
        'This voucher is not active.',
      );
    }
    final expiry = voucher.expiresAt;
    if (expiry != null && !now.isBefore(expiry)) {
      return const VoucherEvaluation.invalid(
        VoucherIssue.expired,
        'This voucher has expired.',
      );
    }
    if (lines.isEmpty) {
      return const VoucherEvaluation.invalid(
        VoucherIssue.emptyCart,
        'Add items to your cart before applying a voucher.',
      );
    }

    final base = _eligibleBase(lines, voucher.categories);
    if (base <= 0) {
      final names = voucher.categories.join(', ');
      final scope = names.isEmpty ? '' : ' in $names';
      return VoucherEvaluation.invalid(
        VoucherIssue.notApplicable,
        'No eligible items$scope. Vouchers do not apply to items that already have a discount.',
      );
    }
    return VoucherEvaluation.valid(
      DiscountMath.amount(voucher.kind, voucher.value, base),
    );
  }
}

/// Customer-specific discount rules (same base as vouchers, no category scope).
class CustomerDiscountRules {
  CustomerDiscountRules._();

  static int amountFor(CustomerDiscount? discount, List<PricedLine> lines) {
    if (discount == null || !discount.active) return 0;
    final base = _eligibleBase(lines, const {});
    return DiscountMath.amount(discount.kind, discount.value, base);
  }
}

/// Delivery charge rule. The SRS defines no delivery charge, so the default
/// policy charges nothing; the type exists so a real rule can be plugged in.
class DeliveryPolicy {
  const DeliveryPolicy({this.flatChargeMinor = 0, this.freeAboveMinor});

  final int flatChargeMinor;
  final int? freeAboveMinor;

  static const DeliveryPolicy none = DeliveryPolicy();

  int chargeFor(int subtotalMinor) {
    final threshold = freeAboveMinor;
    if (threshold != null && subtotalMinor >= threshold) return 0;
    return flatChargeMinor;
  }
}

enum OrderDiscountSource { none, customer, voucher }

/// Item subtotal - product discounts - ONE order-level discount + delivery.
///
/// Stacking rules (documented, conservative; the SRS defines none):
///  1. Product discounts reduce a line's own price.
///  2. Vouchers and customer discounts ignore lines that already carry a
///     product discount.
///  3. Customer discount and voucher never stack: only the larger one applies
///     (ties go to the customer discount).
class PriceBreakdown {
  const PriceBreakdown({
    required this.subtotalMinor,
    required this.productDiscountMinor,
    required this.customerDiscountMinor,
    required this.voucherDiscountMinor,
    required this.deliveryMinor,
    this.voucherCode,
    this.source = OrderDiscountSource.none,
    this.voucherNote,
  });

  /// Sum of catalogue (list) prices.
  final int subtotalMinor;
  final int productDiscountMinor;
  final int customerDiscountMinor;
  final int voucherDiscountMinor;
  final int deliveryMinor;
  final String? voucherCode;
  final OrderDiscountSource source;

  /// Explains why a typed voucher is not currently reducing the price.
  final String? voucherNote;

  int get orderDiscountMinor => customerDiscountMinor + voucherDiscountMinor;
  int get totalDiscountMinor => productDiscountMinor + orderDiscountMinor;

  int get totalMinor {
    final total = subtotalMinor - totalDiscountMinor + deliveryMinor;
    return total < 0 ? 0 : total;
  }
}

class PricingService {
  PricingService._();

  static PriceBreakdown compute(
    List<PricedLine> lines, {
    Voucher? voucher,
    CustomerDiscount? customerDiscount,
    DateTime? now,
    DeliveryPolicy delivery = DeliveryPolicy.none,
  }) {
    final subtotal = lines.fold<int>(0, (s, l) => s + l.listTotalMinor);
    final afterProduct = lines.fold<int>(0, (s, l) => s + l.totalMinor);
    final productDiscount = subtotal - afterProduct;

    final customerAmount = CustomerDiscountRules.amountFor(customerDiscount, lines);

    var voucherAmount = 0;
    String? voucherNote;
    if (voucher != null) {
      final evaluation =
          VoucherRules.evaluate(voucher, lines, now: now ?? DateTime.now());
      if (evaluation.isValid) {
        voucherAmount = evaluation.discountMinor;
      } else {
        voucherNote = evaluation.message;
      }
    }

    var source = OrderDiscountSource.none;
    var appliedCustomer = 0;
    var appliedVoucher = 0;
    if (voucherAmount > customerAmount) {
      source = OrderDiscountSource.voucher;
      appliedVoucher = voucherAmount;
    } else if (customerAmount > 0) {
      source = OrderDiscountSource.customer;
      appliedCustomer = customerAmount;
      if (voucher != null && voucherNote == null) {
        voucherNote =
            'Voucher ${voucher.code} not applied: your customer discount is larger. Only one order-level discount can apply.';
      }
    }

    return PriceBreakdown(
      subtotalMinor: subtotal,
      productDiscountMinor: productDiscount,
      customerDiscountMinor: appliedCustomer,
      voucherDiscountMinor: appliedVoucher,
      deliveryMinor: delivery.chargeFor(afterProduct),
      voucherCode: source == OrderDiscountSource.voucher ? voucher?.code : null,
      source: source,
      voucherNote: voucherNote,
    );
  }
}
