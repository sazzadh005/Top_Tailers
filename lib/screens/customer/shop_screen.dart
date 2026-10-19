import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/catalog_query.dart';
import '../../models/product.dart';
import '../../providers/catalog_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/product_widgets.dart';

/// Browse and search products (original search behaviour preserved), now with
/// sort, in-stock filter and lazy page loading.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final _searchController = TextEditingController();
  final _scroll = ScrollController();

  static final List<String> _labels = ['All', ...kCategories];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 400) {
      context.read<CatalogProvider>().loadMore();
    }
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => const _SortFilterSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();

    // Keep the field in sync when the query is set from elsewhere (home).
    if (_searchController.text != catalog.query) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _searchController.text != catalog.query) {
          _searchController.text = catalog.query;
        }
      });
    }

    final selectedIndex =
        catalog.category == null ? 0 : kCategories.indexOf(catalog.category!) + 1;
    final items = catalog.items;

    Widget body;
    if (catalog.state == LoadState.loading && items.isEmpty) {
      body = GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.62,
        ),
        itemCount: 6,
        itemBuilder: (context, index) => const SkeletonBox(radius: 16),
      );
    } else if (catalog.state == LoadState.error && items.isEmpty) {
      body = ErrorState(
        message: 'We could not load the products.',
        onRetry: () => context.read<CatalogProvider>().loadFirstPage(),
      );
    } else if (items.isEmpty) {
      body = EmptyState(
        icon: Icons.search_off,
        title: catalog.hasActiveFilters ? 'No matching products' : 'No products yet',
        message: catalog.hasActiveFilters
            ? 'Try a different search, category or filter.'
            : 'Check back soon for new arrivals.',
        actionLabel: catalog.hasActiveFilters ? 'Clear filters' : null,
        onAction: catalog.hasActiveFilters
            ? () {
                _searchController.clear();
                context.read<CatalogProvider>().clearFilters();
              }
            : null,
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => context.read<CatalogProvider>().loadFirstPage(),
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 240,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.62,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => ProductCard(product: items[index]),
                  childCount: items.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: catalog.loadingMore
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : (catalog.hasMore
                          ? TextButton(
                              onPressed: () =>
                                  context.read<CatalogProvider>().loadMore(),
                              child: const Text('Load more'),
                            )
                          : Text(
                              'You have seen all ${catalog.total} products',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.muted),
                            )),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: (v) => context.read<CatalogProvider>().setQuery(v),
            decoration: InputDecoration(
              hintText: 'Search name, product code or keyword',
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  catalog.state == LoadState.ready
                      ? '${catalog.total} ${catalog.total == 1 ? 'product' : 'products'}'
                      : ' ',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.muted),
                ),
              ),
              TextButton.icon(
                onPressed: _openFilters,
                icon: Badge(
                  isLabelVisible:
                      catalog.sort != ProductSort.featured || catalog.inStockOnly,
                  smallSize: 8,
                  child: const Icon(Icons.tune, size: 20),
                ),
                label: Text('Sort: ${catalog.sort.label}'),
              ),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

class _SortFilterSheet extends StatelessWidget {
  const _SortFilterSheet();

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sort by',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            for (final option in ProductSort.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(option.label),
                leading: Icon(
                  catalog.sort == option
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: AppColors.burgundy,
                ),
                onTap: () => context.read<CatalogProvider>().setSort(option),
              ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: AppColors.burgundy,
              title: const Text('In stock only'),
              value: catalog.inStockOnly,
              onChanged: (v) => context.read<CatalogProvider>().setInStockOnly(v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      context.read<CatalogProvider>()
                        ..setSort(ProductSort.featured)
                        ..setInStockOnly(false);
                    },
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
