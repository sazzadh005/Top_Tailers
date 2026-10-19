import '../../core/app_exception.dart';
import '../../domain/discount.dart';
import '../../models/catalog_query.dart';
import '../../models/product.dart';
import '../../repositories/repositories.dart';
import 'mock_store.dart';

class MockCatalogRepository implements CatalogRepository {
  MockCatalogRepository(this._store);

  final MockStore _store;

  static String normalizeCode(String code) => code.trim().toUpperCase();

  /// Same matching as the original app (name, description, category) plus the
  /// product code, so admins can search by code.
  static bool _matchesText(Product p, String q) {
    return p.productName.toLowerCase().contains(q) ||
        p.description.toLowerCase().contains(q) ||
        p.category.toLowerCase().contains(q) ||
        p.code.toLowerCase().contains(q);
  }

  @override
  Future<PageResult<Product>> searchProducts(ProductQuery query) async {
    await _store.wait();
    final q = query.text.trim().toLowerCase();
    final matches = _store.products.where((p) {
      if (query.category != null && p.category != query.category) return false;
      if (query.inStockOnly && !p.availability) return false;
      return q.isEmpty || _matchesText(p, q);
    }).toList();

    switch (query.sort) {
      case ProductSort.featured:
        matches.sort((a, b) {
          if (a.isFeatured != b.isFeatured) return a.isFeatured ? -1 : 1;
          final byPop = b.popularity.compareTo(a.popularity);
          return byPop != 0 ? byPop : a.productName.compareTo(b.productName);
        });
        break;
      case ProductSort.newest:
        matches.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case ProductSort.priceLow:
        matches.sort((a, b) => a.effectivePriceMinor.compareTo(b.effectivePriceMinor));
        break;
      case ProductSort.priceHigh:
        matches.sort((a, b) => b.effectivePriceMinor.compareTo(a.effectivePriceMinor));
        break;
      case ProductSort.nameAZ:
        matches.sort((a, b) =>
            a.productName.toLowerCase().compareTo(b.productName.toLowerCase()));
        break;
    }

    final start = (query.page - 1) * query.pageSize;
    final end = start + query.pageSize;
    final slice = start >= matches.length
        ? <Product>[]
        : matches.sublist(start, end > matches.length ? matches.length : end);
    return PageResult<Product>(
      items: slice,
      page: query.page,
      hasMore: end < matches.length,
      total: matches.length,
    );
  }

  @override
  Future<Product?> getProduct(String id) async {
    await _store.wait();
    return _store.productById(id);
  }

  @override
  Future<List<Product>> getProductsByIds(List<String> ids) async {
    await _store.wait();
    return [
      for (final id in ids)
        if (_store.productById(id) != null) _store.productById(id)!,
    ];
  }

  @override
  Future<HomeContent> getHome() async {
    await _store.wait();
    final available = _store.products.where((p) => p.availability).toList();
    List<Product> take(Iterable<Product> items, [int n = 8]) => items.take(n).toList();

    final byPopularity = [...available]
      ..sort((a, b) => b.popularity.compareTo(a.popularity));
    final now = _store.now();
    return HomeContent(
      banners: const [
        PromoBanner(
          id: 'b1',
          title: 'Fine fabrics, ready to stitch',
          subtitle: 'Cotton, linen, silk and wool suiting',
          colorArgb: 0xFF7B1E3A,
          category: 'Fabrics',
        ),
        PromoBanner(
          id: 'b2',
          title: 'Tailoring services',
          subtitle: 'Shirts, panjabis and trousers made to your measurements',
          colorArgb: 0xFF1E2D52,
          category: 'Tailoring',
        ),
        PromoBanner(
          id: 'b3',
          title: 'Demo offer',
          subtitle: 'Try voucher DEMO10 at checkout (demonstration code)',
          colorArgb: 0xFF2F6B4F,
          voucherCode: 'DEMO10',
        ),
      ],
      featured: take(available.where((p) => p.isFeatured && p.isFabric)),
      services: take(available.where((p) => p.category == 'Tailoring')),
      popular: take(byPopularity),
      discounted: take(available.where((p) => p.hasDiscount)),
      offers: _store.vouchers
          .where((v) =>
              v.isPublic &&
              v.isActive &&
              (v.expiresAt == null || now.isBefore(v.expiresAt!)))
          .toList(),
    );
  }

  bool _codeTaken(String code, String? exceptId) {
    final key = normalizeCode(code);
    return _store.products.any((p) => p.code == key && p.id != exceptId);
  }

  @override
  Future<bool> isCodeTaken(String code, {String? exceptProductId}) async {
    await _store.wait();
    return _codeTaken(code, exceptProductId);
  }

  void _validate(Product p, String? exceptId) {
    if (normalizeCode(p.code).isEmpty) throw AppException('Product code is required.');
    if (_codeTaken(p.code, exceptId)) {
      throw AppException('Product code ${normalizeCode(p.code)} is already used by another product.');
    }
    if (p.priceMinor <= 0) throw AppException('Price must be greater than 0.');
    final d = p.discount;
    if (d != null && d.enabled) {
      final error = DiscountMath.validateForPrice(d.kind, d.value, p.priceMinor);
      if (error != null) throw AppException(error);
    }
  }

  @override
  Future<Product> createProduct(Product draft) async {
    await _store.wait();
    _validate(draft, null);
    final product = Product(
      id: _store.newId('p'),
      code: normalizeCode(draft.code),
      productName: draft.productName,
      description: draft.description,
      priceMinor: draft.priceMinor,
      category: draft.category,
      availability: draft.availability,
      imagePaths: draft.imagePaths,
      colors: draft.colors,
      sizes: draft.sizes,
      specs: draft.specs,
      isFeatured: draft.isFeatured,
      popularity: draft.popularity,
      unit: draft.unit,
      requiresMeasurements: draft.requiresMeasurements,
      discount: draft.discount,
      createdAt: _store.now(),
    );
    _store.products.insert(0, product);
    return product;
  }

  @override
  Future<Product> updateProduct(Product product) async {
    await _store.wait();
    final index = _store.products.indexWhere((p) => p.id == product.id);
    if (index < 0) throw AppException('This product no longer exists.');
    _validate(product, product.id);
    final saved = product.copyWith(code: normalizeCode(product.code));
    _store.products[index] = saved;
    return saved;
  }

  @override
  Future<void> deleteProduct(String id) async {
    await _store.wait();
    _store.products.removeWhere((p) => p.id == id);
  }
}
