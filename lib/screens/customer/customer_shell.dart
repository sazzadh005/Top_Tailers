import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/feedback_provider.dart';
import '../../providers/notifications_provider.dart';
import '../../providers/orders_provider.dart';
import '../../providers/wishlist_provider.dart';
import '../shared/notifications_screen.dart';
import '../shared/orders_screen.dart';
import '../shared/profile_screen.dart';
import 'cart_screen.dart';
import 'home_screen.dart';
import 'shop_screen.dart';

/// Customer home: Home, Shop, Cart, Orders and Profile tabs.
class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _index = 0;

  static const int _homeTab = 0;
  static const int _shopTab = 1;

  static const List<String> _titles = [
    AppStrings.appName,
    'Shop',
    'My Cart',
    'My Orders',
    'My Profile',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = context.read<AuthProvider>().user;
      if (user == null) return;
      context.read<CatalogProvider>().load();
      context.read<OrdersProvider>().load(user);
      context.read<NotificationsProvider>().load(user.id);
      context.read<WishlistProvider>().load(user.id);
      context.read<FeedbackProvider>().loadMine(user.id);
      context.read<CartProvider>().attachCustomer(user.id);
    });
  }

  void _goToShop() => setState(() => _index = _shopTab);

  @override
  Widget build(BuildContext context) {
    final cartCount = context.select<CartProvider, int>((c) => c.count);
    final unread = context.select<NotificationsProvider, int>((n) => n.unreadCount);

    return PopScope(
      // Android back from a secondary tab returns to Home before leaving.
      canPop: _index == _homeTab,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(() => _index = _homeTab);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_titles[_index]),
          actions: [
            IconButton(
              tooltip: 'Notifications',
              icon: Badge(
                label: Text('$unread'),
                isLabelVisible: unread > 0,
                child: const Icon(Icons.notifications_outlined),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
              ),
            ),
          ],
        ),
        body: IndexedStack(
          index: _index,
          children: [
            HomeScreen(onOpenShop: _goToShop),
            const ShopScreen(),
            CartScreen(onBrowse: _goToShop),
            OrdersScreen(onBrowse: _goToShop),
            const ProfileScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            const NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront),
              label: 'Shop',
            ),
            NavigationDestination(
              icon: Badge(
                label: Text('$cartCount'),
                isLabelVisible: cartCount > 0,
                child: const Icon(Icons.shopping_cart_outlined),
              ),
              selectedIcon: Badge(
                label: Text('$cartCount'),
                isLabelVisible: cartCount > 0,
                child: const Icon(Icons.shopping_cart),
              ),
              label: 'Cart',
            ),
            const NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Orders',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
