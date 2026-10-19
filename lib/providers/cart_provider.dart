import 'package:flutter/foundation.dart';

import '../domain/pricing.dart';
import '../models/cart_item.dart';
import '../models/customer_discount.dart';
import '../models/product.dart';
import '../models/voucher.dart';
import '../repositories/repositories.dart';

/// Result of trying to apply a voucher code.
class VoucherApplyResult {
  const VoucherApplyResult.success(this.message) : ok = true;
  const VoucherApplyResult.failure(this.message) : ok = false;

  final bool ok;
  final String message;
}

/// Cart state lives on the device (SRS: cart logic is in the Flutter app).
/// All money comes from [breakdown], so cart, checkout and confirmation can
/// never disagree.
class CartProvider extends ChangeNotifier {
  CartProvider(this._vouchers, this._discounts, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const int maxQuantity = 20;

  final VoucherRepository _vouchers;
  final DiscountRepository _discounts;
  final DateTime Function() _clock;

  final Map<String, CartItem> _items = {};
  Voucher? _voucher;
  CustomerDiscount? _customerDiscount;

  List<CartItem> get items => _items.values.toList();
  bool get isEmpty => _items.isEmpty;

  /// Total number of units in the cart (used for the badge).
  int get count => _items.values.fold(0, (sum, item) => sum + item.quantity);

  Voucher? get voucher => _voucher;
  CustomerDiscount? get customerDiscount => _customerDiscount;

  PriceBreakdown get breakdown => PricingService.compute(
        [for (final item in _items.values) item.toPricedLine()],
        voucher: _voucher,
        customerDiscount: _customerDiscount,
        now: _clock(),
      );

  /// Whether any line is a tailoring service that needs measurements.
  bool get needsMeasurements =>
      _items.values.any((i) => i.product.requiresMeasurements);

  int quantityOf(String productId) => _items.values
      .where((i) => i.product.id == productId)
      .fold(0, (sum, i) => sum + i.quantity);

  /// Loads the signed-in customer's discount so totals include it.
  Future<void> attachCustomer(String customerId) async {
    try {
      _customerDiscount = await _discounts.getCustomerDiscount(customerId);
    } catch (_) {
      _customerDiscount = null;
    }
    notifyListeners();
  }

  /// Adds [quantity] units. Returns false when the product cannot be added.
  bool add(Product product, {int quantity = 1, String? colorName, String? size}) {
    if (!product.availability || quantity < 1) return false;
    final key = CartItem.keyFor(product.id, colorName, size);
    final existing = _items[key];
    final next = ((existing?.quantity ?? 0) + quantity).clamp(1, maxQuantity);
    _items[key] = CartItem(
      product: product,
      quantity: next,
      colorName: colorName,
      size: size,
    );
    notifyListeners();
    return true;
  }

  void setQuantity(String key, int quantity) {
    final existing = _items[key];
    if (existing == null) return;
    if (quantity < 1) {
      _items.remove(key);
    } else {
      _items[key] = existing.copyWith(quantity: quantity.clamp(1, maxQuantity));
    }
    notifyListeners();
  }

  void remove(String key) {
    if (_items.remove(key) != null) notifyListeners();
  }

  /// Empties the cart and drops any applied voucher.
  void clear() {
    if (_items.isEmpty && _voucher == null) return;
    _items.clear();
    _voucher = null;
    notifyListeners();
  }

  Future<VoucherApplyResult> applyVoucher(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      return const VoucherApplyResult.failure('Enter a voucher code.');
    }
    if (_items.isEmpty) {
      return const VoucherApplyResult.failure('Add items to your cart before applying a voucher.');
    }
    final voucher = await _vouchers.findByCode(trimmed);
    if (voucher == null) {
      return const VoucherApplyResult.failure('This voucher code is not valid.');
    }
    final lines = [for (final i in _items.values) i.toPricedLine()];
    final evaluation = VoucherRules.evaluate(voucher, lines, now: _clock());
    if (!evaluation.isValid) return VoucherApplyResult.failure(evaluation.message);

    _voucher = voucher;
    notifyListeners();
    final b = breakdown;
    if (b.source == OrderDiscountSource.voucher) {
      return VoucherApplyResult.success('${voucher.code} applied.');
    }
    return VoucherApplyResult.success(
      b.voucherNote ?? '${voucher.code} saved, but it does not reduce this order.',
    );
  }

  void removeVoucher() {
    if (_voucher == null) return;
    _voucher = null;
    notifyListeners();
  }
}
