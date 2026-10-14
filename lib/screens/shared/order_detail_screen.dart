import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import '../../providers/orders_provider.dart';
import '../../widgets/common.dart';

/// Order details with the status timeline. Customers can cancel while the
/// order is Pending; administrators can advance the status or cancel
/// Pending/Confirmed orders (SRS order status flow).
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId, this.adminView = false});

  final String orderId;
  final bool adminView;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String successMessage) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showAppSnack(context, successMessage);
    } catch (e) {
      if (mounted) showAppSnack(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(AppOrder order) async {
    final ok = await confirmDialog(
      context,
      title: 'Cancel order?',
      message: widget.adminView
          ? 'Order ${order.id} will be cancelled and the customer will be notified.'
          : 'Order ${order.id} will be cancelled. This cannot be undone.',
      confirmLabel: 'Cancel order',
      cancelLabel: 'Keep order',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final provider = context.read<OrdersProvider>();
    await _run(
      () => provider.cancelOrder(order.id, byAdmin: widget.adminView),
      'Order cancelled',
    );
  }

  Future<void> _advance(AppOrder order, OrderStatus next) {
    final provider = context.read<OrdersProvider>();
    return _run(
      () => provider.updateStatus(order.id, next),
      'Order marked as ${next.label}. Customer notified.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = context.watch<OrdersProvider>().byId(widget.orderId);
    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order')),
        body: const EmptyState(
          icon: Icons.search_off,
          title: 'Order not found',
          message: 'This order is no longer available.',
        ),
      );
    }

    final textTheme = Theme.of(context).textTheme;
    final next = order.status.next;
    final canCancel = widget.adminView ? order.adminCanCancel : order.customerCanCancel;

    return Scaffold(
      appBar: AppBar(title: Text(order.id)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Order status',
                              style: textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        StatusChip(status: order.status),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _StatusTimeline(status: order.status),
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
                    Text('Items',
                        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    for (final item in order.items) ...[
                      Row(
                        children: [
                          SizedBox(
                            height: 52,
                            width: 52,
                            child: ProductImage(
                              category: item.category,
                              imagePath: item.imagePath,
                              borderRadius: 10,
                              iconSize: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.productName,
                                    maxLines: 2, overflow: TextOverflow.ellipsis),
                                Text(
                                  '${formatMoney(item.price)} x ${item.quantity}',
                                  style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(formatMoney(item.lineTotal),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    const Divider(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text('Total',
                            style: textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text(
                          formatMoney(order.totalPrice),
                          style: textTheme.titleLarge?.copyWith(
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
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    if (widget.adminView) ...[
                      InfoRow(
                        icon: Icons.person_outline,
                        label: 'Customer',
                        value: order.customerName,
                      ),
                      const Divider(),
                    ],
                    InfoRow(
                      icon: Icons.location_on_outlined,
                      label: 'Delivery address',
                      value: order.address,
                    ),
                    const Divider(),
                    InfoRow(
                      icon: Icons.event_outlined,
                      label: 'Order date',
                      value: formatDateTime(order.orderDate),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (widget.adminView && next != null)
              PrimaryButton(
                label: 'Mark as ${next.label}',
                icon: Icons.check_circle_outline,
                busy: _busy,
                onPressed: () => _advance(order, next),
              ),
            if (canCancel) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                ),
                onPressed: _busy ? null : () => _cancel(order),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel Order'),
              ),
            ],
            if (!widget.adminView && order.status == OrderStatus.confirmed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'This order has been confirmed and can no longer be cancelled by you. Please contact the shop if you need help.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Vertical Pending -> Confirmed -> Processing -> Completed tracker, or a
/// cancelled banner.
class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.status});

  final OrderStatus status;

  static const List<OrderStatus> _steps = [
    OrderStatus.pending,
    OrderStatus.confirmed,
    OrderStatus.processing,
    OrderStatus.completed,
  ];

  @override
  Widget build(BuildContext context) {
    if (status == OrderStatus.cancelled) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: AppColors.danger),
            SizedBox(width: 12),
            Expanded(child: Text('This order was cancelled.')),
          ],
        ),
      );
    }

    final currentIndex = _steps.indexOf(status);
    return Column(
      children: [
        for (var i = 0; i < _steps.length; i++)
          _TimelineStep(
            label: _steps[i].label,
            done: i <= currentIndex,
            current: i == currentIndex,
            isLast: i == _steps.length - 1,
          ),
      ],
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.label,
    required this.done,
    required this.current,
    required this.isLast,
  });

  final String label;
  final bool done;
  final bool current;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.burgundy : AppColors.border;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  height: 22,
                  width: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? color : Colors.white,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: done
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
                if (!isLast) Expanded(child: Container(width: 2, color: color)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: current ? FontWeight.w800 : FontWeight.w500,
                  color: done ? AppColors.ink : AppColors.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
