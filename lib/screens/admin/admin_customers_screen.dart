import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../providers/catalog_provider.dart' show LoadState;
import '../../providers/orders_provider.dart';
import '../../widgets/common.dart';
import '../shared/user_avatar.dart';

/// Read-only customer list for administrators.
class AdminCustomersScreen extends StatelessWidget {
  const AdminCustomersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrdersProvider>();
    final customers = provider.customers;

    if (provider.customersState == LoadState.loading && customers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.customersState == LoadState.error && customers.isEmpty) {
      return ErrorState(
        message: 'We could not load customers.',
        onRetry: () => context.read<OrdersProvider>().loadCustomers(),
      );
    }
    if (customers.isEmpty) {
      return const EmptyState(
        icon: Icons.people_outline,
        title: 'No customers yet',
        message: 'Registered customers will appear here.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<OrdersProvider>().loadCustomers(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: customers.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final c = customers[index];
          final orderCount =
              provider.orders.where((o) => o.userId == c.id).length;
          return Card(
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                leading: UserAvatar(user: c, radius: 22),
                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(c.email, overflow: TextOverflow.ellipsis),
                children: [
                  InfoRow(icon: Icons.phone_outlined, label: 'Phone', value: c.phone),
                  InfoRow(
                    icon: Icons.location_on_outlined,
                    label: 'Address',
                    value: c.address.isEmpty ? 'Not set' : c.address,
                  ),
                  InfoRow(
                    icon: Icons.event_outlined,
                    label: 'Joined',
                    value: formatShortDate(c.createdAt),
                  ),
                  InfoRow(
                    icon: Icons.receipt_long_outlined,
                    label: 'Orders',
                    value: '$orderCount',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
