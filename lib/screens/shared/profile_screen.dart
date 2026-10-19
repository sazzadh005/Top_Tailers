import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/customers_provider.dart';
import '../../providers/feedback_provider.dart';
import '../../providers/notifications_provider.dart';
import '../../providers/orders_provider.dart';
import '../../providers/requests_provider.dart';
import '../../providers/wishlist_provider.dart';
import '../../widgets/common.dart';
import '../customer/wishlist_screen.dart';
import 'edit_profile_screen.dart';
import 'measurements_screen.dart';
import 'my_feedback_screen.dart';
import 'requests_screen.dart';
import 'user_avatar.dart';

/// Profile tab used by both customers and administrators.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: 'Log out?',
      message: 'You will need to sign in again to continue.',
      confirmLabel: 'Log out',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final auth = context.read<AuthProvider>();
    final cart = context.read<CartProvider>();
    final orders = context.read<OrdersProvider>();
    final notifications = context.read<NotificationsProvider>();
    final wishlist = context.read<WishlistProvider>();
    final feedback = context.read<FeedbackProvider>();
    final requests = context.read<RequestsProvider>();
    final customers = context.read<CustomersProvider>();
    final catalog = context.read<CatalogProvider>();
    Navigator.of(context).popUntil((route) => route.isFirst);
    cart.clear();
    orders.reset();
    notifications.reset();
    wishlist.reset();
    feedback.reset();
    requests.reset();
    customers.reset();
    catalog.reset();
    auth.logout();
  }

  Widget _menuTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget Function() page,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.burgundy),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) return const SizedBox.shrink();
    final wishCount = context.watch<WishlistProvider>().count;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                UserAvatar(user: user, radius: 44),
                const SizedBox(height: 12),
                Text(
                  user.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Pill(
                  label: user.isAdmin ? 'Shop Admin' : 'Customer',
                  color: AppColors.burgundy,
                  icon: user.isAdmin
                      ? Icons.admin_panel_settings_outlined
                      : Icons.person_outline,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                InfoRow(icon: Icons.mail_outline, label: 'Email', value: user.email),
                const Divider(),
                InfoRow(icon: Icons.phone_outlined, label: 'Profile phone', value: user.phone),
                const Divider(),
                InfoRow(
                  icon: Icons.location_on_outlined,
                  label: 'Saved address',
                  value: user.address.isEmpty ? 'Not set' : user.address,
                ),
                const Divider(),
                InfoRow(
                  icon: Icons.event_outlined,
                  label: 'Member since',
                  value: formatShortDate(user.createdAt),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _menuTile(
                context,
                icon: Icons.edit_outlined,
                title: 'Edit profile',
                page: () => const EditProfileScreen(),
              ),
              if (!user.isAdmin) ...[
                const Divider(),
                _menuTile(
                  context,
                  icon: Icons.straighten,
                  title: 'My measurements',
                  subtitle: user.measurements.isEmpty
                      ? 'Not saved yet'
                      : '${user.measurements.values.length} saved',
                  page: () => const MeasurementsScreen(),
                ),
                const Divider(),
                _menuTile(
                  context,
                  icon: Icons.favorite_border,
                  title: 'Saved items',
                  subtitle: wishCount == 0 ? null : '$wishCount saved',
                  page: () => const WishlistScreen(),
                ),
                const Divider(),
                _menuTile(
                  context,
                  icon: Icons.rate_review_outlined,
                  title: 'My feedback',
                  page: () => const MyFeedbackScreen(),
                ),
                const Divider(),
                _menuTile(
                  context,
                  icon: Icons.lightbulb_outline,
                  title: 'Suggestions & restock requests',
                  page: () => const RequestsScreen(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            side: const BorderSide(color: AppColors.danger),
          ),
          onPressed: () => _logout(context),
          icon: const Icon(Icons.logout),
          label: const Text('Log Out'),
        ),
      ],
    );
  }
}
