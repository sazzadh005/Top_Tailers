import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart' show LoadState;
import '../../providers/orders_provider.dart';
import '../../widgets/common.dart';
import 'order_detail_screen.dart';

/// Order list for customers ("Order history") and administrators
/// ("View orders"). Set [adminView] to show customer names.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, this.adminView = false, this.onBrowse});

  final bool adminView;
  final VoidCallback? onBrowse;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  int _filterIndex = 0; // 0 = All, then OrderStatus.values in order

  static final List<String> _labels = [
    'All',
    ...OrderStatus.values.map((s) => s.label),
  ];

  Future<void> _refresh() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    await context.read<OrdersProvider>().loadOrders(user);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrdersProvider>();
    final all = provider.orders;
    final filtered = _filterIndex == 0
        ? all
        : all.where((o) => o.status == OrderStatus.values[_filterIndex - 1]).toList();

    Widget body;
    if (provider.ordersState == LoadState.loading && all.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (provider.ordersState == LoadState.error && all.isEmpty) {
      body = ErrorState(
        message: 'We could not load your orders.',
        onRetry: _refresh,
      );
    } else if (filtered.isEmpty) {
      body = RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 48),
            EmptyState(
              icon: Icons.receipt_long_outlined,
              title: all.isEmpty ? 'No orders yet' : 'No ${_labels[_filterIndex]} orders',
              message: all.isEmpty
                  ? (widget.adminView
                      ? 'Customer orders will appear here.'
                      : 'Your placed orders will show up here so you can track them.')
                  : 'Try a different status filter.',
              actionLabel: (all.isEmpty && !widget.adminView && widget.onBrowse != null)
                  ? 'Start Shopping'
                  : null,
              onAction: widget.onBrowse,
            ),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: filtered.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) => _OrderCard(
            order: filtered[index],
            adminView: widget.adminView,
          ),
        ),
      );
    }

    return Column(
      children: [
        const SizedBox(height: 8),
        FilterChips(
          labels: _labels,
          selectedIndex: _filterIndex,
          onSelected: (i) => setState(() => _filterIndex = i),
        ),
        Expanded(child: body),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.adminView});

  final AppOrder order;
  final bool adminView;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => OrderDetailScreen(orderId: order.id, adminView: adminView),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.id,
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  StatusChip(status: order.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                formatDateTime(order.orderDate),
                style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
              if (adminView) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 18, color: AppColors.muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(order.customerName, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text(
                order.items.map((i) => '${i.productName} x${i.quantity}').join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    '${order.itemCount} ${order.itemCount == 1 ? 'item' : 'items'}',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                  const Spacer(),
                  Text(
                    formatMoney(order.totalPrice),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.burgundy,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
