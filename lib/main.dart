import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app_config.dart';
import 'app/app_services.dart';
import 'app/supabase_services.dart';
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
import 'screens/auth/new_password_screen.dart';
import 'screens/customer/customer_shell.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Opt-in demo mode: in-memory sample data, clearly bannered. Never the default.
  if (AppConfig.useMockData) {
    runApp(TopTailersApp(services: AppServices.mock()));
    return;
  }

  if (!AppConfig.isBackendConfigured) {
    runApp(const ConfigErrorApp());
    return;
  }

  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  } catch (e) { 
    runApp(ConfigErrorApp(detail: 'Could not start the backend connection.'));
    return;
  }
  runApp(TopTailersApp(services: buildSupabaseServices(Supabase.instance.client)));
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
        Provider<AppServices>.value(value: services),
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
        // Demo data must never be mistaken for live data.
        builder: (context, child) => services.isDemoData
            ? Banner(
                message: 'DEMO DATA',
                location: BannerLocation.topEnd,
                color: AppColors.warning,
                child: child ?? const SizedBox.shrink(),
              )
            : (child ?? const SizedBox.shrink()),
        home: const AuthGate(),
      ),
    );
  }
}

/// Chooses the first screen from the auth state and role (SRS: two roles).
/// This is a convenience: real authorization is enforced by the backend.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isInitializing) return const SplashScreen();
    if (auth.isRecovering) return const NewPasswordScreen();
    final user = auth.user;
    if (user == null) return const LoginScreen();
    return user.isAdmin ? const AdminShell() : const CustomerShell();
  }
}

/// Shown instead of silently falling back to fake data when the build was not
/// given a backend.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, this.detail});

  final String? detail;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.settings_suggest_outlined, size: 56, color: AppColors.burgundy),
                    const SizedBox(height: 16),
                    Text('Backend not configured',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(detail ?? 'This build has no backend address.'),
                    const SizedBox(height: 16),
                    const SelectableText(
                      'flutter run \\\n'
                      '  --dart-define=SUPABASE_URL=https://<project>.supabase.co \\\n'
                      '  --dart-define=SUPABASE_ANON_KEY=<anon key>',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'For an offline demo with sample data add --dart-define=USE_MOCK_DATA=true. '
                      'See docs/BACKEND_SETUP.md.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
