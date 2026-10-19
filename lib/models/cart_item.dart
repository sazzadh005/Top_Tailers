import '../domain/pricing.dart';
import 'product.dart';

/// One line in the cart: a product plus the variant the customer picked.
class CartItem {
  const CartItem({
    required this.product,
    required this.quantity,
    this.colorName,
    this.size,
  });

  final Product product;
  final int quantity;
  final String? colorName;
  final String? size;

  String get key => CartItem.keyFor(product.id, colorName, size);

  static String keyFor(String productId, String? colorName, String? size) =>
      '$productId|${colorName ?? ''}|${size ?? ''}';

  int get listUnitMinor => product.priceMinor;
  int get unitMinor => product.effectivePriceMinor;
  int get lineListTotalMinor => listUnitMinor * quantity;
  int get lineTotalMinor => unitMinor * quantity;

  String get variantLabel {
    final parts = <String>[
      if (colorName != null) colorName!,
      if (size != null) 'Size $size',
    ];
    return parts.join('  |  ');
  }

  PricedLine toPricedLine() => PricedLine(
        category: product.category,
        listUnitMinor: listUnitMinor,
        unitMinor: unitMinor,
        quantity: quantity,
      );

  CartItem copyWith({int? quantity}) {
    return CartItem(
      product: product,
      quantity: quantity ?? this.quantity,
      colorName: colorName,
      size: size,
    );
  }
}
