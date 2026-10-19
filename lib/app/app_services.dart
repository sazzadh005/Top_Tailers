import '../data/demo_payment_gateway.dart';
import '../data/mock/mock_auth_repository.dart';
import '../data/mock/mock_catalog_repository.dart';
import '../data/mock/mock_engagement_repositories.dart';
import '../data/mock/mock_order_repository.dart';
import '../data/mock/mock_pricing_repositories.dart';
import '../data/mock/mock_store.dart';
import '../repositories/repositories.dart';

/// Single place where data sources are chosen. To go live, build an
/// AppServices whose members call the real backend and pass it to
/// TopTailersApp; no screen or provider changes.
class AppServices {
  const AppServices({
    required this.auth,
    required this.catalog,
    required this.discounts,
    required this.vouchers,
    required this.orders,
    required this.notifications,
    required this.payments,
    required this.feedback,
    required this.requests,
    required this.wishlist,
  });

  final AuthRepository auth;
  final CatalogRepository catalog;
  final DiscountRepository discounts;
  final VoucherRepository vouchers;
  final OrderRepository orders;
  final NotificationRepository notifications;
  final PaymentGateway payments;
  final FeedbackRepository feedback;
  final RequestRepository requests;
  final WishlistRepository wishlist;

  /// Demonstration services backed by in-memory mock data.
  factory AppServices.mock({
    Duration latency = const Duration(milliseconds: 350),
    DateTime Function()? clock,
  }) {
    final store = MockStore(latency: latency, clock: clock);
    return AppServices(
      auth: MockAuthRepository(store),
      catalog: MockCatalogRepository(store),
      discounts: MockDiscountRepository(store),
      vouchers: MockVoucherRepository(store),
      orders: MockOrderRepository(store),
      notifications: MockNotificationRepository(store),
      payments: DemoPaymentGateway(latency: latency == Duration.zero ? Duration.zero : const Duration(milliseconds: 300)),
      feedback: MockFeedbackRepository(store),
      requests: MockRequestRepository(store),
      wishlist: MockWishlistRepository(store),
    );
  }
}
