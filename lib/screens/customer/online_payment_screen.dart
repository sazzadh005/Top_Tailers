import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_exception.dart';
import '../../core/format.dart';
import '../../core/idempotency.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import '../../models/payment.dart';
import '../../providers/orders_provider.dart';
import '../../widgets/common.dart';
import 'order_success_screen.dart';

/// Real online payment: opens AamarPay's hosted page in the browser, then asks
/// the BACKEND what happened.
///
/// This screen never decides that a payment succeeded. It only reads the
/// payment status the server recorded after verifying with AamarPay, so
/// closing the browser, a forged redirect or a tampered app cannot mark an
/// order paid.
class OnlinePaymentScreen extends StatefulWidget {
  const OnlinePaymentScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<OnlinePaymentScreen> createState() => _OnlinePaymentScreenState();
}

class _OnlinePaymentScreenState extends State<OnlinePaymentScreen> with WidgetsBindingObserver {
  /// Same key for taps on the same attempt, so a double tap or a retry after a
  /// network error reuses one payment attempt instead of creating several.
  String _attemptKey = newIdempotencyKey();
  Timer? _poll;
  int _polls = 0;
  bool _launching = false;
  bool _checking = false;
  bool _launched = false;
  String? _message;
  bool _messageIsError = false;

  static const int _maxPolls = 30; // about two minutes at 4 s

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the browser: ask the server for the verified status.
    if (state == AppLifecycleState.resumed && _launched) _check();
  }

  Future<void> _pay(AppOrder order) async {
    final orders = context.read<OrdersProvider>();
    setState(() {
      _launching = true;
      _message = null;
    });
    try {
      final session = await orders.startOnlinePayment(order, idempotencyKey: _attemptKey);
      final url = session.redirectUrl;
      if (url == null) throw AppException('The payment page could not be opened. Please try again.');
      final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!opened) throw AppException('Could not open the payment page. Please try again.');
      _launched = true;
      _startPolling();
      if (mounted) {
        setState(() {
          _message = 'Complete the payment in your browser, then return here.';
          _messageIsError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = errorText(e);
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _polls = 0;
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_polls++ >= _maxPolls) {
        _poll?.cancel();
        return;
      }
      _check(silent: true);
    });
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    final orders = context.read<OrdersProvider>();
    final navigator = Navigator.of(context);
    setState(() => _checking = true);
    try {
      final order = await orders.refreshOrder(widget.orderId);
      if (!mounted) return;
      switch (order.payment.status) {
        case PaymentStatus.successful:
          _poll?.cancel();
          navigator.pushReplacement(
            MaterialPageRoute<void>(builder: (_) => OrderSuccessScreen(orderId: order.id)),
          );
          return;
        case PaymentStatus.failed:
        case PaymentStatus.cancelled:
          _poll?.cancel();
          _attemptKey = newIdempotencyKey(); // the next tap starts a fresh attempt
          setState(() {
            _message = order.payment.status == PaymentStatus.failed
                ? 'The payment did not complete. You can try again.'
                : 'The payment was cancelled. You can try again.';
            _messageIsError = true;
          });
        case PaymentStatus.pending:
          if (!silent) {
            setState(() {
              _message = 'Still waiting for the payment gateway to confirm. This can take a moment.';
              _messageIsError = false;
            });
          }
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _message = errorText(e);
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _payLater() {
    _poll?.cancel();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => OrderSuccessScreen(orderId: widget.orderId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = context.watch<OrdersProvider>().byId(widget.orderId);
    final textTheme = Theme.of(context).textTheme;

    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Online payment')),
        body: const EmptyState(
          icon: Icons.search_off,
          title: 'Order not found',
          message: 'You can find your orders in the Orders tab.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Online payment')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('Amount to pay', style: textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                    const SizedBox(height: 4),
                    Text(
                      formatMoney(order.totalMinor),
                      style: textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800, color: AppColors.burgundy),
                    ),
                    const SizedBox(height: 12),
                    InfoRow(icon: Icons.receipt_long_outlined, label: 'Order reference', value: order.reference),
                    Row(
                      children: [
                        Text('Payment status: ', style: textTheme.bodyMedium),
                        PaymentChip(payment: order.payment),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You will pay on AamarPay\u2019s secure page in your browser. This app never sees your card or wallet details. Your order is marked paid only after the payment is verified by our server.',
              style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _messageIsError ? Icons.error_outline : Icons.info_outline,
                    size: 18,
                    color: _messageIsError ? AppColors.danger : AppColors.info,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _message!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: _messageIsError ? AppColors.danger : AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            PrimaryButton(
              label: order.payment.status == PaymentStatus.pending
                  ? 'Pay with AamarPay'
                  : 'Try payment again',
              icon: Icons.lock_outline,
              busy: _launching,
              onPressed: () => _pay(order),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _checking ? null : () => _check(),
              icon: _checking
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              label: const Text('I have paid - check status'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _payLater,
              child: const Text('Pay later (the order stays placed, payment pending)'),
            ),
          ],
        ),
      ),
    );
  }
}
