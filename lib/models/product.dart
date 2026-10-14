/// Product categories offered by the shop. Used by browse filters and the
/// admin product form.
const List<String> kCategories = [
  'Fabrics',
  'Readymade',
  'Tailoring',
  'Accessories',
];

/// Mirrors the `products` Firestore collection in the SRS
/// (productName, description, price, category, image, availability).
class Product {
  const Product({
    required this.id,
    required this.productName,
    required this.description,
    required this.price,
    required this.category,
    required this.availability,
    this.imagePath,
  });

  final String id;
  final String productName;
  final String description;
  final double price;
  final String category;
  final bool availability;

  /// Local path of an uploaded image. Null means "show the placeholder".
  /// With a real backend this becomes a Firebase Storage download URL.
  final String? imagePath;

  Product copyWith({
    String? productName,
    String? description,
    double? price,
    String? category,
    bool? availability,
    String? imagePath,
    bool clearImage = false,
  }) {
    return Product(
      id: id,
      productName: productName ?? this.productName,
      description: description ?? this.description,
      price: price ?? this.price,
      category: category ?? this.category,
      availability: availability ?? this.availability,
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
    );
  }
}
