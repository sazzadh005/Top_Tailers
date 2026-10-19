import '../domain/discount.dart';

/// A voucher *definition*. Eligibility and discount maths live in
/// domain/pricing.dart so a backend can become the authority later.
class Voucher {
  const Voucher({
    required this.code,
    required this.title,
    required this.kind,
    required this.value,
    this.expiresAt,
    this.categories = const {},
    this.isActive = true,
    this.isPublic = false,
  });

  /// Always stored upper-case.
  final String code;
  final String title;
  final DiscountKind kind;

  /// Whole percent when [kind] is percent, otherwise an amount in paisa.
  final int value;
  final DateTime? expiresAt;

  /// Categories the voucher applies to. Empty means every category.
  final Set<String> categories;
  final bool isActive;

  /// Public vouchers are advertised as offers on the home screen.
  final bool isPublic;
}
