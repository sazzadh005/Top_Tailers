import 'product.dart';
import 'voucher.dart';

enum ProductSort { featured, newest, priceLow, priceHigh, nameAZ }

extension ProductSortX on ProductSort {
  String get label {
    switch (this) {
      case ProductSort.featured:
        return 'Featured';
      case ProductSort.newest:
        return 'Newest';
      case ProductSort.priceLow:
        return 'Price: low to high';
      case ProductSort.priceHigh:
        return 'Price: high to low';
      case ProductSort.nameAZ:
        return 'Name: A to Z';
    }
  }
}

/// Query sent to the catalogue. Shaped like a typical REST/GraphQL request so
/// a backend can implement it directly.
class ProductQuery {
  const ProductQuery({
    this.text = '',
    this.category,
    this.sort = ProductSort.featured,
    this.inStockOnly = false,
    this.page = 1,
    this.pageSize = 8,
  });

  final String text;
  final String? category;
  final ProductSort sort;
  final bool inStockOnly;
  final int page;
  final int pageSize;

  ProductQuery withPage(int newPage) => ProductQuery(
        text: text,
        category: category,
        sort: sort,
        inStockOnly: inStockOnly,
        page: newPage,
        pageSize: pageSize,
      );
}

class PageResult<T> {
  const PageResult({
    required this.items,
    required this.page,
    required this.hasMore,
    required this.total,
  });

  final List<T> items;
  final int page;
  final bool hasMore;
  final int total;
}

/// A promotional banner on the home screen.
class PromoBanner {
  const PromoBanner({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.colorArgb,
    this.category,
    this.voucherCode,
  });

  final String id;
  final String title;
  final String subtitle;
  final int colorArgb;

  /// Opens the shop on this category when tapped.
  final String? category;

  /// Shown as "Use code X" on the banner.
  final String? voucherCode;
}

class HomeContent {
  const HomeContent({
    required this.banners,
    required this.featured,
    required this.services,
    required this.popular,
    required this.discounted,
    required this.offers,
  });

  final List<PromoBanner> banners;
  final List<Product> featured;
  final List<Product> services;
  final List<Product> popular;
  final List<Product> discounted;

  /// Public vouchers advertised as offers.
  final List<Voucher> offers;

  static const HomeContent empty = HomeContent(
    banners: [],
    featured: [],
    services: [],
    popular: [],
    discounted: [],
    offers: [],
  );
}
