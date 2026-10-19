import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../domain/discount.dart';
import '../../models/app_user.dart';
import '../../models/customer_discount.dart';
import '../../providers/customers_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/discount_editor.dart';

/// Create, edit, activate/deactivate or remove one customer's discount.
Future<void> showCustomerDiscountSheet(BuildContext context, AppUser customer) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CustomerDiscountSheet(customer: customer),
  );
}

class _CustomerDiscountSheet extends StatefulWidget {
  const _CustomerDiscountSheet({required this.customer});

  final AppUser customer;

  @override
  State<_CustomerDiscountSheet> createState() => _CustomerDiscountSheetState();
}

class _CustomerDiscountSheetState extends State<_CustomerDiscountSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _value;
  late final TextEditingController _note;
  late DiscountKind _kind;
  late bool _active;
  late final bool _exists;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final d = context.read<CustomersProvider>().discountFor(widget.customer.id);
    _exists = d != null;
    _kind = d?.kind ?? DiscountKind.percent;
    _active = d?.active ?? true;
    _value = TextEditingController(
      text: d == null
          ? ''
          : (d.kind == DiscountKind.percent ? '${d.value}' : Money.toInput(d.value)),
    );
    _note = TextEditingController(text: d?.note ?? '');
  }

  @override
  void dispose() {
    _value.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final customers = context.read<CustomersProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await customers.saveDiscount(
        CustomerDiscount(
          customerId: widget.customer.id,
          kind: _kind,
          value: parseDiscountValue(_kind, _value.text)!,
          active: _active,
          note: _note.text.trim(),
          updatedAt: DateTime.now(),
        ),
      );
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Customer discount saved')));
    } catch (e) {
      if (mounted) {
        showAppSnack(context, errorText(e), error: true);
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _remove() async {
    final ok = await confirmDialog(
      context,
      title: 'Remove discount?',
      message: '${widget.customer.name} will no longer receive this discount.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final customers = context.read<CustomersProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await customers.removeDiscount(widget.customer.id);
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Customer discount removed')));
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
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Customer discount',
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text(widget.customer.name, style: textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                'Applies to this customer\u2019s eligible orders. It never stacks with a voucher (the larger one wins) and ignores items that already have a product discount.',
                style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              DiscountEditor(
                kind: _kind,
                valueController: _value,
                onKindChanged: (k) => setState(() {
                  _kind = k;
                  _value.clear();
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _note,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Internal note (optional)'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppColors.burgundy,
                title: const Text('Active'),
                subtitle: Text(_active ? 'Applied at checkout' : 'Saved but not applied'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              const SizedBox(height: 8),
              PrimaryButton(label: 'Save discount', busy: _busy, onPressed: _save),
              if (_exists) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  onPressed: _busy ? null : _remove,
                  child: const Text('Remove discount'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
