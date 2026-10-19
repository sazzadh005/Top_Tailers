import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/customers_provider.dart';
import '../../providers/feedback_provider.dart';
import '../../providers/orders_provider.dart';
import '../../providers/requests_provider.dart';
import '../shared/orders_screen.dart';
import '../shared/profile_screen.dart';
import 'admin_customers_screen.dart';
import 'admin_inbox_screen.dart';
import 'admin_products_screen.dart';

/// Shop Admin home: Products, Orders, Customers, Inbox and Profile.
///
/// The role split is a demonstration convenience. A real backend must
/// authenticate the admin and authorize every admin action.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  static const List<String> _titles = [
    'Manage Products',
    'Manage Orders',
    'Customers',
    'Feedback & Requests',
    'My Profile',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final admin = context.read<AuthProvider>().user;
      if (admin == null) return;
      context.read<CatalogProvider>().loadFirstPage();
      context.read<OrdersProvider>().load(admin);
      context.read<CustomersProvider>().load(admin);
      context.read<FeedbackProvider>().loadAll();
      context.read<RequestsProvider>().loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pending = context.select<OrdersProvider, int>(
      (o) => o.knownOrders.where((x) => x.status == OrderStatus.pending).length,
    );

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(() => _index = 0);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_titles[_index])),
        body: IndexedStack(
          index: _index,
          children: const [
            AdminProductsScreen(),
            OrdersScreen(adminView: true),
            AdminCustomersScreen(),
            AdminInboxScreen(),
            ProfileScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: 'Products',
            ),
            NavigationDestination(
              icon: Badge(
                label: Text('$pending'),
                isLabelVisible: pending > 0,
                child: const Icon(Icons.receipt_long_outlined),
              ),
              selectedIcon: Badge(
                label: Text('$pending'),
                isLabelVisible: pending > 0,
                child: const Icon(Icons.receipt_long),
              ),
              label: 'Orders',
            ),
            const NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Customers',
            ),
            const NavigationDestination(
              icon: Icon(Icons.inbox_outlined),
              selectedIcon: Icon(Icons.inbox),
              label: 'Inbox',
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
