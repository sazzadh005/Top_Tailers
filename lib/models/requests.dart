/// Review state of a customer request, updated by the shop admin.
enum RequestStatus { received, underReview, planned, declined }

extension RequestStatusX on RequestStatus {
  String get label {
    switch (this) {
      case RequestStatus.received:
        return 'Received';
      case RequestStatus.underReview:
        return 'Under review';
      case RequestStatus.planned:
        return 'Planned';
      case RequestStatus.declined:
        return 'Declined';
    }
  }
}

/// A customer's idea for a new fabric or product.
class ProductSuggestion {
  const ProductSuggestion({
    required this.id,
    required this.userId,
    required this.userName,
    required this.title,
    required this.details,
    this.status = RequestStatus.received,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String userName;
  final String title;
  final String details;
  final RequestStatus status;
  final DateTime createdAt;

  ProductSuggestion copyWith({RequestStatus? status}) => ProductSuggestion(
        id: id,
        userId: userId,
        userName: userName,
        title: title,
        details: details,
        status: status ?? this.status,
        createdAt: createdAt,
      );
}

/// A customer's request to bring an existing product back in stock.
class RestockRequest {
  const RestockRequest({
    required this.id,
    required this.userId,
    required this.userName,
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.reason,
    this.status = RequestStatus.received,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String userName;
  final String productId;
  final String productCode;
  final String productName;
  final String reason;
  final RequestStatus status;
  final DateTime createdAt;

  RestockRequest copyWith({RequestStatus? status}) => RestockRequest(
        id: id,
        userId: userId,
        userName: userName,
        productId: productId,
        productCode: productCode,
        productName: productName,
        reason: reason,
        status: status ?? this.status,
        createdAt: createdAt,
      );
}
