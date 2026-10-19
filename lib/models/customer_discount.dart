import '../domain/discount.dart';

/// A discount the admin configured for one specific customer. Kept separate
/// from product discounts and vouchers.
class CustomerDiscount {
  const CustomerDiscount({
    required this.customerId,
    required this.kind,
    required this.value,
    required this.active,
    this.note = '',
    required this.updatedAt,
  });

  final String customerId;
  final DiscountKind kind;

  /// Whole percent or paisa, depending on [kind].
  final int value;
  final bool active;
  final String note;
  final DateTime updatedAt;

  CustomerDiscount copyWith({bool? active}) {
    return CustomerDiscount(
      customerId: customerId,
      kind: kind,
      value: value,
      active: active ?? this.active,
      note: note,
      updatedAt: updatedAt,
    );
  }
}
