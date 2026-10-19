import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/catalog_query.dart';
import '../models/product.dart';
import '../repositories/repositories.dart';
import 'load_state.dart';

export 'load_state.dart';

/// Product browsing: search, category, sort and in-stock filter with paged
/// loading, plus home-screen content and recently viewed products.
///
/// Search behaviour is unchanged from the original app (case-insensitive match
/// on name, description and category; the product code is now matched too).
class CatalogProvider extends ChangeNotifier {
  CatalogProvider(this._repo, {this.pageSize = 8, this.searchDelay = const Duration(milliseconds: 300)});

  final CatalogRepository _repo;
  final int pageSize;
  final Duration searchDelay;

  // Listing state
  LoadState _state = LoadState.idle;
  List<Product> _items = [];
  bool _hasMore = false;
  bool _loadingMore = false;
  int _page = 0;
  int _total = 0;

  // Filters
  String _query = '';
  String? _category;
  ProductSort _sort = ProductSort.featured;
  bool _inStockOnly = false;

  // Home
  LoadState _homeState = LoadState.idle;
  HomeContent _home = HomeContent.empty;

  final Map<String, Product> _cache = {};
  final List<String> _recentIds = [];

  Timer? _debounce;
  int _token = 0;
  bool _disposed = false;

  LoadState get state => _state;
  List<Product> get items => _items;
  bool get hasMore => _hasMore;
  bool get loadingMore => _loadingMore;
  int get total => _total;

  String get query => _query;
  String? get category => _category;
  ProductSort get sort => _sort;
  bool get inStockOnly => _inStockOnly;

  /// True when anything other than the defaults is selected.
  bool get hasActiveFilters =>
      _query.trim().isNotEmpty ||
      _category != null ||
      _sort != ProductSort.featured ||
      _inStockOnly;

  LoadState get homeState => _homeState;
  HomeContent get home => _home;

  List<Product> get recentlyViewed => [
        for (final id in _recentIds)
          if (_cache[id] != null) _cache[id]!,
      ];

  Product? byId(String id) => _cache[id];

  ProductQuery _buildQuery(int page) => ProductQuery(
        text: _query,
        category: _category,
        sort: _sort,
        inStockOnly: _inStockOnly,
        page: page,
        pageSize: pageSize,
      );

  void _remember(Iterable<Product> products) {
    for (final p in products) {
      _cache[p.id] = p;
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Loads the first page for the current filters, plus the home content.
  Future<void> load() async {
    await Future.wait([loadFirstPage(), loadHome()]);
  }

  Future<void> loadFirstPage() async {
    final token = ++_token;
    _state = LoadState.loading;
    _safeNotify();
    try {
      final result = await _repo.searchProducts(_buildQuery(1));
      if (token != _token) return; // a newer request superseded this one
      _items = List<Product>.of(result.items);
      _remember(result.items);
      _page = result.page;
      _hasMore = result.hasMore;
      _total = result.total;
      _state = LoadState.ready;
    } catch (_) {
      if (token != _token) return;
      _state = LoadState.error;
    }
    _safeNotify();
  }

  /// Lazy-loading hook: called when the list scrolls near its end.
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore || _state != LoadState.ready) return;
    final token = _token;
    _loadingMore = true;
    _safeNotify();
    try {
      final result = await _repo.searchProducts(_buildQuery(_page + 1));
      if (token != _token) return;
      _items = [..._items, ...result.items];
      _remember(result.items);
      _page = result.page;
      _hasMore = result.hasMore;
      _total = result.total;
    } catch (_) {
      // Keep what we have; the next scroll retries.
    } finally {
      _loadingMore = false;
      _safeNotify();
    }
  }

  Future<void> loadHome() async {
    _homeState = LoadState.loading;
    _safeNotify();
    try {
      final home = await _repo.getHome();
      _home = home;
      _remember(home.featured);
      _remember(home.services);
      _remember(home.popular);
      _remember(home.discounted);
      _homeState = LoadState.ready;
    } catch (_) {
      _homeState = LoadState.error;
    }
    _safeNotify();
  }

  // ----------------------------------------------------------------- filters

  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
    _safeNotify();
    _debounce?.cancel();
    if (searchDelay == Duration.zero) {
      loadFirstPage();
    } else {
      _debounce = Timer(searchDelay, loadFirstPage);
    }
  }

  void setCategory(String? value) {
    if (value == _category) return;
    _category = value;
    loadFirstPage();
  }

  void setSort(ProductSort value) {
    if (value == _sort) return;
    _sort = value;
    loadFirstPage();
  }

  void setInStockOnly(bool value) {
    if (value == _inStockOnly) return;
    _inStockOnly = value;
    loadFirstPage();
  }

  void clearFilters() {
    _debounce?.cancel();
    _query = '';
    _category = null;
    _sort = ProductSort.featured;
    _inStockOnly = false;
    loadFirstPage();
  }

  /// Opens the shop on a category (used by home banners and chips).
  void showCategory(String? category) {
    _debounce?.cancel();
    _query = '';
    _category = category;
    loadFirstPage();
  }

  /// Opens the shop on a search from the home screen.
  void showSearch(String text) {
    _debounce?.cancel();
    _query = text;
    _category = null;
    loadFirstPage();
  }

  // ---------------------------------------------------- lookups & recents

  Future<Product?> ensureProduct(String id) async {
    final cached = _cache[id];
    if (cached != null) return cached;
    final product = await _repo.getProduct(id);
    if (product != null) {
      _cache[id] = product;
      _safeNotify();
    }
    return product;
  }

  void markViewed(Product product) {
    _cache[product.id] = product;
    _recentIds.remove(product.id);
    _recentIds.insert(0, product.id);
    if (_recentIds.length > 10) _recentIds.removeLast();
    _safeNotify();
  }

  // ------------------------------------------------------------ admin edits

  Future<void> createProduct(Product draft) async {
    await _repo.createProduct(draft);
    await load();
  }

  Future<void> updateProduct(Product product) async {
    final saved = await _repo.updateProduct(product);
    _cache[saved.id] = saved;
    _items = [for (final p in _items) p.id == saved.id ? saved : p];
    _safeNotify();
    loadHome();
  }

  Future<void> deleteProduct(String id) async {
    await _repo.deleteProduct(id);
    _cache.remove(id);
    _recentIds.remove(id);
    _items = _items.where((p) => p.id != id).toList();
    _total = _total > 0 ? _total - 1 : 0;
    _safeNotify();
    loadHome();
  }

  /// Products for pickers (e.g. restock requests). A real API would expose a
  /// dedicated endpoint; here it is one large page.
  Future<List<Product>> fetchPickerProducts() async {
    final result = await _repo.searchProducts(
      const ProductQuery(sort: ProductSort.nameAZ, pageSize: 100),
    );
    _remember(result.items);
    return result.items;
  }

  Future<bool> isCodeTaken(String code, {String? exceptProductId}) =>
      _repo.isCodeTaken(code, exceptProductId: exceptProductId);

  /// Clears everything on logout so the next user starts fresh.
  void reset() {
    _debounce?.cancel();
    _token++;
    _items = [];
    _hasMore = false;
    _page = 0;
    _total = 0;
    _query = '';
    _category = null;
    _sort = ProductSort.featured;
    _inStockOnly = false;
    _state = LoadState.idle;
    _home = HomeContent.empty;
    _homeState = LoadState.idle;
    _cache.clear();
    _recentIds.clear();
    _safeNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
