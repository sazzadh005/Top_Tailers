import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/load_state.dart';
import '../../providers/notifications_provider.dart';
import '../../widgets/common.dart';

/// Shows notifications from the last 30 days, newest first. Older ones are
/// hidden by the repository (hiding is not deletion; permanent cleanup is a
/// backend job).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh every time the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    await context.read<NotificationsProvider>().load(user.id);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationsProvider>();
    final items = provider.items;
    // Capture now: the pop callback may run while this screen is being removed.
    final notifications = context.read<NotificationsProvider>();

    Widget body;
    if (provider.state == LoadState.loading && items.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (provider.state == LoadState.error && items.isEmpty) {
      body = ErrorState(message: 'We could not load notifications.', onRetry: _load);
    } else if (items.isEmpty) {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 64),
            EmptyState(
              icon: Icons.notifications_none,
              title: 'No recent notifications',
              message: 'Order updates and announcements from the last 30 days appear here.',
            ),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: items.length + 1,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index == items.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Notifications are shown for 30 days.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.muted),
                ),
              );
            }
            final n = items[index];
            final created = n.createdAt;
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: CircleAvatar(
                  backgroundColor: AppColors.burgundy.withValues(alpha: 0.1),
                  child: const Icon(Icons.notifications_outlined, color: AppColors.burgundy),
                ),
                title: Text(
                  n.title,
                  style: TextStyle(fontWeight: n.read ? FontWeight.w500 : FontWeight.w800),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.body),
                      const SizedBox(height: 4),
                      Text(
                        created == null
                            ? ''
                            : '${formatRelative(created)}  |  ${formatDateTime(created)}',
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

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) notifications.markAllRead();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: body,
      ),
    );
  }
}
