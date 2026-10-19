import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/cart_item.dart';
import '../../providers/cart_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/price_breakdown_card.dart';
import '../../widgets/product_widgets.dart';
import '../../widgets/voucher_panel.dart';
import 'checkout_screen.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key, required this.onBrowse});

  final VoidCallback onBrowse;

  Future<void> _clear(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: 'Clear cart?',
      message: 'All items and any applied voucher will be removed.',
      confirmLabel: 'Clear cart',
      destructive: true,
    );
    if (ok && context.mounted) context.read<CartProvider>().clear();
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    if (cart.isEmpty) {
      return EmptyState(
        icon: Icons.shopping_cart_outlined,
        title: 'Your cart is empty',
        message: 'Add fabrics, garments or tailoring services to get started.',
        actionLabel: 'Browse Products',
        onAction: onBrowse,
      );
    }

    final items = cart.items;
    final b = cart.breakdown;
    final inCart = items.map((i) => i.product.id).toSet();
    final home = context.watch<CatalogProvider>().home;
    final recommended = [
      ...home.featured,
      ...home.popular,
    ].where((p) => !inCart.contains(p.id)).toList();
    final seen = <String>{};
    final unique = recommended.where((p) => seen.add(p.id)).take(6).toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${cart.count} ${cart.count == 1 ? 'item' : 'items'}',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _clear(context),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                    label: const Text('Clear cart'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  ),
                ],
              ),
              for (final item in items) ...[
                _CartTile(item: item),
                const SizedBox(height: 12),
              ],
              const VoucherPanel(),
              const SizedBox(height: 12),
              PriceBreakdownCard(breakdown: b),
              if (unique.isNotEmpty) ...[
                const SizedBox(height: 4),
                const SectionHeader(title: 'You may also like'),
                SizedBox(
                  height: 292,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: unique.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 12),
                    itemBuilder: (context, index) => SizedBox(
                      width: 170,
                      child: ProductCard(product: unique[index], compact: true),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total payable',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.muted)),
                  Text(
                    formatMoney(b.totalMinor),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800, color: AppColors.burgundy),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: PrimaryButton(
                  label: 'Checkout',
                  icon: Icons.arrow_forward,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const CheckoutScreen()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CartTile extends StatelessWidget {
  const _CartTile({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartProvider>();
    final textTheme = Theme.of(context).textTheme;
    final product = item.product;
    final discounted = item.unitMinor < item.listUnitMinor;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 78,
              width: 78,
              child: ProductVisual(
                product: product,
                colorName: item.colorName,
                borderRadius: 12,
                iconSize: 30,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          product.productName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove from cart',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          cart.remove(item.key);
                          showAppSnack(context, '${product.productName} removed');
                        },
                        icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                      ),
                    ],
                  ),
                  if (item.variantLabel.isNotEmpty)
                    Text(item.variantLabel,
                        style: textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${formatMoney(item.unitMinor)} each',
                        style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (discounted)
                        Text(
                          formatMoney(item.listUnitMinor),
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.muted,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Decrease quantity',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => cart.setQuantity(item.key, item.quantity - 1),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('${item.quantity}',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      IconButton(
                        tooltip: 'Increase quantity',
                        visualDensity: VisualDensity.compact,
                        onPressed: item.quantity < CartProvider.maxQuantity
                            ? () => cart.setQuantity(item.key, item.quantity + 1)
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      const Spacer(),
                      Text(
                        formatMoney(item.lineTotalMinor),
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.burgundy,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
