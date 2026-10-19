import '../domain/discount.dart';

/// Product categories offered by the shop.
const List<String> kCategories = [
  'Fabrics',
  'Readymade',
  'Tailoring',
  'Accessories',
];

class FabricColor {
  const FabricColor({required this.name, required this.argb});

  final String name;
  final int argb;
}

/// Mirrors the `products` collection in the SRS (productName, description,
/// price, category, image, availability) plus catalogue fields for product
/// codes, discounts and variants. Money is in paisa.
class Product {
  const Product({
    required this.id,
    required this.code,
    required this.productName,
    required this.description,
    required this.priceMinor,
    required this.category,
    required this.availability,
    this.imagePaths = const [],
    this.colors = const [],
    this.sizes = const [],
    this.specs = const {},
    this.isFeatured = false,
    this.popularity = 0,
    this.unit = 'piece',
    this.requiresMeasurements = false,
    this.discount,
    required this.createdAt,
  });

  final String id;

  /// Unique, stable product code (e.g. FAB-COT-001). A backend must enforce
  /// uniqueness.
  final String code;
  final String productName;
  final String description;
  final int priceMinor;
  final String category;
  final bool availability;
  final List<String> imagePaths;
  final List<FabricColor> colors;
  final List<String> sizes;
  final Map<String, String> specs;
  final bool isFeatured;

  /// Mock popularity score used for the "Popular" shelf.
  final int popularity;

  /// 'yard' for fabric, 'piece' for garments, 'service' for tailoring.
  final String unit;

  /// True for services that need body measurements (e.g. stitching).
  final bool requiresMeasurements;
  final ProductDiscount? discount;
  final DateTime createdAt;

  String? get imagePath => imagePaths.isEmpty ? null : imagePaths.first;
  bool get isFabric => category == 'Fabrics';

  int get discountAmountMinor => discount?.amountFor(priceMinor) ?? 0;
  bool get hasDiscount => discountAmountMinor > 0;
  int get effectivePriceMinor => priceMinor - discountAmountMinor;

  /// Whole-percent equivalent for badges (rounded down).
  int get discountPercent =>
      priceMinor == 0 ? 0 : (discountAmountMinor * 100) ~/ priceMinor;

  bool get hasVariants => colors.isNotEmpty || sizes.isNotEmpty;

  Product copyWith({
    String? code,
    String? productName,
    String? description,
    int? priceMinor,
    String? category,
    bool? availability,
    List<String>? imagePaths,
    List<FabricColor>? colors,
    List<String>? sizes,
    Map<String, String>? specs,
    bool? isFeatured,
    int? popularity,
    String? unit,
    bool? requiresMeasurements,
    ProductDiscount? discount,
    bool clearDiscount = false,
  }) {
    return Product(
      id: id,
      code: code ?? this.code,
      productName: productName ?? this.productName,
      description: description ?? this.description,
      priceMinor: priceMinor ?? this.priceMinor,
      category: category ?? this.category,
      availability: availability ?? this.availability,
      imagePaths: imagePaths ?? this.imagePaths,
      colors: colors ?? this.colors,
      sizes: sizes ?? this.sizes,
      specs: specs ?? this.specs,
      isFeatured: isFeatured ?? this.isFeatured,
      popularity: popularity ?? this.popularity,
      unit: unit ?? this.unit,
      requiresMeasurements: requiresMeasurements ?? this.requiresMeasurements,
      discount: clearDiscount ? null : (discount ?? this.discount),
      createdAt: createdAt,
    );
  }
}
