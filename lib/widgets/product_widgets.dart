import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../domain/discount.dart';
import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../providers/wishlist_provider.dart';
import '../screens/customer/product_detail_screen.dart';
import 'common.dart';

IconData categoryIcon(String category) {
  switch (category) {
    case 'Fabrics':
      return Icons.texture;
    case 'Readymade':
      return Icons.checkroom;
    case 'Tailoring':
      return Icons.content_cut;
    default:
      return Icons.style_outlined;
  }
}

Color categoryColor(String category) {
  switch (category) {
    case 'Fabrics':
      return const Color(0xFFE6D9C6);
    case 'Readymade':
      return const Color(0xFFDCC9D1);
    case 'Tailoring':
      return const Color(0xFFCBD7E0);
    default:
      return const Color(0xFFD9DCC6);
  }
}

/// Base colour used to draw a product: the chosen/first fabric colour, or a
/// category tint.
Color productBaseColor(Product p, {String? colorName}) {
  if (p.colors.isNotEmpty) {
    for (final c in p.colors) {
      if (c.name == colorName) return Color(c.argb);
    }
    return Color(p.colors.first.argb);
  }
  return categoryColor(p.category);
}

/// Draws a simple woven-fabric look so products have a visual even without
/// uploaded photos.
class _SwatchPainter extends CustomPainter {
  _SwatchPainter(this.base, this.pattern);

  final Color base;
  final int pattern;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final light = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1.2;
    final dark = Paint()
      ..color = Colors.black.withValues(alpha: 0.07)
      ..strokeWidth = 1.2;
    final step = pattern % 4 == 3 ? 14.0 : 7.0;
    switch (pattern % 4) {
      case 0:
      case 3:
        for (var x = 0.0; x < size.width; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), light);
        }
        for (var y = 0.0; y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), dark);
        }
        break;
      case 1:
        for (var d = -size.height; d < size.width; d += step) {
          canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), light);
        }
        break;
      case 2:
        for (var x = 0.0; x < size.width; x += step * 2) {
          canvas.drawRect(Rect.fromLTWH(x, 0, step, size.height), light);
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _SwatchPainter old) =>
      old.base != base || old.pattern != pattern;
}

/// Product picture: an uploaded image when available, otherwise a generated
/// fabric swatch (with a category icon for non-fabric items).
class ProductVisual extends StatelessWidget {
  const ProductVisual({
    super.key,
    required this.product,
    this.index = 0,
    this.colorName,
    this.borderRadius = 12,
    this.iconSize = 36,
  });

  final Product product;

  /// Gallery position: uploaded images first, then generated swatches.
  final int index;
  final String? colorName;
  final double borderRadius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final images = product.imagePaths;
    Widget content;
    if (index < images.length) {
      content = Image.file(
        File(images[index]),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => _swatch(0),
      );
    } else {
      content = _swatch(index - images.length);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: content,
    );
  }

  Widget _swatch(int pattern) {
    final base = productBaseColor(product, colorName: colorName);
    final dark = base.computeLuminance() < 0.45;
    return SizedBox.expand(
      child: CustomPaint(
        painter: _SwatchPainter(base, pattern),
        child: product.isFabric
            ? null
            : Center(
                child: Icon(
                  categoryIcon(product.category),
                  size: iconSize,
                  color: (dark ? Colors.white : AppColors.burgundy).withValues(alpha: 0.7),
                ),
              ),
      ),
    );
  }
}

/// "-10%" or "BDT 200 off" badge for a discounted product.
class DiscountBadge extends StatelessWidget {
  const DiscountBadge({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final d = product.discount;
    if (!product.hasDiscount || d == null) return const SizedBox.shrink();
    final text = d.kind == DiscountKind.percent
        ? '-${d.value}%'
        : '${formatMoney(product.discountAmountMinor)} off';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
      ),
    );
  }
}

/// Discounted price with the original struck through.
class PriceText extends StatelessWidget {
  const PriceText({super.key, required this.product, this.large = false, this.showUnit = false});

  final Product product;
  final bool large;
  final bool showUnit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final main = (large ? textTheme.headlineSmall : textTheme.titleSmall)?.copyWith(
      fontWeight: FontWeight.w800,
      color: AppColors.burgundy,
    );
    final unit = showUnit && product.unit != 'piece' ? ' / ${product.unit}' : '';
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text('${formatMoney(product.effectivePriceMinor)}$unit', style: main),
        if (product.hasDiscount)
          Text(
            formatMoney(product.priceMinor),
            style: (large ? textTheme.titleMedium : textTheme.bodySmall)?.copyWith(
              color: AppColors.muted,
              decoration: TextDecoration.lineThrough,
            ),
          ),
      ],
    );
  }
}

/// Heart button that toggles a product in the wishlist.
class WishlistButton extends StatelessWidget {
  const WishlistButton({super.key, required this.product, this.small = true});

  final Product product;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final saved = context.select<WishlistProvider, bool>((w) => w.isSaved(product.id));
    final size = small ? 36.0 : 44.0;
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          context.read<WishlistProvider>().toggle(product);
          showAppSnack(
            context,
            saved ? 'Removed from saved items' : 'Saved to your wishlist',
          );
        },
        child: SizedBox(
          height: size,
          width: size,
          child: Tooltip(
            message: saved ? 'Remove from wishlist' : 'Save to wishlist',
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
              child: Icon(
                saved ? Icons.favorite : Icons.favorite_border,
                key: ValueKey<bool>(saved),
                size: small ? 20 : 24,
                color: saved ? AppColors.danger : AppColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Little colour dots + extra info under a product name.
class VariantHint extends StatelessWidget {
  const VariantHint({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted);
    if (product.colors.isNotEmpty) {
      final shown = product.colors.take(4).toList();
      final extra = product.colors.length - shown.length;
      return Row(
        children: [
          for (final c in shown)
            Container(
              height: 14,
              width: 14,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: Color(c.argb),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
            ),
          if (extra > 0) Text('+$extra', style: style),
        ],
      );
    }
    if (product.sizes.isNotEmpty) {
      return Text('Sizes ${product.sizes.first}-${product.sizes.last}', style: style);
    }
    if (product.requiresMeasurements) {
      return Text('Made to measure', style: style);
    }
    return const SizedBox(height: 14);
  }
}

void openProduct(BuildContext context, Product product) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => ProductDetailScreen(productId: product.id)),
  );
}

/// Product card used in grids and carousels.
class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, this.compact = false});

  final Product product;

  /// Compact cards are used inside horizontal carousels.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final available = product.availability;
    // Items needing a choice open the detail page instead of a blind quick-add.
    final needsChoice = product.hasVariants || product.requiresMeasurements;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openProduct(context, product),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductVisual(product: product, borderRadius: 0),
                  if (!available)
                    Container(
                      color: Colors.white.withValues(alpha: 0.65),
                      alignment: Alignment.center,
                      child: const Pill(label: 'Out of stock', color: AppColors.ink),
                    ),
                  Positioned(left: 8, top: 8, child: DiscountBadge(product: product)),
                  Positioned(right: 6, top: 6, child: WishlistButton(product: product)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.code,
                    style: textTheme.labelSmall?.copyWith(color: AppColors.muted, letterSpacing: 0.4),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.2),
                  ),
                  const SizedBox(height: 4),
                  VariantHint(product: product),
                  Row(
                    children: [
                      Expanded(child: PriceText(product: product, showUnit: true)),
                      IconButton(
                        tooltip: needsChoice ? 'Choose options' : 'Add to cart',
                        onPressed: !available
                            ? null
                            : () {
                                if (needsChoice) {
                                  openProduct(context, product);
                                } else {
                                  context.read<CartProvider>().add(product);
                                  showAppSnack(context, '${product.productName} added to cart');
                                }
                              },
                        icon: Icon(needsChoice ? Icons.tune : Icons.add_shopping_cart),
                        color: AppColors.burgundy,
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

/// Horizontal carousel of compact product cards. Fixed height avoids nested
/// scroll conflicts with the page's vertical scrolling.
class ProductCarousel extends StatelessWidget {
  const ProductCarousel({super.key, required this.products, this.height = 292});

  final List<Product> products;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: products.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) => SizedBox(
          width: 170,
          child: ProductCard(product: products[index], compact: true),
        ),
      ),
    );
  }
}
