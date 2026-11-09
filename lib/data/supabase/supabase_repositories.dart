import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_exception.dart';
import '../../domain/order_search.dart';
import '../../models/app_notification.dart';
import '../../models/app_user.dart';
import '../../models/catalog_query.dart';
import '../../models/customer_discount.dart';
import '../../models/customer_summary.dart';
import '../../models/feedback.dart';
import '../../models/measurements.dart';
import '../../models/order.dart';
import '../../models/payment.dart';
import '../../models/product.dart';
import '../../models/requests.dart';
import '../../models/voucher.dart';
import '../../repositories/repositories.dart';
import 'error_mapper.dart';
import 'json_mappers.dart';

/// Every call goes through the audited SQL functions, and every failure
/// becomes a safe [AppException].
class _Rpc {
  _Rpc(this.client);

  final SupabaseClient client;

  Future<dynamic> call(String fn, [Map<String, dynamic>? params]) async {
    try {
      return await client.rpc(fn, params: params);
    } catch (e) {
      throw appExceptionFrom(e);
    }
  }
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(SupabaseClient client)
      : _client = client,
        _rpc = _Rpc(client);

  final SupabaseClient _client;
  final _Rpc _rpc;

  /// Deep link configured in Supabase Auth for password-reset emails.
  static const String authRedirect = 'io.supabase.toptailers://login-callback/';

  Future<AppUser> _profile() async => userFromJson(asJson(await _rpc.call('my_profile')));

  @override
  Future<AppUser> login(String email, String password) async {
    try {
      await _client.auth.signInWithPassword(email: email.trim(), password: password);
    } catch (e) {
      throw appExceptionFrom(e);
    }
    return _profile();
  }

  @override
  Future<AppUser> register({
    required String name,
    required String email,
    required String phone,
    required String address,
    required String password,
    BodyMeasurements measurements = BodyMeasurements.empty,
  }) async {
    final AuthResponse res;
    try {
      res = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'name': name.trim(),
          'phone': phone.trim(),
          'address': address.trim(),
          if (measurements.isNotEmpty) 'measurements': measurementsToJson(measurements),
        },
      );
    } catch (e) {
      throw appExceptionFrom(e);
    }
    if (res.session == null) {
      throw AppException('Account created. Please confirm your email, then sign in.');
    }
    return _profile();
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim(), redirectTo: authRedirect);
    } catch (e) {
      throw appExceptionFrom(e);
    }
  }

  @override
  Future<AppUser> updateProfile(AppUser u) async {
    final hasImage = u.profileImage != null && u.profileImagePublicId != null;
    final json = await _rpc.call('update_my_profile', {
      'p_name': u.name,
      'p_phone': u.phone,
      'p_address': u.address,
      'p_image_url': hasImage ? u.profileImage : null,
      'p_image_public_id': hasImage ? u.profileImagePublicId : null,
      'p_clear_image': u.profileImage == null,
    });
    return userFromJson(asJson(json));
  }

  @override
  Future<AppUser> updateMeasurements(
    String customerId,
    BodyMeasurements measurements, {
    required AppUser actor,
  }) async {
    final json = await _rpc.call('set_measurements', {
      'p_customer': customerId,
      'p_values': measurementsToJson(measurements),
    });
    return userFromJson(asJson(json));
  }

  @override
  Future<List<CustomerSummary>> getCustomerSummaries({required AppUser actor}) async {
    final json = await _rpc.call('admin_list_customers');
    return [for (final c in asJsonList(json)) customerSummaryFromJson(c)];
  }

  @override
  Future<AppUser?> restoreSession() async {
    if (_client.auth.currentSession == null) return null;
    try {
      return await _profile();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> logout() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      throw appExceptionFrom(e);
    }
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } catch (e) {
      throw appExceptionFrom(e);
    }
  }

  @override
  Stream<void> get passwordRecoveryEvents => _client.auth.onAuthStateChange
      .where((s) => s.event == AuthChangeEvent.passwordRecovery)
      .map((_) {});

  @override
  Stream<void> get sessionEndedEvents => _client.auth.onAuthStateChange
      .where((s) => s.event == AuthChangeEvent.signedOut)
      .map((_) {});
}

class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository(SupabaseClient client) : _rpc = _Rpc(client);

  final _Rpc _rpc;

  @override
  Future<PageResult<Product>> searchProducts(ProductQuery q) async {
    final json = await _rpc.call('search_products', {
      'p_text': q.text,
      'p_category': q.category,
      'p_sort': q.sort.name,
      'p_in_stock': q.inStockOnly,
      'p_page': q.page,
      'p_page_size': q.pageSize,
    });
    return productPageFromJson(asJson(json));
  }

  @override
  Future<Product?> getProduct(String id) async {
    final list = await getProductsByIds([id]);
    return list.isEmpty ? null : list.first;
  }

  @override
  Future<List<Product>> getProductsByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final json = await _rpc.call('get_products_by_ids', {'p_ids': ids});
    return [for (final p in asJsonList(json)) productFromJson(p)];
  }

  @override
  Future<HomeContent> getHome() async => homeFromJson(asJson(await _rpc.call('get_home')));

  @override
  Future<Product> createProduct(Product draft) async =>
      productFromJson(asJson(await _rpc.call('admin_save_product', {'p': productToJson(draft)})));

  @override
  Future<Product> updateProduct(Product product) async =>
      productFromJson(asJson(await _rpc.call('admin_save_product', {'p': productToJson(product)})));

  @override
  Future<void> deleteProduct(String id) async {
    await _rpc.call('admin_delete_product', {'p_id': id});
  }

  @override
  Future<bool> isCodeTaken(String code, {String? exceptProductId}) async {
    final r = await _rpc.call('admin_is_code_taken', {'p_code': code, 'p_except': exceptProductId});
    return r == true;
  }
}

class SupabaseDiscountRepository implements DiscountRepository {
  SupabaseDiscountRepository(SupabaseClient client) : _rpc = _Rpc(client);

  final _Rpc _rpc;

  /// The server always answers for the signed-in caller, so only the caller's
  /// own discount can be read, whatever [customerId] says.
  @override
  Future<CustomerDiscount?> getCustomerDiscount(String customerId) async {
    final json = await _rpc.call('my_customer_discount');
    return json == null ? null : customerDiscountFromJson(asJson(json));
  }

  @override
  Future<List<CustomerDiscount>> listCustomerDiscounts() async {
    final json = await _rpc.call('admin_list_customer_discounts');
    return [for (final d in asJsonList(json)) customerDiscountFromJson(d)];
  }

  @override
  Future<CustomerDiscount> saveCustomerDiscount(CustomerDiscount d) async {
    final json = await _rpc.call('admin_save_customer_discount', {
      'p_customer': d.customerId,
      'p_kind': d.kind.name,
      'p_value': d.value,
      'p_active': d.active,
      'p_note': d.note,
    });
    return customerDiscountFromJson(asJson(json));
  }

  @override
  Future<void> removeCustomerDiscount(String customerId) async {
    await _rpc.call('admin_remove_customer_discount', {'p_customer': customerId});
  }
}

class SupabaseVoucherRepository implements VoucherRepository {
  SupabaseVoucherRepository(SupabaseClient client) : _rpc = _Rpc(client);

  final _Rpc _rpc;

  @override
  Future<Voucher?> findByCode(String code) async {
    final json = await _rpc.call('get_voucher', {'p_code': code});
    return json == null ? null : voucherFromJson(asJson(json));
  }
}

class SupabaseOrderRepository implements OrderRepository {
  SupabaseOrderRepository(SupabaseClient client) : _rpc = _Rpc(client);

  final _Rpc _rpc;

  @override
  Future<AppOrder> placeOrder(PlaceOrderRequest request) async {
    final json = await _rpc.call('place_order', {
      'p_request': orderRequestToJson(request),
      'p_idempotency_key': request.idempotencyKey,
    });
    return orderFromJson(asJson(json));
  }

  /// Which orders come back is decided by the server from the caller's
  /// identity; [viewer] is not sent.
  @override
  Future<List<AppOrder>> searchOrders(OrderSearchQuery query, {required AppUser viewer}) async {
    final json = await _rpc.call('search_orders', {
      'p_text': query.text,
      'p_status': query.status?.name,
      'p_payment_status': query.paymentStatus?.name,
      'p_from': dateOnly(query.from),
      'p_to': dateOnly(query.to),
      'p_limit': 100,
      'p_offset': 0,
    });
    return [for (final o in asJsonList(json)) orderFromJson(o)];
  }

  @override
  Future<AppOrder> getOrder(String orderId) async =>
      orderFromJson(asJson(await _rpc.call('get_order', {'p_id': orderId})));

  @override
  Future<AppOrder> cancelOrder(
    String orderId, {
    required AppUser actor,
    required String reason,
    String note = '',
  }) async {
    final json = await _rpc.call('cancel_order', {'p_order_id': orderId, 'p_reason': reason, 'p_note': note});
    return orderFromJson(asJson(json));
  }

  @override
  Future<AppOrder> updateStatus(String orderId, OrderStatus status) async {
    final json = await _rpc.call('update_order_status', {'p_order_id': orderId, 'p_status': status.name});
    return orderFromJson(asJson(json));
  }

  @override
  Future<AppOrder> updatePayment(
    String orderId,
    PaymentStatus status, {
    PaymentProvider provider = PaymentProvider.demo,
    String? transactionRef,
  }) {
    throw AppException('Payment status is recorded by the server once the payment gateway confirms it.');
  }
}

class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository(SupabaseClient client) : _rpc = _Rpc(client);

  final _Rpc _rpc;

  /// The server applies the 30-day rule (exactly 30 days old is still shown).
  @override
  Future<List<AppNotification>> getVisible(String userId) async {
    final json = await _rpc.call('visible_notifications');
    return [for (final n in asJsonList(json)) notificationFromJson(n)];
  }

  @override
  Future<void> markAllRead(String userId) async {
    await _rpc.call('mark_notifications_read');
  }
}

class SupabaseFeedbackRepository implements FeedbackRepository {
  SupabaseFeedbackRepository(SupabaseClient client) : _rpc = _Rpc(client);

  final _Rpc _rpc;

  @override
  Future<ProductFeedback> submit(ProductFeedback f) async {
    final json = await _rpc.call('submit_feedback', {
      'p_order_id': f.orderId,
      'p_product_id': f.productId,
      'p_rating': f.rating,
      'p_comment': f.comment,
    });
    return feedbackFromJson(asJson(json));
  }

  @override
  Future<List<ProductFeedback>> forProduct(String productId) async {
    final json = await _rpc.call('feedback_for_product', {'p_product_id': productId});
    return [for (final f in asJsonList(json)) feedbackFromJson(f)];
  }

  @override
  Future<List<ProductFeedback>> forUser(String userId) async {
    final json = await _rpc.call('my_feedback');
    return [for (final f in asJsonList(json)) feedbackFromJson(f)];
  }

  @override
  Future<List<ProductFeedback>> all() async {
    final json = await _rpc.call('admin_all_feedback');
    return [for (final f in asJsonList(json)) feedbackFromJson(f)];
  }
}

class SupabaseRequestRepository implements RequestRepository {
  SupabaseRequestRepository(SupabaseClient client) : _rpc = _Rpc(client);

  final _Rpc _rpc;

  @override
  Future<ProductSuggestion> submitSuggestion(ProductSuggestion s) async => suggestionFromJson(
        asJson(await _rpc.call('submit_suggestion', {'p_title': s.title, 'p_details': s.details})),
      );

  @override
  Future<RestockRequest> submitRestock(RestockRequest r) async => restockFromJson(
        asJson(await _rpc.call('submit_restock', {'p_product_id': r.productId, 'p_reason': r.reason})),
      );

  @override
  Future<List<ProductSuggestion>> suggestionsFor(String userId) async =>
      [for (final s in asJsonList(await _rpc.call('my_suggestions'))) suggestionFromJson(s)];

  @override
  Future<List<RestockRequest>> restocksFor(String userId) async =>
      [for (final r in asJsonList(await _rpc.call('my_restocks'))) restockFromJson(r)];

  @override
  Future<List<ProductSuggestion>> allSuggestions() async =>
      [for (final s in asJsonList(await _rpc.call('admin_all_suggestions'))) suggestionFromJson(s)];

  @override
  Future<List<RestockRequest>> allRestocks() async =>
      [for (final r in asJsonList(await _rpc.call('admin_all_restocks'))) restockFromJson(r)];

  @override
  Future<void> setSuggestionStatus(String id, RequestStatus status) async {
    await _rpc.call('set_suggestion_status', {'p_id': id, 'p_status': status.name});
  }

  @override
  Future<void> setRestockStatus(String id, RequestStatus status) async {
    await _rpc.call('set_restock_status', {'p_id': id, 'p_status': status.name});
  }
}

/// Wishlist rows are protected by row-level security (own rows only).
class SupabaseWishlistRepository implements WishlistRepository {
  SupabaseWishlistRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Set<String>> ids(String userId) async {
    try {
      final rows = await _client.from('wishlist_items').select('product_id').eq('user_id', userId);
      return {for (final r in rows) r['product_id'] as String};
    } catch (e) {
      throw appExceptionFrom(e);
    }
  }

  @override
  Future<void> add(String userId, String productId) async {
    try {
      await _client
          .from('wishlist_items')
          .upsert({'user_id': userId, 'product_id': productId}, onConflict: 'user_id,product_id', ignoreDuplicates: true);
    } catch (e) {
      throw appExceptionFrom(e);
    }
  }

  @override
  Future<void> remove(String userId, String productId) async {
    try {
      await _client.from('wishlist_items').delete().eq('user_id', userId).eq('product_id', productId);
    } catch (e) {
      throw appExceptionFrom(e);
    }
  }
}
