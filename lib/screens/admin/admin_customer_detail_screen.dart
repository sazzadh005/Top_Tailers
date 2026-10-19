import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/spending.dart';
import '../../providers/customers_provider.dart';
import '../../providers/orders_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/measurement_form.dart';
import '../shared/measurements_screen.dart';
import '../shared/order_detail_screen.dart';
import '../shared/user_avatar.dart';
import 'customer_discount_sheet.dart';
import 'discounts_screen.dart';

/// Everything the shop admin needs to know about one customer. Personal data
/// such as measurements and spending is shown only here (admin context).
class AdminCustomerDetailScreen extends StatelessWidget {
  const AdminCustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context) {
    final customers = context.watch<CustomersProvider>();
    final customer = customers.byId(customerId);
    if (customer == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Customer')),
        body: const EmptyState(
          icon: Icons.person_off_outlined,
          title: 'Customer not found',
          message: 'This customer is no longer available.',
        ),
      );
    }

    final orders = context
        .watch<OrdersProvider>()
        .knownOrders
        .where((o) => o.userId == customer.id)
        .toList()
      ..sort((a, b) => b.orderDate.compareTo(a.orderDate));
    final spending = SpendingCalculator.lifetimeSpendingMinor(orders);
    final discount = customers.discountFor(customer.id);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Customer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      UserAvatar(user: customer, radius: 30),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(customer.name,
                                style: textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            Text('Customer ID: ${customer.id}',
                                style: textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  InfoRow(icon: Icons.mail_outline, label: 'Email', value: customer.email),
                  InfoRow(icon: Icons.phone_outlined, label: 'Profile phone', value: customer.phone),
                  InfoRow(
                    icon: Icons.location_on_outlined,
                    label: 'Saved address',
                    value: customer.address.isEmpty ? 'Not set' : customer.address,
                  ),
                  InfoRow(
                    icon: Icons.event_outlined,
                    label: 'Account created',
                    value: formatShortDate(customer.createdAt),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lifetime Spending',
                      style: textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                  Text(
                    formatMoney(spending),
                    style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800, color: AppColors.success),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${SpendingCalculator.orderCount(orders)} orders in total. Counts Completed orders with confirmed payment only; cancelled orders and pending or failed online payments are excluded. Demonstration figure from mock data, not a verified financial record.',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Customer discount',
                            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      TextButton(
                        onPressed: () => showCustomerDiscountSheet(context, customer),
                        child: Text(discount == null ? 'Add' : 'Edit'),
                      ),
                    ],
                  ),
                  if (discount == null)
                    Text('No discount set.',
                        style: textTheme.bodyMedium?.copyWith(color: AppColors.muted))
                  else ...[
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(describeDiscount(discount.kind, discount.value),
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        Pill(
                          label: discount.active ? 'Active' : 'Inactive',
                          color: discount.active ? AppColors.success : AppColors.muted,
                        ),
                      ],
                    ),
                    if (discount.note.isNotEmpty)
                      Text(discount.note,
                          style: textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                    Text(
                      discount.active
                          ? 'Applied automatically to this customer\u2019s eligible orders (not on already-discounted items, not stacked with vouchers).'
                          : 'Not applied while inactive.',
                      style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Saved body measurements',
                            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => MeasurementsScreen(customer: customer),
                          ),
                        ),
                        child: const Text('Edit'),
                      ),
                    ],
                  ),
                  MeasurementSummary(measurements: customer.measurements),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Order history',
              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (orders.isEmpty)
            Text('No orders yet.',
                style: textTheme.bodyMedium?.copyWith(color: AppColors.muted))
          else
            for (final o in orders)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => OrderDetailScreen(orderId: o.id, adminView: true),
                      ),
                    ),
                    title: Text(o.reference,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${formatShortDate(o.orderDate)}  |  ${formatMoney(o.totalMinor)}  |  ${o.contactPhone}'),
                    trailing: StatusChip(status: o.status),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
