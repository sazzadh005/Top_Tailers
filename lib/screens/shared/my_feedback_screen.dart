import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../providers/feedback_provider.dart';
import '../../widgets/common.dart';

/// The customer's own product feedback.
class MyFeedbackScreen extends StatelessWidget {
  const MyFeedbackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = context.watch<FeedbackProvider>().mine;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('My feedback')),
      body: items.isEmpty
          ? const EmptyState(
              icon: Icons.rate_review_outlined,
              title: 'No feedback yet',
              message:
                  'After an order is Completed, open it and tap "Give feedback" on any item.',
            )
          : ListView.separated(
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
                            Text(formatShortDate(f.createdAt),
                                style: textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(f.comment),
                        const SizedBox(height: 6),
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
