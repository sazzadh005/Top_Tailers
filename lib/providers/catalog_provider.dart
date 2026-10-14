import 'package:flutter/foundation.dart';

import '../models/product.dart';
import '../services/mock_backend.dart';

enum LoadState { idle, loading, ready, error }

class CatalogProvider extends ChangeNotifier {
  final MockBackend _backend = MockBackend.instance;

  List<Product> _products = [];
  LoadState _state = LoadState.idle;
  String _query = '';
  String? _category; // null = all categories

  LoadState get state => _state;
  List<Product> get products => _products;
  String get query => _query;
  String? get category => _category;

  /// Products matching the current search text and category filter.
  List<Product> get filtered {
    final q = _query.trim().toLowerCase();
    return _products.where((p) {
      final matchesCategory = _category == null || p.category == _category;
      final matchesQuery = q.isEmpty ||
          p.productName.toLowerCase().contains(q) ||
          p.description.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  Product? byId(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> load() async {
    _state = LoadState.loading;
    notifyListeners();
    try {
      _products = List<Product>.of(await _backend.getProducts());
      _state = LoadState.ready;
    } catch (_) {
      _state = LoadState.error;
    }
    notifyListeners();
  }

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  void setCategory(String? value) {
    _category = value;
    notifyListeners();
  }

  // ------------------------------------------------------------ Admin only

  Future<void> addProduct(Product draft) async {
    final created = await _backend.addProduct(draft);
    _products = [created, ..._products];
    notifyListeners();
  }

  Future<void> updateProduct(Product product) async {
    final saved = await _backend.updateProduct(product);
    _products = [
      for (final p in _products)
        if (p.id == saved.id) saved else p,
    ];
    notifyListeners();
  }

  Future<void> deleteProduct(String id) async {
    await _backend.deleteProduct(id);
    _products = _products.where((p) => p.id != id).toList();
    notifyListeners();
  }
}
