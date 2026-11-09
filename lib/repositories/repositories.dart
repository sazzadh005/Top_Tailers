import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../models/catalog_query.dart';
import '../models/customer_summary.dart';
import '../models/uploaded_image.dart';
import '../models/customer_discount.dart';
import '../models/feedback.dart';
import '../models/measurements.dart';
import '../models/order.dart';
import '../models/payment.dart';
import '../models/product.dart';
import '../models/requests.dart';
import '../models/voucher.dart';
import '../domain/order_search.dart';
import 'package:image_picker/image_picker.dart';

/// These interfaces are the seam between the UI and a future backend.
/// Mock implementations live in lib/data/mock. A REST/Firebase implementation
/// can replace them without touching providers or screens.
///
/// Authorization (who may read or change what) MUST be enforced by the real
/// backend; the mock implementations only imitate it.

abstract class AuthRepository {
  Future<AppUser> login(String email, String password);
  Future<AppUser> register({
    required String name,
    required String email,
    required String phone,
    required String address,
    required String password,
    BodyMeasurements measurements = BodyMeasurements.empty,
  });
  Future<void> sendPasswordReset(String email);
  Future<AppUser> updateProfile(AppUser updated);

  /// Restores a persisted session at app start, or null when signed out.
  Future<AppUser?> restoreSession();
  Future<void> logout();

  /// Sets a new password after the reset-email link was opened.
  Future<void> updatePassword(String newPassword);

  /// Fires when the app was opened from a password-reset link.
  Stream<void> get passwordRecoveryEvents;

  /// Fires when the session ended (sign-out elsewhere, expired refresh token).
  Stream<void> get sessionEndedEvents;

  /// Customers may update their own; admins may update any customer's.
  Future<AppUser> updateMeasurements(
    String customerId,
    BodyMeasurements measurements, {
    required AppUser actor,
  });

  /// Admin only. Includes each customer's order count and server-calculated
  /// Lifetime Spending.
  Future<List<CustomerSummary>> getCustomerSummaries({required AppUser actor});
}

abstract class CatalogRepository {
  Future<PageResult<Product>> searchProducts(ProductQuery query);
  Future<Product?> getProduct(String id);
  Future<List<Product>> getProductsByIds(List<String> ids);
  Future<HomeContent> getHome();

  /// Admin operations. Product codes must be unique; implementations throw
  /// [AppException] on a duplicate.
  Future<Product> createProduct(Product draft);
  Future<Product> updateProduct(Product product);
  Future<void> deleteProduct(String id);
  Future<bool> isCodeTaken(String code, {String? exceptProductId});
}

abstract class DiscountRepository {
  Future<CustomerDiscount?> getCustomerDiscount(String customerId);
  Future<List<CustomerDiscount>> listCustomerDiscounts();
  Future<CustomerDiscount> saveCustomerDiscount(CustomerDiscount discount);
  Future<void> removeCustomerDiscount(String customerId);
}

abstract class VoucherRepository {
  /// Returns null when the code is unknown.
  Future<Voucher?> findByCode(String code);
}

abstract class OrderRepository {
  Future<AppOrder> placeOrder(PlaceOrderRequest request);

  /// Customers get only their own orders; admins get every order.
  Future<List<AppOrder>> searchOrders(
    OrderSearchQuery query, {
    required AppUser viewer,
  });
  Future<AppOrder> cancelOrder(
    String orderId, {
    required AppUser actor,
    required String reason,
    String note = '',
  });
  Future<AppOrder> updateStatus(String orderId, OrderStatus status);
  Future<AppOrder> getOrder(String orderId);

  /// DEMO ONLY. A real backend never lets a client set payment state: the
  /// server records it after verifying with the payment provider.
  Future<AppOrder> updatePayment(
    String orderId,
    PaymentStatus status, {
    PaymentProvider provider = PaymentProvider.demo,
    String? transactionRef,
  });
}

abstract class NotificationRepository {
  /// Returns only notifications the customer should see (30-day retention).
  Future<List<AppNotification>> getVisible(String userId);
  Future<void> markAllRead(String userId);
}

/// Replaceable payment gateway. The real AamarPay implementation lives behind
/// the backend: merchant credentials, transaction initiation, callback
/// verification and payment validation never touch the app.
abstract class PaymentGateway {
  bool get isDemo;
  String get displayName;
  /// [amountMinor] is for display only: a real gateway takes the amount from
  /// the stored order on the server.
  Future<PaymentSession> initiate({
    required String orderId,
    required int amountMinor,
    String? idempotencyKey,
  });
}

/// Uploads images to the image host (Cloudinary). Real uploads are authorised
/// by a server-signed ticket; the app never holds the API secret.
abstract class ImageUploader {
  Future<UploadedImage> uploadProductImage(XFile image);
  Future<UploadedImage> uploadAvatar(XFile image);
}

abstract class FeedbackRepository {
  Future<ProductFeedback> submit(ProductFeedback feedback);
  Future<List<ProductFeedback>> forProduct(String productId);
  Future<List<ProductFeedback>> forUser(String userId);
  Future<List<ProductFeedback>> all();
}

abstract class RequestRepository {
  Future<ProductSuggestion> submitSuggestion(ProductSuggestion s);
  Future<RestockRequest> submitRestock(RestockRequest r);
  Future<List<ProductSuggestion>> suggestionsFor(String userId);
  Future<List<RestockRequest>> restocksFor(String userId);
  Future<List<ProductSuggestion>> allSuggestions();
  Future<List<RestockRequest>> allRestocks();
  Future<void> setSuggestionStatus(String id, RequestStatus status);
  Future<void> setRestockStatus(String id, RequestStatus status);
}

abstract class WishlistRepository {
  Future<Set<String>> ids(String userId);
  Future<void> add(String userId, String productId);
  Future<void> remove(String userId, String productId);
}
