import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/theme.dart';
import '../../models/cancellation.dart';
import '../../models/order.dart';
import '../../providers/orders_provider.dart';
import '../../widgets/common.dart';

/// Cancellation dialog for both roles. A reason is required; "Other" needs a
/// written note. The result is stored as a permanent CancellationRecord.
Future<bool> showCancelOrderSheet(
  BuildContext context, {
  required AppOrder order,
  required bool byAdmin,
}) async {
  final cancelled = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CancelOrderSheet(order: order, byAdmin: byAdmin),
  );
  return cancelled ?? false;
}

class _CancelOrderSheet extends StatefulWidget {
  const _CancelOrderSheet({required this.order, required this.byAdmin});

  final AppOrder order;
  final bool byAdmin;

  @override
  State<_CancelOrderSheet> createState() => _CancelOrderSheetState();
}

class _CancelOrderSheetState extends State<_CancelOrderSheet> {
  String? _reason;
  final _note = TextEditingController();
  String? _error;
  bool _busy = false;

  List<String> get _reasons =>
      widget.byAdmin ? kAdminCancelReasons : kCustomerCancelReasons;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = 'Please choose a reason.');
      return;
    }
    if (reason == 'Other' && _note.text.trim().length < 5) {
      setState(() => _error = 'Please describe the reason.');
      return;
    }
    final confirmed = await confirmDialog(
      context,
      title: 'Cancel this order?',
      message: widget.byAdmin
          ? '${widget.order.reference} will be cancelled and the customer will be notified. This cannot be undone.'
          : '${widget.order.reference} will be cancelled. This cannot be undone.',
      confirmLabel: 'Yes, cancel order',
      cancelLabel: 'Keep order',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final orders = context.read<OrdersProvider>();
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await orders.cancelOrder(
        widget.order.id,
        reason: reason,
        note: _note.text,
      );
      navigator.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cancel order',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Order ${widget.order.reference}. Please tell us why '
              '${widget.byAdmin ? 'it is being cancelled' : 'you are cancelling'}.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            for (final r in _reasons)
              ChoiceTile<String>(
                value: r,
                groupValue: _reason,
                title: r,
                onChanged: (v) => setState(() {
                  _reason = v;
                  _error = null;
                }),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              maxLines: 3,
              maxLength: 300,
              decoration: InputDecoration(
                labelText: _reason == 'Other' ? 'Describe the reason' : 'Additional notes (optional)',
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.danger)),
              ),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Cancel order'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: const Text('Keep order'),
            ),
          ],
        ),
      ),
    );
  }
}
