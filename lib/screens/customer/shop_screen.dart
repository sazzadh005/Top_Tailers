import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../providers/cart_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../widgets/common.dart';
import 'product_detail_screen.dart';

/// Browse by category, search and open product details.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final _searchController = TextEditingController();

  static final List<String> _labels = ['All', ...kCategories];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final selectedIndex =
        catalog.category == null ? 0 : kCategories.indexOf(catalog.category!) + 1;
    final products = catalog.filtered;

    Widget body;
    if (catalog.state == LoadState.loading && catalog.products.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (catalog.state == LoadState.error && catalog.products.isEmpty) {
      body = ErrorState(
        message: 'We could not load the products.',
        onRetry: () => context.read<CatalogProvider>().load(),
      );
    } else if (products.isEmpty) {
      final searching = catalog.query.trim().isNotEmpty || catalog.category != null;
      body = EmptyState(
        icon: Icons.search_off,
        title: searching ? 'No matching products' : 'No products yet',
        message: searching
            ? 'Try a different search or category.'
            : 'Check back soon for new arrivals.',
        actionLabel: searching ? 'Clear filters' : null,
        onAction: searching
            ? () {
                _searchController.clear();
                final c = context.read<CatalogProvider>();
                c.setQuery('');
                c.setCategory(null);
              }
            : null,
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => context.read<CatalogProvider>().load(),
        child: GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.66,
          ),
          itemCount: products.length,
          itemBuilder: (context, index) => _ProductCard(product: products[index]),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: (v) => context.read<CatalogProvider>().setQuery(v),
            decoration: InputDecoration(
              hintText: 'Search fabrics, shirts, services...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: catalog.query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchController.clear();
                        context.read<CatalogProvider>().setQuery('');
                      },
                    ),
            ),
          ),
        ),
        FilterChips(
          labels: _labels,
          selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
          onSelected: (i) => context
              .read<CatalogProvider>()
              .setCategory(i == 0 ? null : kCategories[i - 1]),
        ),
        Expanded(child: body),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final available = product.availability;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ProductDetailScreen(productId: product.id),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductImage(
                    category: product.category,
                    imagePath: product.imagePath,
                    borderRadius: 0,
                  ),
                  if (!available)
                    Container(
                      color: Colors.white.withValues(alpha: 0.65),
                      alignment: Alignment.center,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Out of stock',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.category,
                    style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          formatMoney(product.price),
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.burgundy,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Add to cart',
                        onPressed: available
                            ? () {
                                context.read<CartProvider>().add(product);
                                showAppSnack(
                                  context,
                                  '${product.productName} added to cart',
                                );
                              }
                            : null,
                        icon: const Icon(Icons.add_shopping_cart),
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
