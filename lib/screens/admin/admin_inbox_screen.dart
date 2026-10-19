import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/requests.dart';
import '../../providers/feedback_provider.dart';
import '../../providers/load_state.dart';
import '../../providers/requests_provider.dart';
import '../../widgets/common.dart';

/// Customer feedback and requests for the shop admin. Feedback, suggestions
/// and restock requests stay in separate tabs.
class AdminInboxScreen extends StatelessWidget {
  const AdminInboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: const [
          TabBar(
            labelColor: AppColors.burgundy,
            indicatorColor: AppColors.burgundy,
            tabs: [Tab(text: 'Feedback'), Tab(text: 'Ideas'), Tab(text: 'Restock')],
          ),
          Expanded(
            child: TabBarView(children: [_FeedbackTab(), _IdeasTab(), _RestockTab()]),
          ),
        ],
      ),
    );
  }
}

class _FeedbackTab extends StatelessWidget {
  const _FeedbackTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FeedbackProvider>();
    final items = provider.all;
    if (provider.allState == LoadState.loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.rate_review_outlined,
        title: 'No feedback yet',
        message: 'Product feedback from completed orders will appear here.',
      );
    }
    final textTheme = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: () => context.read<FeedbackProvider>().loadAll(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final f = items[index];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.productName,
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      StarRating(rating: f.rating.toDouble()),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${f.userName}  |  ${formatShortDate(f.createdAt)}',
                          style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(f.comment),
                  const SizedBox(height: 4),
                  Text('Order ${f.orderId}',
                      style: textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatusMenu extends StatelessWidget {
  const _StatusMenu({required this.status, required this.onSelected});

  final RequestStatus status;
  final ValueChanged<RequestStatus> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<RequestStatus>(
      tooltip: 'Change status',
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final s in RequestStatus.values)
          PopupMenuItem<RequestStatus>(value: s, child: Text(s.label)),
      ],
      child: Pill(
        label: '${status.label}  \u25BE',
        color: requestStatusColor(status),
      ),
    );
  }
}

Future<void> _update(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) showAppSnack(context, errorText(e), error: true);
  }
}

class _IdeasTab extends StatelessWidget {
  const _IdeasTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RequestsProvider>();
    final items = provider.suggestions;
    if (provider.state == LoadState.loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.lightbulb_outline,
        title: 'No suggestions yet',
        message: 'New-product ideas from customers will appear here.',
      );
    }
    final textTheme = Theme.of(context).textTheme;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final s = items[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(s.title,
                          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    _StatusMenu(
                      status: s.status,
                      onSelected: (st) => _update(
                        context,
                        () => context.read<RequestsProvider>().setSuggestionStatus(s.id, st),
                      ),
                    ),
                  ],
                ),
                if (s.details.isNotEmpty) ...[const SizedBox(height: 6), Text(s.details)],
                const SizedBox(height: 6),
                Text('${s.userName}  |  ${formatShortDate(s.createdAt)}',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.muted)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RestockTab extends StatelessWidget {
  const _RestockTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RequestsProvider>();
    final items = provider.restocks;
    if (provider.state == LoadState.loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_outlined,
        title: 'No restock requests',
        message: 'Customer requests to restock products will appear here.',
      );
    }
    final textTheme = Theme.of(context).textTheme;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final r = items[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('${r.productName} (${r.productCode})',
                          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    _StatusMenu(
                      status: r.status,
                      onSelected: (st) => _update(
                        context,
                        () => context.read<RequestsProvider>().setRestockStatus(r.id, st),
                      ),
                    ),
                  ],
                ),
                if (r.reason.isNotEmpty) ...[const SizedBox(height: 6), Text(r.reason)],
                const SizedBox(height: 6),
                Text('${r.userName}  |  ${formatShortDate(r.createdAt)}',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.muted)),
              ],
            ),
          ),
        );
      },
    );
  }
}
