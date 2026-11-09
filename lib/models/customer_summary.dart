import 'app_user.dart';

/// A customer plus figures the SERVER calculates (so they stay correct even
/// when the app has only loaded part of the order history).
class CustomerSummary {
  const CustomerSummary({
    required this.user,
    required this.orderCount,
    required this.lifetimeSpendingMinor,
  });

  final AppUser user;
  final int orderCount;

  /// Completed orders with confirmed payment only (see SpendingCalculator).
  final int lifetimeSpendingMinor;

  CustomerSummary withUser(AppUser updated) => CustomerSummary(
        user: updated,
        orderCount: orderCount,
        lifetimeSpendingMinor: lifetimeSpendingMinor,
      );
}
