import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app_services.dart';
import 'core/app_strings.dart';
import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/catalog_provider.dart';
import 'providers/customers_provider.dart';
import 'providers/feedback_provider.dart';
import 'providers/notifications_provider.dart';
import 'providers/orders_provider.dart';
import 'providers/requests_provider.dart';
import 'providers/wishlist_provider.dart';
import 'screens/admin/admin_shell.dart';
import 'screens/auth/login_screen.dart';
import 'screens/customer/customer_shell.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Demonstration data only. Swap AppServices.mock() for a backend-backed
  // AppServices to go live; no screen needs to change.
  runApp(TopTailersApp(services: AppServices.mock()));
}

class TopTailersApp extends StatelessWidget {
  const TopTailersApp({
    super.key,
    required this.services,
    this.splashDuration = const Duration(milliseconds: 1200),
  });

  final AppServices services;
  final Duration splashDuration;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(services.auth, splash: splashDuration),
        ),
        ChangeNotifierProvider(create: (_) => CatalogProvider(services.catalog)),
        ChangeNotifierProvider(
          create: (_) => CartProvider(services.vouchers, services.discounts),
        ),
        ChangeNotifierProvider(
          create: (_) => OrdersProvider(services.orders, services.payments),
        ),
        ChangeNotifierProvider(
          create: (_) => CustomersProvider(services.auth, services.discounts),
        ),
        ChangeNotifierProvider(
          create: (_) => NotificationsProvider(services.notifications),
        ),
        ChangeNotifierProvider(create: (_) => FeedbackProvider(services.feedback)),
        ChangeNotifierProvider(create: (_) => RequestsProvider(services.requests)),
        ChangeNotifierProvider(
          create: (_) => WishlistProvider(services.wishlist, services.catalog),
        ),
      ],
      child: MaterialApp(
        title: AppStrings.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const AuthGate(),
      ),
    );
  }
}

/// Chooses the first screen from the auth state and role (SRS: two roles).
/// This is a demonstration convenience: real authorization belongs to the
/// backend.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isInitializing) return const SplashScreen();
    final user = auth.user;
    if (user == null) return const LoginScreen();
    return user.isAdmin ? const AdminShell() : const CustomerShell();
  }
}
