import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../providers/catalog_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/product_widgets.dart';
import 'discounts_screen.dart';
import 'product_form_screen.dart';

/// Admin product list: search by product code, name or keyword, filter by
/// category, add/edit/delete, and open discount management.
class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  static final List<String> _labels = ['All', ...kCategories];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.extentAfter < 300) {
        context.read<CatalogProvider>().loadMore();
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _openForm([Product? product]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ProductFormScreen(product: product)),
    );
  }

  Future<void> _delete(Product product) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete product?',
      message: '"${product.productName}" (${product.code}) will be removed from the catalog. Existing orders keep their own copy of the item.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final catalog = context.read<CatalogProvider>();
    try {
      await catalog.deleteProduct(product.id);
      if (mounted) showAppSnack(context, 'Product deleted');
    } catch (e) {
      if (mounted) showAppSnack(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final items = catalog.items;
    final selectedIndex =
        catalog.category == null ? 0 : kCategories.indexOf(catalog.category!) + 1;

    Widget body;
    if (catalog.state == LoadState.loading && items.isEmpty) {
      body = ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) => const SkeletonBox(height: 92, radius: 16),
      );
    } else if (catalog.state == LoadState.error && items.isEmpty) {
      body = ErrorState(
        message: 'We could not load the products.',
        onRetry: () => context.read<CatalogProvider>().loadFirstPage(),
      );
    } else if (items.isEmpty) {
      body = EmptyState(
        icon: Icons.inventory_2_outlined,
        title: catalog.hasActiveFilters ? 'No matching products' : 'No products yet',
        message: catalog.hasActiveFilters
            ? 'Try a different code, name or category.'
            : 'Add your first product to start selling.',
        actionLabel: catalog.hasActiveFilters ? 'Clear filters' : 'Add Product',
        onAction: catalog.hasActiveFilters
            ? () {
                _search.clear();
                context.read<CatalogProvider>().clearFilters();
              }
            : () => _openForm(),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => context.read<CatalogProvider>().loadFirstPage(),
        child: ListView.separated(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: items.length + 1,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index == items.length) {
              return Center(
                child: catalog.loadingMore
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      )
                    : Text(
                        catalog.hasMore ? '' : '${catalog.total} products',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.muted),
                      ),
              );
            }
            final p = items[index];
            return _AdminProductTile(
              product: p,
              onEdit: () => _openForm(p),
              onDelete: () => _delete(p),
            );
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (v) => context.read<CatalogProvider>().setQuery(v),
                    decoration: InputDecoration(
                      hintText: 'Search by product code, name or keyword',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: catalog.query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _search.clear();
                                context.read<CatalogProvider>().setQuery('');
                              },
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Manage discounts',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const DiscountsScreen()),
                  ),
                  icon: const Icon(Icons.sell_outlined),
                ),
              ],
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
      ),
    );
  }
}

class _AdminProductTile extends StatelessWidget {
  const _AdminProductTile({
    required this.product,
    required this.onEdit,
    required this.onDelete,
  });

  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                height: 72,
                width: 72,
                child: ProductVisual(product: product, borderRadius: 12, iconSize: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.code,
                      style: textTheme.labelSmall?.copyWith(
                          color: AppColors.burgundy,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4),
                    ),
                    Text(
                      product.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    PriceText(product: product, showUnit: true),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Pill(
                          label: product.availability ? 'Available' : 'Unavailable',
                          color: product.availability ? AppColors.success : AppColors.danger,
                        ),
                        if (product.hasDiscount) DiscountBadge(product: product),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    tooltip: 'Edit product',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, color: AppColors.burgundy),
                  ),
                  IconButton(
                    tooltip: 'Delete product',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
