import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../domain/pricing.dart';
import '../models/order.dart';

/// Builds the same breakdown structure from a stored order, so confirmation
/// and order details show exactly what checkout showed.
PriceBreakdown breakdownOfOrder(AppOrder o) => PriceBreakdown(
      subtotalMinor: o.subtotalMinor,
      productDiscountMinor: o.productDiscountMinor,
      customerDiscountMinor: o.customerDiscountMinor,
      voucherDiscountMinor: o.voucherDiscountMinor,
      deliveryMinor: o.deliveryMinor,
      voucherCode: o.voucherCode,
    );

/// Item subtotal, each discount on its own line, delivery, and the final
/// payable amount.
class PriceBreakdownCard extends StatelessWidget {
  const PriceBreakdownCard({
    super.key,
    required this.breakdown,
    this.totalLabel = 'Total payable',
    this.elevated = true,
  });

  final PriceBreakdown breakdown;
  final String totalLabel;
  final bool elevated;

  Widget _row(BuildContext context, String label, String value, {Color? color, bool bold = false}) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = breakdown;
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _row(context, 'Items subtotal', formatMoney(b.subtotalMinor)),
          if (b.productDiscountMinor > 0)
            _row(context, 'Product discounts', '-${formatMoney(b.productDiscountMinor)}',
                color: AppColors.success),
          if (b.customerDiscountMinor > 0)
            _row(context, 'Customer discount', '-${formatMoney(b.customerDiscountMinor)}',
                color: AppColors.success),
          if (b.voucherDiscountMinor > 0)
            _row(
              context,
              b.voucherCode == null ? 'Voucher' : 'Voucher (${b.voucherCode})',
              '-${formatMoney(b.voucherDiscountMinor)}',
              color: AppColors.success,
            ),
          if (b.deliveryMinor > 0)
            _row(context, 'Delivery charge', formatMoney(b.deliveryMinor)),
          const Divider(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  totalLabel,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  formatMoney(b.totalMinor),
                  key: ValueKey<int>(b.totalMinor),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.burgundy,
                      ),
                ),
              ),
            ],
          ),
          if (b.totalDiscountMinor > 0)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'You save ${formatMoney(b.totalDiscountMinor)}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.success, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
    return elevated ? Card(child: content) : content;
  }
}
