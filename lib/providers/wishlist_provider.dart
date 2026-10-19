import 'package:flutter/foundation.dart';

import '../models/product.dart';
import '../repositories/repositories.dart';

class WishlistProvider extends ChangeNotifier {
  WishlistProvider(this._wishlist, this._catalog);

  final WishlistRepository _wishlist;
  final CatalogRepository _catalog;

  String? _userId;
  Set<String> _ids = {};
  List<Product> _products = [];
  bool _loading = false;

  Set<String> get ids => _ids;
  List<Product> get products => _products;
  bool get loading => _loading;
  int get count => _ids.length;

  bool isSaved(String productId) => _ids.contains(productId);

  Future<void> load(String userId) async {
    _userId = userId;
    _loading = true;
    notifyListeners();
    try {
      _ids = await _wishlist.ids(userId);
      _products = await _catalog.getProductsByIds(_ids.toList());
    } catch (_) {
      // keep what we had
    }
    _loading = false;
    notifyListeners();
  }

  /// Adds or removes a product; the heart updates immediately.
  Future<void> toggle(Product product) async {
    final userId = _userId;
    if (userId == null) return;
    if (_ids.contains(product.id)) {
      _ids = {..._ids}..remove(product.id);
      _products = _products.where((p) => p.id != product.id).toList();
      notifyListeners();
      await _wishlist.remove(userId, product.id);
    } else {
      _ids = {..._ids, product.id};
      _products = [product, ..._products];
      notifyListeners();
      await _wishlist.add(userId, product.id);
    }
  }

  void reset() {
    _userId = null;
    _ids = {};
    _products = [];
    notifyListeners();
  }
}
