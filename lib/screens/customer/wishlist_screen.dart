import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/wishlist_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/product_widgets.dart';

class WishlistScreen extends StatelessWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wishlist = context.watch<WishlistProvider>();
    final products = wishlist.products;

    Widget body;
    if (wishlist.loading && products.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (products.isEmpty) {
      body = const EmptyState(
        icon: Icons.favorite_border,
        title: 'No saved items yet',
        message: 'Tap the heart on any product to save it here for later.',
      );
    } else {
      body = GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.62,
        ),
        itemCount: products.length,
        itemBuilder: (context, index) => ProductCard(product: products[index]),
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('Saved items')), body: body);
  }
}
