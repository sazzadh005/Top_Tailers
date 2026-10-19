enum DiscountKind { percent, fixed }

extension DiscountKindX on DiscountKind {
  String get label => this == DiscountKind.percent ? 'Percentage' : 'Fixed amount';
}

/// Central discount maths used by products, customer discounts and vouchers.
/// Percent values are whole percents; fixed values are paisa.
class DiscountMath {
  DiscountMath._();

  /// Percentages above this are rejected so a price can never reach zero by
  /// percentage alone. (Conservative mock rule; the SRS defines none.)
  static const int maxPercent = 99;

  /// Amount taken off [basisMinor]: rounded down to the paisa, never negative
  /// and never more than the basis.
  static int amount(DiscountKind kind, int value, int basisMinor) {
    if (basisMinor <= 0 || value <= 0) return 0;
    final raw =
        kind == DiscountKind.percent ? (basisMinor * value) ~/ 100 : value;
    return raw > basisMinor ? basisMinor : raw;
  }

  /// Validation message for a discount on an item priced at [priceMinor], or
  /// null when the discount is acceptable.
  static String? validateForPrice(DiscountKind kind, int value, int priceMinor) {
    if (value <= 0) return 'Enter a value greater than 0';
    if (kind == DiscountKind.percent) {
      if (value > maxPercent) return 'Percentage must be between 1 and $maxPercent';
    } else if (value >= priceMinor) {
      return 'A fixed discount must be less than the price';
    }
    return null;
  }

  /// Validation for discounts that are not tied to one price (customers).
  static String? validateGeneral(DiscountKind kind, int value) {
    if (value <= 0) return 'Enter a value greater than 0';
    if (kind == DiscountKind.percent && value > maxPercent) {
      return 'Percentage must be between 1 and $maxPercent';
    }
    return null;
  }
}

/// A discount configured on a single product by the shop admin.
class ProductDiscount {
  const ProductDiscount({
    required this.enabled,
    required this.kind,
    required this.value,
  });

  final bool enabled;
  final DiscountKind kind;
  final int value;

  int amountFor(int priceMinor) =>
      enabled ? DiscountMath.amount(kind, value, priceMinor) : 0;

  ProductDiscount copyWith({bool? enabled, DiscountKind? kind, int? value}) {
    return ProductDiscount(
      enabled: enabled ?? this.enabled,
      kind: kind ?? this.kind,
      value: value ?? this.value,
    );
  }
}
