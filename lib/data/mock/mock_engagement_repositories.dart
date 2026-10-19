import '../../core/app_exception.dart';
import '../../models/feedback.dart';
import '../../models/order.dart';
import '../../models/requests.dart';
import '../../repositories/repositories.dart';
import 'mock_store.dart';

class MockFeedbackRepository implements FeedbackRepository {
  MockFeedbackRepository(this._store);

  final MockStore _store;

  /// Mirrors the server-side rule: feedback is allowed only for a product in
  /// the user's own Completed order, once per order item.
  @override
  Future<ProductFeedback> submit(ProductFeedback fb) async {
    await _store.wait();
    if (fb.rating < 1 || fb.rating > 5) throw AppException('Choose a rating from 1 to 5.');
    if (fb.comment.trim().length < 5) {
      throw AppException('Please write at least a few words of feedback.');
    }
    final index = _store.orderIndex(fb.orderId);
    if (index < 0) throw AppException('Order not found.');
    final order = _store.orders[index];
    if (order.userId != fb.userId) throw AppException('This is not your order.');
    if (order.status != OrderStatus.completed) {
      throw AppException('You can leave feedback after the order is Completed.');
    }
    if (!order.items.any((i) => i.productId == fb.productId)) {
      throw AppException('This product is not part of that order.');
    }
    if (_store.feedback.any((f) => f.key == fb.key)) {
      throw AppException('You have already reviewed this item.');
    }
    final saved = ProductFeedback(
      id: _store.newId('f'),
      orderId: fb.orderId,
      productId: fb.productId,
      productName: fb.productName,
      userId: fb.userId,
      userName: fb.userName,
      rating: fb.rating,
      comment: fb.comment.trim(),
      createdAt: _store.now(),
    );
    _store.feedback.insert(0, saved);
    return saved;
  }

  List<ProductFeedback> _sorted(Iterable<ProductFeedback> items) {
    final list = items.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<List<ProductFeedback>> forProduct(String productId) async {
    await _store.wait();
    return _sorted(_store.feedback.where((f) => f.productId == productId));
  }

  @override
  Future<List<ProductFeedback>> forUser(String userId) async {
    await _store.wait();
    return _sorted(_store.feedback.where((f) => f.userId == userId));
  }

  @override
  Future<List<ProductFeedback>> all() async {
    await _store.wait();
    return _sorted(_store.feedback);
  }
}

class MockRequestRepository implements RequestRepository {
  MockRequestRepository(this._store);

  final MockStore _store;

  @override
  Future<ProductSuggestion> submitSuggestion(ProductSuggestion s) async {
    await _store.wait();
    if (s.title.trim().length < 3) throw AppException('Please enter what you would like us to stock.');
    final saved = ProductSuggestion(
      id: _store.newId('s'),
      userId: s.userId,
      userName: s.userName,
      title: s.title.trim(),
      details: s.details.trim(),
      createdAt: _store.now(),
    );
    _store.suggestions.insert(0, saved);
    return saved;
  }

  @override
  Future<RestockRequest> submitRestock(RestockRequest r) async {
    await _store.wait();
    final product = _store.productById(r.productId);
    if (product == null) throw AppException('Product not found.');
    final duplicate = _store.restocks.any((x) =>
        x.userId == r.userId &&
        x.productId == r.productId &&
        (x.status == RequestStatus.received || x.status == RequestStatus.underReview));
    if (duplicate) throw AppException('You already have an open restock request for this product.');
    final saved = RestockRequest(
      id: _store.newId('r'),
      userId: r.userId,
      userName: r.userName,
      productId: product.id,
      productCode: product.code,
      productName: product.productName,
      reason: r.reason.trim(),
      createdAt: _store.now(),
    );
    _store.restocks.insert(0, saved);
    return saved;
  }

  @override
  Future<List<ProductSuggestion>> suggestionsFor(String userId) async {
    await _store.wait();
    return _store.suggestions.where((s) => s.userId == userId).toList();
  }

  @override
  Future<List<RestockRequest>> restocksFor(String userId) async {
    await _store.wait();
    return _store.restocks.where((r) => r.userId == userId).toList();
  }

  @override
  Future<List<ProductSuggestion>> allSuggestions() async {
    await _store.wait();
    return List<ProductSuggestion>.of(_store.suggestions);
  }

  @override
  Future<List<RestockRequest>> allRestocks() async {
    await _store.wait();
    return List<RestockRequest>.of(_store.restocks);
  }

  @override
  Future<void> setSuggestionStatus(String id, RequestStatus status) async {
    await _store.wait();
    final i = _store.suggestions.indexWhere((s) => s.id == id);
    if (i < 0) throw AppException('Request not found.');
    _store.suggestions[i] = _store.suggestions[i].copyWith(status: status);
  }

  @override
  Future<void> setRestockStatus(String id, RequestStatus status) async {
    await _store.wait();
    final i = _store.restocks.indexWhere((r) => r.id == id);
    if (i < 0) throw AppException('Request not found.');
    _store.restocks[i] = _store.restocks[i].copyWith(status: status);
  }
}

class MockWishlistRepository implements WishlistRepository {
  MockWishlistRepository(this._store);

  final MockStore _store;

  @override
  Future<Set<String>> ids(String userId) async {
    await _store.wait();
    return Set<String>.of(_store.wishlists[userId] ?? const <String>{});
  }

  @override
  Future<void> add(String userId, String productId) async {
    _store.wishlists.putIfAbsent(userId, () => <String>{}).add(productId);
  }

  @override
  Future<void> remove(String userId, String productId) async {
    _store.wishlists[userId]?.remove(productId);
  }
}
