import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../providers/cart_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../widgets/common.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int _quantity = 1;

  @override
  Widget build(BuildContext context) {
    final product = context.watch<CatalogProvider>().byId(widget.productId);
    if (product == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Product')),
        body: const EmptyState(
          icon: Icons.search_off,
          title: 'Product not found',
          message: 'This product is no longer available.',
        ),
      );
    }

    final textTheme = Theme.of(context).textTheme;
    final available = product.availability;

    return Scaffold(
      appBar: AppBar(title: const Text('Product Details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          AspectRatio(
            aspectRatio: 1.2,
            child: ProductImage(
              category: product.category,
              imagePath: product.imagePath,
              borderRadius: 16,
              iconSize: 72,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Chip(
                label: Text(product.category),
                backgroundColor: AppColors.burgundy.withValues(alpha: 0.08),
                side: BorderSide.none,
              ),
              const SizedBox(width: 8),
              Chip(
                avatar: Icon(
                  available ? Icons.check_circle : Icons.remove_circle,
                  size: 18,
                  color: available ? AppColors.success : AppColors.danger,
                ),
                label: Text(available ? 'In stock' : 'Out of stock'),
                backgroundColor:
                    (available ? AppColors.success : AppColors.danger).withValues(alpha: 0.1),
                side: BorderSide.none,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            product.productName,
            style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            formatMoney(product.price),
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.burgundy,
            ),
          ),
          const SizedBox(height: 20),
          Text('Description',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(product.description, style: textTheme.bodyLarge?.copyWith(height: 1.5)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              if (available) ...[
                _QuantityStepper(
                  quantity: _quantity,
                  onChanged: (q) => setState(() => _quantity = q),
                ),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: PrimaryButton(
                  label: available ? 'Add to Cart' : 'Out of Stock',
                  icon: available ? Icons.add_shopping_cart : null,
                  onPressed: available
                      ? () {
                          context.read<CartProvider>().add(product, quantity: _quantity);
                          showAppSnack(
                            context,
                            '$_quantity x ${product.productName} added to cart',
                          );
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({required this.quantity, required this.onChanged});

  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Decrease quantity',
            onPressed: quantity > 1 ? () => onChanged(quantity - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
          IconButton(
            tooltip: 'Increase quantity',
            onPressed: quantity < CartProvider.maxQuantity
                ? () => onChanged(quantity + 1)
                : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
