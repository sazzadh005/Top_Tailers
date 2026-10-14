import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/orders_provider.dart';
import '../../widgets/common.dart';
import 'order_success_screen.dart';

/// Use case "place an order" from the SRS: review items, confirm the
/// delivery address, tap Place Order. On failure the cart is kept.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _address;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _address = TextEditingController(
      text: context.read<AuthProvider>().user?.address ?? '',
    );
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final user = context.read<AuthProvider>().user;
    final cart = context.read<CartProvider>();
    final orders = context.read<OrdersProvider>();
    final navigator = Navigator.of(context);
    if (user == null || cart.isEmpty) return;

    setState(() => _busy = true);
    try {
      final order = await orders.placeOrder(
        user: user,
        items: cart.items,
        address: _address.text,
      );
      cart.clear();
      navigator.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => OrderSuccessScreen(order: order)),
      );
    } catch (e) {
      // Cart is intentionally left untouched so the customer can retry.
      if (mounted) {
        showAppSnack(context, errorText(e), error: true);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final textTheme = Theme.of(context).textTheme;
    final items = cart.items;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order summary',
                        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            for (final item in items)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${item.product.productName} x ${item.quantity}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(formatMoney(item.lineTotal)),
                                  ],
                                ),
                              ),
                            const Divider(height: 24),
                            Row(
                              children: [
                                Text('Total',
                                    style: textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700)),
                                const Spacer(),
                                Text(
                                  formatMoney(cart.total),
                                  style: textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.burgundy,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Delivery address',
                        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Form(
                      key: _formKey,
                      child: TextFormField(
                        controller: _address,
                        maxLines: 3,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Confirm your delivery address',
                          alignLabelWithHint: true,
                          prefixIcon: Padding(
                            padding: EdgeInsets.only(bottom: 44),
                            child: Icon(Icons.location_on_outlined),
                          ),
                        ),
                        validator: Validators.address,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Online payment is not part of this version. The shop will contact you to arrange payment and delivery.',
                      style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: PrimaryButton(
                label: 'Place Order',
                icon: Icons.check,
                busy: _busy,
                onPressed: cart.isEmpty ? null : _placeOrder,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
