import 'package:flutter/foundation.dart';

import '../models/feedback.dart';
import '../repositories/repositories.dart';
import 'load_state.dart';

class FeedbackProvider extends ChangeNotifier {
  FeedbackProvider(this._repo);

  final FeedbackRepository _repo;

  List<ProductFeedback> _mine = [];
  List<ProductFeedback> _all = [];
  final Map<String, List<ProductFeedback>> _byProduct = {};
  LoadState _allState = LoadState.idle;

  List<ProductFeedback> get mine => _mine;
  List<ProductFeedback> get all => _all;
  LoadState get allState => _allState;

  List<ProductFeedback> forProduct(String productId) =>
      _byProduct[productId] ?? const [];

  bool hasFeedbackFor(String orderId, String productId) {
    final key = ProductFeedback.keyFor(orderId, productId);
    return _mine.any((f) => f.key == key);
  }

  ProductFeedback? feedbackFor(String orderId, String productId) {
    final key = ProductFeedback.keyFor(orderId, productId);
    for (final f in _mine) {
      if (f.key == key) return f;
    }
    return null;
  }

  /// Average rating, or null when there is no feedback yet.
  double? averageFor(String productId) {
    final list = forProduct(productId);
    if (list.isEmpty) return null;
    return list.fold<int>(0, (s, f) => s + f.rating) / list.length;
  }

  Future<void> loadMine(String userId) async {
    try {
      _mine = await _repo.forUser(userId);
    } catch (_) {
      // keep previous list
    }
    notifyListeners();
  }

  Future<void> loadForProduct(String productId) async {
    try {
      _byProduct[productId] = await _repo.forProduct(productId);
    } catch (_) {
      // keep previous list
    }
    notifyListeners();
  }

  Future<void> loadAll() async {
    _allState = LoadState.loading;
    notifyListeners();
    try {
      _all = await _repo.all();
      _allState = LoadState.ready;
    } catch (_) {
      _allState = LoadState.error;
    }
    notifyListeners();
  }

  Future<void> submit(ProductFeedback draft) async {
    final saved = await _repo.submit(draft);
    _mine = [saved, ..._mine];
    _byProduct[saved.productId] = [saved, ...forProduct(saved.productId)];
    notifyListeners();
  }

  void reset() {
    _mine = [];
    _all = [];
    _byProduct.clear();
    _allState = LoadState.idle;
    notifyListeners();
  }
}
