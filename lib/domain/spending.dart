import '../models/order.dart';
import '../models/payment.dart';

/// Lifetime Spending: the single place this figure is calculated.
///
/// Rules:
///  - an order counts only when it is Completed AND its payment is
///    successful (for COD, payment is confirmed on delivery);
///  - Cancelled orders and failed/pending/cancelled online payments are
///    excluded;
///  - every order id is counted once even if it appears twice in the input;
///  - refunds and partial refunds are not modelled (the SRS defines none),
///    so nothing is subtracted.
///
/// This is a frontend figure from mock data, not a verified financial record.
class SpendingCalculator {
  SpendingCalculator._();

  static bool qualifies(AppOrder order) =>
      order.status == OrderStatus.completed &&
      order.payment.status == PaymentStatus.successful;

  static int lifetimeSpendingMinor(Iterable<AppOrder> orders) {
    final seen = <String>{};
    var total = 0;
    for (final order in orders) {
      if (!seen.add(order.id)) continue;
      if (qualifies(order)) total += order.totalMinor;
    }
    return total;
  }

  static int orderCount(Iterable<AppOrder> orders) =>
      orders.map((o) => o.id).toSet().length;
}
