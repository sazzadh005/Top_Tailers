import 'package:flutter/foundation.dart';

import '../models/cart_item.dart';
import '../models/product.dart';

/// Cart state lives on the device only (SRS: cart logic is in the Flutter app).
class CartProvider extends ChangeNotifier {
  static const int maxQuantity = 20;

  final Map<String, CartItem> _items = {};

  List<CartItem> get items => _items.values.toList();
  bool get isEmpty => _items.isEmpty;

  /// Total number of units in the cart (used for the badge).
  int get count => _items.values.fold(0, (sum, item) => sum + item.quantity);

  double get total =>
      _items.values.fold(0.0, (sum, item) => sum + item.lineTotal);

  int quantityOf(String productId) => _items[productId]?.quantity ?? 0;

  /// Adds [quantity] units. Returns false when the product cannot be added.
  bool add(Product product, {int quantity = 1}) {
    if (!product.availability || quantity < 1) return false;
    final existing = _items[product.id];
    final next = ((existing?.quantity ?? 0) + quantity).clamp(1, maxQuantity);
    _items[product.id] = CartItem(product: product, quantity: next);
    notifyListeners();
    return true;
  }

  void setQuantity(String productId, int quantity) {
    final existing = _items[productId];
    if (existing == null) return;
    if (quantity < 1) {
      _items.remove(productId);
    } else {
      _items[productId] = existing.copyWith(quantity: quantity.clamp(1, maxQuantity));
    }
    notifyListeners();
  }

  void remove(String productId) {
    if (_items.remove(productId) != null) notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }
}
