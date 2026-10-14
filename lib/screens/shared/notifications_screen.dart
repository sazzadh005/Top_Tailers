import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart' show LoadState;
import '../../providers/orders_provider.dart';
import '../../widgets/common.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    final provider = context.read<OrdersProvider>();
    await provider.loadNotifications(user);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrdersProvider>();
    final items = provider.notifications;

    Widget body;
    if (provider.notificationsState == LoadState.loading && items.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (provider.notificationsState == LoadState.error && items.isEmpty) {
      body = ErrorState(message: 'We could not load notifications.', onRetry: _load);
    } else if (items.isEmpty) {
      body = const EmptyState(
        icon: Icons.notifications_none,
        title: 'No notifications',
        message: 'Order updates and announcements will appear here.',
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final n = items[index];
            return Card(
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: CircleAvatar(
                  backgroundColor: AppColors.burgundy.withValues(alpha: 0.1),
                  child: const Icon(Icons.notifications_outlined,
                      color: AppColors.burgundy),
                ),
                title: Text(
                  n.title,
                  style: TextStyle(
                    fontWeight: n.read ? FontWeight.w500 : FontWeight.w800,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.body),
                      const SizedBox(height: 4),
                      Text(
                        formatDateTime(n.createdAt),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                trailing: n.read
                    ? null
                    : const Icon(Icons.circle, size: 10, color: AppColors.burgundy),
              ),
            );
          },
        ),
      );
    }

    // Capture providers now: the callback below can run while this screen is
    // being removed, when looking them up through context is no longer safe.
    final auth = context.read<AuthProvider>();
    final ordersProvider = context.read<OrdersProvider>();

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        // Mark everything read when leaving the screen.
        final user = auth.user;
        if (didPop && user != null) {
          ordersProvider.markAllNotificationsRead(user);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: body,
      ),
    );
  }
}
