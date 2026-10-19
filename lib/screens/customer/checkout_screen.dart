import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../models/measurements.dart';
import '../../models/payment.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/orders_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/measurement_form.dart';
import '../../widgets/price_breakdown_card.dart';
import '../../widgets/product_widgets.dart';
import '../../widgets/voucher_panel.dart';
import 'order_success_screen.dart';
import 'payment_demo_screen.dart';

enum _MeasureMode { saved, order, other }

/// Checkout: order-specific contact number, address, measurements and note;
/// voucher; payment method; and the same price breakdown as the cart.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phone;
  late final TextEditingController _address;
  final _note = TextEditingController();
  final _otherName = TextEditingController();
  late final MeasurementControllers _orderMeasurements;
  late final MeasurementControllers _otherMeasurements;

  bool _saveNumber = false;
  bool _useSavedAddress = true;
  _MeasureMode _mode = _MeasureMode.saved;
  PaymentMethod _method = PaymentMethod.cod;
  String? _measureError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user!;
    _phone = TextEditingController(text: user.phone);
    _address = TextEditingController(text: user.address);
    _useSavedAddress = user.address.trim().isNotEmpty;
    _orderMeasurements = MeasurementControllers(user.measurements);
    _otherMeasurements = MeasurementControllers();
    if (user.measurements.isEmpty) _mode = _MeasureMode.order;
  }

  @override
  void dispose() {
    _phone.dispose();
    _address.dispose();
    _note.dispose();
    _otherName.dispose();
    _orderMeasurements.dispose();
    _otherMeasurements.dispose();
    super.dispose();
  }

  OrderMeasurementSnapshot? _snapshot(BodyMeasurements saved) {
    final now = DateTime.now();
    switch (_mode) {
      case _MeasureMode.saved:
        return OrderMeasurementSnapshot(
          measurements: saved,
          source: MeasurementSource.profile,
          capturedAt: now,
        );
      case _MeasureMode.order:
        return OrderMeasurementSnapshot(
          measurements: _orderMeasurements.toMeasurements(),
          source: MeasurementSource.enteredForOrder,
          capturedAt: now,
        );
      case _MeasureMode.other:
        return OrderMeasurementSnapshot(
          measurements: _otherMeasurements.toMeasurements(),
          source: MeasurementSource.otherPerson,
          forPerson: _otherName.text.trim(),
          capturedAt: now,
        );
    }
  }

  Future<void> _placeOrder() async {
    FocusScope.of(context).unfocus();
    final auth = context.read<AuthProvider>();
    final cart = context.read<CartProvider>();
    final orders = context.read<OrdersProvider>();
    final navigator = Navigator.of(context);
    final user = auth.user;
    if (user == null || cart.isEmpty) return;

    final formOk = _formKey.currentState!.validate();
    OrderMeasurementSnapshot? snapshot;
    String? measureError;
    if (cart.needsMeasurements) {
      snapshot = _snapshot(user.measurements);
      if (snapshot == null || snapshot.measurements.isEmpty) {
        measureError = _mode == _MeasureMode.saved
            ? 'You have no saved measurements. Enter measurements for this order instead.'
            : 'Enter at least one measurement for this tailoring order.';
      }
    }
    setState(() => _measureError = measureError);
    if (!formOk || measureError != null) return;

    final breakdown = cart.breakdown;
    final phone = _phone.text.trim();
    final address = _useSavedAddress ? user.address : _address.text;

    setState(() => _busy = true);
    try {
      final order = await orders.placeOrder(
        user: user,
        items: cart.items,
        breakdown: breakdown,
        contactPhone: phone,
        address: address,
        note: _note.text,
        measurements: snapshot,
        method: _method,
      );
      cart.clear();
      // Saving the number to the profile is opt-in and never affects the
      // order, which keeps its own copy.
      if (_saveNumber && phone != user.phone) {
        try {
          await auth.updateProfile(
            name: user.name,
            phone: phone,
            address: user.address,
          );
        } catch (_) {
          // The order is placed; a profile save failure is not fatal.
        }
      }
      if (!mounted) return;
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => order.payment.method == PaymentMethod.online
              ? PaymentDemoScreen(orderId: order.id)
              : OrderSuccessScreen(orderId: order.id),
        ),
      );
    } catch (e) {
      // Cart is intentionally left untouched so the customer can retry.
      if (mounted) {
        showAppSnack(context, errorText(e), error: true);
        setState(() => _busy = false);
      }
    }
  }

  Widget _section(BuildContext context, String title, IconData icon, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.burgundy),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final user = context.watch<AuthProvider>().user;
    final textTheme = Theme.of(context).textTheme;
    final items = cart.items;
    final b = cart.breakdown;
    final hasSavedAddress = (user?.address ?? '').trim().isNotEmpty;
    final hasSavedMeasurements = user?.measurements.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _section(context, 'Contact number for this order', Icons.phone_outlined, [
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Mobile number',
                          hintText: '01XXXXXXXXX',
                          helperText: 'Used for this order only. Your profile is not changed.',
                        ),
                        validator: Validators.phone,
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: AppColors.burgundy,
                        title: const Text('Also save as my profile number'),
                        value: _saveNumber,
                        onChanged: (v) => setState(() => _saveNumber = v ?? false),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    _section(context, 'Delivery address', Icons.location_on_outlined, [
                      if (hasSavedAddress)
                        Column(
                          children: [
                            ChoiceTile<bool>(
                              value: true,
                              groupValue: _useSavedAddress,
                              title: 'Saved address',
                              subtitle: user?.address ?? '',
                              onChanged: (v) => setState(() => _useSavedAddress = v),
                            ),
                            ChoiceTile<bool>(
                              value: false,
                              groupValue: _useSavedAddress,
                              title: 'Use a different address',
                              onChanged: (v) => setState(() => _useSavedAddress = v),
                            ),
                          ],
                        ),
                      if (!hasSavedAddress || !_useSavedAddress)
                        TextFormField(
                          controller: _address,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Delivery address',
                            alignLabelWithHint: true,
                          ),
                          validator: Validators.address,
                        ),
                    ]),
                    if (cart.needsMeasurements) ...[
                      const SizedBox(height: 12),
                      _section(context, 'Measurements for tailoring', Icons.straighten, [
                        Text(
                          'Order measurements are stored with this order only. Your saved profile measurements are never overwritten here.',
                          style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
                        ),
                        const SizedBox(height: 8),
                        Column(
                          children: [
                            ChoiceTile<_MeasureMode>(
                              value: _MeasureMode.saved,
                              groupValue: _mode,
                              enabled: hasSavedMeasurements,
                              title: 'Use my saved measurements',
                              subtitle: hasSavedMeasurements
                                  ? null
                                  : 'None saved yet (add them in your profile)',
                              onChanged: (v) => setState(() {
                                _mode = v;
                                _measureError = null;
                              }),
                            ),
                            ChoiceTile<_MeasureMode>(
                              value: _MeasureMode.order,
                              groupValue: _mode,
                              title: 'Enter measurements for this order',
                              onChanged: (v) => setState(() {
                                _mode = v;
                                _measureError = null;
                              }),
                            ),
                            ChoiceTile<_MeasureMode>(
                              value: _MeasureMode.other,
                              groupValue: _mode,
                              title: 'Measurements for someone else',
                              onChanged: (v) => setState(() {
                                _mode = v;
                                _measureError = null;
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_mode == _MeasureMode.saved && user != null)
                          MeasurementSummary(measurements: user.measurements),
                        if (_mode == _MeasureMode.order)
                          MeasurementFormSection(controllers: _orderMeasurements),
                        if (_mode == _MeasureMode.other) ...[
                          TextFormField(
                            controller: _otherName,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: "Person's name",
                              isDense: true,
                            ),
                            validator: (v) => _mode == _MeasureMode.other
                                ? Validators.required(v, 'Name')
                                : null,
                          ),
                          const SizedBox(height: 12),
                          MeasurementFormSection(controllers: _otherMeasurements),
                        ],
                        if (_measureError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(_measureError!,
                                style: textTheme.bodySmall?.copyWith(color: AppColors.danger)),
                          ),
                      ]),
                    ],
                    const SizedBox(height: 12),
                    _section(context, 'Order notes (optional)', Icons.edit_note, [
                      TextFormField(
                        controller: _note,
                        maxLines: 3,
                        maxLength: 300,
                        decoration: const InputDecoration(
                          hintText: 'Special instructions, preferred call time...',
                          alignLabelWithHint: true,
                        ),
                        validator: Validators.note,
                      ),
                    ]),
                    const SizedBox(height: 12),
                    const VoucherPanel(),
                    const SizedBox(height: 12),
                    _section(context, 'Payment method', Icons.payments_outlined, [
                      Column(
                        children: [
                          ChoiceTile<PaymentMethod>(
                            value: PaymentMethod.cod,
                            groupValue: _method,
                            title: 'Cash on Delivery',
                            subtitle: 'Pay in cash when your order is delivered.',
                            onChanged: (v) => setState(() => _method = v),
                          ),
                          ChoiceTile<PaymentMethod>(
                            value: PaymentMethod.online,
                            groupValue: _method,
                            title: 'Online Payment',
                            subtitle: 'Pay now through the online payment gateway.',
                            onChanged: (v) => setState(() => _method = v),
                          ),
                        ],
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        alignment: Alignment.topCenter,
                        child: _method == PaymentMethod.online
                            ? const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: DemoNotice(
                                  message:
                                      'Online payment is a DEMONSTRATION in this version. A real gateway (SSLCommerz) is not connected, no payment is taken and no card or wallet details are collected. Your order is placed first; payment is a separate step.',
                                ),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Order summary',
                                style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 8),
                            for (final item in items)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      height: 40,
                                      width: 40,
                                      child: ProductVisual(
                                        product: item.product,
                                        colorName: item.colorName,
                                        borderRadius: 8,
                                        iconSize: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '${item.product.productName}${item.variantLabel.isEmpty ? '' : ' (${item.variantLabel})'} x ${item.quantity}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(formatMoney(item.lineTotalMinor)),
                                  ],
                                ),
                              ),
                            const Divider(height: 24),
                            Text('Contact: ${_phone.text.trim().isEmpty ? '-' : _phone.text.trim()}',
                                style: textTheme.bodySmall),
                            Text('Payment: ${_method.label}', style: textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    PriceBreakdownCard(breakdown: b),
                    const SizedBox(height: 8),
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
                label: _method == PaymentMethod.cod
                    ? 'Place Order  |  ${formatMoney(b.totalMinor)}'
                    : 'Place Order & Continue to Payment',
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
