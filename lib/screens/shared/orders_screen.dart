import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import '../../models/payment.dart';
import '../../providers/auth_provider.dart';
import '../../providers/load_state.dart';
import '../../providers/orders_provider.dart';
import '../../widgets/common.dart';
import 'order_detail_screen.dart';

/// Order list with search and filters, shared by customers ("Order history")
/// and the shop admin ("Manage orders"). Which orders are visible is decided
/// by the repository from the signed-in user, never by this widget.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, this.adminView = false, this.onBrowse});

  final bool adminView;
  final VoidCallback? onBrowse;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _search = TextEditingController();

  static final List<String> _labels = [
    'All',
    ...OrderStatus.values.map((s) => s.label),
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() => context.read<OrdersProvider>().refresh();

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _OrderFilterSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrdersProvider>();
    final user = context.watch<AuthProvider>().user;
    final q = provider.query;
    final orders = provider.orders;
    final statusIndex = q.status == null ? 0 : q.status!.index + 1;
    final extraFilters = (q.paymentStatus != null ? 1 : 0) + (q.from != null || q.to != null ? 1 : 0);

    Widget body;
    if (provider.state == LoadState.loading && orders.isEmpty) {
      body = ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 4,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) => const SkeletonBox(height: 120, radius: 16),
      );
    } else if (provider.state == LoadState.error) {
      body = ErrorState(
        message: provider.error ?? 'We could not load orders.',
        onRetry: _refresh,
      );
    } else if (orders.isEmpty) {
      final filtering = !q.isEmpty;
      body = RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 48),
            EmptyState(
              icon: filtering ? Icons.search_off : Icons.receipt_long_outlined,
              title: filtering ? 'No matching orders' : 'No orders yet',
              message: filtering
                  ? 'Try different words or clear the filters.'
                  : (widget.adminView
                      ? 'Customer orders will appear here.'
                      : 'Your placed orders will show up here so you can track them.'),
              actionLabel: filtering
                  ? 'Clear search'
                  : ((!widget.adminView && widget.onBrowse != null) ? 'Start Shopping' : null),
              onAction: filtering
                  ? () {
                      _search.clear();
                      context.read<OrdersProvider>().clearSearch();
                    }
                  : widget.onBrowse,
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
          itemCount: orders.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) => _OrderCard(
            order: orders[index],
            adminView: widget.adminView,
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: (v) => context.read<OrdersProvider>().setText(v),
            decoration: InputDecoration(
              hintText: widget.adminView
                  ? 'Order, customer, phone or product code'
                  : 'Order reference, product or phone',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: q.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        context.read<OrdersProvider>().setText('');
                      },
                    ),
            ),
          ),
        ),
        FilterChips(
          labels: _labels,
          selectedIndex: statusIndex,
          onSelected: (i) => context
              .read<OrdersProvider>()
              .setStatus(i == 0 ? null : OrderStatus.values[i - 1]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  provider.state == LoadState.ready
                      ? '${orders.length} ${orders.length == 1 ? 'order' : 'orders'}'
                      : ' ',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.muted),
                ),
              ),
              if (!q.isEmpty)
                TextButton(
                  onPressed: () {
                    _search.clear();
                    context.read<OrdersProvider>().clearSearch();
                  },
                  child: const Text('Clear all'),
                ),
              TextButton.icon(
                onPressed: _openFilters,
                icon: Badge(
                  isLabelVisible: extraFilters > 0,
                  label: Text('$extraFilters'),
                  child: const Icon(Icons.tune, size: 20),
                ),
                label: const Text('Filters'),
              ),
            ],
          ),
        ),
        if (provider.state == LoadState.loading && orders.isNotEmpty)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(child: user == null ? const SizedBox.shrink() : body),
      ],
    );
  }
}

class _OrderFilterSheet extends StatelessWidget {
  const _OrderFilterSheet();

  Future<void> _pickRange(BuildContext context) async {
    final provider = context.read<OrdersProvider>();
    final q = provider.query;
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: (q.from != null && q.to != null)
          ? DateTimeRange(start: q.from!, end: q.to!)
          : null,
    );
    if (picked != null) provider.setDateRange(picked.start, picked.end);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrdersProvider>();
    final q = provider.query;
    final hasRange = q.from != null && q.to != null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payment status',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Any'),
                  selected: q.paymentStatus == null,
                  onSelected: (_) => provider.setPaymentStatus(null),
                ),
                for (final s in PaymentStatus.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: q.paymentStatus == s,
                    onSelected: (_) => provider.setPaymentStatus(s),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Order date',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _pickRange(context),
              icon: const Icon(Icons.date_range),
              label: Text(hasRange
                  ? '${formatShortDate(q.from!)} - ${formatShortDate(q.to!)}'
                  : 'Choose date range'),
            ),
            if (hasRange)
              TextButton(
                onPressed: () => provider.setDateRange(null, null),
                child: const Text('Clear dates'),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
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
                      order.reference,
                      style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800, letterSpacing: 0.3),
                    ),
                  ),
                  StatusChip(status: order.status),
                ],
              ),
              const SizedBox(height: 2),
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
                      child: Text(
                        '${order.customerName}  |  ${order.contactPhone}',
                        overflow: TextOverflow.ellipsis,
                      ),
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
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: PaymentChip(payment: order.payment),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatMoney(order.totalMinor),
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
