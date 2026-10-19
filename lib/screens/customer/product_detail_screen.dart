import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../providers/cart_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/feedback_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/product_widgets.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final _pageController = PageController();
  int _page = 0;
  int _quantity = 1;
  String? _colorName;
  String? _size;
  String? _variantError;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final catalog = context.read<CatalogProvider>();
      final feedback = context.read<FeedbackProvider>();
      final product = await catalog.ensureProduct(widget.productId);
      if (!mounted) return;
      setState(() => _requested = true);
      if (product != null) {
        catalog.markViewed(product);
        feedback.loadForProduct(product.id);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool _validateVariants(Product p) {
    if (p.colors.isNotEmpty && _colorName == null) {
      setState(() => _variantError = 'Please choose a colour.');
      return false;
    }
    if (p.sizes.isNotEmpty && _size == null) {
      setState(() => _variantError = 'Please choose a size.');
      return false;
    }
    return true;
  }

  void _addToCart(Product p) {
    if (!_validateVariants(p)) return;
    final ok = context.read<CartProvider>().add(
          p,
          quantity: _quantity,
          colorName: _colorName,
          size: _size,
        );
    if (ok) {
      setState(() => _variantError = null);
      showAppSnack(context, '$_quantity x ${p.productName} added to cart');
    } else {
      showAppSnack(context, 'This item cannot be added right now.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = context.watch<CatalogProvider>().byId(widget.productId);
    if (product == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Product')),
        body: _requested
            ? const EmptyState(
                icon: Icons.search_off,
                title: 'Product not found',
                message: 'This product is no longer available.',
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }

    final textTheme = Theme.of(context).textTheme;
    final available = product.availability;
    final feedback = context.watch<FeedbackProvider>();
    final reviews = feedback.forProduct(product.id);
    final average = feedback.averageFor(product.id);
    final galleryCount = product.imagePaths.length + 3;
    final qtyLabel = product.isFabric ? 'Length (yards)' : 'Quantity';
    final lineTotal = product.effectivePriceMinor * _quantity;

    return Scaffold(
      appBar: AppBar(title: Text(product.code)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          AspectRatio(
            aspectRatio: 1.15,
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pageController,
                  itemCount: galleryCount,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: ProductVisual(
                      product: product,
                      index: index,
                      colorName: _colorName,
                      borderRadius: 20,
                      iconSize: 72,
                    ),
                  ),
                ),
                Positioned(left: 28, top: 12, child: DiscountBadge(product: product)),
                Positioned(
                  right: 28,
                  top: 8,
                  child: WishlistButton(product: product, small: false),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < galleryCount; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          height: 6,
                          width: i == _page ? 18 : 6,
                          decoration: BoxDecoration(
                            color: i == _page
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Pill(label: product.category, color: AppColors.burgundy),
                    Pill(
                      label: available ? 'In stock' : 'Out of stock',
                      color: available ? AppColors.success : AppColors.danger,
                      icon: available ? Icons.check_circle : Icons.remove_circle,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(product.productName,
                    style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Product code: ${product.code}',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                if (average != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      StarRating(rating: average),
                      const SizedBox(width: 6),
                      Text('${average.toStringAsFixed(1)} (${reviews.length})',
                          style: textTheme.bodySmall),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                PriceText(product: product, large: true, showUnit: true),
                if (product.hasDiscount)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'You save ${formatMoney(product.discountAmountMinor)} per ${product.unit}',
                      style: textTheme.bodySmall?.copyWith(
                          color: AppColors.success, fontWeight: FontWeight.w700),
                    ),
                  ),
                if (product.colors.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Colour${_colorName == null ? '' : ': $_colorName'}',
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final c in product.colors)
                        _ColorChoice(
                          color: c,
                          selected: c.name == _colorName,
                          onTap: () => setState(() {
                            _colorName = c.name;
                            _variantError = null;
                          }),
                        ),
                    ],
                  ),
                ],
                if (product.sizes.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Size${_size == null ? '' : ': $_size'}',
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final s in product.sizes)
                        ChoiceChip(
                          label: Text(s),
                          selected: s == _size,
                          showCheckmark: false,
                          selectedColor: AppColors.burgundy,
                          labelStyle: TextStyle(
                            color: s == _size ? Colors.white : AppColors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                          onSelected: (_) => setState(() {
                            _size = s;
                            _variantError = null;
                          }),
                        ),
                    ],
                  ),
                ],
                if (_variantError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_variantError!,
                        style: textTheme.bodySmall?.copyWith(color: AppColors.danger)),
                  ),
                if (available) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(qtyLabel,
                            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      _QuantityStepper(
                        quantity: _quantity,
                        onChanged: (q) => setState(() => _quantity = q),
                      ),
                    ],
                  ),
                ],
                if (product.requiresMeasurements) ...[
                  const SizedBox(height: 16),
                  const DemoNotice(
                    message:
                        'This service is made to measure. You will choose saved measurements, enter new ones for this order, or measure someone else at checkout.',
                  ),
                ],
                if (product.specs.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(product.isFabric ? 'Fabric information' : 'Details',
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        children: [
                          for (final e in product.specs.entries)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 100,
                                    child: Text(e.key,
                                        style: textTheme.bodyMedium
                                            ?.copyWith(color: AppColors.muted)),
                                  ),
                                  Expanded(child: Text(e.value)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text('Description',
                    style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(product.description, style: textTheme.bodyLarge?.copyWith(height: 1.5)),
                const SizedBox(height: 20),
                Text('Customer feedback',
                    style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                if (reviews.isEmpty)
                  Text('No feedback yet.',
                      style: textTheme.bodyMedium?.copyWith(color: AppColors.muted))
                else
                  for (final r in reviews.take(5))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  StarRating(rating: r.rating.toDouble(), size: 14),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${r.userName.split(' ').first}  |  ${formatShortDate(r.createdAt)}',
                                      style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(r.comment),
                            ],
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
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
              if (available)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total', style: textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                      Text(
                        formatMoney(lineTotal),
                        style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800, color: AppColors.burgundy),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: PrimaryButton(
                  label: available ? 'Add to Cart' : 'Out of Stock',
                  icon: available ? Icons.add_shopping_cart : null,
                  onPressed: available ? () => _addToCart(product) : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({required this.color, required this.selected, required this.onTap});

  final FabricColor color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: color.name,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 44,
          width: 44,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.burgundy : AppColors.border,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(color: Color(color.argb), shape: BoxShape.circle),
            child: selected
                ? Icon(
                    Icons.check,
                    size: 18,
                    color: Color(color.argb).computeLuminance() < 0.45
                        ? Colors.white
                        : AppColors.ink,
                  )
                : null,
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
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Decrease',
            onPressed: quantity > 1 ? () => onChanged(quantity - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          IconButton(
            tooltip: 'Increase',
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
