import '../models/payment.dart';
import '../repositories/repositories.dart';

/// DEMONSTRATION gateway. It starts a fake session so the UI flow can be
/// built and tested. It contacts no payment provider, collects no
/// credentials and can never produce a genuine payment confirmation.
///
/// To integrate SSLCommerz later, add a gateway that calls YOUR backend
/// (which holds the merchant credentials, initiates the transaction and
/// verifies the provider callback), then register it in AppServices.
class DemoPaymentGateway implements PaymentGateway {
  DemoPaymentGateway({this.latency = const Duration(milliseconds: 300)});

  final Duration latency;
  int _counter = 0;

  @override
  bool get isDemo => true;

  @override
  String get displayName => 'Demonstration gateway (no real payment)';

  @override
  Future<PaymentSession> initiate({
    required String orderId,
    required int amountMinor,
  }) async {
    if (latency != Duration.zero) await Future<void>.delayed(latency);
    _counter++;
    return PaymentSession(
      id: 'DEMO-SESSION-$_counter',
      orderId: orderId,
      amountMinor: amountMinor,
      provider: PaymentProvider.demo,
    );
  }
}
