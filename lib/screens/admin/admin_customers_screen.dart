import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/spending.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customers_provider.dart';
import '../../providers/load_state.dart';
import '../../providers/orders_provider.dart';
import '../../widgets/common.dart';
import '../shared/user_avatar.dart';
import 'admin_customer_detail_screen.dart';
import 'discounts_screen.dart';

/// Admin customer list with order count, Lifetime Spending and discount status.
class AdminCustomersScreen extends StatefulWidget {
  const AdminCustomersScreen({super.key});

  @override
  State<AdminCustomersScreen> createState() => _AdminCustomersScreenState();
}

class _AdminCustomersScreenState extends State<AdminCustomersScreen> {
  String _query = '';

  Future<void> _refresh() async {
    final admin = context.read<AuthProvider>().user;
    if (admin == null) return;
    await Future.wait([
      context.read<CustomersProvider>().load(admin),
      context.read<OrdersProvider>().load(admin),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomersProvider>();
    final orders = context.watch<OrdersProvider>().knownOrders;
    final q = _query.trim().toLowerCase();
    final customers = provider.customers.where((c) {
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) ||
          c.email.toLowerCase().contains(q) ||
          c.phone.contains(q) ||
          c.id.toLowerCase().contains(q);
    }).toList();

    Widget body;
    if (provider.state == LoadState.loading && provider.customers.isEmpty) {
      body = ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 4,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) => const SkeletonBox(height: 84, radius: 16),
      );
    } else if (provider.state == LoadState.error && provider.customers.isEmpty) {
      body = ErrorState(
        message: provider.error ?? 'We could not load customers.',
        onRetry: _refresh,
      );
    } else if (customers.isEmpty) {
      body = EmptyState(
        icon: Icons.people_outline,
        title: provider.customers.isEmpty ? 'No customers yet' : 'No matching customers',
        message: provider.customers.isEmpty
            ? 'Registered customers will appear here.'
            : 'Try a different name, phone, email or ID.',
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: customers.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final c = customers[index];
            final mine = orders.where((o) => o.userId == c.id).toList();
            final spending = SpendingCalculator.lifetimeSpendingMinor(mine);
            final discount = provider.discountFor(c.id);
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdminCustomerDetailScreen(customerId: c.id),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      UserAvatar(user: c, radius: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.name,
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text('${c.phone}  |  ${c.id}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.muted)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Pill(
                                  label: '${SpendingCalculator.orderCount(mine)} orders',
                                  color: AppColors.info,
                                ),
                                Pill(
                                  label: 'Spent ${formatMoney(spending)}',
                                  color: AppColors.success,
                                ),
                                if (discount != null)
                                  Pill(
                                    label: discount.active
                                        ? describeDiscount(discount.kind, discount.value)
                                        : 'Discount inactive',
                                    color: discount.active
                                        ? AppColors.burgundy
                                        : AppColors.muted,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Search customers by name, phone, email or ID',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}
