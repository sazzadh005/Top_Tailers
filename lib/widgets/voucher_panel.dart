import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_exception.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/validators.dart';
import '../domain/pricing.dart';
import '../providers/cart_provider.dart';

/// Voucher entry used in the cart and checkout. All maths comes from
/// CartProvider.breakdown, so both places always agree.
class VoucherPanel extends StatefulWidget {
  const VoucherPanel({super.key});

  @override
  State<VoucherPanel> createState() => _VoucherPanelState();
}

class _VoucherPanelState extends State<VoucherPanel> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final cart = context.read<CartProvider>();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await cart.applyVoucher(_controller.text);
      if (!mounted) return;
      setState(() {
        _message = result.message;
        _messageIsError = !result.ok;
        if (result.ok) _controller.clear();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = errorText(e);
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final voucher = cart.voucher;
    final b = cart.breakdown;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_offer_outlined, color: AppColors.burgundy, size: 20),
                const SizedBox(width: 8),
                Text('Voucher',
                    style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 12),
            if (voucher != null) ...[
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                decoration: BoxDecoration(
                  color: (b.source == OrderDiscountSource.voucher
                          ? AppColors.success
                          : AppColors.warning)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      b.source == OrderDiscountSource.voucher
                          ? Icons.check_circle
                          : Icons.info_outline,
                      color: b.source == OrderDiscountSource.voucher
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(voucher.code,
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(
                            b.source == OrderDiscountSource.voucher
                                ? 'Saving ${formatMoney(b.voucherDiscountMinor)}'
                                : (b.voucherNote ?? 'Not reducing this order'),
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove voucher',
                      onPressed: () {
                        context.read<CartProvider>().removeVoucher();
                        setState(() => _message = null);
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ] else
              Form(
                key: _formKey,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _controller,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _apply(),
                        decoration: const InputDecoration(
                          labelText: 'Voucher code',
                          isDense: true,
                        ),
                        validator: Validators.voucherCode,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(88, 52),
                        ),
                        onPressed: _busy ? null : _apply,
                        child: _busy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: Colors.white),
                              )
                            : const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _messageIsError ? Icons.error_outline : Icons.check_circle_outline,
                    size: 16,
                    color: _messageIsError ? AppColors.danger : AppColors.success,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _message!,
                      style: textTheme.bodySmall?.copyWith(
                        color: _messageIsError ? AppColors.danger : AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (voucher == null) ...[
              const SizedBox(height: 10),
              Text('Demonstration codes (mock data):',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.muted)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 0,
                children: [
                  for (final code in const [
                    'DEMO10',
                    'DEMOFAB15',
                    'DEMOFLAT100',
                    'DEMOEXPIRED',
                    'DEMOOFF',
                  ])
                    ActionChip(
                      label: Text(code, style: const TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _controller.text = code),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
