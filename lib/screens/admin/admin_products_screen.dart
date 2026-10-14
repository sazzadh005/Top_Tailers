import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../providers/catalog_provider.dart';
import '../../widgets/common.dart';
import 'product_form_screen.dart';

/// Add, edit and delete products (SRS administration area).
class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> {
  String _query = '';

  void _openForm([Product? product]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ProductFormScreen(product: product)),
    );
  }

  Future<void> _delete(Product product) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete product?',
      message: '"${product.productName}" will be removed from the catalog.',
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
    final q = _query.trim().toLowerCase();
    final products = catalog.products
        .where((p) =>
            q.isEmpty ||
            p.productName.toLowerCase().contains(q) ||
            p.category.toLowerCase().contains(q))
        .toList();

    Widget body;
    if (catalog.state == LoadState.loading && catalog.products.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (catalog.state == LoadState.error && catalog.products.isEmpty) {
      body = ErrorState(
        message: 'We could not load the products.',
        onRetry: () => context.read<CatalogProvider>().load(),
      );
    } else if (products.isEmpty) {
      body = EmptyState(
        icon: Icons.inventory_2_outlined,
        title: catalog.products.isEmpty ? 'No products yet' : 'No matching products',
        message: catalog.products.isEmpty
            ? 'Add your first product to start selling.'
            : 'Try a different search.',
        actionLabel: catalog.products.isEmpty ? 'Add Product' : null,
        onAction: catalog.products.isEmpty ? () => _openForm() : null,
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => context.read<CatalogProvider>().load(),
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: products.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final p = products[index];
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Search products',
                prefixIcon: Icon(Icons.search),
              ),
            ),
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
    final available = product.availability;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                height: 68,
                width: 68,
                child: ProductImage(
                  category: product.category,
                  imagePath: product.imagePath,
                  borderRadius: 10,
                  iconSize: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
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
                      '${product.category}  |  ${formatMoney(product.price)}',
                      style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      available ? 'Available' : 'Unavailable',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: available ? AppColors.success : AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
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
        ),
      ),
    );
  }
}
