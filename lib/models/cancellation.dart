enum CancelActor { customer, shopAdmin }

extension CancelActorX on CancelActor {
  String get label => this == CancelActor.customer ? 'Customer' : 'Shop Admin';
}

/// Permanent record of who cancelled an order, when and why. Cancelled orders
/// are never deleted.
class CancellationRecord {
  const CancellationRecord({
    required this.cancelledBy,
    required this.cancelledByName,
    required this.reason,
    this.note = '',
    required this.cancelledAt,
  });

  final CancelActor cancelledBy;
  final String cancelledByName;
  final String reason;
  final String note;
  final DateTime cancelledAt;
}

/// Reasons offered in the cancel dialog. "Other" requires a written note.
const List<String> kCustomerCancelReasons = [
  'Ordered by mistake',
  'Found a better price elsewhere',
  'Need to change the order details',
  'No longer needed',
  'Other',
];

const List<String> kAdminCancelReasons = [
  'Item out of stock',
  'Unable to reach the customer',
  'Customer requested cancellation',
  'Pricing or listing error',
  'Other',
];
