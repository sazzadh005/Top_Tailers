/// A customer's feedback on a product they received in an order.
class ProductFeedback {
  const ProductFeedback({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  final String id;
  final String orderId;
  final String productId;
  final String productName;
  final String userId;
  final String userName;

  /// 1 to 5.
  final int rating;
  final String comment;
  final DateTime createdAt;

  static String keyFor(String orderId, String productId) => '$orderId|$productId';

  String get key => keyFor(orderId, productId);
}
