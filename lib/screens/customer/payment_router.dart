import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/orders_provider.dart';
import 'online_payment_screen.dart';
import 'payment_demo_screen.dart';

/// Picks the payment screen for the configured gateway: the clearly-labelled
/// demonstration, or the real hosted-page flow.
Widget paymentScreenFor(BuildContext context, String orderId) {
  final demo = context.read<OrdersProvider>().isDemoGateway;
  return demo ? PaymentDemoScreen(orderId: orderId) : OnlinePaymentScreen(orderId: orderId);
}
