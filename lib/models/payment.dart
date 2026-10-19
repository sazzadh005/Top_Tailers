/// How the customer pays for an order. Exactly two methods are offered.
enum PaymentMethod { cod, online }

extension PaymentMethodX on PaymentMethod {
  String get label => this == PaymentMethod.cod ? 'Cash on Delivery' : 'Online Payment';
}

/// Payment state, tracked separately from the order's fulfilment status.
enum PaymentStatus { pending, successful, failed, cancelled }

extension PaymentStatusX on PaymentStatus {
  String get label {
    switch (this) {
      case PaymentStatus.pending:
        return 'Pending';
      case PaymentStatus.successful:
        return 'Paid';
      case PaymentStatus.failed:
        return 'Failed';
      case PaymentStatus.cancelled:
        return 'Cancelled';
    }
  }
}

/// Which system produced a payment record.
///  - none:       cash on delivery, no gateway involved
///  - demo:       the frontend demonstration flow (NOT a real payment)
///  - sslcommerz: reserved for the future verified SSLCommerz integration
enum PaymentProvider { none, demo, sslcommerz }

class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.method,
    required this.status,
    required this.amountMinor,
    required this.provider,
    this.transactionRef,
    required this.updatedAt,
  });

  final String id;
  final PaymentMethod method;
  final PaymentStatus status;
  final int amountMinor;
  final PaymentProvider provider;

  /// Provider transaction reference. Always null for demo/COD records.
  final String? transactionRef;
  final DateTime updatedAt;

  bool get isDemo => provider == PaymentProvider.demo;

  /// Text for payment chips. A demo "Paid" is explicitly marked as demo.
  String get statusLabel {
    if (method == PaymentMethod.cod) {
      return status == PaymentStatus.successful ? 'Paid on delivery' : 'Pay on delivery';
    }
    if (isDemo && status == PaymentStatus.successful) return 'Paid (demo)';
    return status.label;
  }

  PaymentRecord copyWith({
    PaymentStatus? status,
    PaymentProvider? provider,
    String? transactionRef,
    DateTime? updatedAt,
  }) {
    return PaymentRecord(
      id: id,
      method: method,
      status: status ?? this.status,
      amountMinor: amountMinor,
      provider: provider ?? this.provider,
      transactionRef: transactionRef ?? this.transactionRef,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Handle returned when an online payment is started with a gateway.
class PaymentSession {
  const PaymentSession({
    required this.id,
    required this.orderId,
    required this.amountMinor,
    required this.provider,
    this.redirectUrl,
  });

  final String id;
  final String orderId;
  final int amountMinor;
  final PaymentProvider provider;

  /// Hosted payment page a real gateway would return. Null for the demo.
  final String? redirectUrl;
}
