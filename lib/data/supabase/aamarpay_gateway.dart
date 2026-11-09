import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_exception.dart';
import '../../models/payment.dart';
import '../../repositories/repositories.dart';
import 'error_mapper.dart';

/// Starts an AamarPay payment through the backend's `payments-initiate`
/// function. The app sends only the order id: the amount, customer details and
/// merchant credentials are all server-side, and the payment is marked paid
/// only after the SERVER verifies it with AamarPay. This class never reports
/// success.
class AamarPayGateway implements PaymentGateway {
  AamarPayGateway(this._client);

  final SupabaseClient _client;

  @override
  bool get isDemo => false;

  @override
  String get displayName => 'AamarPay';

  @override
  Future<PaymentSession> initiate({
    required String orderId,
    required int amountMinor,
    String? idempotencyKey,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'payments-initiate',
        body: {
          'orderId': orderId,
          if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
        },
      );
      final data = res.data;
      if (data is! Map || data['paymentUrl'] is! String) {
        throw AppException('The payment page could not be opened. Please try again.');
      }
      return PaymentSession(
        id: data['tranId'] as String,
        orderId: orderId,
        amountMinor: (data['amountMinor'] as num).toInt(),
        provider: PaymentProvider.aamarpay,
        redirectUrl: data['paymentUrl'] as String,
      );
    } catch (e) {
      throw appExceptionFrom(e);
    }
  }
}
