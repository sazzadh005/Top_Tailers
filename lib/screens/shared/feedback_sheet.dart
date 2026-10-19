import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/theme.dart';
import '../../models/feedback.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/feedback_provider.dart';
import '../../widgets/common.dart';

/// Bottom sheet for rating and reviewing one item of a Completed order.
Future<void> showFeedbackSheet(
  BuildContext context, {
  required AppOrder order,
  required OrderItem item,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FeedbackSheet(order: order, item: item),
  );
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet({required this.order, required this.item});

  final AppOrder order;
  final OrderItem item;

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _formKey = GlobalKey<FormState>();
  final _comment = TextEditingController();
  int _rating = 0;
  String? _ratingError;
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = context.read<AuthProvider>().user;
    final feedback = context.read<FeedbackProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (user == null) return;
    final valid = _formKey.currentState!.validate();
    setState(() => _ratingError = _rating == 0 ? 'Please choose a star rating.' : null);
    if (!valid || _rating == 0) return;

    setState(() => _busy = true);
    try {
      await feedback.submit(
        ProductFeedback(
          id: '',
          orderId: widget.order.id,
          productId: widget.item.productId,
          productName: widget.item.productName,
          userId: user.id,
          userName: user.name,
          rating: _rating,
          comment: _comment.text,
          createdAt: DateTime.now(),
        ),
      );
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Thank you for your feedback')));
    } catch (e) {
      if (mounted) {
        showAppSnack(context, errorText(e), error: true);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rate this product',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${widget.item.productName} (${widget.item.productCode})',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Center(
                child: StarPicker(
                  value: _rating,
                  onChanged: (v) => setState(() {
                    _rating = v;
                    _ratingError = null;
                  }),
                ),
              ),
              if (_ratingError != null)
                Center(
                  child: Text(_ratingError!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.danger)),
                ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _comment,
                maxLines: 4,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Your feedback',
                  alignLabelWithHint: true,
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Please write a few words';
                  if (t.length < 5) return 'Please write at least 5 characters';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              PrimaryButton(label: 'Submit feedback', busy: _busy, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
